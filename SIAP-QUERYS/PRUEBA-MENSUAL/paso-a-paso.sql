
Esta es una función de PostgreSQL muy completa y compleja, diseñada para generar un reporte 
detallado de las marcaciones mensuales de un empleado, incluyendo cálculos avanzados de horas trabajadas, retrasos, horas extras (RE), y horas adicionales (RA en diferentes porcentajes), aplicando una serie de reglas de negocio intrincadas.

La función toma como entrada un año, un mes y el código de personal, y devuelve una tabla con una gran cantidad de columnas que resumen la actividad diaria del empleado para ese mes.

Vamos a desglosarla parte por parte, explicando cada Bloque de Expresión de Tabla Común (CTE, por sus siglas en inglés: WITH ... AS (...)) y la lógica final.

Nombre de la Función y Parámetros:
CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas5(...): Crea o reemplaza una función llamada marcaciones_por_mes_horas5 en el esquema public.
Parámetros de Entrada:
anio integer: El año para el cual se generará el reporte.
mes integer: El mes para el cual se generará el reporte.
param_reg_cod_personal integer: El código del empleado para quien se generará el reporte.
RETURNS TABLE(...): La función devuelve una tabla con una larga lista de columnas, que incluye datos de marcación, turno, parámetros, cálculos de tiempo, información de ocurrencias (permisos/ausencias), feriados y tolerancias especiales.
Configuración Inicial (LANGUAGE plpgsql y BEGIN):
SQL

LANGUAGE plpgsql
AS
$function$
BEGIN
	PERFORM set_config('timezone', 'UTC', true); -- Configura la zona horaria a UTC para la sesión actual. Importante para consistencia en cálculos de tiempo.
	PERFORM set_config('DateStyle', 'ISO, DMY', true); -- Configura el estilo de fecha a ISO, DMY (Día-Mes-Año).
	RETURN QUERY
	-- ... (aquí comienza la lógica SQL)
END;
$function$
;
LANGUAGE plpgsql: Indica que el cuerpo de la función está escrito en PL/pgSQL, el lenguaje de procedimientos de PostgreSQL.
PERFORM set_config(...): Estas líneas establecen configuraciones de sesión para la función. Aseguran que la manipulación de fechas y tiempos sea consistente (UTC para la zona horaria y DMY para el estilo de fecha) sin importar la configuración global del servidor o del cliente.
CTEs (Common Table Expressions - Bloques WITH):
Aquí es donde reside la mayor parte de la lógica. Cada CTE prepara un conjunto de datos intermedio que luego se utiliza en CTEs posteriores o en la consulta final.

1. calendar
SQL

	WITH RECURSIVE calendar AS (
		SELECT DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
		UNION ALL
		SELECT (date + INTERVAL '1 day')::DATE
		FROM calendar
		WHERE date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
	),
Propósito: Genera una lista de todas las fechas para el mes y año dados (anio, mes).
RECURSIVE: Permite que el CTE se refiera a sí mismo.
Parte Base: Selecciona el primer día del mes especificado.
Parte Recursiva: Añade un día a la fecha anterior hasta que la fecha exceda el último día del mes.
Resultado: Una tabla con una columna date que contiene cada día del mes.
2. marcaciones_completas
SQL

	marcaciones_completas AS (
		SELECT COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
    			COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal,
    			t.tur_entrada,
    			t.tur_salida,
    			p.par_valor_time,
				t.tur_tipo,
				e.tol_tiempo_interval,	
    			e.reg_hora AS reg_hora_entrada,
    			s.reg_hora AS reg_hora_salida,
    			-- Cálculo reg_horas_trabajadas (igual que en la vista `marcaciones_entradas_salidas`)
    			CASE
        			WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada
        				THEN s.reg_hora - t.tur_entrada
        			ELSE 
        				s.reg_hora - e.reg_hora
    			END AS reg_horas_trabajadas,
    			-- Cálculo reg_retraso (con ajuste por tolerancia especial y '00:00:59')
    			CASE
       				WHEN t.tur_tipo = 4 -- Si el tipo de turno es 4 (ej. "Ausente", "Libre"), no hay retraso
       					THEN '00:00:00'::interval
       				-- Si hay entrada y la hora de entrada es mayor que (entrada_turno + tolerancia_general + 59 segundos + tolerancia_especial)
       				WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval + e.tol_tiempo_interval ) 
       					THEN e.reg_hora - (t.tur_entrada + p.par_valor_time + e.tol_tiempo_interval)
    				ELSE 
    					'00:00:00'::interval
				END AS reg_retraso,
    			-- Cálculo reg_horas_extras (similar al de la vista `marcaciones_entradas_salidas`, simplificado ligeramente)
    			CASE
        			WHEN e.reg_hora IS NULL 
        				THEN NULL::interval
        			ELSE
            		CASE
                		WHEN s.reg_hora IS NULL 
                			THEN '00:00:00'::interval
                		WHEN e.reg_hora <= t.tur_entrada 
                			THEN s.reg_hora - t.tur_salida
                		ELSE 
                			s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
            		END
    			END AS reg_horas_extras
		FROM marcacion_entrada_adsoluta e
			FULL JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
			LEFT JOIN turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
    			AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
    			AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
			LEFT JOIN parametros p ON p.par_cod = t.tur_tolerancia
		WHERE COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
	),
Propósito: Combina las marcaciones de entrada y salida "absolutas" (marcacion_entrada_adsoluta, marcacion_salida_adsoluta), las une con los turnos y parametros (tolerancias generales), y calcula las reg_horas_trabajadas, reg_retraso y reg_horas_extras iniciales para cada día y empleado.
FULL JOIN: Es crucial para incluir días donde solo hay entrada o solo hay salida.
LEFT JOIN con turnos y parametros: Trae la información del turno asignado y la tolerancia general (par_valor_time).
e.tol_tiempo_interval: Esta columna proviene de la vista marcacion_entrada_adsoluta y representa una tolerancia especial individual o de grupo que podría aplicarse.
Cálculo reg_retraso (Diferencia clave con la vista anterior):
Si tur_tipo es 4 (ej. un día libre o tipo de turno que no aplica retraso), el retraso es 0.
Si no, y la hora de entrada real (e.reg_hora) es posterior a la tur_entrada más par_valor_time (tolerancia general) más 00:00:59 (casi un minuto) más e.tol_tiempo_interval (tolerancia especial), entonces se calcula el retraso. El + '00:00:59'::interval parece ser un pequeño buffer para redondear o asegurar que solo se detecte retraso si supera una tolerancia muy estricta (casi un minuto extra de buffer además de la tolerancia oficial). Si la hora de entrada está dentro de estas tolerancias, el retraso es 0.
Cálculo reg_horas_extras: Es similar al de la vista marcaciones_entradas_salidas, con la lógica de ajustar la salida programada si la entrada fue tarde pero dentro del tiempo de ajuste.
Filtro WHERE COALESCE(...) = param_reg_cod_personal: Solo procesa las marcaciones para el empleado especificado en el parámetro de la función.
3. ocurrencias_filtradas
SQL

	ocurrencias_filtradas AS (
		SELECT subquery.reg_cod_personal,
				subquery.reg_fecha,
				-- Agrega descripciones y tipos de ocurrencias en una sola cadena, ordenadas alfabéticamente
				STRING_AGG(subquery.ocu_descripcion::text, ', ' ORDER BY subquery.ocu_descripcion)::text AS ocu_descripcion, 
    			STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo)::text AS ocurrencia_tipo, 
				MIN(subquery.ocu_tipo) AS ocu_tipo, -- Toma el tipo de ocurrencia con el valor numérico más bajo (posiblemente para priorizar)
				STRING_AGG(subquery.tip_codigo::character varying, ', ' ORDER BY subquery.tip_codigo)::character varying AS tip_codigo, 
				MAX(subquery.ocu_horas_estaticas) AS ocu_horas_estaticas,
				SUM(subquery.ocu_horas_extras) AS ocu_horas_extras,
				SUM(subquery.ocu_horas_adicionales) AS ocu_horas_adicionales,
				SUM(subquery.ocu_horas_adicionales_100) AS ocu_horas_adicionales_100
		FROM (
				SELECT o.ocu_cod_persona AS reg_cod_personal,
      					-- Genera una serie de fechas para expandir el rango de la ocurrencia a días individuales
      					generate_series(
        					GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1)), -- Inicio: la mayor entre la fecha de inicio de la ocurrencia y el 1er día del mes
        						LEAST(
            						CASE -- Fin: la menor entre la fecha de fin de la ocurrencia (con manejo de ocu_fecha_desde = ocu_fecha_hasta)
                						WHEN o.ocu_fecha_desde = o.ocu_fecha_hasta 
                							THEN o.ocu_fecha_hasta
                					ELSE 
                						o.ocu_fecha_hasta
            						END,
            						(make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date -- y el último día del mes
        						) ,
        						'1 day'
    					)::date AS reg_fecha,
    					o.ocu_descripcion,
    					t.tip_descripcion AS ocurrencia_tipo,
    					t.tip_codigo,
    					o.ocu_tipo,
    					o.ocu_horas_estaticas,
    					o.ocu_horas_extras,
    					o.ocu_horas_adicionales,
    					o.ocu_horas_adicionales_100
				FROM ocurrencias o -- Tabla de ocurrencias (permisos, licencias, etc.)
					JOIN tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod -- Une con los tipos de ocurrencia para descripciones
				WHERE o.ocu_cod_persona = param_reg_cod_personal -- Filtra por el empleado
    			AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date -- Ocurrencia empieza en o antes del fin del mes
    			AND o.ocu_fecha_hasta >= make_date(anio, mes, 1) -- Ocurrencia termina en o después del inicio del mes
			) AS subquery
		WHERE NOT (
    			subquery.ocu_tipo = 1 -- Si el tipo de ocurrencia es 1 (posiblemente "Vacaciones")
    			AND 
    			(EXTRACT(DOW FROM subquery.reg_fecha::date) = 6 -- Y es sábado (6)
    			OR 
    			EXTRACT(DOW FROM subquery.reg_fecha::date) = 0) -- O es domingo (0)
			) -- Excluye los sábados y domingos para las vacaciones (tipo 1).
		GROUP BY subquery.reg_cod_personal, subquery.reg_fecha -- Agrupa por empleado y fecha para consolidar múltiples ocurrencias en un día
	),
Propósito: Identifica y consolida todas las ocurrencias (permisos, licencias, vacaciones, etc.) para el empleado y el mes dado, expandiendo los rangos de fecha de las ocurrencias a días individuales.
generate_series: Esencial para "expandir" una ocurrencia que dura varios días en filas individuales para cada día.
Filtros de Fecha (ocu_fecha_desde, ocu_fecha_hasta): Aseguran que solo se incluyan las ocurrencias que se superponen con el mes de interés.
WHERE NOT (...): Excluye ocurrencias de ocu_tipo = 1 (ej. Vacaciones) si caen en fines de semana (sábados o domingos). EXTRACT(DOW FROM date) devuelve el día de la semana (0=Domingo, 6=Sábado).
STRING_AGG: Concatena las descripciones y tipos si un empleado tiene múltiples ocurrencias en el mismo día.
MIN(ocu_tipo) / MAX(ocu_horas_estaticas) / SUM(...): Consolida otros valores de ocurrencia para cada día.
4. feriados_filtrados
SQL

	feriados_filtrados AS (
		SELECT f.fer_fecha AS reg_fecha,
    			f.fer_descripcion AS feriado_descripcion
		FROM feriados f
		WHERE EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
	),
Propósito: Filtra los feriados que caen dentro del mes y año especificados.
5. tolerancias_especiales_filtradas
SQL

	tolerancias_especiales_filtradas AS (
		SELECT te.tol_cod_personal,
    			te.tol_fecha_desde,
    			te.tol_fecha_hasta,
    			te.tol_descripcion,
    			te.tol_tiempo,
    			te.tol_tipo,
    			te.tol_sed_cod
		FROM tolerancias_especiales te
		WHERE (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal) -- Tolerancias individuales
    		OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal)) -- Tolerancias de grupo (por sede)
	),
Propósito: Obtiene las tolerancias especiales aplicables al empleado (individuales) o a su grupo/sede (grupales). No se filtra por fecha aquí, esto se hará en la consulta final al unir.
6. compensaciones_detalles_filtradas
SQL

	compensaciones_detalles_filtradas AS (
		SELECT com_cod_personal,
    			com_det_fecha,
    			SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,
    			SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,
    			SUM(com_det_horas_restantes) AS com_det_horas_restantes,
    			STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado
		FROM (SELECT c.com_cod_personal,
        				cd.com_det_fecha,
        				cd.com_det_horas_a_compensar,
        				cd.com_det_horas_compensadas,
        				cd.com_det_horas_restantes,
        				c.com_estado
    			FROM compensaciones_detalles cd
    				JOIN compensaciones_completas c ON cd.com_cod = c.com_cod
    			WHERE c.com_cod_personal = param_reg_cod_personal
        		AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio
        		AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes
				) sub
		GROUP BY com_cod_personal, com_det_fecha
	),
Propósito: Agrega los detalles de compensaciones (horas a compensar, compensadas, restantes, estado) por día para el empleado y mes. Esto es clave para determinar si las horas extras deben ser calculadas o si están sujetas a un esquema de compensación.
7. re_diaria
SQL

	re_diaria AS (
		SELECT c.date AS reg_fecha,
				COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
				-- ... otras columnas de p y of ...
				CASE
					-- Escenario excepcional: Ocurrencia tipo 12 (ej. Horas Estáticas) con ocu_horas_estaticas = 1
					WHEN of.ocu_tipo = 12 AND of.ocu_horas_estaticas = 1 
						THEN of.ocu_horas_extras::interval	
    				-- Escenario 1: Si hay horas pendientes de compensar (`com_det_horas_restantes` > 0), no se calculan horas extras `re`.
    				WHEN cd.com_det_horas_restantes > '00:00:00'::interval 
    					THEN '00:00:00'::interval
    				-- Escenario 2: Si la persona llegó tarde (`reg_retraso` > 0) y NO tiene permisos/ocurrencias específicos (33, 26, 12, 29), no se calculan horas extras `re`.
    				WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
        				SELECT 1 FROM ocurrencias_filtradas of WHERE of.reg_fecha = c.date AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN '00:00:00'::interval
					-- Nuevo Escenario (muy específico): Si hay ocurrencia tipo 12 Y retraso > 59 segundos.
    				WHEN EXISTS (SELECT 1 FROM ocurrencias_filtradas of WHERE of.reg_fecha = c.date AND of.ocu_tipo = 12) AND p.reg_retraso > '00:59:59'::interval 
    					THEN
        					CASE
            					WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
            						THEN LEAST((p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval, '02:00:00'::interval)
            					ELSE '00:00:00'::interval
        					END
    				-- Escenario 3: Si NO hay horas pendientes (`com_det_horas_restantes = 0`), PERO SÍ hay permisos/ocurrencias específicos (33, 26, 12, 29), calcular `re` con reglas especiales.
    				WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
        				SELECT 1 FROM ocurrencias_filtradas of WHERE of.reg_fecha = c.date AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN
        			CASE
						-- Sub-escenario 3.1: Ocurrencia tipo 12 Y retraso > 59 segundos.
						WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval 
							THEN
	            				CASE
	                				WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
	                					THEN LEAST((p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval, '02:00:00'::interval)
	                				ELSE '00:00:00'::interval
	            				END
            			-- Sub-escenario 3.2: Ocurrencia tipo 29.
            			WHEN of.ocu_tipo = 29 
            				THEN
                				CASE
                    				WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > '09:00:00'::interval 
                    					THEN LEAST((p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - '08:00:00'::interval, '02:00:00'::interval)
                    				ELSE '00:00:00'::interval
                				END
            				-- Sub-escenario 3.3: Otros tipos de ocurrencias (33, 26).
            				ELSE
                				CASE
                    				WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
                    					THEN LEAST((p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval, '02:00:00'::interval)
                    				ELSE '00:00:00'::interval
                				END
        					END
    					-- Escenario 4: Si no hay horas pendientes Y no hay permisos específicos.
    					WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (
        						SELECT 1 FROM ocurrencias_filtradas of WHERE of.reg_fecha = c.date AND of.ocu_tipo IN (33, 26, 12, 29)
    						) 
    						THEN '00:00:00'::interval
        				-- Escenario 5 (General): Si ninguna de las condiciones anteriores aplica, calcula `re` si las horas trabajadas superan las 9h, limitando a 2h de RE.
    					WHEN p.reg_horas_trabajadas > '09:00:00'::interval 
    						THEN LEAST(p.reg_horas_trabajadas - '08:00:00'::interval, '02:00:00'::interval)
    					-- En caso contrario, `re` es 0.
    					ELSE '00:00:00'::interval
					END AS re,
					-- ... otras columnas de compensación y ocurrencias ...
		FROM calendar c
			LEFT JOIN marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
			LEFT JOIN ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal
			LEFT JOIN compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal
	),
Propósito: Esta es una de las CTEs más complejas. Une el calendar (todos los días del mes) con las marcaciones_completas, ocurrencias_filtradas y compensaciones_detalles_filtradas para calcular las Horas Extras Diarias (re) aplicando una serie de reglas de negocio intrincadas.
LEFT JOIN: Se usan LEFT JOIN con marcaciones_completas, ocurrencias_filtradas y compensaciones_detalles_filtradas para asegurar que cada día del calendario esté presente, incluso si no hay marcaciones, ocurrencias o compensaciones para ese día.
Lógica de re (Recargo Extraordinario / Horas Extras): Contiene múltiples CASE WHEN para aplicar reglas de negocio sobre cuándo se pagan horas extras, dependiendo de:
Horas Estáticas (ocu_tipo = 12): Puede haber un valor fijo de horas extras.
Horas Pendientes de Compensar: Si el empleado tiene horas restantes por compensar, no genera RE.
Retrasos: Si el empleado llega tarde y no tiene un permiso/ocurrencia específica, no genera RE.
Ocurrencias Específicas (ocu_tipo IN (33, 26, 12, 29)): Estas ocurrencias (permisos, licencias, etc.) modifican el cálculo de RE.
Horas Trabajadas (reg_horas_trabajadas): Si supera un umbral (ej. 9 horas), se calcula RE.
Límites: El LEAST función limita las horas extras a un máximo (ej. 2 horas).
Esta lógica es el corazón de las reglas de negocio para determinar las horas extras diarias.
8. re_semanal
SQL

	re_semanal AS (
		SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week,
				LEAST( -- Limita el total semanal a un máximo
					COALESCE(
						SUM( -- Suma las RE diarias
							CASE
								WHEN rd.re >= '01:00:00' -- Solo suma RE si es al menos 1 hora
									THEN LEAST(rd.re, '02:00:00'::interval) -- Limita cada día a 2 horas de RE para la suma semanal
								ELSE 
									'00:00:00'::interval
							END
						) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5), -- SOLO SUMA RE de Lunes a Viernes
						'00:00:00'::interval -- Si no hay RE, COALESCE a 0
					),
					'08:00:00'::interval -- Límite semanal: el total de RE semanal no puede exceder 8 horas
				) AS re_semanal_suma
		FROM re_diaria rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha) -- Agrupa por empleado y semana
	),
Propósito: Calcula la suma total de re por empleado a nivel semanal, aplicando límites.
EXTRACT(WEEK FROM rd.reg_fecha): Agrupa por número de semana ISO.
LEAST(SUM(...) , '08:00:00'::interval): La suma semanal total de re está limitada a un máximo de 8 horas.
FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5): Solo se consideran las horas extras de Lunes a Viernes (ISODOW 1=Lunes, 5=Viernes) para esta suma semanal.
Límite diario para la suma: LEAST(rd.re, '02:00:00'::interval) indica que, aunque un día pueda tener más de 2 horas de RE, para la suma semanal solo se cuentan hasta 2 horas por día.
9. re_mensual
SQL

	re_mensual AS (
		SELECT rs.reg_cod_personal,
				LEAST( -- Limita el total mensual a un máximo
					SUM(rs.re_semanal_suma), -- Suma las RE semanales ya limitadas
					'32:00:00'::interval -- Límite mensual: el total de RE mensual no puede exceder 32 horas
				) AS re_mensual_suma
		FROM re_semanal rs
		GROUP BY rs.reg_cod_personal -- Agrupa por empleado para obtener el total mensual
	),
Propósito: Calcula la suma total de re por empleado a nivel mensual, aplicando límites.
LEAST(SUM(...) , '32:00:00'::interval): La suma mensual total de re está limitada a un máximo de 32 horas.
10. re_acumulada_semanal
SQL

	re_acumulada_semanal AS (
		SELECT rd.reg_cod_personal,
				rd.reg_fecha,
				EXTRACT(WEEK FROM rd.reg_fecha) AS semana,
				rd.re,
				SUM(rd.re) OVER (
					PARTITION BY rd.reg_cod_personal, -- Acumula por empleado
					EXTRACT(YEAR FROM rd.reg_fecha), -- Por año
					EXTRACT(WEEK FROM rd.reg_fecha) -- Y por semana
					ORDER BY rd.reg_fecha ROWS UNBOUNDED PRECEDING -- Suma todas las RE desde el inicio de la semana hasta la fecha actual
				) AS re_acumulada_semanal
		FROM re_diaria rd
		WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5  -- Considerar solo días de lunes a viernes
	),
Propósito: Calcula un total acumulado de re por semana, reiniciándose cada semana, solo considerando los días hábiles (Lunes a Viernes). Esto es un "running total" semanal.
11. re_mensual_con_limited
SQL

	re_mensual_con_limited AS (
		SELECT rsa.reg_cod_personal,
				rsa.reg_fecha,
				rsa.re,
				CASE
					-- Si la suma acumulada semanal es MAYOR O IGUAL a 8 horas, entonces las RE de ese día (para efectos de la suma mensual) se vuelven 0
					WHEN rsa.re_acumulada_semanal > '08:00:00'::interval 
						THEN '00:00:00'::interval
					-- Si la suma acumulada semanal AÚN NO LLEGA a 8 horas, se mantiene la RE original del día
					ELSE 
						rsa.re
				END AS re_con_limited -- Las RE diarias, ajustadas para no exceder el límite semanal de 8h en la acumulación mensual.
		FROM re_acumulada_semanal rsa
	),
Propósito: Ajusta las re diarias para el cálculo de la acumulación mensual, asegurándose de que la re semanal no exceda las 8 horas por semana. Si la acumulación semanal ya alcanzó las 8 horas, las re del día se anulan a 0 para el propósito de la suma mensual.
12. re_acumulada_mensual
SQL

	re_acumulada_mensual AS (
		SELECT rml.reg_cod_personal,
				rml.reg_fecha,
				SUM(rml.re_con_limited) OVER (
					PARTITION BY rml.reg_cod_personal ORDER BY rml.reg_fecha -- Acumula por empleado a lo largo del mes
				) AS re_acumulada_mensual -- RE acumulada mensual, respetando el tope semanal de 8h.
		FROM re_mensual_con_limited rml
	),
Propósito: Calcula un total acumulado de re por mes, utilizando las re_con_limited (que ya respetan el tope semanal), para llevar un registro del total mensual acumulado día a día.
13. ra (Recargo Adicional)
SQL

	ra AS (
		SELECT rd.reg_cod_personal,
				rd.reg_fecha,
				-- ... otras columnas de rd, ras, ram ...
				CASE
					-- Escenario excepcional: Ocurrencia tipo 12 (Horas Estáticas) con ocu_horas_estaticas = 1
					WHEN rd.ocu_tipo = 12 AND rd.ocu_horas_estaticas = 1 
						THEN rd.ocu_horas_adicionales::interval+rd.ocu_horas_adicionales_100::interval
					-- Si es sábado (`ISODOW = 6`), el RA es el total de horas trabajadas (`reg_horas_trabajadas`).
					WHEN EXTRACT(ISODOW FROM rd.reg_fecha) = 6 
						THEN rd.reg_horas_trabajadas
					-- Si `re` es menor a 1 hora, RA es 0.
					WHEN rd.re < '01:00:00'::interval 
						THEN '00:00:00'::interval		
					-- Validación 1: Si la RE acumulada semanal (`ras.re_acumulada_semanal`) es mayor a 8 horas.
					WHEN ras.re_acumulada_semanal > '08:00:00'::interval 
						THEN
							CASE
								-- Si las horas trabajadas son más de 9 horas, RA es (Horas Trabajadas - 8 horas).
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas  - '08:00:00'::interval
								ELSE 
									'00:00:00'::interval
							END
					-- Validación 2: Si la RE acumulada mensual (`ram.re_acumulada_mensual`) está entre 32 y 33:59:59 horas.
					WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval 
						THEN
							CASE
								-- Si las horas trabajadas son más de 9 horas, RA es (Horas Trabajadas - 9 horas).
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas - '09:00:00'::interval
								ELSE 
								'00:00:00'::interval
							END
					-- Validación 3: Si la RE acumulada mensual (`ram.re_acumulada_mensual`) es mayor a 34 horas.
					WHEN ram.re_acumulada_mensual > '34:00:00'::interval 
						THEN
							CASE
								-- Si las horas trabajadas son más de 9 horas, RA es (Horas Trabajadas - 8 horas).
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas - '08:00:00'::interval
								ELSE 
									'00:00:00'::interval
							END
						-- Cálculo general: Si ninguna de las validaciones anteriores aplica.
					ELSE
						CASE
							-- Si las horas trabajadas son más de 10 horas, RA es (Horas Trabajadas - 10 horas).
							WHEN rd.reg_horas_trabajadas > '10:00:00'::interval 
								THEN rd.reg_horas_trabajadas - '10:00:00'::interval
							ELSE 
								'00:00:00'::interval
						END
				END AS ra	 
		FROM re_diaria rd
			LEFT JOIN re_acumulada_semanal ras ON rd.reg_cod_personal = ras.reg_cod_personal AND rd.reg_fecha = ras.reg_fecha
			LEFT JOIN re_acumulada_mensual ram ON rd.reg_cod_personal = ram.reg_cod_personal AND rd.reg_fecha = ram.reg_fecha
	),
Propósito: Esta es otra CTE compleja que calcula el Recargo Adicional (ra). Utiliza re_diaria, re_acumulada_semanal y re_acumulada_mensual para aplicar diversas reglas de negocio sobre cuándo y cómo se calculan las ra.
Lógica de ra: Contiene múltiples CASE WHEN para determinar las ra basadas en:
Horas Estáticas (ocu_tipo = 12): Puede haber un valor fijo de RA.
Sábados: Si es sábado, las ra son las reg_horas_trabajadas (indicando que todo el trabajo en sábado puede considerarse RA).
re diario: Si el re diario es menos de 1 hora, no hay ra.
Límites de re acumulada semanal/mensual: Las ra se calculan de manera diferente si las re acumuladas ya alcanzaron ciertos umbrales semanales o mensuales. Esto indica que hay una jerarquía o un sistema de "cups" entre re y ra.
Horas Trabajadas: Se compara con umbrales como 9h o 10h.
14. ra_semanal_suma
SQL

	ra_semanal_suma AS (
		SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week,
				SUM(
					CASE
						WHEN rd.ra IS NOT NULL 
							THEN rd.ra
						ELSE 
							'00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_semanal_suma -- Incluye sábados (hasta ISODOW = 6)
		FROM ra rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
Propósito: Suma las ra por empleado a nivel semanal.
FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6): Incluye los sábados para la suma semanal de ra.
15. ra_mensual_suma
SQL

	ra_mensual_suma AS (
		SELECT rs.reg_cod_personal,
				SUM(rs.ra_semanal_suma) AS ra_mensual_suma
		FROM ra_semanal_suma rs
		GROUP BY rs.reg_cod_personal
	),
Propósito: Suma las ra por empleado a nivel mensual a partir de las sumas semanales.
16. ra_dividida
SQL

	ra_dividida AS (
		SELECT ra.reg_cod_personal,
				ra.reg_fecha,
				ra.ra,  -- El valor de RA calculado previamente
				ra.reg_hora_salida, -- Hora de salida
				-- ... otras columnas ...
    
				-- Cálculo de RA_80 (recargo adicional al 80%)
				CASE
					--Calculo excepcional ocu tipo 12  horas estaticas
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales::interval
					-- Si es sábado, RA_80 es siempre '00:00:00' (se asume que los sábados van a RA_100)
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN '00:00:00'::interval
					-- Si la hora de salida es antes o igual a las 19:59:59, todo el RA se considera RA_80.
					WHEN ra.reg_hora_salida <= '19:59:59'::time 
						THEN ra.ra
					-- Si la hora de salida es después de las 19:59:59, RA_80 es la parte del RA que fue antes de las 19:59:59.
					ELSE 
						ra.ra - (ra.reg_hora_salida - '19:59:59'::time)::interval
				END AS ra_80,
    
				-- Cálculo de RA_100 (recargo adicional al 100%)
				CASE
					--Calculo excepcional ocu tipo 12  horas estaticas
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales_100::interval
					-- Si es sábado, RA_100 es el total de horas trabajadas (ya que en RA_80 se puso 0).
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN ra.reg_horas_trabajadas
					-- Si la hora de salida es después de las 19:59:59, RA_100 es la parte del RA que fue después de las 19:59:59 (limitado al RA total).
					WHEN ra.reg_hora_salida > '19:59:59'::time 
						THEN LEAST(ra.ra, (ra.reg_hora_salida - '19:59:59'::time)::interval)
					-- Si la hora de salida es antes de las 19:59:59, no hay RA_100.
					ELSE 
						'00:00:00'::interval
				END AS ra_100
		FROM ra
	),
Propósito: Divide las ra calculadas previamente en ra_80% y ra_100% basándose en la hora de salida (19:59:59 parece ser el punto de corte para recargos diferentes) y si es sábado.
Lógica ra_80 / ra_100:
Horas Estáticas (ocu_tipo = 12): Valores fijos para RA_80 y RA_100.
Sábados: Las horas de los sábados (ISODOW = 6) se asignan completamente a ra_100 y ra_80 es 0.
Punto de Corte 19:59:59: Las horas ra antes de las 20:00 se consideran ra_80. Las horas ra después de las 20:00 (o si es sábado) se consideran ra_100.
17. ra_divida_semanal_suma
SQL

	ra_divida_semanal_suma AS (
		SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week,
				SUM(
					CASE
						WHEN rd.ra_80 IS NOT NULL AND rd.ra_80 > '00:00:00'::interval 
							THEN rd.ra_80
						ELSE 
							'00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal, -- Suma RA_80 de Lunes a Viernes
				SUM(
					CASE
						WHEN rd.ra_100 IS NOT NULL 
							THEN rd.ra_100
						ELSE 
							'00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal -- Suma RA_100 de Lunes a Sábado
		FROM ra_dividida rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
Propósito: Suma ra_80 y ra_100 por empleado a nivel semanal.
Filtros de día de la semana: ra_80_semanal solo suma de Lunes a Viernes, mientras que ra_100_semanal suma de Lunes a Sábado.
18. ra_dividia_mensual_suma
SQL

	ra_dividia_mensual_suma AS (
		SELECT 
			rs.reg_cod_personal,
			SUM(rs.ra_80_semanal) AS ra_80_mensual,
			SUM(rs.ra_100_semanal) AS ra_100_mensual
		FROM 
			ra_divida_semanal_suma rs
		GROUP BY 
		rs.reg_cod_personal
	),
Propósito: Suma ra_80_semanal y ra_100_semanal por empleado a nivel mensual.
19. re_recalculada
SQL

	re_recalculada AS (
		SELECT ras.reg_cod_personal,
				ras.reg_fecha,
				rd.reg_horas_trabajadas,
				ras.re,
				ras.re_acumulada_semanal,
				CASE
					-- Si la RE acumulada semanal ya alcanzó o superó las 8 horas.
					WHEN ras.re_acumulada_semanal >= '08:00:00'::interval THEN
						CASE
							-- Si las horas trabajadas son más de 9 horas
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
								-- Recalcula RE restando el exceso semanal de las 8 horas.
								THEN ras.re - (ras.re_acumulada_semanal - '08:00:00'::interval)
							ELSE
								'00:00:00'::interval -- Si no, RE es 0.
						END
					ELSE
						-- Si la RE acumulada semanal NO ha alcanzado 8 horas, devuelve 0 por defecto aquí.
						-- Esto puede parecer contraintuitivo, pero se usa para "ajustar" el RE final en la SELECT principal.
						'00:00:00'::interval
				END AS re_recalculada
		FROM re_acumulada_semanal ras
			JOIN re_diaria rd ON ras.reg_cod_personal = rd.reg_cod_personal AND ras.reg_fecha = rd.reg_fecha
	)
Propósito: Este CTE realiza un re-cálculo final de re por día, asegurándose de que la cantidad total semanal no exceda el límite de 8 horas, y "ajustando" las horas extras del último día que excedería el tope.
Lógica: Si la re_acumulada_semanal (running total) ya superó las 8 horas en un día determinado, entonces la re_recalculada para ese día se ajusta restándole el exceso acumulado, o se pone a 0. Esto evita que la suma final exceda el tope.
Consulta Principal (SELECT) y Uniones Finales:
SQL

	SELECT r.reg_fecha,
			r.reg_cod_personal,
			p.tur_entrada,
			p.tur_salida,
			p.par_valor_time,
			p.reg_hora_entrada,
			p.reg_hora_salida,
			p.reg_horas_trabajadas,
			p.reg_retraso,
			p.reg_horas_extras,
			-- Uso condicional de 're_recalculada'
			CASE
				WHEN re_rec.re_recalculada <> '00:00:00'::interval THEN re_rec.re_recalculada
				ELSE r.re
			END AS re, -- Aquí se elige el RE final: el recalculado si no es cero, sino el diario original
			r.horas_a_compensar,
			r.horas_compensadas,
			r.horas_restantes,
			r.estado_compensacion,
			s.re_semanal_suma,
			m.re_mensual_suma,
			ra_semanal.re_acumulada_semanal, -- RE acumulada semanal (running total)
			ra_mensual.re_acumulada_mensual, -- RE acumulada mensual (running total)
			ra.ra AS horas_adicionales, -- Recargo Adicional total
			ras.ra_semanal_suma,         -- Suma semanal de RA
			ma.ra_mensual_suma,          -- Suma mensual de RA
			ra_dividida.ra_80,           -- Recargo Adicional 80% diario
			ra_dividida.ra_100,          -- Recargo Adicional 100% diario
			rds.ra_80_semanal,           -- Suma semanal de RA 80%
			rds.ra_100_semanal,          -- Suma semanal de RA 100%
			rdm.ra_80_mensual,           -- Suma mensual de RA 80%
			rdm.ra_100_mensual,          -- Suma mensual de RA 100%
			-- Cálculo del día de la semana en texto
			btrim(
				CASE
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
				ELSE 
					NULL
				END
			) AS dia_semana,
			of.ocu_descripcion AS ocurrencia_descripcion,
			of.ocurrencia_tipo,
			of.ocu_tipo,
			of.tip_codigo,
			ff.feriado_descripcion,
			-- Formato de la tolerancia especial (individual o de grupo)
			CASE
				WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta 
					THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta 
					THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				ELSE 
					NULL
			END AS tolerancia_especial
	FROM re_diaria r -- La CTE principal que ya contiene todos los días del mes y las RE diarias
		LEFT JOIN marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
		LEFT JOIN re_recalculada re_rec ON r.reg_cod_personal = re_rec.reg_cod_personal AND r.reg_fecha = re_rec.reg_fecha -- Para el ajuste final de RE
		LEFT JOIN ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
		LEFT JOIN feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
		LEFT JOIN tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta -- Unión con tolerancias por rango de fecha
		LEFT JOIN re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
		LEFT JOIN re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
		LEFT JOIN re_acumulada_semanal ra_semanal ON r.reg_cod_personal = ra_semanal.reg_cod_personal AND r.reg_fecha = ra_semanal.reg_fecha
		LEFT JOIN re_acumulada_mensual ra_mensual ON r.reg_cod_personal = ra_mensual.reg_cod_personal AND r.reg_fecha = ra_mensual.reg_fecha
		LEFT JOIN ra ra ON r.reg_cod_personal = ra.reg_cod_personal AND r.reg_fecha = ra.reg_fecha
		LEFT JOIN ra_dividida ON ra.reg_cod_personal = ra_dividida.reg_cod_personal AND ra.reg_fecha = ra_dividida.reg_fecha
		LEFT JOIN ra_semanal_suma ras ON r.reg_cod_personal = ras.reg_cod_personal 
			AND EXTRACT(WEEK FROM r.reg_fecha) = ras.week 
			AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		LEFT JOIN ra_mensual_suma ma ON r.reg_cod_personal = ma.reg_cod_personal
		LEFT JOIN ra_divida_semanal_suma rds ON r.reg_cod_personal = rds.reg_cod_personal 
			AND EXTRACT(WEEK FROM r.reg_fecha) = rds.week 
			AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		LEFT JOIN ra_dividia_mensual_suma rdm ON r.reg_cod_personal = rdm.reg_cod_personal
	ORDER BY r.reg_fecha, r.reg_cod_personal;
Propósito: Esta es la consulta final que une todos los CTEs previamente calculados.
FROM re_diaria r: Se toma re_diaria como la base, ya que contiene todos los días del mes y las RE iniciales.
LEFT JOIN: Todas las demás CTEs se unen utilizando LEFT JOIN para asegurar que cada día del calendario para el empleado esté presente, incluso si no hay datos de otras CTEs para ese día. Las condiciones de unión son principalmente por fecha y código de personal.
Selección de Columnas: Todas las columnas de la tabla de retorno de la función se seleccionan de las CTEs unidas.
CASE para re final: Aquí se decide cuál valor de re se muestra: el re_recalculada si no es cero (es decir, si hubo un ajuste por el tope semanal), de lo contrario, el re diario original.
dia_semana: Convierte el número de día de la semana (1-7) a su nombre textual (LUNES, MARTES, etc.).
tolerancia_especial: Muestra la descripción y el tiempo de la tolerancia especial aplicable al día, si existe y es vigente.
ORDER BY: Ordena el resultado por fecha y luego por código de personal, asegurando un informe cronológico.
En Resumen, ¿Qué hace toda esta función?
La función marcaciones_por_mes_horas5 es un motor de cálculo de asistencia muy sofisticado. Para un empleado y un mes dados, itera por cada día, identifica sus marcaciones de entrada y salida "absolutas", las compara con su turno programado y tolerancias, y luego aplica un conjunto complejo de reglas de negocio para calcular:

Horas trabajadas
Retrasos
Horas extras (RE), con reglas que consideran:
Presencia de ocurrencias (permisos, etc.)
Estado de compensaciones (horas pendientes)
Límites máximos de RE a nivel diario (implícito), semanal (8h) y mensual (32h).
Recálculos para asegurar el cumplimiento de estos límites.
Horas adicionales (RA), también con reglas que consideran:
Sábados
Niveles de RE acumulada
Umbrales de horas trabajadas.
División de RA en RA 80% y RA 100% según la hora de salida y el día.
Provee información adicional como ocurrencias, feriados y detalles de compensación, todo presentado en un formato de tabla diaria para el mes completo.
Es una función de reporte muy completa que automatiza gran parte de la lógica de negocio de gestión de tiempo y asistencia.








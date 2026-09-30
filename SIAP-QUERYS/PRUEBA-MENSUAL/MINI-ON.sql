CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas5Modificada(
	anio integer, -- El año para el cual se generará el reporte.
	mes integer, -- El mes para el cual se generará el reporte.
	param_reg_cod_personal integer -- El código del empleado específico para el cual se generará el informe.
	)
	-- Su propósito es generar un reporte detallado de las marcaciones mensuales de un empleado, incluyendo cálculos avanzados de horas trabajadas, retrasos, horas extras (RE), y horas adicionales (RA en diferentes porcentajes), aplicando una serie de reglas de negocio intrincadas.
	-- La función toma como entrada un año, un mes y el código de personal, y devuelve una tabla con una gran cantidad de columnas que resumen la actividad diaria del empleado para ese mes.

RETURNS TABLE(	
				-- La función devuelve una tabla con una larga lista de columnas, que incluye datos de marcación, turno, parámetros, cálculos de tiempo, información de ocurrencias (permisos/ausencias), feriados y tolerancias especiales.
				reg_fecha date,								-- Fecha del registro.
				reg_cod_personal integer,					-- Código del personal.
				tur_entrada time without time zone,			-- Hora de entrada programada del turno.
				tur_salida time without time zone,			-- Hora de salida programada del turno.
				par_valor_time interval,					-- Valor de la tolerancia general del turno.
				reg_hora_entrada time without time zone,	-- Hora de la marcación de entrada del empleado.
				reg_hora_salida time without time zone,		-- Hora de la marcación de salida del empleado.
				reg_horas_trabajadas interval,				-- Horas trabajadas calculadas.
				reg_retraso interval,						-- Retraso calculado.
				reg_horas_extras interval,					-- Horas extras iniciales (RE).
				re interval,					-- Horas de Recargo Extra (RE) final, ya con reglas de negocio.
				horas_a_compensar interval,		-- Horas a compensar (de registros de compensación).
				horas_compensadas interval,					-- Horas ya compensadas.
				horas_restantes interval,					-- Horas restantes por compensar.
				estado_compensacion character varying,		-- Estado de la compensación.
				re_semanal_suma interval,					-- Suma semanal de RE.
				re_mensual_suma interval,					-- Suma mensual de RE.
				re_acumulada_semanal interval,				-- RE acumulada dentro de la semana.
				re_acumulada_mensual interval,				-- RE acumulada dentro del mes.
				ra interval,								-- Horas de Recargo Adicional (RA) inicial.
				ra_semanal_suma interval,					-- Suma semanal de RA. 
				ra_mensual_suma interval,					-- Suma mensual de RA.
				ra_80 interval,								-- Horas de Recargo Adicional al 80%.
				ra_100 interval,							-- Horas de Recargo Adicional al 100%.
				ra_80_semanal interval,						-- Suma semanal de RA al 80%.
				ra_100_semanal interval,					-- Suma semanal de RA al 100%.
				ra_80_mensual interval,						-- Suma mensual de RA al 80%.
				ra_100_mensual interval,					-- Suma mensual de RA al 100%.
				dia_semana text,						-- Nombre del día de la semana (Lunes, Martes, etc.).
				ocurrencia_descripcion text,	-- Descripción de las ocurrencias (permisos, licencias, etc.).
				ocurrencia_tipo text,						-- Tipo de ocurrencia.
				ocu_tipo integer,							-- Código del tipo de ocurrencia.
				tip_codigo character varying,				-- Código del tipo de ocurrencia (ej. "VAC", "PER").
				feriado_descripcion character varying,		-- Descripción del feriado (si aplica).
				tolerancia_especial text					-- Descripción de la tolerancia especial aplicada.
			)
LANGUAGE plpgsql
AS 
$function$
BEGIN
	/*
	 * Estas líneas establecen configuraciones de sesión para la función. Aseguran que la manipulación de 
	 fechas y tiempos sea consistente (UTC para la zona horaria y DMY para el estilo de fecha) sin importar 
	 la configuración global del servidor o del cliente.
	*/
	PERFORM set_config('timezone', 'UTC', true); 		-- Configura la zona horaria a UTC para la sesión actual. Importante para consistencia en cálculos de tiempo.
	PERFORM set_config('DateStyle', 'ISO, DMY', true); 	-- Configura el estilo de fecha a ISO, DMY (Día-Mes-Año).
	
	
	RETURN QUERY -- Indica que el resultado de la siguiente consulta (que contiene múltiples CTEs) será el resultado devuelto por la función.
	
	-- CTEs (Common Table Expressions - Bloques WITH):
	-- Aquí es donde reside la mayor parte de la lógica. Cada CTE prepara un conjunto de datos intermedio que luego se utiliza en CTEs posteriores o en la consulta final.

	
	/*
	 * calendar (Generador de Fechas del Mes):
	 - Crea una tabla temporal calendar que contiene todas las fechas día por día para el mes y año 
	 especificados en los parámetros de la función. Es fundamental para asegurar que el informe incluya 
	 todos los días del mes, incluso aquellos sin marcaciones.
	*/
	WITH RECURSIVE calendar AS (
		SELECT DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date -- Selecciona el primer día del mes dado por 'anio' y 'mes'
		UNION ALL								-- Une con los siguientes días de forma recursiva
		SELECT (date + INTERVAL '1 day')::DATE	-- Suma un día a la fecha anterior
		FROM calendar
		WHERE date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month' -- Condición para detener la recursión: hasta el último día del mes
	),

	/*
	 * marcaciones_completas (Marcaciones con Turnos y Cálculos Básicos):
	 - Centraliza las marcaciones de entrada y salida, les asocia el turno correspondiente y sus 
	 tolerancias, y realiza los cálculos iniciales de reg_horas_trabajadas, reg_retraso (con un ajuste 
	 de 59 segundos de gracia y tolerancia especial) y reg_horas_extras. Todo esto, filtrado para el 
	 param_reg_cod_personal de la función.
	*/
	marcaciones_completas AS (
		SELECT COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha, -- Fecha consolidada (de entrada o salida)
    			COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal, -- Código de personal consolidado
    			t.tur_entrada,					-- Hora de entrada programada del turno
    			t.tur_salida,					-- Hora de salida programada del turno
    			p.par_valor_time,				-- Valor del parámetro de tolerancia general
				t.tur_tipo,						-- Tipo de turno
				e.tol_tiempo_interval,			-- Tolerancia especial (obtenida de marcacion_entrada_adsoluta)
    			e.reg_hora AS reg_hora_entrada,	-- Hora de la marcación de entrada
    			s.reg_hora AS reg_hora_salida,	-- Hora de la marcación de salida
				-- Cálculo de Horas Trabajadas (igual que en la vista marcaciones_entradas_salidas)
    			CASE
        			WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada 
        				THEN s.reg_hora - t.tur_entrada
        			ELSE 
        				s.reg_hora - e.reg_hora
    			END AS reg_horas_trabajadas,
				-- Cálculo de Retraso (ajustado para incluir tolerancia especial y un segundo de gracia)
    			CASE
       				WHEN t.tur_tipo = 4 
       					THEN '00:00:00'::interval
       				WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval + e.tol_tiempo_interval ) 
       					THEN e.reg_hora - (t.tur_entrada + p.par_valor_time + e.tol_tiempo_interval)
    				ELSE 
    					'00:00:00'::interval
				END AS reg_retraso,
				-- Cálculo de Horas Extras Iniciales (igual que en la vista marcaciones_entradas_salidas)
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
		FROM marcacion_entrada_adsoluta e -- Vista de entradas absolutas
			FULL JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal -- Se unen entradas y salidas, incluyendo días donde solo hay una.
			LEFT JOIN turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
    			AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
    			AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha)) -- Se unen los turnos vigentes para esa fecha y personal.
			LEFT JOIN parametros p ON p.par_cod = t.tur_tolerancia -- Se unen los parámetros de tolerancia asociados al turno.
		WHERE COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal -- **FILTRO CLAVE**: Limita los resultados al empleado pasado como parámetro.
	),

	/*
	 * ocurrencias_filtradas (Eventos y Ausencias):
	 - Identifica y consolida todas las "ocurrencias" (permisos, licencias, vacaciones, etc.) aplicables 
	 a un empleado durante el mes. Utiliza generate_series para "expandir" las ocurrencias de rango de 
	 fechas a días individuales y luego las agrupa para manejar múltiples ocurrencias en un mismo día. 
	 Excluye fines de semana para ciertos tipos de ocurrencia (ej. vacaciones).
	*/
	/*ocurrencias_filtradas AS (
		SELECT subquery.reg_cod_personal,
				subquery.reg_fecha,
				STRING_AGG(subquery.ocu_descripcion::text, ', ' ORDER BY subquery.ocu_descripcion)::text AS ocu_descripcion, -- Agrupa descripciones de ocurrencias por día
    			STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo)::text AS ocurrencia_tipo, -- Agrupa tipos de ocurrencias por día
				MIN(subquery.ocu_tipo) AS ocu_tipo,
				STRING_AGG(subquery.tip_codigo::character varying, ', ' ORDER BY subquery.tip_codigo)::character varying AS tip_codigo, -- Agrupa códigos de tipo (ej. "VAC", "PER")
				MAX(subquery.ocu_horas_estaticas) AS ocu_horas_estaticas, -- Máximo de horas estáticas
				SUM(subquery.ocu_horas_extras) AS ocu_horas_extras,	-- Suma de horas extras de ocurrencias
				SUM(subquery.ocu_horas_adicionales) AS ocu_horas_adicionales, -- Suma de horas adicionales de ocurrencias (RA 80%)
				SUM(subquery.ocu_horas_adicionales_100) AS ocu_horas_adicionales_100 -- Suma de horas adicionales de ocurrencias (RA 100%)
		FROM (
				SELECT o.ocu_cod_persona AS reg_cod_personal,
      					generate_series(
        					GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1)), -- Inicia desde la fecha de inicio de la ocurrencia o el inicio del mes, el que sea posterior
        						LEAST(
            						CASE 
                						-- Mantener tus condiciones existentes
                						WHEN o.ocu_fecha_desde = o.ocu_fecha_hasta 
                							THEN o.ocu_fecha_hasta
                					ELSE 
                						o.ocu_fecha_hasta
            						END,
            						(make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date -- Termina en la fecha de fin de la ocurrencia o el fin del mes, el que sea anterior
        						) ,  -- Añadimos un día al límite superior
        						'1 day'
    					)::date AS reg_fecha, -- Genera una fila por cada día que la ocurrencia está vigente en el mes
    					o.ocu_descripcion,
    					t.tip_descripcion AS ocurrencia_tipo,
    					t.tip_codigo,
    					o.ocu_tipo,
    					o.ocu_horas_estaticas,
    					o.ocu_horas_extras,
    					o.ocu_horas_adicionales,
    					o.ocu_horas_adicionales_100
				FROM ocurrencias o
					JOIN tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod -- Une con los tipos de ocurrencias para obtener descripciones
				WHERE o.ocu_cod_persona = param_reg_cod_personal -- Filtra para el empleado específico
    			AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date -- Ocurrencia debe iniciar en o antes del fin del mes
    			AND o.ocu_fecha_hasta >= make_date(anio, mes, 1) -- Ocurrencia debe terminar en o después del inicio del mes
			) AS subquery
		WHERE NOT (
    			subquery.ocu_tipo = 1 -- Excluye ciertos tipos de ocurrencia (ej. si ocu_tipo 1 es vacaciones)
    			AND 
    			(EXTRACT(DOW FROM subquery.reg_fecha::date) = 6 -- Que caen en sábado (DOW=6)
    			OR 
    			EXTRACT(DOW FROM subquery.reg_fecha::date) = 0) -- O domingo (DOW=0)
			) -- Esto implica que para 'ocu_tipo = 1', los fines de semana no se cuentan como parte de la ocurrencia(Excluir sábados (6) y domingos (0) para vacaciones).
		GROUP BY subquery.reg_cod_personal, subquery.reg_fecha -- Agrupa para consolidar múltiples ocurrencias en un mismo día.
	), */

	/*
	 * feriados_filtrados (Días Feriados):
	 - Obtiene una lista de todos los días feriados dentro del mes y año especificados.
	*/
	/*feriados_filtrados AS (
		SELECT f.fer_fecha AS reg_fecha, 					-- Fecha del feriado
    			f.fer_descripcion AS feriado_descripcion 	-- Descripción del feriado
		FROM feriados f
		WHERE EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes -- Filtra feriados para el año y mes dados.
	),*/

	/*
	 * tolerancias_especiales_filtradas (Tolerancias Individuales/Grupo):
	 - Obtiene todas las tolerancias especiales (sean individuales o por grupo/sede) que podrían 
	 afectar al empleado durante el mes.
	*/
	/*tolerancias_especiales_filtradas AS (
		SELECT te.tol_cod_personal,	-- Código del personal para tolerancia individual
    			te.tol_fecha_desde,	-- Fecha de inicio de vigencia
    			te.tol_fecha_hasta,	-- Fecha de fin de vigencia
    			te.tol_descripcion,	-- Descripción de la tolerancia
    			te.tol_tiempo,		-- Valor de tiempo de la tolerancia
    			te.tol_tipo,		-- Tipo de tolerancia ('I' para Individual, 'G' para Grupo)
    			te.tol_sed_cod		-- Código de la sede para tolerancia de grupo
		FROM tolerancias_especiales te
		WHERE (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal) -- Filtra por tolerancias individuales del empleado
    		OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal)) -- O tolerancias de grupo que apliquen a la sede del empleado
	), */

	/*
	 * compensaciones_detalles_filtradas (Detalles de Compensaciones):
	 -  Consolida los detalles de compensación (horas a compensar, compensadas, restantes, estado) para 
	 el empleado en el mes dado.
	 Agrega los detalles de compensaciones (horas a compensar, compensadas, restantes, estado) por día 
	 para el empleado y mes. Esto es clave para determinar si las horas extras deben ser calculadas 
	 o si están sujetas a un esquema de compensación.
	*/
	/*compensaciones_detalles_filtradas AS (
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
	),*/

	/*
	 * re_diaria (Cálculo Diario de RE - Recargo Extra/Horas Extras):
	 - Calcula el valor final de las re (horas de recargo extra) para cada día del mes. Aplica una serie de 
	 reglas de negocio condicionales que consideran:
	 + Si hay horas estáticas por ocurrencia (tipo 12).
	 + Si el empleado tiene horas restantes por compensar (no se calculan extras).
	 + Si el empleado llegó con retraso (y si ese retraso es justificado por cierto tipo de ocurrencia).
	 + Las horas trabajadas reales y las horas de entrada/salida vs. el turno programado.
	 + Se asume que los tipos de ocurrencia 33, 26, 12, 29 representan permisos o situaciones que "justifican" el retraso o impactan el cálculo de RE.
	*/
	/*re_diaria AS (
		SELECT c.date AS reg_fecha,-- Fecha del calendario
				COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal, -- Código de personal consolidado
				-- Lógica compleja para calcular `re` (horas extras finales por día)
				CASE
					-- Escenario excepcional: HORAS ESTATICAS (ocu_tipo = 12 y ocu_horas_estaticas = 1)
					WHEN of.ocu_tipo = 12 AND of.ocu_horas_estaticas = 1 
						THEN of.ocu_horas_extras::interval	-- Las RE son las horas extras definidas en la ocurrencia
    				-- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras (RE es 0)
    				WHEN cd.com_det_horas_restantes > '00:00:00'::interval 
    					THEN '00:00:00'::interval
    				-- Escenario 2: Si la persona llegó tarde (retraso > 0) y NO tiene permisos específicos (tipos 33, 26, 12, 29), no se calculan horas extras
					WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN '00:00:00'::interval

    				-- Nuevo Escenario (específico para ocu_tipo = 12 y retraso > 59 segundos) Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
					WHEN EXISTS (
        					SELECT 1
        					FROM ocurrencias_filtradas of
        					WHERE of.reg_fecha = c.date
        					AND of.ocu_tipo = 12
    					) AND p.reg_retraso > '00:59:59'::interval 
    					THEN
        					CASE
            					WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
            						THEN
                						LEAST(
                    						(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                    						'02:00:00'::interval
                						)
            					ELSE 
            						'00:00:00'::interval
        					END
					
    				-- Escenario 3: No hay horas pendientes DE COMPENSAR, PERO hay permisos específicos (tipos 33, 26, 12, 29), calcular horas extras con reglas especiales
					WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN
        			CASE
						WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval 
							THEN -- Misma lógica que el "Nuevo Escenario" de arriba
	            				CASE
	                				WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
	                					THEN
	                    					LEAST(
	                        					(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
	                        					'02:00:00'::interval
	                    					)
	                				ELSE 
	                					'00:00:00'::interval
	            				END
            			WHEN of.ocu_tipo = 29 
            				THEN -- Lógica específica para ocu_tipo 29 (ej. permiso de salida)
                				CASE
                    				WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > '09:00:00'::interval 
                    					THEN
                        					LEAST(
                            					(p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - '08:00:00'::interval,
                            					'02:00:00'::interval
                        					)
                    				ELSE 
                    					'00:00:00'::interval
                				END
            				ELSE -- Lógica general para otros tipos de ocurrencia
                				CASE
                    				WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
                    					THEN
                        					LEAST(
                            					(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                            					'02:00:00'::interval
                        					)
                    				ELSE 
                    					'00:00:00'::interval
                				END
        					END
						
						-- Escenario 4: No hay horas pendientes NI permisos, y es parte de una seguidilla de días (esta condición es un poco confusa en su redacción SQL, puede estar incompleta o mal interpretada aquí), no calcular horas extras
               			-- La condición `NOT EXISTS (SELECT 1 FROM ocurrencias_filtradas of WHERE of.reg_fecha = c.date AND of.ocu_tipo IN (33, 26, 12, 29))` se repite desde el escenario 2.
						WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (
        						SELECT 1
        						FROM ocurrencias_filtradas of
        						WHERE of.reg_fecha = c.date
        						AND of.ocu_tipo IN (33, 26, 12, 29)
    						) 
    						THEN '00:00:00'::interval

    					-- Escenario 5: Cálculo general de RE si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
						WHEN p.reg_horas_trabajadas > '09:00:00'::interval 
    						THEN
        						LEAST(
            						p.reg_horas_trabajadas - '08:00:00'::interval,
            						'02:00:00'::interval
        						) -- Si trabajó más de 9 horas, las extras son el exceso sobre 8 horas, topado a 2 horas.

    					-- En caso contrario, las horas extras son 00:00:00
    					ELSE 
    						'00:00:00'::interval
					END AS re,
					cd.com_det_horas_a_compensar AS horas_a_compensar,
					cd.com_det_horas_compensadas AS horas_compensadas,
					cd.com_det_horas_restantes AS horas_restantes,
					cd.com_estado::character varying AS estado_compensacion,
					p.reg_horas_trabajadas,
					p.reg_hora_salida,
					p.reg_retraso,
					of.ocu_tipo,
					of.ocu_horas_estaticas,
					of.ocu_horas_extras,
					of.ocu_horas_adicionales,
					of.ocu_horas_adicionales_100
		FROM calendar c -- Se une con el calendario para asegurar que todas las fechas del mes estén presentes
			LEFT JOIN marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal -- Se unen las marcaciones del empleado
			LEFT JOIN ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal -- Se unen las ocurrencias del empleado
			LEFT JOIN compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal -- Se unen los detalles de compensación
	),*/

	/*
	 * re_semanal (Suma Semanal de RE):
	 - Calcula la suma total de re por semana para cada empleado, con un tope de 8 horas semanales, y 
	 considerando solo los días laborables (Lunes a Viernes).
	*/
	/*re_semanal AS (
		SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week, -- Extrae el número de semana
				LEAST(
					COALESCE(
						SUM(
							CASE
								WHEN rd.re >= '01:00:00' 
									THEN LEAST(rd.re, '02:00:00'::interval) -- Si RE es >= 1 hora, se considera hasta un máximo de 2 horas diarias
								ELSE 
									'00:00:00'::interval
							END
						) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5), -- SUMA solo de Lunes a Viernes (ISODOW 1-5)
						'00:00:00'::interval
					),
					'08:00:00'::interval -- Tope semanal: El total de RE por semana no puede exceder las 8 horas.
				) AS re_semanal_suma
		FROM re_diaria rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha) -- Agrupa por personal y semana.
	),*/

	/*
	 * re_mensual (Suma Mensual de RE):
	 - Calcula la suma total de re por mes para cada empleado, con un tope de 32 horas 
	 mensuales (asumiendo 4 semanas de 8 horas cada una).
	*/
	/*re_mensual AS (
		SELECT rs.reg_cod_personal,
				LEAST(
					SUM(rs.re_semanal_suma), -- Suma las RE semanales ya topadas
					'32:00:00'::interval -- Tope mensual: El total de RE por mes no puede exceder las 32 horas.
				) AS re_mensual_suma
		FROM re_semanal rs
		GROUP BY rs.reg_cod_personal -- Agrupa por personal para obtener la suma mensual.
	),*/

	/*
	 * re_acumulada_semanal (RE Acumulada Semanalmente):
	 - Calcula un total acumulado de re para cada día dentro de su semana correspondiente. Esta es una 
	 ventana de agregación que reinicia el conteo cada semana.
	*/
	/*re_acumulada_semanal AS (
		-- CTE que acumula las RE semanalmente, reiniciando cada lunes (EXTRACT(ISODOW) = 1)
		SELECT rd.reg_cod_personal,
				rd.reg_fecha,
				EXTRACT(WEEK FROM rd.reg_fecha) AS semana,
				rd.re,
				SUM(rd.re) OVER (
					PARTITION BY rd.reg_cod_personal, 
					EXTRACT(YEAR FROM rd.reg_fecha), 
					EXTRACT(WEEK FROM rd.reg_fecha) 
					ORDER BY rd.reg_fecha ROWS UNBOUNDED PRECEDING
				) AS re_acumulada_semanal -- Suma acumulada de `re` para cada semana, desde el inicio de la semana hasta la fecha actual.
		FROM re_diaria rd
		WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5  -- Considera solo días de lunes a viernes para la acumulación semanal.
	),*/

	/*
	 * re_mensual_con_limited (RE Diaria con Límite Semanal Aplicado):
	 - Ajusta el valor de re de cada día, de modo que si ya se ha alcanzado el tope semanal de 8 horas 
	 con días anteriores, las RE de ese día (y los siguientes de la misma semana) se contabilizan como 
	 cero para la acumulación mensual.
	*/
	/*re_mensual_con_limited AS (
		-- Aplica un límite de 08:00 horas por semana a las RE
		SELECT rsa.reg_cod_personal,               -- Código de la persona
				rsa.reg_fecha,                      -- Fecha de la marcación
				rsa.re,
				-- Suma diaria limitada por la acumulación semanal (máximo 08:00 horas por semana)
				CASE
					-- Si la RE acumulada semanal ya excede o iguala las 8 horas, la RE para este día es 0 (no se acumula más RE para la semana), no sumamos más horas.
					WHEN rsa.re_acumulada_semanal > '08:00:00'::interval 
						THEN '00:00:00'::interval
					-- Si no se ha alcanzado el límite semanal, se utiliza la RE diaria original.
					ELSE 
						rsa.re
				END AS re_con_limited -- RE diaria ajustada para no superar el tope semanal.
		FROM re_acumulada_semanal rsa
	),*/

	/*
	 * re_acumulada_mensual (RE Acumulada Mensual con Límite Semanal):
	 - Calcula un total acumulado de re para cada día del mes, pero utilizando los valores de re que ya 
	 han sido "limitados" por el tope semanal.
	*/
	/*re_acumulada_mensual AS (
		SELECT rml.reg_cod_personal,               	-- Código de la persona
				rml.reg_fecha,                      -- Fecha de la marcación
				SUM(rml.re_con_limited) OVER (
					PARTITION BY rml.reg_cod_personal ORDER BY rml.reg_fecha -- Suma acumulada de `re_con_limited` por empleado, a lo largo del mes.
				) AS re_acumulada_mensual           -- RE acumulada mensual con el tope semanal aplicado
		FROM re_mensual_con_limited rml
	),*/

	/*
	 * ra (Cálculo Diario de RA - Recargo Adicional):
	 - Calcula el valor de ra (Recargo Adicional) para cada día. Esta lógica es aún más intrincada que la 
	 de re, ya que sus cálculos dependen de si ya se han alcanzado ciertos topes de RE (semanales o mensuales) 
	 y del tipo de ocurrencia. Asigna el total de horas trabajadas como RA si es sábado.
	*/
	/*ra AS (
		SELECT rd.reg_cod_personal,
				rd.reg_fecha,
				rd.reg_hora_salida,
				rd.reg_horas_trabajadas,
				rd.reg_retraso,  
				rd.ocu_tipo,
				rd.ocu_horas_estaticas,
				rd.ocu_horas_extras,
				rd.ocu_horas_adicionales,
				rd.ocu_horas_adicionales_100,
				-- Lógica muy compleja para calcular `ra` (horas adicionales/recargo adicional)
				CASE
					-- Escenario excepcional: HORAS ESTATICAS (ocu_tipo = 12 y ocu_horas_estaticas = 1)
					WHEN rd.ocu_tipo = 12 AND rd.ocu_horas_estaticas = 1 
						THEN rd.ocu_horas_adicionales::interval+rd.ocu_horas_adicionales_100::interval -- RA es la suma de horas adicionales 80% y 100% de la ocurrencia
					-- Si es Sábado (ISODOW = 6), el RA es el total de horas trabajadas, sin importar el retraso.
					WHEN EXTRACT(ISODOW FROM rd.reg_fecha) = 6 
						THEN rd.reg_horas_trabajadas
					-- Si RE es menor a 1 hora (00:59:59 o menos), RA es 0 (no se acumulan RA si no hay RE significativas)
					WHEN rd.re < '01:00:00'::interval 
						THEN '00:00:00'::interval
					-- Validación: Si la RE acumulada semanal es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
					WHEN ras.re_acumulada_semanal > '08:00:00'::interval 
						THEN
							CASE
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas  - '08:00:00'::interval -- RA es el exceso sobre 8 horas (se asume que RE cubrió las primeras 8)
								ELSE 
									'00:00:00'::interval
							END
					-- Si la RE acumulada mensual está entre 32 y 33:59:59 (después de alcanzar el tope mensual de RE)
					WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval 
						THEN
							CASE
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas - '09:00:00'::interval -- RA es el exceso sobre 9 horas
								ELSE 
								'00:00:00'::interval
							END
					-- Si la RE acumulada mensual es mayor a 34 horas
					WHEN ram.re_acumulada_mensual > '34:00:00'::interval 
						THEN
							CASE
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas - '08:00:00'::interval -- RA es el exceso sobre 8 horas
								ELSE 
									'00:00:00'::interval
							END
						-- Cálculo general: Si ninguna de las validaciones anteriores aplica, RA es el exceso sobre 10 horas trabajadas.
					ELSE
						CASE
							WHEN rd.reg_horas_trabajadas > '10:00:00'::interval 
								THEN rd.reg_horas_trabajadas - '10:00:00'::interval
							ELSE 
								'00:00:00'::interval
						END
				END AS ra	 
		FROM re_diaria rd
			LEFT JOIN re_acumulada_semanal ras ON rd.reg_cod_personal = ras.reg_cod_personal AND rd.reg_fecha = ras.reg_fecha -- Se une para usar la RE acumulada semanal
			LEFT JOIN re_acumulada_mensual ram ON rd.reg_cod_personal = ram.reg_cod_personal AND rd.reg_fecha = ram.reg_fecha -- Se une para usar la RE acumulada mensual
	),*/

	/*
	 * ra_semanal_suma (Suma Semanal de RA):
	 - Calcula la suma total de ra por semana para cada empleado, incluyendo sábados. No tiene un tope 
	 semanal explícito en esta CTE.
	*/
	/*ra_semanal_suma AS (
		SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week,
				SUM(
					CASE
						-- Sumar directamente las horas adicionales (RA) sin límite o tope
						WHEN rd.ra IS NOT NULL 
							THEN rd.ra
						ELSE 
							'00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_semanal_suma -- Suma RA semanal, incluyendo sábados (ISODOW <= 6).
		FROM ra rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),*/

	/*
	 * ra_mensual_suma (Suma Mensual de RA):
	 - Calcula la suma total de ra por mes para cada empleado.
	*/
	/*ra_mensual_suma AS (
		SELECT rs.reg_cod_personal,
				SUM(rs.ra_semanal_suma) AS ra_mensual_suma -- Suma las RA semanales para obtener el total mensual.
		FROM ra_semanal_suma rs
		GROUP BY rs.reg_cod_personal
	),*/

	/*
	 * ra_dividida (División de RA en 80% y 100%):
	 - Divide las horas de ra calculadas diariamente en dos categorías: ra_80 (generalmente horas adicionales 
	 en horario diurno o normal) y ra_100 (generalmente horas adicionales en horario nocturno o festivo). 
	 La división se basa en la reg_hora_salida y el umbral de las 19:59:59. También maneja el caso especial 
	 de sábados donde todo el RA puede ser 100%.
	*/
	/*ra_dividida AS (
		SELECT ra.reg_cod_personal,
				ra.reg_fecha,
				ra.ra,  			-- El valor de RA calculado previamente
				ra.reg_hora_salida, -- Hora de salida
				ra.reg_horas_trabajadas,
				ra.ocu_tipo,
				ra.ocu_horas_estaticas,
				ra.ocu_horas_extras,
				ra.ocu_horas_adicionales,
				ra.ocu_horas_adicionales_100,
    
				-- Cálculo de RA_80(recargo adicional al 80%) hasta las 19:59:59
				CASE
					--Calculo excepcional ocu tipo 12  horas estaticas
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales::interval
					-- Si es sábado, RA_80 es siempre '00:00:00'
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN '00:00:00'::interval
					-- Si la hora de salida es antes o igual a las 19:59:59, todo el RA se asigna a RA_80
					WHEN ra.reg_hora_salida <= '19:59:59'::time 
						THEN ra.ra
					-- Si la hora de salida es después de las 19:59:59, RA_80 es la parte del RA que ocurrió antes de las 19:59:59
					ELSE 
						ra.ra - (ra.reg_hora_salida - '19:59:59'::time)::interval
				END AS ra_80,
    
				-- Cálculo de RA_100(recargo adicional al 100%) después de las 19:59:59
				CASE
					--Calculo excepcional ocu tipo 12  horas estaticas
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales_100::interval
					-- Si es sábado (día de la semana = 6) y hay horas trabajadas, todo RA se asigna a RA_100
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN ra.reg_horas_trabajadas
					-- Si la hora de salida es después de las 19:59:59, RA_100 es la parte del RA que ocurrió después de las 19:59:59, topado al valor de RA
					WHEN ra.reg_hora_salida > '19:59:59'::time 
						THEN LEAST(ra.ra, (ra.reg_hora_salida - '19:59:59'::time)::interval)
					-- Si la hora de salida es antes de las 19:59:59, no hay RA_100
					ELSE 
						'00:00:00'::interval
				END AS ra_100

		FROM ra  -- Utilizamos el CTE `ra` previamente calculado para obtener los valores de RA
	),*/

	/*
	 * ra_divida_semanal_suma (Suma Semanal de RA 80% y 100%):
	 - Calcula la suma semanal de ra_80 (solo días laborables) y ra_100 (incluyendo sábados).
	*/
	/*ra_divida_semanal_suma AS (
		SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week,
				SUM(
					CASE
						-- Sumar directamente las horas adicionales (RA) sin límite o tope  Sumar solo si rd.ra_80 es mayor que '00:00:00'
						WHEN rd.ra_80 IS NOT NULL AND rd.ra_80 > '00:00:00'::interval 
							THEN rd.ra_80
						ELSE 
							'00:00:00'::interval
						END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal, -- Suma RA_80 de Lunes a Viernes.
				SUM(
					CASE
						-- Sumar directamente las horas adicionales (RA) sin límite o tope
						WHEN rd.ra_100 IS NOT NULL 
							THEN rd.ra_100
						ELSE 
							'00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal -- Suma RA_100 incluyendo Sábados.
		FROM ra_dividida rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),*/

	/*
	 * ra_dividia_mensual_suma (Suma Mensual de RA 80% y 100%):
	 - Calcula la suma mensual de ra_80 y ra_100.
	*/
	/*ra_dividia_mensual_suma AS (
		SELECT 
			rs.reg_cod_personal,
			SUM(rs.ra_80_semanal) AS ra_80_mensual, -- Suma las RA_80 semanales para el total mensual.
			SUM(rs.ra_100_semanal) AS ra_100_mensual -- Suma las RA_100 semanales para el total mensual.
		FROM 
			ra_divida_semanal_suma rs
		GROUP BY 
		rs.reg_cod_personal
	),*/

	-- re_recalculada
	-- Propósito: Este CTE realiza un re-cálculo final de re por día, asegurándose de que la cantidad total semanal no exceda el límite de 8 horas, y "ajustando" las horas extras del último día que excedería el tope.
	-- Lógica: Si la re_acumulada_semanal (running total) ya superó las 8 horas en un día determinado, entonces la re_recalculada para ese día se ajusta restándole el exceso acumulado, o se pone a 0. Esto evita que la suma final exceda el tope.
	/*
	 * re_recalculada (RE Recalculada/Ajustada):
	 - Este CTE parece ser un ajuste final al valor de re diario, para asegurarse de que el total semanal no 
	 exceda el límite de 8 horas. Si la acumulación semanal ya superó las 8 horas, recalcula la re de ese día 
	 para reducirla. Sin embargo, su lógica de "ELSE '00:00:00'::interval" cuando re_acumulada_semanal no 
	 es >= '08:00:00' sugiere que su uso principal es para reducir las RE cuando el tope semanal se excede, y 
	 en otros casos se usaría la RE original.
	*/
	/*re_recalculada AS (
		SELECT ras.reg_cod_personal,
				ras.reg_fecha,
				rd.reg_horas_trabajadas,
				ras.re,
				ras.re_acumulada_semanal,
				CASE
					-- Verifica si `re_acumulada_semanal` es mayor o igual a 08:00:00
					WHEN ras.re_acumulada_semanal >= '08:00:00'::interval THEN -- Si la RE acumulada semanal ya alcanzó el tope de 8 horas.
						CASE
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval -- Y si las horas trabajadas superan las 9 horas.
								THEN ras.re - (ras.re_acumulada_semanal - '08:00:00'::interval) -- Resta el exceso de la acumulación semanal al RE diario.
							ELSE
								'00:00:00'::interval -- Si no, RE recalculada es 0.
						END
					ELSE
						-- Si la acumulación semanal no ha llegado al tope, RE recalculada es 0 (se asume que se usa la RE original).
						'00:00:00'::interval
				END AS re_recalculada
		FROM re_acumulada_semanal ras
			JOIN re_diaria rd ON ras.reg_cod_personal = rd.reg_cod_personal AND ras.reg_fecha = rd.reg_fecha -- Se une para comparar con las horas trabajadas diarias.
	)*/

	/*
	 * Esta es la parte que une todas las CTEs anteriores para construir la tabla de resultados final de 
	 la función.
	*/
	SELECT r.reg_fecha, 			-- Fecha del registro
			r.reg_cod_personal, 	-- Código del personal
			p.tur_entrada, 			-- Hora de entrada del turno programado
			p.tur_salida, 			-- Hora de salida del turno programado
			p.par_valor_time, 		-- Valor del parámetro de tolerancia del turno
			p.reg_hora_entrada, 	-- Hora de la marcación de entrada
			p.reg_hora_salida,		-- Hora de la marcación de salida
			p.reg_horas_trabajadas,	-- Horas trabajadas calculadas
			p.reg_retraso, 			-- Retraso calculado
			p.reg_horas_extras, 	-- Horas extras iniciales
			-- Utiliza 're_recalculada' si no es cero, de lo contrario, usa 're' de re_diaria
			CASE
				WHEN re_rec.re_recalculada <> '00:00:00'::interval THEN re_rec.re_recalculada
				ELSE r.re
			END AS re, 							-- Horas de Recargo Extra (RE) final ajustadas
			r.horas_a_compensar, 				-- Horas a compensar (de compensaciones)
			r.horas_compensadas, 				-- Horas ya compensadas
			r.horas_restantes, 					-- Horas restantes por compensar
			r.estado_compensacion, 				-- Estado de la compensación
			s.re_semanal_suma, 					-- Suma semanal de RE
			m.re_mensual_suma, 					-- Suma mensual de RE
			ra_semanal.re_acumulada_semanal,	-- RE acumulada semanalmente
			ra_mensual.re_acumulada_mensual, 	-- RE acumulada mensualmente
			ra.ra AS horas_adicionales, 		-- Horas de Recargo Adicional (RA) diaria
			ras.ra_semanal_suma, 				-- Suma semanal de RA total
			ma.ra_mensual_suma, 				-- Suma mensual de RA total
			ra_dividida.ra_80,   				-- RA al 80% (diaria)
			ra_dividida.ra_100,  				-- RA al 100% (diaria)
			rds.ra_80_semanal, 					-- Suma semanal de RA al 80%
			rds.ra_100_semanal, 				-- Suma semanal de RA al 100%
			rdm.ra_80_mensual, 					-- Suma mensual de RA al 80%
			rdm.ra_100_mensual, 				-- Suma mensual de RA al 100%
			btrim(
				CASE -- Convierte el número del día de la semana a su nombre en español
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
			) AS dia_semana, 								-- Nombre del día de la semana
			of.ocu_descripcion AS ocurrencia_descripcion,	-- Descripción de la ocurrencia
			of.ocurrencia_tipo, 							-- Tipo de ocurrencia (texto)
			of.ocu_tipo, 									-- Tipo de ocurrencia (código numérico)
			of.tip_codigo, 									-- Código de tipo de ocurrencia (ej. "VAC")
			ff.feriado_descripcion, 						-- Descripción del feriado
			CASE -- Construye la cadena de texto para la tolerancia especial
				WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta 
					THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta 
					THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				ELSE 
					NULL
			END AS tolerancia_especial -- Descripción de la tolerancia especial aplicada.
	FROM re_diaria r -- Tabla base de la unión: todos los días del mes con RE diaria calculada
		LEFT JOIN marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal -- Marcaciones y turnos
		LEFT JOIN re_recalculada re_rec ON r.reg_cod_personal = re_rec.reg_cod_personal AND r.reg_fecha = re_rec.reg_fecha -- RE con ajuste final
		LEFT JOIN ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal -- Ocurrencias
		LEFT JOIN feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha 		-- Feriados
		LEFT JOIN tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta -- Tolerancias especiales (no por personal, se filtrará después por tipo y sede/personal)
		LEFT JOIN re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week -- RE semanal
		LEFT JOIN re_mensual m ON r.reg_cod_personal = m.reg_cod_personal 	-- RE mensual
		LEFT JOIN re_acumulada_semanal ra_semanal ON r.reg_cod_personal = ra_semanal.reg_cod_personal AND r.reg_fecha = ra_semanal.reg_fecha -- RE acumulada semanal
		LEFT JOIN re_acumulada_mensual ra_mensual ON r.reg_cod_personal = ra_mensual.reg_cod_personal AND r.reg_fecha = ra_mensual.reg_fecha -- RE acumulada mensual
		LEFT JOIN ra ra ON r.reg_cod_personal = ra.reg_cod_personal AND r.reg_fecha = ra.reg_fecha -- RA diaria
		LEFT JOIN ra_dividida ON ra.reg_cod_personal = ra_dividida.reg_cod_personal AND ra.reg_fecha = ra_dividida.reg_fecha -- RA dividida
		LEFT JOIN ra_semanal_suma ras ON r.reg_cod_personal = ras.reg_cod_personal 
			AND EXTRACT(WEEK FROM r.reg_fecha) = ras.week 
			AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6 						-- RA semanal total
		LEFT JOIN ra_mensual_suma ma ON r.reg_cod_personal = ma.reg_cod_personal -- RA mensual total
		LEFT JOIN ra_divida_semanal_suma rds ON r.reg_cod_personal = rds.reg_cod_personal 
			AND EXTRACT(WEEK FROM r.reg_fecha) = rds.week 
			AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6 						-- RA 80/100 semanal
		LEFT JOIN ra_dividia_mensual_suma rdm ON r.reg_cod_personal = rdm.reg_cod_personal -- RA 80/100 mensual
	ORDER BY r.reg_fecha, r.reg_cod_personal; -- Ordena el resultado final por fecha y personal.
END; 
$function$
;


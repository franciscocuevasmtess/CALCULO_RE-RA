CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas5Modificada(
	anio integer, 
	mes integer, 
	param_reg_cod_personal integer
)
	RETURNS TABLE(
		reg_fecha date, 
		reg_cod_personal integer, 
		tur_entrada time without time zone, 
		tur_salida time without time zone, 
		par_valor_time interval, 
		reg_hora_entrada time without time zone, 
		reg_hora_salida time without time zone, 
		reg_horas_trabajadas interval, 
		reg_retraso interval, 
		reg_horas_extras interval, 
		re interval, 
		horas_a_compensar interval, 
		horas_compensadas interval, 
		horas_restantes interval, 
		estado_compensacion character varying, 
		re_semanal_suma interval, 
		re_mensual_suma interval, 
		re_acumulada_semanal interval, 
		re_acumulada_mensual interval, 
		ra interval, 
		ra_semanal_suma interval, 
		ra_mensual_suma interval, 
		ra_80 interval, 
		ra_100 interval, 
		ra_80_semanal interval, 
		ra_100_semanal interval, 
		ra_80_mensual interval, 
		ra_100_mensual interval, 
		dia_semana text, 
		ocurrencia_descripcion text, 
		ocurrencia_tipo text, 
		ocu_tipo integer, 
		tip_codigo character varying, 
		feriado_descripcion character varying, 
		tolerancia_especial text
	)
LANGUAGE plpgsql
AS $function$
BEGIN
	/*
	 * Estas líneas establecen configuraciones de sesión para la función. 
	 * Aseguran que la manipulación de fechas y tiempos sea consistente (UTC 
	 * para la zona horaria y DMY para el estilo de fecha) sin importar la 
	 * configuración global del servidor o del cliente.
	*/
	-- Configura la zona horaria a UTC para la sesión actual. Importante 
	-- para consistencia en cálculos de tiempo.
	PERFORM set_config('timezone', 'UTC', true);
	
	-- Configura el estilo de fecha a ISO, DMY (Día-Mes-Año).
    PERFORM set_config('DateStyle', 'ISO, DMY', true);
	
	-- Indica que el resultado de la siguiente consulta (que contiene 
	-- múltiples CTEs) será el resultado devuelto por la función.
    RETURN QUERY
	
	-- CTEs (Common Table Expressions - Bloques WITH):
	-- Aquí es donde reside la mayor parte de la lógica. 
	-- Cada CTE prepara un conjunto de datos intermedio que luego 
	-- se utiliza en CTEs posteriores o en la consulta final.
	
	/*
	 * calendar (Generador de Fechas del Mes):
	 - Crea una tabla temporal calendar que contiene todas las fechas día por día 
	 para el "mes y año" especificados en los parámetros de la función. 
	 Es fundamental para asegurar que el informe incluya todos los días del mes, 
	 incluso aquellos sin marcaciones.
	*/
    WITH RECURSIVE calendar AS (
        SELECT DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date	-- Selecciona el primer día del mes dado por 'anio' y 'mes'
        UNION ALL								-- Une con los siguientes días de forma recursiva
        SELECT (date + INTERVAL '1 day')::DATE	-- Suma un día a la fecha anterior
        FROM calendar
        WHERE date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'	-- Condición para detener la recursión: hasta el último día del mes
    ),
	/*
	 * marcaciones_completas (Marcaciones con Turnos y Cálculos Básicos):
	 - Centraliza las marcaciones de entrada y salida, les asocia el turno correspondiente 
	 y sus tolerancias, y realiza los cálculos iniciales de reg_horas_trabajadas, 
	 reg_retraso (con un ajuste de 59 segundos de gracia y tolerancia especial) y reg_horas_extras. 
	 Todo esto, filtrado para el param_reg_cod_personal de la función.
	*/
	marcaciones_completas AS (
        SELECT COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha, 						-- Fecha consolidada (de entrada o salida)
    			COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal, 	-- Código de personal consolidado
    			t.tur_entrada,															-- Hora de entrada programada del turno
    			t.tur_salida,															-- Hora de salida programada del turno
    			p.par_valor_time,														-- Valor del parámetro de tolerancia general
				t.tur_tipo,																-- Tipo de turno
				e.tol_tiempo_interval,													-- Tolerancia especial (obtenida de marcacion_entrada_adsoluta)
    			e.reg_hora AS reg_hora_entrada,											-- Hora de la marcación de entrada
    			s.reg_hora AS reg_hora_salida,											-- Hora de la marcación de salida
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
        FROM marcacion_entrada_adsoluta e
			FULL JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
			LEFT JOIN turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
				AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
				AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
			LEFT JOIN parametros p ON p.par_cod = t.tur_tolerancia
        WHERE COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
	/*
	 * ocurrencias_filtradas (Eventos y Ausencias):
	 - Identifica y consolida todas las "ocurrencias" (permisos, licencias, vacaciones, etc.) 
	 aplicables a un empleado durante el mes. Utiliza generate_series para "expandir" las 
	 ocurrencias de rango de fechas a días individuales y luego las agrupa para manejar 
	 múltiples ocurrencias en un mismo día. 
	 Excluye fines de semana para ciertos tipos de ocurrencia (ej. vacaciones).
	*/
	ocurrencias_filtradas AS (
		SELECT subquery.reg_cod_personal,	-- Código del personal
				subquery.reg_fecha,			-- Fecha del día específico. Generada por 'generate_series' para cada día de la ocurrencia dentro del mes.
				STRING_AGG(subquery.ocu_descripcion::text, ', ' ORDER BY subquery.ocu_descripcion)::text AS ocu_descripcion,	-- Agrupa descripciones de ocurrencias por día
    			STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo)::text AS ocurrencia_tipo,	-- Agrupa tipos de ocurrencias por día
				MIN(subquery.ocu_tipo) AS ocu_tipo,
				STRING_AGG(subquery.tip_codigo::character varying, ', ' ORDER BY subquery.tip_codigo)::character varying AS tip_codigo,	-- Agrupa códigos de tipo (ej. "VAC", "PER")
				MAX(subquery.ocu_horas_estaticas) AS ocu_horas_estaticas, 				-- Máximo de horas estáticas
				SUM(subquery.ocu_horas_extras) AS ocu_horas_extras,						-- Suma de horas extras de ocurrencias
				SUM(subquery.ocu_horas_adicionales) AS ocu_horas_adicionales, 			-- Suma de horas adicionales de ocurrencias (RA 80%)
				SUM(subquery.ocu_horas_adicionales_100) AS ocu_horas_adicionales_100 	-- Suma de horas adicionales de ocurrencias (RA 100%)
		FROM (
			SELECT o.ocu_cod_persona AS reg_cod_personal,
					
					-- Genera una serie de fechas (día a día) para cada ocurrencia, 
            		-- limitando el rango a la intersección entre la duración de la ocurrencia 
            		-- y el mes de interés (anio, mes).
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
    				)::date AS reg_fecha, 					-- Genera una fila por cada día que la ocurrencia está vigente en el mes
					o.ocu_descripcion,						-- Descripción original de la ocurrencia.
					t.tip_descripcion AS ocurrencia_tipo,	-- Descripción textual del tipo de ocurrencia (ej. "Vacaciones").
					t.tip_codigo,							-- Código del tipo de ocurrencia (ej. "VAC").
					o.ocu_tipo,								-- Código numérico del tipo de ocurrencia.
					o.ocu_horas_estaticas,					-- Horas estáticas asociadas a la ocurrencia.
					o.ocu_horas_extras,						-- Horas extras asociadas a la ocurrencia.
					o.ocu_horas_adicionales,				-- Horas adicionales (RA 80%) asociadas a la ocurrencia.
					o.ocu_horas_adicionales_100				-- Horas adicionales (RA 100%) asociadas a la ocurrencia.
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
	),
	/*
	 * feriados_filtrados (Días Feriados):
	 - Obtiene una lista de todos los días feriados dentro del mes y año especificados.
	*/
    feriados_filtrados AS (
        SELECT f.fer_fecha AS reg_fecha, 					-- Fecha del feriado
    			f.fer_descripcion AS feriado_descripcion 	-- Descripción del feriado
		FROM feriados f
		WHERE EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes -- Filtra feriados para el año y mes dados.
    ),
	/*
	 * tolerancias_especiales_filtradas (Tolerancias Individuales/Grupo):
	 - Obtiene todas las tolerancias especiales (sean individuales o por grupo/sede) que podrían 
	 afectar al empleado durante el mes.
	*/
	tolerancias_especiales_filtradas AS (
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
    ),
	/*
	 * compensaciones_detalles_filtradas (Detalles de Compensaciones):
	 -  Consolida los detalles de compensación (horas a compensar, compensadas, restantes, estado) para 
	 el empleado en el mes dado.
	 Agrega los detalles de compensaciones (horas a compensar, compensadas, restantes, estado) por día 
	 para el empleado y mes. Esto es clave para determinar si las horas extras deben ser calculadas 
	 o si están sujetas a un esquema de compensación.
	*/
    compensaciones_detalles_filtradas AS (
        SELECT com_cod_personal,	-- Código del personal.
    			com_det_fecha,		-- Fecha del detalle de la compensación.
    			SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,	-- Suma todas las horas "a compensar" para un empleado en un día específico.
    			SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,	-- Suma todas las horas "ya compensadas" para un empleado en un día específico.
    			SUM(com_det_horas_restantes) AS com_det_horas_restantes,		-- Suma todas las horas "restantes por compensar" para un empleado en un día específico.
    			STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado	-- Concatena de forma única todos los estados de compensación para un empleado en un día específico.
		FROM ( 
				-- Esta subconsulta interna selecciona los detalles de compensación y su estado,
        		-- filtrando por el empleado y el mes/año (alias como 'sub').
				SELECT c.com_cod_personal,				-- Código del personal.
        				cd.com_det_fecha,				-- Fecha específica del detalle de compensación.
        				cd.com_det_horas_a_compensar,	-- Horas inicialmente a compensar.
        				cd.com_det_horas_compensadas,	-- Horas que ya han sido compensadas.
        				cd.com_det_horas_restantes,		-- Horas que aún quedan por compensar.
        				c.com_estado					-- Estado general de la compensación (ej. 'Pendiente', 'Cerrado').
    			FROM compensaciones_detalles cd	-- Tabla que contiene los registros de compensación detallados por fecha.
    				JOIN compensaciones_completas c ON cd.com_cod = c.com_cod	-- Une con la tabla maestra de compensaciones para obtener el código de personal y el estado general.
    			WHERE c.com_cod_personal = param_reg_cod_personal	-- Filtra por el código de personal del empleado.
        		AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio	-- Filtra por el año de la fecha del detalle.
        		AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes	-- Filtra por el mes de la fecha del detalle.
				) sub
		GROUP BY com_cod_personal, com_det_fecha -- Agrupa los resultados por empleado y por fecha. Esto consolida todos los registros de compensación que afectan a un mismo día para un empleado dado.
    ),
	/*
	 * re_diaria (Cálculo Diario de RE - Recargo Extra/Horas Extras):
	 - Calcula el valor final de las re (horas de recargo extra) para cada día del mes. 
	 Aplica una serie de reglas de negocio condicionales que consideran:
	 + Si hay horas estáticas por ocurrencia (tipo 12).
	 + Si el empleado tiene horas restantes por compensar (no se calculan extras).
	 + Si el empleado llegó con retraso (y si ese retraso es justificado por cierto tipo de ocurrencia).
	 + Las horas trabajadas reales y las horas de entrada/salida vs. el turno programado.
	 + Se asume que los tipos de ocurrencia 33, 26, 12, 29 representan permisos o situaciones 
	 que "justifican" el retraso o impactan el cálculo de RE.
	*/
	re_diaria AS (
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
					cd.com_det_horas_a_compensar AS horas_a_compensar,			-- Muestra las horas pendientes que deben ser compensadas para el día.
					cd.com_det_horas_compensadas AS horas_compensadas,			-- Muestra las horas que ya han sido compensadas para el día.
					cd.com_det_horas_restantes AS horas_restantes,				-- Muestra el saldo de horas restantes por compensar (o a favor/en contra) para el día.
					cd.com_estado::character varying AS estado_compensacion,	-- Muestra el estado (o los estados, si hay varios únicos) de las compensaciones para el día.
					p.reg_horas_trabajadas,										-- Muestra las horas de trabajo calculadas para el día.
					p.reg_hora_salida,											-- Muestra la hora de salida registrada por el empleado.
					p.reg_retraso,												-- Muestra el tiempo de retraso en la entrada del empleado.
					of.ocu_tipo,												-- Muestra el tipo de ocurrencia principal para el día (si aplica).
					of.ocu_horas_estaticas,										-- Indica si las horas extras de la ocurrencia son estáticas/predefinidas.
					of.ocu_horas_extras,										-- Muestra las horas extras especificadas en la ocurrencia.
					of.ocu_horas_adicionales,									-- Muestra las horas adicionales (ej. recargo al 80%) de la ocurrencia.
					of.ocu_horas_adicionales_100								-- Muestra las horas adicionales (ej. recargo al 100%) de la ocurrencia.
		FROM calendar c -- Se une con el calendario para asegurar que todas las fechas del mes estén presentes
			LEFT JOIN marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal -- Se unen las marcaciones del empleado
			LEFT JOIN ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal -- Se unen las ocurrencias del empleado
			LEFT JOIN compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal -- Se unen los detalles de compensación
	),
	re_semanal AS (
        SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week,
				LEAST(
					COALESCE(
						SUM(
							CASE
								WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
								ELSE '00:00:00'::interval
							END
						) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
						'00:00:00'::interval
					),
					'08:00:00'::interval
				) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    re_mensual AS (
        SELECT rs.reg_cod_personal,
				LEAST(
					SUM(rs.re_semanal_suma),
					'32:00:00'::interval
				) AS re_mensual_suma
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    ),
	re_acumulada_semanal AS (
		-- CTE que acumula las RE semanalmente, reiniciando cada lunes (EXTRACT(ISODOW) = 1)
		SELECT rd.reg_cod_personal,
				rd.reg_fecha,
				EXTRACT(WEEK FROM rd.reg_fecha) AS semana,
				rd.re,
				SUM(rd.re) OVER (PARTITION BY rd.reg_cod_personal, EXTRACT(YEAR FROM rd.reg_fecha), EXTRACT(WEEK FROM rd.reg_fecha) 
									ORDER BY rd.reg_fecha ROWS UNBOUNDED PRECEDING) AS re_acumulada_semanal
		FROM re_diaria rd
		WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5  -- Considerar solo días de lunes a viernes
	),
	re_mensual_con_limited AS (
		-- Aplica un límite de 08:00 horas por semana a las RE
		SELECT rsa.reg_cod_personal,               -- Código de la persona
				rsa.reg_fecha,                      -- Fecha de la marcación
				rsa.re,
				-- Suma diaria limitada por la acumulación semanal (máximo 08:00 horas por semana)
				CASE
					-- Si la acumulación semanal es mayor o igual a 08:00:00, no sumamos más horas
					WHEN rsa.re_acumulada_semanal > '08:00:00'::interval THEN '00:00:00'::interval
					-- Si la acumulación semanal es menor a 08:00:00, sumamos las horas RE restantes
					ELSE rsa.re
				END AS re_con_limited
		FROM re_acumulada_semanal rsa
	),
	re_acumulada_mensual AS (
		-- CTE que acumula las RE a lo largo del mes, respetando el límite de 08:00 horas por semana
		SELECT rml.reg_cod_personal,               -- Código de la persona
				rml.reg_fecha,                      -- Fecha de la marcación
				SUM(rml.re_con_limited) OVER (
					PARTITION BY rml.reg_cod_personal ORDER BY rml.reg_fecha
				) AS re_acumulada_mensual           -- RE acumulada mensual con el tope semanal aplicado
		FROM re_mensual_con_limited rml
	),
	ra AS (
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
				-- Cálculo de horas adicionales (RA) basado en las validaciones de RE semanal y mensual
				CASE
					-- Escenario excepcional HORAS ESTATICAS
					WHEN rd.ocu_tipo = 12 AND rd.ocu_horas_estaticas = 1 THEN rd.ocu_horas_adicionales::interval+rd.ocu_horas_adicionales_100::interval
					-- Si es sábado, el RA será el total de horas trabajadas sin importar el retraso
					WHEN EXTRACT(ISODOW FROM rd.reg_fecha) = 6 THEN rd.reg_horas_trabajadas
					--si no hay re 
					WHEN rd.re < '01:00:00'::interval THEN '00:00:00'::interval		
					-- Si tiene retraso mayor a 00:00:59 y no es sábado, no sumamos horas RA
					--WHEN rd.reg_retraso > '00:00:59'::interval THEN '00:00:00'::interval
					-- Validación: Si la RE acumulada semanal es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
					WHEN ras.re_acumulada_semanal > '08:00:00'::interval THEN
						CASE
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
							THEN rd.reg_horas_trabajadas  - '08:00:00'::interval
							ELSE '00:00:00'::interval
						END
					-- Validación: Si la RE acumulada mensual es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
					WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval THEN
					   CASE
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval THEN rd.reg_horas_trabajadas - '09:00:00'::interval
						   ELSE '00:00:00'::interval
						END
					-- Validación para RE mensual mayor a 34 horas
					WHEN ram.re_acumulada_mensual > '34:00:00'::interval THEN
					   CASE
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval THEN rd.reg_horas_trabajadas - '08:00:00'::interval
						   ELSE '00:00:00'::interval
						END
					-- Cálculo general: Si ninguna de las validaciones anteriores aplica, se calcula RA si las horas trabajadas son más de 10:00:00
					ELSE
						CASE
							WHEN rd.reg_horas_trabajadas > '10:00:00'::interval THEN rd.reg_horas_trabajadas - '10:00:00'::interval
							ELSE '00:00:00'::interval
						END
				END AS ra
		FROM re_diaria rd
			LEFT JOIN re_acumulada_semanal ras ON rd.reg_cod_personal = ras.reg_cod_personal AND rd.reg_fecha = ras.reg_fecha
			LEFT JOIN re_acumulada_mensual ram ON rd.reg_cod_personal = ram.reg_cod_personal AND rd.reg_fecha = ram.reg_fecha
	),
	ra_semanal_suma AS (
		SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week,
				SUM(
					CASE
						-- Sumar directamente las horas adicionales (RA) sin límite o tope
						WHEN rd.ra IS NOT NULL THEN rd.ra
						ELSE '00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_semanal_suma
		FROM ra rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
	ra_mensual_suma AS (
        SELECT rs.reg_cod_personal,
				SUM(rs.ra_semanal_suma) AS ra_mensual_suma
		FROM ra_semanal_suma rs
		GROUP BY rs.reg_cod_personal
    ),
	ra_dividida AS (
	    SELECT ra.reg_cod_personal,
				ra.reg_fecha,
				ra.ra,  -- El valor de RA calculado previamente
				ra.reg_hora_salida, -- Hora de salida
				ra.reg_horas_trabajadas,
				ra.ocu_tipo,
				ra.ocu_horas_estaticas,
				ra.ocu_horas_extras,
				ra.ocu_horas_adicionales,
				ra.ocu_horas_adicionales_100,
				
				-- Cálculo de RA_80 (hasta las 19:59:59)
				CASE
					--Calculo excepcional ocu tipo 12  horas estaticas
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 THEN ra.ocu_horas_adicionales::interval
					-- Si es sábado, RA_80 es siempre '00:00:00'
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 THEN '00:00:00'::interval
					-- Si la hora de salida es menor o igual a las 19:59:59, todo RA se contabiliza en RA_80
					WHEN ra.reg_hora_salida <= '19:59:59'::time THEN ra.ra
					-- Si la hora de salida es después de las 19:59:59, calculamos cuánto tiempo adicional fue antes de las 19:59:59
					ELSE 
						 ra.ra - (ra.reg_hora_salida - '19:59:59'::time)::interval
				END AS ra_80,
	        
				-- Cálculo de RA_100 (después de las 19:59:59)
				CASE
					--Calculo excepcional ocu tipo 12  horas estaticas
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 THEN ra.ocu_horas_adicionales_100::interval
					-- Si es sábado (día de la semana = 6) y hay horas trabajadas, todo RA se asigna a RA_100
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 THEN ra.reg_horas_trabajadas
					-- Si la hora de salida es después de las 19:59:59, calculamos RA_100
					WHEN ra.reg_hora_salida > '19:59:59'::time THEN
					  LEAST(ra.ra, (ra.reg_hora_salida - '19:59:59'::time)::interval)
					-- Si la hora de salida es antes de las 19:59:59, no hay RA_100
					ELSE '00:00:00'::interval
				END AS ra_100
	
	    FROM ra  -- Utilizamos el CTE `ra` previamente calculado para obtener los valores de RA
	),
	ra_divida_semanal_suma AS (
		SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week,
				SUM(
					CASE
						-- Sumar directamente las horas adicionales (RA) sin límite o tope  Sumar solo si rd.ra_80 es mayor que '00:00:00'
						WHEN rd.ra_80 IS NOT NULL AND rd.ra_80 > '00:00:00'::interval THEN rd.ra_80
						ELSE '00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal,
				SUM(
					CASE
						-- Sumar directamente las horas adicionales (RA) sin límite o tope
						WHEN rd.ra_100 IS NOT NULL THEN rd.ra_100
						ELSE '00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal
    	FROM ra_dividida rd
    	GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
 	ra_dividia_mensual_suma AS (
        SELECT rs.reg_cod_personal,
				SUM(rs.ra_80_semanal) AS ra_80_mensual,
				SUM(rs.ra_100_semanal) AS ra_100_mensual
		FROM ra_divida_semanal_suma rs
		GROUP BY rs.reg_cod_personal
    ),
	re_recalculada AS (
		SELECT ras.reg_cod_personal,
				ras.reg_fecha,
				rd.reg_horas_trabajadas,
				ras.re,
				ras.re_acumulada_semanal,
				CASE
					-- Verifica si `re_acumulada_semanal` es mayor o igual a 08:00:00
					WHEN ras.re_acumulada_semanal >= '08:00:00'::interval THEN
						CASE
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval THEN
								ras.re - (ras.re_acumulada_semanal - '08:00:00'::interval)
							ELSE
								'00:00:00'::interval
						END
					ELSE
						-- Si `re_acumulada_semanal` no es mayor o igual a 08:00:00, simplemente devuelve `re` original
						'00:00:00'::interval
				END AS re_recalculada
		FROM re_acumulada_semanal ras
			JOIN re_diaria rd ON ras.reg_cod_personal = rd.reg_cod_personal AND ras.reg_fecha = rd.reg_fecha
	)
    SELECT r.reg_fecha,				-- Fecha del registro
			r.reg_cod_personal,		-- Código del personal
			p.tur_entrada, 			-- Hora de entrada del turno programado
			p.tur_salida,			-- Hora de salida del turno programado
			p.par_valor_time,		-- Valor del parámetro de tolerancia del turno
			p.reg_hora_entrada,		-- Hora de la marcación de entrada
			p.reg_hora_salida,		-- Hora de la marcación de salida
			p.reg_horas_trabajadas,	-- Horas trabajadas calculadas
			p.reg_retraso,			-- Retraso calculado
			p.reg_horas_extras,		-- Horas extras iniciales
			-- Utilizamos 're_recalculada' si es diferente de '00:00:00', de lo contrario, usamos 'r.re'
			CASE
				WHEN re_rec.re_recalculada <> '00:00:00'::interval THEN re_rec.re_recalculada
				ELSE r.re
			END AS re,
			r.horas_a_compensar,	-- Horas a compensar (de compensaciones)
			r.horas_compensadas,	-- Horas ya compensadas
			r.horas_restantes,		-- Horas restantes por compensar
			r.estado_compensacion,	-- Estado de la compensación
			s.re_semanal_suma,
			m.re_mensual_suma,
			ra_semanal.re_acumulada_semanal, 
			ra_mensual.re_acumulada_mensual,
			ra.ra AS horas_adicionales,
			ras.ra_semanal_suma,
			ma.ra_mensual_suma,
			ra_dividida.ra_80,  
			ra_dividida.ra_100,  
			rds.ra_80_semanal,
			rds.ra_100_semanal,
			rdm.ra_80_mensual,
			rdm.ra_100_mensual,
			btrim(
				CASE
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
					ELSE NULL
				END
			) AS dia_semana,
			of.ocu_descripcion AS ocurrencia_descripcion,
			of.ocurrencia_tipo,
			of.ocu_tipo,
			of.tip_codigo,
			ff.feriado_descripcion,
			CASE
				WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				ELSE NULL
			END AS tolerancia_especial
	FROM re_diaria r
		LEFT JOIN marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
		LEFT JOIN re_recalculada re_rec ON r.reg_cod_personal = re_rec.reg_cod_personal AND r.reg_fecha = re_rec.reg_fecha
		LEFT JOIN ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
		LEFT JOIN feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
		LEFT JOIN tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
		LEFT JOIN re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
		LEFT JOIN re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
		LEFT JOIN re_acumulada_semanal ra_semanal ON r.reg_cod_personal = ra_semanal.reg_cod_personal AND r.reg_fecha = ra_semanal.reg_fecha
		LEFT JOIN re_acumulada_mensual ra_mensual ON r.reg_cod_personal = ra_mensual.reg_cod_personal AND r.reg_fecha = ra_mensual.reg_fecha
		LEFT JOIN ra ra ON r.reg_cod_personal = ra.reg_cod_personal AND r.reg_fecha = ra.reg_fecha
		LEFT JOIN ra_dividida ON ra.reg_cod_personal = ra_dividida.reg_cod_personal AND ra.reg_fecha = ra_dividida.reg_fecha
		LEFT JOIN ra_semanal_suma ras ON r.reg_cod_personal = ras.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = ras.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		LEFT JOIN ra_mensual_suma ma ON r.reg_cod_personal = ma.reg_cod_personal
		LEFT JOIN ra_divida_semanal_suma rds ON r.reg_cod_personal = rds.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = rds.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		LEFT JOIN ra_dividia_mensual_suma rdm ON r.reg_cod_personal = rdm.reg_cod_personal
    ORDER BY r.reg_fecha, r.reg_cod_personal;
END; 
$function$
;



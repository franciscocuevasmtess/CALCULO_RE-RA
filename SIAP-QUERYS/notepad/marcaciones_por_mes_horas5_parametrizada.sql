CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas5_parametrizada(
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
DECLARE
    param RECORD;
BEGIN
	-- Obtener los parámetros del año solicitado.
    SELECT * INTO param
    FROM calculo_parametros
    WHERE periodo_year = anio
    LIMIT 1;
	
    IF param IS NULL THEN
        RAISE EXCEPTION 'No hay parámetros para el año %', anio;
    END IF;
   	
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
       				WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval + e.tol_tiempo_interval) 
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
	 - Identifica y consolida todas las "ocurrencias" (permisos, licencias, vacaciones, etc.) 
	 aplicables a un empleado durante el mes. Utiliza generate_series para "expandir" las 
	 ocurrencias de rango de fechas a días individuales y luego las agrupa para manejar 
	 múltiples ocurrencias en un mismo día. 
	 Excluye fines de semana para ciertos tipos de ocurrencia (ej. vacaciones).
	*/
	ocurrencias_filtradas AS (
		SELECT subquery.reg_cod_personal,	-- Código del personal
				subquery.reg_fecha,			-- Fecha del día específico. Generada por 'generate_series' para cada día de la ocurrencia dentro del mes.
				STRING_AGG(subquery.ocu_descripcion::text, ', ' ORDER BY subquery.ocu_descripcion)::text AS ocu_descripcion,				-- Agrupa descripciones de ocurrencias por día
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
		SELECT c.date AS reg_fecha, -- Fecha del calendario (cada día del mes).
				COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal, -- Código de personal consolidado
				-- Lógica compleja para calcular `re` (horas extras finales por día)
				-- Esta es la parte central que determina las "horas extra" o "recargo extra" según varias reglas de negocio.
				CASE
					-- Escenario excepcional: HORAS ESTATICAS (ocu_tipo = 12 y ocu_horas_estaticas = 1)
					-- Si la ocurrencia es de tipo 12 (ej. un tipo especial de permiso o evento) Y se ha marcado con 'ocu_horas_estaticas = 1' (indicando que las horas extra ya están predefinidas por la ocurrencia).
					WHEN of.ocu_tipo = 12 AND of.ocu_horas_estaticas = 1 
						THEN of.ocu_horas_extras::interval	-- Las RE son las horas extras definidas en la ocurrencia
    				
					-- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras (RE es 0)
					-- Si el empleado tiene un saldo positivo de horas restantes a compensar.
    				WHEN cd.com_det_horas_restantes > '00:00:00'::interval 
    					THEN '00:00:00'::interval
    				
					-- Escenario 2: Si la persona llegó tarde (retraso > 0) y NO tiene permisos específicos (tipos 33, 26, 12, 29), no se calculan horas extras
					-- Verifica si el empleado tuvo un retraso en la entrada Y no hay ninguna ocurrencia específica (33, 26, 12, 29) que justifique ese retraso.
					WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) 
						THEN '00:00:00'::interval

    				-- Nuevo Escenario (específico para ocu_tipo = 12 y retraso > 59 segundos) Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
					-- Si existe una ocurrencia del tipo 12 Y el retraso en la marcación es significativo (más de 59 segundos).
					WHEN EXISTS (
						SELECT 1
						FROM ocurrencias_filtradas of
						WHERE of.reg_fecha = c.date
						AND of.ocu_tipo = 12
					) AND p.reg_retraso > '00:59:59'::interval 
    					THEN
        					CASE
								-- Si las horas trabajadas desde la entrada del turno (programado) hasta la salida real son más de 9 horas.
            					WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
            						THEN
                						LEAST(
                    						(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval, -- Las horas extra son el exceso sobre 8 horas (calculado desde la entrada del turno, no la marcación real).
                    						param.max_re_diario -- Pero se topan a un máximo de 2 horas.
                						)
            					ELSE 
            						'00:00:00'::interval -- Si no se cumple la condición de las 9 horas, no hay extras.
        					END
					
    				-- Escenario 3: No hay horas pendientes DE COMPENSAR, PERO hay permisos específicos (tipos 33, 26, 12, 29), calcular horas extras con reglas especiales
					-- Si no hay horas restantes a compensar Y existe alguna ocurrencia específica que podría afectar el cálculo de horas extras.
					WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) 
						THEN
							CASE
								WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval 
									THEN -- Misma lógica que el "Nuevo Escenario" de arriba
										CASE
											WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
												THEN
													LEAST((p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval, param.max_re_diario)
											ELSE 
												'00:00:00'::interval
										END
								WHEN of.ocu_tipo = 29 
									THEN -- Lógica específica para ocu_tipo 29 (ej. permiso de salida)
										-- Aquí se ajusta el cálculo de las horas trabajadas restando las horas compensadas (`cd.com_det_horas_compensadas`).
										CASE
											WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > '09:00:00'::interval 
												THEN
													LEAST((p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - '08:00:00'::interval, param.max_re_diario)
											ELSE 
												'00:00:00'::interval
										END
								ELSE -- Lógica general para otros tipos de ocurrencia
									CASE
										WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
											THEN
												LEAST((p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval, param.max_re_diario)
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
    					THEN 
							'00:00:00'::interval

    				-- Escenario 5: Cálculo general de RE si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
					-- Este es el caso "por defecto" para calcular las horas extras si ninguna de las condiciones especiales anteriores se cumplió.
					WHEN p.reg_horas_trabajadas > '09:00:00'::interval
    					THEN
        					LEAST(p.reg_horas_trabajadas - '08:00:00'::interval, param.max_re_diario) -- Si trabajó más de 9 horas, las extras son el exceso sobre 8 horas, topado a 2 horas.

					-- En caso contrario (si ninguna de las condiciones anteriores se cumple), las horas extras son 00:00:00
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
	/*
	 * CTE re_semanal. 
	 Esta CTE es crucial para agrupar las horas de recargo extra (re) calculadas diariamente y consolidarlas 
	 a nivel semanal, aplicando límites máximos tanto diarios como semanales.
	*/
	re_semanal AS (
        SELECT rd.reg_cod_personal, -- Código del personal.
				EXTRACT(WEEK FROM rd.reg_fecha) AS week, -- Número de semana del año para la fecha del registro. Esta columna se usa para agrupar los datos semanalmente.
				LEAST( -- LEAST asegura que el resultado no exceda el 'max_re_semanal'.
					COALESCE( -- COALESCE maneja el caso donde SUM podría devolver NULL (si no hay días que cumplan el filtro), convirtiéndolo a '00:00:00'.
						SUM( -- Suma los valores de RE para todos los días de la semana que cumplen la condición.
							CASE
								WHEN rd.re >= '01:00:00' -- Si las RE calculadas para el día son de 1 hora o más...
									THEN 
										LEAST(rd.re, param.max_re_diario)
								ELSE -- ...entonces toma el valor de 're' o el 'max_re_diario', el que sea menor. Esto limita las RE diarias.
									'00:00:00'::interval
							END
						) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) = ANY(ARRAY(
							-- FILTRO: Esta parte asegura que solo se sumen las RE de los días laborables definidos en los parámetros.
							-- EXTRACT(ISODOW FROM rd.reg_fecha): Devuelve el día de la semana como un entero (1=Lunes, 7=Domingo según ISO 8601).
							-- ARRAY(SELECT jsonb_array_elements_text(param.dias_laborables)::int): Esto asume que 'param.dias_laborables'
							-- es un campo JSONB que contiene un array de enteros (ej. '[1,2,3,4,5]' para L-V).
							-- 'jsonb_array_elements_text' extrae cada elemento del array JSON como texto, y '::int' lo convierte a entero.
							-- ANY(...): Compara si el día de la semana actual es uno de los días laborables definidos.
							SELECT jsonb_array_elements_text(param.dias_laborables)::int
						))),
						'00:00:00'::interval -- Si el SUM retorna NULL (ej. no hay días laborables con RE), se convierte a 0 horas.
					),
					param.max_re_semanal -- El resultado de la suma diaria topada se compara con 'max_re_semanal', y se toma el valor menor. Esto aplica el límite semanal.
				) AS re_semanal_suma
        FROM re_diaria rd -- Se toma como fuente de datos la CTE 're_diaria', que ya calculó las RE por día.
        -- Agrupación:
		GROUP BY 
			rd.reg_cod_personal, -- Agrupa por empleado.
			EXTRACT(WEEK FROM rd.reg_fecha) -- Agrupa por semana. Esto crea una fila por cada empleado por cada semana del mes.
    ),
	/*
	 * CTE re_mensual.
	 - Se encarga de la consolidación final de las horas de recargo extra.
	 - Da el monto definitivo de las horas de recargo extra para el período de un mes para cada 
	  empleado, después de haber pasado por todas las reglas de negocio diarias y semanales.
	*/
    re_mensual AS (
        SELECT rs.reg_cod_personal, -- Código del personal.
				LEAST( -- LEAST asegura que el resultado no exceda el 'max_re_mensual'.
					SUM(rs.re_semanal_suma), -- Suma las horas semanales de RE consolidadas en 're_semanal' para el empleado.
					param.max_re_mensual -- El resultado de la suma se compara con 'param.max_re_mensual', y se toma el valor menor. Esto aplica el límite mensual.
				) AS re_mensual_suma
        FROM re_semanal rs -- Se toma como fuente de datos la CTE 're_semanal', que ya calculó las RE por semana (y aplicó límites diarios y semanales).
        GROUP BY 
			rs.reg_cod_personal -- Agrupa por empleado. Esto consolida todas las semanas de un empleado en una única fila mensual.
    ),
	/*
	 * CTE re_acumulada_semanal
	  Proporciona un "subtotal en curso" de las horas de recargo extra para cada día laboral de un 
	  empleado, reiniciándose al comienzo de cada semana.
	*/
	re_acumulada_semanal AS (
		-- CTE que acumula las RE semanalmente, reiniciando cada lunes (EXTRACT(ISODOW) = 1)
		SELECT rd.reg_cod_personal, 						-- Código del personal.
				rd.reg_fecha, 								-- Fecha del día específico.
				EXTRACT(WEEK FROM rd.reg_fecha) AS semana, 	-- Número de semana del año para la fecha. Útil para particionar la acumulación.
				rd.re,										-- Horas de recargo extra (RE) para ese día.
				SUM(rd.re) OVER (
					PARTITION BY 
						rd.reg_cod_personal, 				-- La suma se calcula de forma independiente para cada empleado.
						EXTRACT(YEAR FROM rd.reg_fecha), 	-- Y para cada año (para manejar el cambio de año correctamente si el mes cubre dos años).
						EXTRACT(WEEK FROM rd.reg_fecha) 	-- Y crucialmente, la suma se reinicia para cada nueva semana.
					ORDER BY 
						rd.reg_fecha -- La suma se acumula ordenando los días por fecha (del más antiguo al más reciente).
						ROWS UNBOUNDED PRECEDING
				) AS re_acumulada_semanal -- Suma desde el inicio de la partición (el primer día de la semana) hasta la fila actual.
		FROM re_diaria rd -- Se toma como fuente de datos la CTE 're_diaria', que tiene las RE diarias.
		WHERE EXTRACT(ISODOW FROM rd.reg_fecha) = ANY(ARRAY(
			-- FILTRO: Considerar solo días laborables para la acumulación semanal.
            -- Esto significa que si 're_diaria' produjo RE para un fin de semana (dependiendo de tu lógica),
            -- esta CTE las ignora en esta acumulación semanal.
            -- Se asume que 'param.dias_laborables' es un array de enteros que define los días laborables (1=Lunes, 7=Domingo).
			SELECT jsonb_array_elements_text(param.dias_laborables)::int
		))  -- Considerar solo días de lunes a viernes
	),
	/*
	 * CTE re_mensual_con_limited. 
	 - Esta CTE refina aún más el cálculo de las horas extras (re) aplicando el límite semanal a nivel 
	 diario, basándose en la acumulación diaria dentro de la semana.
	*/
	re_mensual_con_limited AS (
		-- Aplica un límite de 08:00 horas por semana a las RE
		SELECT rsa.reg_cod_personal,		-- Código de la persona
				rsa.reg_fecha,				-- Fecha de la marcación
				rsa.re,						-- Horas de recargo extra (RE) calculadas para ese día (sin límite semanal aún).
				-- Suma diaria limitada por la acumulación semanal (máximo 08:00 horas por semana)
				CASE
					-- Si la acumulación semanal es mayor o igual a 08:00:00, no sumamos más horas
					WHEN rsa.re_acumulada_semanal > param.max_re_semanal 
						THEN 
							'00:00:00'::interval
					-- Si la acumulación semanal es menor a 08:00:00, sumamos las horas RE restantes
					ELSE 
						rsa.re
				END AS re_con_limited
		FROM re_acumulada_semanal rsa -- Se toma como fuente de datos la CTE 're_acumulada_semanal', que tiene las RE diarias y su acumulación semanal.
	),
	/*
	 * CTE re_acumulada_mensual. 
	 - Esta CTE es el paso final para obtener un acumulado de las horas de recargo extra a lo largo de todo el 
	 mes, incorporando todas las reglas de negocio anteriores (diarias, semanales y límites).
	*/
	re_acumulada_mensual AS (
		-- CTE que acumula las RE a lo largo del mes, respetando el límite de 08:00 horas por semana
		SELECT rml.reg_cod_personal,               	-- Código de la persona
				rml.reg_fecha,                      -- Fecha de la marcación
				SUM(rml.re_con_limited) OVER (
					PARTITION BY 
						rml.reg_cod_personal 	-- La suma se calcula de forma independiente para cada empleado.
					ORDER BY 
						rml.reg_fecha			-- La suma se acumula ordenando los días por fecha (del más antiguo al más reciente) dentro del mes.
				) AS re_acumulada_mensual       -- El marco de la ventana por defecto es 'RANGE UNBOUNDED PRECEDING', lo que suma desde el inicio de la partición hasta la fila actual.
		FROM re_mensual_con_limited rml			-- Se toma como fuente de datos la CTE 're_mensual_con_limited', que ya tiene las RE diarias ajustadas por el límite semanal.
	),
	/*
	 * CTE ra 
	 - Es donde se calcula el "Recargo Adicional" (RA), que a menudo se refiere a horas extras con una tasa de pago más 
	 alta (ej. 80% o 100% de recargo) o a horas trabajadas más allá de un cierto umbral, una vez que las horas "normales" 
	 de recargo extra (re) ya han sido consideradas y limitadas. La lógica aquí es bastante compleja, ya que depende 
	 de múltiples factores y reglas de negocio.
	*/
	ra AS (
		SELECT rd.reg_cod_personal,				-- Código del personal.
				rd.reg_fecha,					-- Fecha del día.
				rd.reg_hora_salida,				-- Hora de salida registrada.
				rd.reg_horas_trabajadas,		-- Horas trabajadas para el día.
				rd.reg_retraso,					-- Retraso en la entrada para el día.
				rd.ocu_tipo,					-- Tipo de ocurrencia principal para el día.
				rd.ocu_horas_estaticas,			-- Indicador de horas estáticas en ocurrencia.
				rd.ocu_horas_extras,			-- Horas extras predefinidas en ocurrencia.
				rd.ocu_horas_adicionales,		-- Horas adicionales (80%) predefinidas en ocurrencia.
				rd.ocu_horas_adicionales_100,	-- Horas adicionales (100%) predefinidas en ocurrencia.
				
				-- ra:
				-- Calcula el valor final de las horas de Recargo Adicional (RA) para cada día,
				-- aplicando una jerarquía compleja de reglas de negocio que consideran ocurrencias,
				-- días de la semana, retrasos y acumulados semanales/mensuales de RE.
				CASE
					-- Escenario 1: HORAS ESTATICAS (ocu_tipo = 12 y ocu_horas_estaticas = 1)
					-- Si la ocurrencia es de tipo 12 Y se ha marcado con 'ocu_horas_estaticas = 1'.
					WHEN rd.ocu_tipo = 12 AND rd.ocu_horas_estaticas = 1 
						THEN rd.ocu_horas_adicionales::interval + rd.ocu_horas_adicionales_100::interval
						-- Las RA son la suma de las horas adicionales predefinidas en la ocurrencia (RA 80% + RA 100%).
						
					-- Escenario 2: Si es sábado
					-- Si el día de la semana es Sábado (ISODOW = 6).
					WHEN EXTRACT(ISODOW FROM rd.reg_fecha) = 6 
						THEN rd.reg_horas_trabajadas
						-- Las RA son las horas trabajadas totales del sábado. Esto implica que todo lo trabajado un sábado se considera "recargo adicional".
						
					-- Escenario 3: Si no hay RE calculadas para el día (menos de 1 hora de RE).
					WHEN rd.re < '01:00:00'::interval 
						THEN '00:00:00'::interval
						-- Si no hubo al menos 1 hora de Recargo Extra (RE), no hay Recargo Adicional (RA).
						
					-- Si tiene retraso mayor a 00:00:59 y no es sábado, no sumamos horas RA
					--WHEN rd.reg_retraso > '00:00:59'::interval THEN '00:00:00'::interval
					
					-- Escenario 5: Validación para RE acumulada semanal (si supera el límite semanal)
					-- Si la acumulación semanal de RE (hasta este día) ya es mayor que el límite semanal (param.max_re_semanal).
					WHEN ras.re_acumulada_semanal > param.max_re_semanal 
						THEN
							CASE
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval -- Si las horas trabajadas superan las 9 horas.
									THEN rd.reg_horas_trabajadas  - '08:00:00'::interval -- Las RA son las horas trabajadas que exceden las 8 horas (diferente al cálculo normal de RE que resta 9h).
								ELSE 
									'00:00:00'::interval
							END
					
					-- Escenario 6: Validación para RE acumulada mensual (entre 32 y 33:59:59 horas)
					-- Si la acumulación mensual de RE (hasta este día) está en este rango específico.
					WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval THEN
						CASE
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval -- Si las horas trabajadas superan las 9 horas.
								THEN rd.reg_horas_trabajadas - '09:00:00'::interval -- Las RA son las horas trabajadas que exceden las 9 horas.
							ELSE 
								'00:00:00'::interval
						END
					
					-- Validación para RE mensual mayor a 34 horas
					
					-- Escenario 7: Validación para RE mensual mayor a 34 horas
					-- Si la acumulación mensual de RE (hasta este día) supera las 34 horas.
					WHEN ram.re_acumulada_mensual > '34:00:00'::interval THEN
						CASE
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval -- Si las horas trabajadas superan las 9 horas.
								THEN rd.reg_horas_trabajadas - '08:00:00'::interval -- Las RA son las horas trabajadas que exceden las 8 horas.
							ELSE 
								'00:00:00'::interval
						END
					
					-- Escenario 8: Cálculo general (si ninguna de las validaciones anteriores aplica)
					-- Si ninguna de las condiciones anteriores se cumple.
					ELSE
						CASE
							WHEN rd.reg_horas_trabajadas > param.limite_ra_normal -- Si las horas trabajadas superan un límite normal para RA (ej. 10:00:00).
								THEN rd.reg_horas_trabajadas - param.limite_ra_normal -- Las RA son el excedente sobre ese límite normal.
							ELSE 
								'00:00:00'::interval
						END
				END AS ra -- Fin de la lógica CASE para la columna 'ra'.
		FROM re_diaria rd -- Fuente principal de datos diarios.
			LEFT JOIN re_acumulada_semanal ras ON rd.reg_cod_personal = ras.reg_cod_personal AND rd.reg_fecha = ras.reg_fecha -- Une para acceder a la RE acumulada semanal.
			LEFT JOIN re_acumulada_mensual ram ON rd.reg_cod_personal = ram.reg_cod_personal AND rd.reg_fecha = ram.reg_fecha -- Une para acceder a la RE acumulada mensual.
	),
	/*
	 * Esta CTE da el monto total de las horas de recargo adicional acumuladas por cada empleado 
	 por semana, excluyendo los domingos.
	*/
	ra_semanal_suma AS (
		SELECT rd.reg_cod_personal, -- Código del personal.
				EXTRACT(WEEK FROM rd.reg_fecha) AS week, -- Número de semana del año para la fecha del registro. Esta columna se usa para agrupar los datos semanalmente.
				
				-- ra_semanal_suma:
				-- Calcula la suma total de las horas de Recargo Adicional (RA) para la semana.
				SUM( -- SUMa los valores de RA para todos los días de la semana que cumplen la condición.
					CASE
						-- Si rd.ra tiene un valor (es decir, no es NULL), sumarlo directamente.
						-- Esto implica que, a diferencia de 're', no se aplica un límite diario o un umbral mínimo de 1 hora para RA a nivel de suma semanal en este punto.
						WHEN rd.ra IS NOT NULL 
							THEN rd.ra
						ELSE 
							'00:00:00'::interval -- Si rd.ra es NULL (no hubo RA para ese día), se considera 0.
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_semanal_suma
				-- FILTRO: Esta parte asegura que solo se sumen las RA de los días de Lunes a Sábado.
				-- EXTRACT(ISODOW FROM rd.reg_fecha): Devuelve el día de la semana como un entero (1=Lunes, 7=Domingo según ISO 8601).
				-- <= 6: Incluye Lunes (1), Martes (2), Miércoles (3), Jueves (4), Viernes (5), y Sábado (6). Los Domingos (7) quedan excluidos de esta suma.
		
		FROM ra rd -- Se toma como fuente de datos la CTE 'ra', que ya calculó las RA por día con sus reglas complejas.
		
		-- Agrupación:
		GROUP BY 
			rd.reg_cod_personal, -- Agrupa por empleado.
			EXTRACT(WEEK FROM rd.reg_fecha) -- Agrupa por semana. Esto crea una fila por cada empleado por cada semana del mes.
	),
	/*
	 * CTE ra_mensual_suma. 
	 - Esta es una CTE sencilla y directa que consolida el Recargo Adicional (ra) al nivel mensual.
	 - Da el monto total de las horas de recargo adicional que un empleado ha acumulado durante el 
	 mes, sumando sus totales semanales.
	*/
	ra_mensual_suma AS (
        SELECT rs.reg_cod_personal, -- Código del personal.
				
				-- ra_mensual_suma:
				-- Calcula la suma total de las horas de Recargo Adicional (RA) para todo el mes.
				SUM(rs.ra_semanal_suma) AS ra_mensual_suma
				-- Simplemente suma los totales de RA de cada semana (calculados en 'ra_semanal_suma') para cada empleado.
				-- No se aplica ningún límite mensual en esta CTE, lo que sugiere que si hay un límite para RA,
				-- se aplicaría en una CTE posterior o en la consulta final que use este resultado.
		
		FROM ra_semanal_suma rs -- Se toma como fuente de datos la CTE 'ra_semanal_suma', que ya calculó las RA por semana.
		
		-- Agrupación:
		GROUP BY 
			rs.reg_cod_personal -- Agrupa por empleado. Esto consolida todas las semanas de un empleado en una única fila mensual.
    ),
	ra_dividida AS (
	    SELECT ra.reg_cod_personal,				-- Código del personal.
				ra.reg_fecha,					-- Fecha del día.
				ra.ra,							-- El valor total de RA calculado previamente para el día.
				ra.reg_hora_salida,				-- Hora de salida registrada del empleado.
				ra.reg_horas_trabajadas,		-- Horas trabajadas para el día.
				ra.ocu_tipo,					-- Tipo de ocurrencia principal.
				ra.ocu_horas_estaticas,			-- Indicador de horas estáticas.
				ra.ocu_horas_extras,			-- Horas extras predefinidas.
				ra.ocu_horas_adicionales,		-- Horas adicionales (80%) predefinidas en ocurrencia.
				ra.ocu_horas_adicionales_100,	-- Horas adicionales (100%) predefinidas en ocurrencia.
				
				-- ra_80 (Cálculo de Recargo Adicional al 80%)
				-- Determina la porción del RA total que se clasifica como RA al 80%.
				-- La lógica principal se basa en si la hora de salida está antes o después de 'param.hora_tope_ra_80'.
				CASE
					-- Escenario 1: Cálculo excepcional para ocurrencia tipo 12 con horas estáticas.
					-- Si la ocurrencia es de tipo 12 Y tiene horas estáticas, el RA_80 es directamente 'ocu_horas_adicionales'.
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales::interval
					
					-- Escenario 2: Si es sábado, RA_80 es siempre '00:00:00'.
					-- Esto implica que, para los sábados, todas las RA se asignan a RA_100 (ver la lógica de ra_100 más abajo).
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN '00:00:00'::interval
					
					-- Escenario 3: Si la hora de salida es antes o igual a 'param.hora_tope_ra_80' (ej. 19:59:59).
					WHEN ra.reg_hora_salida <= param.hora_tope_ra_80 
						THEN ra.ra -- Todo el RA calculado para el día se considera RA_80.
						
					-- Escenario 4: Si la hora de salida es después de 'param.hora_tope_ra_80'.
					ELSE 
						-- Calcula el RA que cae *antes* de la hora tope.
						-- Esto se hace restando el tiempo que el empleado trabajó *después* de la hora tope (reg_hora_salida - param.hora_tope_ra_80)
						-- del total de RA. El resultado es la porción de RA que está antes de la hora tope.
						ra.ra - (ra.reg_hora_salida - param.hora_tope_ra_80)::interval
				END AS ra_80,
	        
				-- ra_100 (Cálculo de Recargo Adicional al 100%):
				-- Determina la porción del RA total que se clasifica como RA al 100%.
				-- La lógica principal se basa en si la hora de salida está después de 'param.hora_tope_ra_80'.
				CASE
					-- Escenario 1: Cálculo excepcional para ocurrencia tipo 12 con horas estáticas.
					-- Si la ocurrencia es de tipo 12 Y tiene horas estáticas, el RA_100 es directamente 'ocu_horas_adicionales_100'.
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales_100::interval
					
					-- Escenario 2: Si es sábado (día de la semana = 6) y hay horas trabajadas.
					-- Toda las horas trabajadas en sábado se consideran RA_100. Esto complementa la regla de RA_80 para sábados.
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN ra.reg_horas_trabajadas
					
					-- Escenario 3: Si la hora de salida es después de 'param.hora_tope_ra_80'.
					WHEN ra.reg_hora_salida > param.hora_tope_ra_80 
						THEN
							-- Calcula cuánto tiempo de RA cae *después* de la hora tope.
							-- LEAST(ra.ra, ...): Asegura que el RA_100 no sea más que el RA total del día.
							-- (ra.reg_hora_salida - param.hora_tope_ra_80): Calcula el tiempo transcurrido desde la hora tope hasta la salida real.
							-- El RA_100 es el mínimo entre el RA total del día y el tiempo trabajado después de la hora tope.
							LEAST(ra.ra, (ra.reg_hora_salida - param.hora_tope_ra_80)::interval)
					
					-- Escenario 4: Si la hora de salida es antes o igual a 'param.hora_tope_ra_80'.
					ELSE 
						'00:00:00'::interval -- No hay RA_100 si la salida es antes de la hora tope.
				END AS ra_100
	
	    FROM ra  -- Utilizamos el CTE `ra` previamente calculado para obtener los valores de RA.
	),
	/*
	 * CTE ra_divida_semanal_suma. 
	 - Esta CTE es el siguiente paso lógico después de ra_dividida, ya que consolida los recargos 
	 adicionales (ra_80 y ra_100) a nivel semanal, aplicando filtros específicos para los días 
	 de la semana.
	*/
	ra_divida_semanal_suma AS (
		SELECT rd.reg_cod_personal,							-- Código del personal.
				EXTRACT(WEEK FROM rd.reg_fecha) AS week, 	-- Número de semana del año para la fecha del registro. Se usa para agrupar semanalmente.
				
				-- ra_80_semanal (Suma semanal de Recargo Adicional al 80%):
				-- Totaliza las horas de RA al 80% para la semana, considerando solo días laborables (Lunes a Viernes).
				SUM( -- Suma los valores de RA_80 para los días que cumplen las condiciones.
					CASE
						-- Condición: Solo suma rd.ra_80 si no es NULL Y es mayor que '00:00:00' (es decir, tiene un valor positivo de RA_80).
						WHEN rd.ra_80 IS NOT NULL AND rd.ra_80 > '00:00:00'::interval 
							THEN rd.ra_80
						ELSE 
							'00:00:00'::interval -- Si no cumple la condición o es NULL/cero, se considera 0 para la suma.
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal,
				-- FILTRO: Esta parte es crucial: solo incluye RA_80 de Lunes a Viernes (ISODOW 1 a 5).
				-- Implica que las RA_80 de fines de semana (Sábados y Domingos) no se contabilizan en esta suma.
				
				-- ra_100_semanal (Suma semanal de Recargo Adicional al 100%):
				-- Totaliza las horas de RA al 100% para la semana, incluyendo días laborables y Sábados.
				SUM( -- Suma los valores de RA_100 para los días que cumplen las condiciones.
					CASE
						-- Condición: Si rd.ra_100 no es NULL, sumarlo directamente.
						-- A diferencia de RA_80, no hay un filtro para '> 00:00:00' aquí, lo que podría implicar que incluso pequeñas cantidades de RA_100 se suman.
						WHEN rd.ra_100 IS NOT NULL 
							THEN rd.ra_100
						ELSE 
							'00:00:00'::interval	-- Si es NULL, se considera 0.
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal
				-- FILTRO: Esta parte es crucial: solo incluye RA_100 de Lunes a Sábado (ISODOW 1 a 6).
				-- Esto es coherente con la lógica de 'ra_dividida' donde los sábados se asignaban completamente a RA_100.
				-- Los Domingos (7) quedan excluidos de esta suma.
		
    	FROM ra_dividida rd -- Se toma como fuente de datos la CTE 'ra_dividida', que ya dividió las RA en 80% y 100%.
    	
		-- Agrupación:
		GROUP BY 
			rd.reg_cod_personal, -- Agrupa por empleado.
			EXTRACT(WEEK FROM rd.reg_fecha) -- Agrupa por semana. Esto crea una fila por cada empleado por cada semana del mes.
	),
	/*
	 * CTE ra_divida_mensual_suma. 
	 - Esta es la CTE final en la cadena de cálculo del Recargo Adicional, consolidando los totales semanales al nivel 
	 mensual para cada tipo de recargo (80% y 100%).
	*/
 	ra_dividia_mensual_suma AS (
        SELECT rs.reg_cod_personal,	-- Código del personal.
				
				-- ra_80_mensual (Suma mensual de Recargo Adicional al 80%):
				-- Totaliza las horas de RA al 80% para todo el mes.
				SUM(rs.ra_80_semanal) AS ra_80_mensual,
				-- Simplemente suma los totales de RA_80 de cada semana (calculados en 'ra_divida_semanal_suma') para cada empleado.
				-- No se aplica ningún límite mensual en esta CTE para RA_80.
		
				-- ra_100_mensual (Suma mensual de Recargo Adicional al 100%):
				-- Propósito: Totaliza las horas de RA al 100% para todo el mes.
				SUM(rs.ra_100_semanal) AS ra_100_mensual
				-- Simplemente suma los totales de RA_100 de cada semana (calculados en 'ra_divida_semanal_suma') para cada empleado.
				-- No se aplica ningún límite mensual en esta CTE para RA_100.
		
		FROM ra_divida_semanal_suma rs	-- Se toma como fuente de datos la CTE 'ra_divida_semanal_suma', que ya calculó las RA 80% y 100% por semana.
		GROUP BY 
			rs.reg_cod_personal	-- Agrupa por empleado. Esto consolida todas las semanas de un empleado en una única fila mensual para ambos tipos de RA.
    ),
	/*
	 * CTE re_recalculada. 
	 - Esta CTE parece intentar ajustar o "recular" el valor de re para un día si el acumulado semanal ya ha alcanzado 
	 o superado un límite, evitando así un posible "doble conteo" o la aplicación incorrecta de horas extras cuando ya 
	 se ha llegado al tope semanal.
	*/
	re_recalculada AS (
		SELECT ras.reg_cod_personal,		-- Código del personal.
				ras.reg_fecha,				-- Fecha del día.
				rd.reg_horas_trabajadas,	-- Horas trabajadas para el día.
				ras.re,						-- Horas de recargo extra (RE) para ese día (sin recalcular aún).
				ras.re_acumulada_semanal,	-- Acumulado semanal de RE hasta este día.
				
				-- re_recalculada
				-- Recalcula o ajusta el valor de 're' para un día, específicamente si el acumulado semanal
				-- de RE ha alcanzado o superado el límite 'param.max_re_semanal'.
				CASE
					-- Verifica si `re_acumulada_semanal` es mayor o igual a 08:00:00
					
					-- Condición Principal: Verifica si el acumulado semanal de RE (hasta este día) es mayor o igual al límite semanal (param.max_re_semanal).
					WHEN ras.re_acumulada_semanal >= param.max_re_semanal 
						THEN
							CASE
								-- Si las horas trabajadas en este día superan las 9 horas.
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN
										-- Lógica de ajuste: Resta el "exceso" semanal del RE de este día.
										-- 'ras.re': El RE original calculado para este día.
										-- '(ras.re_acumulada_semanal - param.max_re_semanal)': Calcula cuánto se ha excedido el límite semanal con la acumulación hasta este día.
										-- El resultado es el RE de este día menos el exceso, potencialmen
										ras.re - (ras.re_acumulada_semanal - param.max_re_semanal)
								ELSE
									'00:00:00'::interval
							END
					ELSE
						-- Si el acumulado semanal de RE aún NO ha alcanzado el límite semanal, entonces 're_recalculada' es 0.
						-- Esta lógica es un poco inusual, ya que normalmente querrías mantener el 're' original en este caso.
						-- Si el propósito es solo "ajustar si se pasa del límite", esta parte debería ser 'ras.re'.
						'00:00:00'::interval
				END AS re_recalculada
		FROM re_acumulada_semanal ras	-- Fuente principal, que proporciona el RE diario y su acumulado semanal.
			JOIN re_diaria rd ON ras.reg_cod_personal = rd.reg_cod_personal AND ras.reg_fecha = rd.reg_fecha
			-- Se une con 're_diaria' para obtener 'reg_horas_trabajadas', que no está directamente en 're_acumulada_semanal'.
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
			
			-- re:
			-- Horas de Recargo Extra (RE) para el día, con prioridad a la versión 'recalculada' si existe un ajuste.
			CASE
				-- Si 're_recalculada' (la versión ajustada por límite semanal) no es '00:00:00' (es decir, hay un ajuste efectivo)...
				WHEN re_rec.re_recalculada <> '00:00:00'::interval 
					THEN re_rec.re_recalculada -- ...entonces usa el valor ajustado.
				ELSE 
					r.re -- De lo contrario, usa el valor original de 're' del día (calculado en 're_diaria').
			END AS re, -- Proviene de la CTE 're_recalculada' (alias 're_rec') o de 're_diaria' (alias 'r').
			
			r.horas_a_compensar,	-- Horas a compensar (de compensaciones)
			r.horas_compensadas,	-- Horas ya compensadas
			r.horas_restantes,		-- Horas restantes por compensar
			r.estado_compensacion,	-- Estado de la compensación (ej. 'PENDIENTE', 'COMPENSADO').
			s.re_semanal_suma, 		-- Suma total de las horas de Recargo Extra (RE) para la semana, con límites diarios y semanales aplicados. Proviene de la CTE 're_semanal' (alias 's').
			m.re_mensual_suma, 		-- Suma total de las horas de Recargo Extra (RE) para el mes, con límite mensual aplicado. Proviene de 're_mensual'
			ra_semanal.re_acumulada_semanal, -- Suma acumulada diaria de RE dentro de cada semana.
			ra_mensual.re_acumulada_mensual, -- Suma acumulada diaria de RE a lo largo de todo el mes.
			ra.ra AS horas_adicionales,	-- Horas de Recargo Adicional (RA) para el día, aplicando múltiples reglas de negocio complejas.
			ras.ra_semanal_suma,		-- Suma total de las horas de Recargo Adicional (RA) para la semana, excluyendo domingos.
			ma.ra_mensual_suma,			-- Suma total de las horas de Recargo Adicional (RA) para el mes.
			ra_dividida.ra_80,  		-- Porción de las horas de Recargo Adicional (RA) que se pagarán con un 80% de recargo.
			ra_dividida.ra_100,  		-- Porción de las horas de Recargo Adicional (RA) que se pagarán con un 100% de recargo.
			rds.ra_80_semanal,			-- Suma semanal de las horas de RA al 80%, considerando solo de Lunes a Viernes.
			rds.ra_100_semanal,			-- Suma semanal de las horas de RA al 100%, considerando de Lunes a Sábado.
			rdm.ra_80_mensual,			-- Suma mensual de las horas de RA al 80%.
			rdm.ra_100_mensual,			-- Suma mensual de las horas de RA al 100%.
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
			of.ocu_descripcion AS ocurrencia_descripcion,	-- Descripción de la ocurrencia aplicada al registro (ej. 'Permiso', 'Vacaciones').
			of.ocurrencia_tipo,		-- Tipo general de la ocurrencia.
			of.ocu_tipo,			-- Código numérico del tipo de ocurrencia.
			of.tip_codigo,			-- Código del tipo de la ocurrencia.
			ff.feriado_descripcion,	-- Descripción del feriado si la fecha del registro coincide con un feriado.
			CASE
				WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				ELSE NULL
			END AS tolerancia_especial	-- Descripción y tiempo de una tolerancia especial si aplica a la fecha del registro.
	FROM re_diaria r	-- La CTE re_diaria actúa como la tabla base, asegurando que cada fila en el resultado corresponda a un registro diario de un empleado.
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


-------------------------------------------
-- REPORTE: MARCACIONES - INFORME MENSUAL
-------------------------------------------
SELECT per_cod,
		per_nombre || ' ' || per_apellido || ' (' || per_cod || ') ' || '(' ||per_ci|| ')' AS full_details
FROM personales
WHERE per_estado = 1
ORDER BY per_cod;

SELECT mes_cod, mes_letras FROM meses ORDER BY mes_cod;

SELECT cod, numero FROM anhos ORDER BY numero;

-- select utilizado para encabezado(Datos del Turno del funcionario)
SELECT t.tur_descripcion,    -- Descripción del turno (ej. "Turno Mañana", "Turno Noche")
		t.tur_entrada,        -- Hora de entrada programada para este turno
		t.tur_salida,         -- Hora de salida programada para este turno
		t.tur_tipo,           -- Código del tipo de turno (ej. 1, 2, 3)
		t.tur_cod_personal,   -- Código del empleado al que está asignado este turno
		pe.per_nombre,        -- Nombre del empleado
		pe.per_apellido,      -- Apellido del empleado
		pe.per_ci,            -- Número de Cédula de Identidad del empleado
		t.tur_horas_trabajo,  -- Horas de trabajo programadas para este turno
		tt.tip_descripcion,   -- Descripción del tipo de turno (ej. "Diurno", "Nocturno", "Rotativo")
		tur_fecha_desde,      -- Fecha de inicio de vigencia de la asignación de este turno al empleado
		tur_fecha_hasta,      -- Fecha de fin de vigencia de la asignación de este turno al empleado (puede ser nula si no tiene fin)
		p.par_valor_time as tolerancia -- Valor del parámetro de tolerancia asociado a este turno (ej. '00:15:00' para 15 minutos)

FROM turnos t -- Tabla principal: 'turnos' (contiene las asignaciones de turnos a los empleados)
        INNER JOIN tipos_turnos tt ON tt.tip_cod = t.tur_tipo -- Une con 'tipos_turnos' para obtener la descripción del tipo de turno (ej. "Diurno"). Requiere que haya un tipo de turno válido.
        INNER JOIN personales pe on pe.per_cod = t.tur_cod_personal -- Une con 'personales' para obtener los datos del empleado. Requiere que el empleado exista.
        INNER JOIN parametros p ON p.par_cod = t.tur_tolerancia -- Une con 'parametros' para obtener el valor de la tolerancia. Requiere que el parámetro de tolerancia exista para ese turno.

WHERE t.tur_cod_personal = 604 -- PRIMER FILTRO: Limita la consulta a un empleado específico (en este caso, el empleado con código 8).

AND t.tur_fecha_desde <= (date_trunc('month', make_date(2024, 6, 1)) + INTERVAL '1 month') - INTERVAL '1 day'
    -- SEGUNDO FILTRO (Inicio de Vigencia del Turno):
    -- Esta parte calcula el ÚLTIMO DÍA del mes de JUNIO de 2024.
    -- make_date(2024, 6, 1): Crea la fecha '2024-06-01'.
    -- date_trunc('month', ...): La trunca al inicio del mes, sigue siendo '2024-06-01'.
    -- + INTERVAL '1 month': Le suma un mes, resultando '2024-07-01'.
    -- - INTERVAL '1 day': Le resta un día, resultando '2024-06-30'.
    -- Entonces, la condición es: `t.tur_fecha_desde <= '2024-06-30'`.
    -- Esto significa que el turno debe haber comenzado en o antes del último día del mes de interés (Junio 2023).

AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= make_date(2024, 6, 1));
    -- TERCER FILTRO (Fin de Vigencia del Turno):
    -- Esta parte asegura que el turno aún sea relevante para el mes de interés (Junio 2023).
    -- t.tur_fecha_hasta IS NULL: Incluye los turnos que no tienen una fecha de fin (son vigentes indefinidamente).
    -- OR t.tur_fecha_hasta >= make_date(2023, 6, 1): Incluye los turnos cuya fecha de fin es igual o posterior al primer día del mes de interés (Junio 2023).
    -- En conjunto, estas dos condiciones garantizan que el turno no haya terminado antes del inicio del mes de interés.
---------------------------------------------------------------------------------------

-- select utilizado en la grilla de datos del funcionario --
SELECT * FROM marcaciones_por_mes_horas5(2024, 6, 604);
-----------------------------------------------------------------------------------------------------

--desde-junio-2023
SELECT --DISTINCT ON (res_func.reg_fecha, res_func.reg_cod_personal)
		res_func.reg_fecha, 
		res_func.reg_cod_personal,
FROM (SELECT per_cod FROM personales WHERE per_estado = 1) AS p -- Personal activo
		CROSS JOIN (SELECT mes_cod FROM meses) AS m -- Todos los meses (del 1 al 12)
		CROSS JOIN (SELECT numero AS anho FROM anhos) AS a -- Todos los años cargados (ej. 2022 a 2025)
		JOIN LATERAL marcaciones_por_mes_horas5(a.anho, m.mes_cod, p.per_cod) AS res_func ON TRUE
WHERE res_func.reg_fecha between '2023-06-30' and '2023-07-04'
and res_func.reg_cod_personal IS NOT null
and res_func.reg_cod_personal = 8; -- Asegura que haya un código de personal válido
-----------------------------------------------------------------------------------------------------

select * from historico_marcaciones_mensual;
select count(*) as total from historico_marcaciones_mensual; --126804; 632613
select * from log_cron_historico_marcaciones;
select insertar_historico_marcaciones_mensual();
---------------------------------------------------------

/*
------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas5(anio integer, mes integer, param_reg_cod_personal integer)
RETURNS TABLE(reg_fecha date, 
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
				tolerancia_especial text)
LANGUAGE plpgsql
AS 
$function$
BEGIN
	PERFORM set_config('timezone', 'UTC', true);
	PERFORM set_config('DateStyle', 'ISO, DMY', true);
	RETURN QUERY
	WITH RECURSIVE calendar AS (
		SELECT DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
		UNION ALL
		SELECT (date + INTERVAL '1 day')::DATE
		FROM calendar
		WHERE date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
	),
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
    			CASE
        			WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada 
        				THEN s.reg_hora - t.tur_entrada
        			ELSE 
        				s.reg_hora - e.reg_hora
    			END AS reg_horas_trabajadas,
    			CASE
       				WHEN t.tur_tipo = 4 
       					THEN '00:00:00'::interval
       				WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval + e.tol_tiempo_interval ) 
       					THEN e.reg_hora - (t.tur_entrada + p.par_valor_time + e.tol_tiempo_interval)
    				ELSE 
    					'00:00:00'::interval
				END AS reg_retraso,
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
	ocurrencias_filtradas AS (
		SELECT subquery.reg_cod_personal,
				subquery.reg_fecha,
				STRING_AGG(subquery.ocu_descripcion::text, ', ' ORDER BY subquery.ocu_descripcion)::text AS ocu_descripcion, 
    			STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo)::text AS ocurrencia_tipo, 
				MIN(subquery.ocu_tipo) AS ocu_tipo,
				STRING_AGG(subquery.tip_codigo::character varying, ', ' ORDER BY subquery.tip_codigo)::character varying AS tip_codigo, 
				MAX(subquery.ocu_horas_estaticas) AS ocu_horas_estaticas,
				SUM(subquery.ocu_horas_extras) AS ocu_horas_extras,
				SUM(subquery.ocu_horas_adicionales) AS ocu_horas_adicionales,
				SUM(subquery.ocu_horas_adicionales_100) AS ocu_horas_adicionales_100
		FROM (
				SELECT o.ocu_cod_persona AS reg_cod_personal,
      					generate_series(
        					GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1)), 
        						LEAST(
            						CASE 
                						-- Mantener tus condiciones existentes
                						WHEN o.ocu_fecha_desde = o.ocu_fecha_hasta 
                							THEN o.ocu_fecha_hasta
                					ELSE 
                						o.ocu_fecha_hasta
            						END,
            						(make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date
        						) ,  -- Añadimos un día al límite superior
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
				FROM ocurrencias o
					JOIN tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
				WHERE o.ocu_cod_persona = param_reg_cod_personal
    			AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date
    			AND o.ocu_fecha_hasta >= make_date(anio, mes, 1)
			) AS subquery
		WHERE NOT (
    			subquery.ocu_tipo = 1 
    			AND 
    			(EXTRACT(DOW FROM subquery.reg_fecha::date) = 6 
    			OR 
    			EXTRACT(DOW FROM subquery.reg_fecha::date) = 0)
			) -- Excluir sábados (6) y domingos (0) para vacaciones
		GROUP BY subquery.reg_cod_personal, subquery.reg_fecha
	), 
	feriados_filtrados AS (
		SELECT f.fer_fecha AS reg_fecha,
    			f.fer_descripcion AS feriado_descripcion
		FROM feriados f
		WHERE EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
	),
	tolerancias_especiales_filtradas AS (
		SELECT te.tol_cod_personal,
    			te.tol_fecha_desde,
    			te.tol_fecha_hasta,
    			te.tol_descripcion,
    			te.tol_tiempo,
    			te.tol_tipo,
    			te.tol_sed_cod
		FROM tolerancias_especiales te
		WHERE (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
    		OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
	), 
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
	re_diaria AS (
		SELECT c.date AS reg_fecha,
				COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
				CASE
					-- Escenario excepcional HORAS ESTATICAS
					WHEN of.ocu_tipo = 12 AND of.ocu_horas_estaticas = 1 
						THEN of.ocu_horas_extras::interval	
    				-- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras
    				WHEN cd.com_det_horas_restantes > '00:00:00'::interval 
    					THEN '00:00:00'::interval

    				-- Escenario 2: Si la persona llegó tarde (más de 1 hora) y no tiene permisos específicos, no se calculan horas extras
    				WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN '00:00:00'::interval

					-- Nuevo Escenario: Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
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
					
    				-- Escenario 3: Si no hay horas pendientes, pero hay permisos específicos, calcular horas extras con reglas especiales
    				WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN
        			CASE
						WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval 
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
            			WHEN of.ocu_tipo = 29 
            				THEN
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
            				ELSE
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

    					-- Escenario 4: Si no hay horas pendientes ni permisos, y además es parte de una seguidilla de días, no calcular horas extras
    					WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (
        						SELECT 1
        						FROM ocurrencias_filtradas of
        						WHERE of.reg_fecha = c.date
        						AND of.ocu_tipo IN (33, 26, 12, 29)
    						) 
    						THEN '00:00:00'::interval

        				-- Escenario 5: Si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
    					WHEN p.reg_horas_trabajadas > '09:00:00'::interval 
    						THEN
        						LEAST(
            						p.reg_horas_trabajadas - '08:00:00'::interval,
            						'02:00:00'::interval
        						)

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
		FROM calendar c
			LEFT JOIN marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
			LEFT JOIN ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal
			LEFT JOIN compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal
	),
	re_semanal AS (
		SELECT rd.reg_cod_personal,
				EXTRACT(WEEK FROM rd.reg_fecha) AS week,
				LEAST(
					COALESCE(
						SUM(
							CASE
								WHEN rd.re >= '01:00:00' 
									THEN LEAST(rd.re, '02:00:00'::interval)
								ELSE 
									'00:00:00'::interval
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
				SUM(rd.re) OVER (
					PARTITION BY rd.reg_cod_personal, 
					EXTRACT(YEAR FROM rd.reg_fecha), 
					EXTRACT(WEEK FROM rd.reg_fecha) 
					ORDER BY rd.reg_fecha ROWS UNBOUNDED PRECEDING
				) AS re_acumulada_semanal
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
					WHEN rsa.re_acumulada_semanal > '08:00:00'::interval 
						THEN '00:00:00'::interval
					-- Si la acumulación semanal es menor a 08:00:00, sumamos las horas RE restantes
					ELSE 
						rsa.re
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
					WHEN rd.ocu_tipo = 12 AND rd.ocu_horas_estaticas = 1 
						THEN rd.ocu_horas_adicionales::interval+rd.ocu_horas_adicionales_100::interval
					-- Si es sábado, el RA será el total de horas trabajadas sin importar el retraso
					WHEN EXTRACT(ISODOW FROM rd.reg_fecha) = 6 
						THEN rd.reg_horas_trabajadas
					--si no hay re 
					WHEN rd.re < '01:00:00'::interval 
						THEN '00:00:00'::interval		
					-- Si tiene retraso mayor a 00:00:59 y no es sábado, no sumamos horas RA
					--WHEN rd.reg_retraso > '00:00:59'::interval THEN '00:00:00'::interval
					-- Validación: Si la RE acumulada semanal es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
					WHEN ras.re_acumulada_semanal > '08:00:00'::interval 
						THEN
							CASE
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas  - '08:00:00'::interval
								ELSE 
									'00:00:00'::interval
							END
					-- Validación: Si la RE acumulada mensual es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
					WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval 
						THEN
							CASE
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas - '09:00:00'::interval
								ELSE 
								'00:00:00'::interval
							END
					-- Validación para RE mensual mayor a 34 horas
					WHEN ram.re_acumulada_mensual > '34:00:00'::interval 
						THEN
							CASE
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas - '08:00:00'::interval
								ELSE 
									'00:00:00'::interval
							END
						-- Cálculo general: Si ninguna de las validaciones anteriores aplica, se calcula RA si las horas trabajadas son más de 10:00:00
					ELSE
						CASE
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
	ra_semanal_suma AS (
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
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales::interval
					-- Si es sábado, RA_80 es siempre '00:00:00'
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN '00:00:00'::interval
					-- Si la hora de salida es menor o igual a las 19:59:59, todo RA se contabiliza en RA_80
					WHEN ra.reg_hora_salida <= '19:59:59'::time 
						THEN ra.ra
					-- Si la hora de salida es después de las 19:59:59, calculamos cuánto tiempo adicional fue antes de las 19:59:59
					ELSE 
						ra.ra - (ra.reg_hora_salida - '19:59:59'::time)::interval
				END AS ra_80,
    
				-- Cálculo de RA_100 (después de las 19:59:59)
				CASE
					--Calculo excepcional ocu tipo 12  horas estaticas
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales_100::interval
					-- Si es sábado (día de la semana = 6) y hay horas trabajadas, todo RA se asigna a RA_100
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN ra.reg_horas_trabajadas
					-- Si la hora de salida es después de las 19:59:59, calculamos RA_100
					WHEN ra.reg_hora_salida > '19:59:59'::time 
						THEN LEAST(ra.ra, (ra.reg_hora_salida - '19:59:59'::time)::interval)
					-- Si la hora de salida es antes de las 19:59:59, no hay RA_100
					ELSE 
						'00:00:00'::interval
				END AS ra_100

		FROM ra  -- Utilizamos el CTE `ra` previamente calculado para obtener los valores de RA
	),
	ra_divida_semanal_suma AS (
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
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal,
				SUM(
					CASE
						-- Sumar directamente las horas adicionales (RA) sin límite o tope
						WHEN rd.ra_100 IS NOT NULL 
							THEN rd.ra_100
						ELSE 
							'00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal
		FROM ra_dividida rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
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
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
								THEN ras.re - (ras.re_acumulada_semanal - '08:00:00'::interval)
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
			-- Utilizamos 're_recalculada' si es diferente de '00:00:00', de lo contrario, usamos 'r.re'
			CASE
				WHEN re_rec.re_recalculada <> '00:00:00'::interval THEN re_rec.re_recalculada
				ELSE r.re
			END AS re,
			r.horas_a_compensar,
			r.horas_compensadas,
			r.horas_restantes,
			r.estado_compensacion,
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
				ELSE 
					NULL
				END
			) AS dia_semana,
			of.ocu_descripcion AS ocurrencia_descripcion,
			of.ocurrencia_tipo,
			of.ocu_tipo,
			of.tip_codigo,
			ff.feriado_descripcion,
			CASE
				WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta 
					THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta 
					THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				ELSE 
					NULL
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
		LEFT JOIN ra_semanal_suma ras ON r.reg_cod_personal = ras.reg_cod_personal 
			AND EXTRACT(WEEK FROM r.reg_fecha) = ras.week 
			AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		LEFT JOIN ra_mensual_suma ma ON r.reg_cod_personal = ma.reg_cod_personal
		LEFT JOIN ra_divida_semanal_suma rds ON r.reg_cod_personal = rds.reg_cod_personal 
			AND EXTRACT(WEEK FROM r.reg_fecha) = rds.week 
			AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		LEFT JOIN ra_dividia_mensual_suma rdm ON r.reg_cod_personal = rdm.reg_cod_personal
	ORDER BY r.reg_fecha, r.reg_cod_personal;
END; 
$function$
;
*/

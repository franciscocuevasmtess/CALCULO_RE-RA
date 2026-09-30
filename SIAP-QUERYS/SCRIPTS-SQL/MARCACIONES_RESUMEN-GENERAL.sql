---------------------------------------------------
-- REPORTE: MARCACIONES RESUMEN GENERAL
---------------------------------------------------

SELECT mes_cod, mes_letras FROM meses ORDER BY mes_cod;

SELECT cod, numero FROM anhos ORDER BY numero;

SELECT hem.reg_cod_personal,hem.per_nombre,hem.per_apellido,hem.per_ci,	hem.re_mensual_suma,
hem.ra_80_mensual,hem.ra_100_mensual, 2023 anho, 6 mes
FROM horas_extras_mensuales(2023, 6) hem 
ORDER BY hem.re_mensual_suma, hem.ra_80_mensual, hem.ra_100_mensual asc;

select hxm.reg_cod_personal,hxm.per_nombre,hxm.per_apellido,hxm.per_ci,hxm.re_mensual_suma,
hxm.ra_80_mensual,hxm.ra_100_mensual,a.numero AS anho,m.mes_cod AS mes
from (select numero from anhos) a
		cross join (select mes_cod from meses) m
		left join lateral public.horas_extras_mensuales(a.numero, m.mes_cod) hxm on true 
--where hxm.reg_cod_personal is not null;
order by a.numero, m.mes_cod desc;


-- Crear una tarea programada que ejecute la funcion: insertar_horas_extras_historico(anho, mes).
-- ¿En que momento se debe ejecutar esta tarea programada?, los usuarios de SIAP deben poder
--saber sus horarios de marcacion en cualquier momento del dia?.
-- ¿Esta bien que solo se guarden en la tabla: historico_horas_extras_mensuales los datos
--que devuelve la funcion actual que realiza el calculo de horas extras?.
-- No se toco ni modifico ningun calculo, solo se creo la tabla historicos y se insertaron
--esos datos.

/*
[reg_cod_personal, per_nombre, per_apellido, per_ci, re_mensual_suma, ra_80_mensual, ra_100_mensual]
 */
-------------------------------------------------------------------------------------

select * from historico_marcaciones_resumen_general;
select count(*) from historico_marcaciones_resumen_general; --20784
select * from log_cron_historico_marcaciones;
select insertar_historico_marcaciones_resumen_general();
select count(*)
from (select numero AS anho from anhos) a
		cross join (select mes_cod as mes from meses) m
		left join lateral horas_extras_mensuales(a.anho, m.mes) hxm on true; --20784

select * 
from historico_marcaciones_resumen_general 
where anho = 2023 
and mes = 6 
order by re_mensual_suma, ra_80_mensual, ra_100_mensual asc;
SELECT SUM(re_mensual_suma) AS total_re_mensual_suma, --42:33:35
    SUM(ra_80_mensual) AS total_ra_80_mensual, --02:31:09
    SUM(ra_100_mensual) AS total_ra_100_mensual --00:00:00
FROM horas_extras_mensuales(2023, 6);
select SUM(re_mensual_suma::NUMERIC) AS total_re_mensual_suma, 
		SUM(ra_80_mensual::NUMERIC) AS total_ra_80_mensual,
		SUM(ra_100_mensual::NUMERIC) AS total_ra_100_mensual
from historico_marcaciones_resumen_general
where anho = 2023
and mes = 6;




-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.horas_extras_mensuales(anio integer, mes integer)
	RETURNS TABLE(reg_cod_personal integer, 
					per_nombre character varying, 
					per_apellido character varying, 
					per_ci character varying, 
					re_mensual_suma interval, 
					ra_80_mensual interval, 
					ra_100_mensual interval)
	LANGUAGE plpgsql
	AS $function$
BEGIN
	RETURN QUERY
	
	SELECT  p.per_cod AS reg_cod_personal,
        	p.per_nombre,
        	p.per_apellido,
        	p.per_ci,
        	COALESCE(result.re_mensual_suma, '00:00:00'::interval) AS re_mensual_suma,
        	COALESCE(result.ra_80_mensual, '00:00:00'::interval) AS ra_80_mensual,
        	COALESCE(result.ra_100_mensual, '00:00:00'::interval) AS ra_100_mensual
    FROM personales p
    		LEFT JOIN LATERAL (SELECT sub.re_mensual_suma, 
            							sub.ra_80_mensual, 
            							sub.ra_100_mensual
        						FROM marcaciones_por_mes_horas(anio, mes, p.per_cod) AS sub
        						WHERE sub.re_mensual_suma IS NOT NULL 
          						AND sub.ra_80_mensual IS NOT NULL 
          						AND sub.ra_100_mensual IS NOT NULL
        						LIMIT 1
    						) AS result ON true
	WHERE p.per_estado = 1 -- Considerando que "1" indica activo
    ORDER BY p.per_cod;
END;
$function$
;




-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas(anio integer, 
																mes integer, 
																param_reg_cod_personal integer)
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
	AS $function$
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
		FROM (SELECT o.ocu_cod_persona AS reg_cod_personal,
					generate_series(
						GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1)), 
						LEAST(
							CASE 
								-- Mantener tus condiciones existentes
								WHEN o.ocu_fecha_desde = o.ocu_fecha_hasta THEN o.ocu_fecha_hasta
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
		WHERE NOT (subquery.ocu_tipo = 1 
					AND 
					(EXTRACT(DOW FROM subquery.reg_fecha::date) = 6 OR EXTRACT(DOW FROM subquery.reg_fecha::date) = 0)
				) -- Excluir sábados (6) y domingos (0) para vacaciones
		GROUP BY subquery.reg_cod_personal, subquery.reg_fecha
	), 
    feriados_filtrados AS (
        SELECT f.fer_fecha AS reg_fecha, f.fer_descripcion AS feriado_descripcion
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
				OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede 
															FROM personales 
															WHERE per_cod = param_reg_cod_personal)
															)
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
					WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (SELECT 1
																				FROM ocurrencias_filtradas of
																				WHERE of.reg_fecha = c.date
																				AND of.ocu_tipo IN (33, 26, 12, 29)
																			) THEN '00:00:00'::interval
					-- Nuevo Escenario: Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
					WHEN EXISTS (SELECT 1
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
					WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (SELECT 1
																						FROM ocurrencias_filtradas of
																						WHERE of.reg_fecha = c.date
																						AND of.ocu_tipo IN (33, 26, 12, 29)
																					) 
						THEN
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
					WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (SELECT 1
																							FROM ocurrencias_filtradas of
																							WHERE of.reg_fecha = c.date
																							AND of.ocu_tipo IN (33, 26, 12, 29)
																							) 
						THEN 
							'00:00:00'::interval
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
		SELECT
			rml.reg_cod_personal,               -- Código de la persona
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
								ELSE '00:00:00'::interval
							END
					-- Validación: Si la RE acumulada mensual es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
					WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval 
						THEN
							CASE
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN rd.reg_horas_trabajadas - '09:00:00'::interval
								ELSE '00:00:00'::interval
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
        SELECT rs.reg_cod_personal, SUM(rs.ra_semanal_suma) AS ra_mensual_suma
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
						THEN
							LEAST(ra.ra, (ra.reg_hora_salida - '19:59:59'::time)::interval)
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
						ELSE '00:00:00'::interval
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal,
				SUM(
					CASE
						-- Sumar directamente las horas adicionales (RA) sin límite o tope
						WHEN rd.ra_100 IS NOT NULL 
							THEN rd.ra_100
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
					WHEN ras.re_acumulada_semanal >= '08:00:00'::interval 
						THEN
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
				WHEN re_rec.re_recalculada <> '00:00:00'::interval 
					THEN re_rec.re_recalculada
				ELSE 
					r.re
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
					ELSE NULL
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
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------







-----------------------------------------------------------------------------
-- DESGLOSADO
-----------------------------------------------------------------------------



-----------------------------------------------------------------------------
-- DROP FUNCTION public.marcaciones_por_mes_horas(int4, int4, int4); --
-----------------------------------------------------------------------------
C-REATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas(
	anio integer, -- El año para el cual se quieren procesar las marcaciones.
	mes integer,  -- El mes para el cual se quieren procesar las marcaciones.
	param_reg_cod_personal integer -- El código del personal (empleado) específico para el cual se generará el reporte.
	)
	RETURNS TABLE(
		/*
		 * Indica que la función devolverá un conjunto de resultados con la estructura de tabla 
		 * definida, incluyendo muchas columnas de diversos tipos de datos. Esta es una forma 
		 * común de devolver múltiples filas y columnas en PL/pgSQL.
		 */
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
	LANGUAGE plpgsql -- Especifica que el cuerpo de la función está escrito en PL/pgSQL, el lenguaje procedimental de PostgreSQL.
	AS $function$ --Marca el inicio del cuerpo de la función. El $function$ es un delimitador de cadena.
	BEGIN -- Marca el inicio del bloque ejecutable de la función.
		
		PERFORM set_config('timezone', 'UTC', true); -- Establece temporalmente la configuración de la zona horaria de la sesión a 'UTC'. Esto es muy importante para asegurar que los cálculos de fecha y hora sean consistentes y no se vean afectados por la zona horaria del servidor o del cliente. true indica que el cambio es a nivel de transacción.
    	
		PERFORM set_config('DateStyle', 'ISO, DMY', true); -- Establece el estilo de fecha a ISO, DMY. Esto significa que las fechas se interpretarán o mostrarán en formato AAAA-MM-DD o DD/MM/AAAA (dependiendo del contexto), lo cual es útil para consistencia. true también es a nivel de transacción.
    	
		RETURN QUERY -- Esta cláusula indica que la función devolverá el resultado de la siguiente consulta. Todo lo que sigue será la consulta que genera el conjunto de resultados de la función.
		    WITH RECURSIVE calendar AS (
		    	/*
		    	 * Define una CTE recursiva llamada calendar. Las CTEs recursivas se utilizan 
		    	 * para generar series de datos, en este caso, una serie de fechas.
		    	 */
		        
		    	SELECT DATE_TRUNC('month', make_date(/*anio, mes,*/2025, 4, 21))::DATE AS date -- Primera parte de la CTE (Ancla)
		        
		    	UNION ALL -- Combina el resultado del ancla con el resultado de la parte recursiva.
		        
		    	SELECT (date + INTERVAL '1 day')::DATE FROM calendar WHERE date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(/*anio, mes,*/2025, 4, 21)) + INTERVAL '1 month' -- En cada paso de la recursión, selecciona la fecha del paso anterior (date de calendar) y le suma un día.
		    
		    ), -- Resultado de calendar: Esta CTE genera una tabla temporal con una única columna date que contiene todos los días del mes y año especificados (o Mayo de 2025, según las líneas comentadas).
			marcaciones_completas AS (
				/*
				 * Define otra CTE llamada marcaciones_completas. Esta CTE es el corazón 
				 * del cálculo de las horas.
				 * */
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
				/*
				 * Esta CTE genera un listado de todas las "ocurrencias" (como vacaciones, 
				 * permisos, licencias, etc.) que afectan a un empleado específico durante 
				 * un mes y año dados. Lo hace expandiendo los rangos de fechas de las 
				 * ocurrencias a días individuales y luego agrupándolos para consolidar 
				 * información si hay múltiples ocurrencias en el mismo día. También 
				 * aplica una regla para excluir fines de semana en el caso de 
				 * las vacaciones.
				 * */
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
						-- Esta es la primera parte que se ejecuta. 
						--Genera una fila por cada día afectado por una ocurrencia 
						--para el empleado y el mes en cuestión.
						SELECT o.ocu_cod_persona AS reg_cod_personal,
								generate_series(
									GREATEST(o.ocu_fecha_desde::date, make_date(/*anio, mes,*/2025, 3, 1)), 
									LEAST(
										CASE 
											-- Mantener tus condiciones existentes
											WHEN o.ocu_fecha_desde = o.ocu_fecha_hasta THEN o.ocu_fecha_hasta
										ELSE 
											o.ocu_fecha_hasta
										END,
										(make_date(/*anio, mes,*/2025, 3, 1) + INTERVAL '1 month - 1 day')::date
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
						AND o.ocu_fecha_desde <= (make_date(/*anio, mes,*/2025, 3, 1) + INTERVAL '1 month - 1 day')::date
						AND o.ocu_fecha_hasta >= make_date(/*anio, mes,*/2025, 3, 1)
					) AS subquery
				WHERE NOT (subquery.ocu_tipo = 1 
							AND 
							(EXTRACT(DOW FROM subquery.reg_fecha::date) = 6 OR EXTRACT(DOW FROM subquery.reg_fecha::date) = 0)
						) -- Excluir sábados (6) y domingos (0) para vacaciones
				GROUP BY subquery.reg_cod_personal, subquery.reg_fecha
			), 
		    feriados_filtrados AS (
		    	/*
		    	 * Esta CTE tiene como objetivo principal identificar y listar 
		    	 * todos los días feriados que caen dentro del mes y año 
		    	 * específicos que se están procesando en la función 
		    	 * principal (anio y mes).
		    	 * */
		        SELECT f.fer_fecha AS reg_fecha, f.fer_descripcion AS feriado_descripcion
		        FROM feriados f
		        WHERE EXTRACT(YEAR FROM f.fer_fecha) = anio 
		        AND EXTRACT(MONTH FROM f.fer_fecha) = mes
		    ),
			tolerancias_especiales_filtradas AS (
				/*
				 * Esta CTE tiene como objetivo seleccionar todas las tolerancias de 
				 * tiempo especiales que son aplicables a un empleado 
				 * específico (param_reg_cod_personal) para el mes que se está 
				 * procesando. Considera tanto tolerancias 
				 * individuales (directamente asignadas al empleado) como 
				 * tolerancias generales (asignadas a la sede donde trabaja el empleado).
				 * */
		        SELECT te.tol_cod_personal,
						te.tol_fecha_desde,
						te.tol_fecha_hasta,
						te.tol_descripcion,
						te.tol_tiempo,
						te.tol_tipo,
						te.tol_sed_cod
		        FROM tolerancias_especiales te
		        WHERE (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
						OR 
						(te.tol_tipo = 'G' 
							AND 
							te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal)
						)
		    ), 
		    compensaciones_detalles_filtradas AS (
		    	/*
		    	 * Esta CTE tiene como objetivo consolidar y resumir la información de 
		    	 * compensaciones (horas a compensar, horas compensadas, horas restantes 
		    	 * y estado de compensación) para un empleado específico (param_reg_cod_personal) 
		    	 * por cada día dentro del mes y año que se está procesando. Suma las horas si 
		    	 * hay múltiples entradas de compensación para el mismo día y empleado.
		    	 * */
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
						WHERE c.com_cod_personal = /*param_reg_cod_personal*/29
		                AND EXTRACT(YEAR FROM cd.com_det_fecha) = /*anio*/2025
		                AND EXTRACT(MONTH FROM cd.com_det_fecha) = /*mes*/3
					) sub
		        GROUP BY com_cod_personal, com_det_fecha
		    ),
			re_diaria AS (
				/*
				 * Esta CTE re_diaria es una de las partes más complejas y centrales de la función, ya que realiza 
				 * el cálculo de las horas extras (RE) en base a una multitud de condiciones y escenarios.
				 * Propósito General de la CTE re_diaria: La CTE re_diaria (que probablemente significa "Registro de 
				 * Horas Extras Diario") combina el calendario de días del mes con las marcaciones completas, las 
				 * ocurrencias y los detalles de compensación para calcular las horas extras de cada día, aplicando 
				 * una compleja lógica de negocio basada en el tipo de ocurrencia, retrasos y estado de compensaciones.
				 * 
				 * Esta CTE genera una fila por cada día del mes (para el empleado dado), conteniendo:
				 * La fecha del día.
				 * El código del personal.
				 * El valor calculado de las horas extras (re) para ese día, basado en una compleja lógica de negocio 
				 * que considera marcaciones, retrasos, ocurrencias especiales y el estado de compensaciones.
				 * Información relevante sobre las compensaciones, marcaciones y ocurrencias de ese día.
				 */
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
																							) 
								THEN
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
								THEN 
									'00:00:00'::interval
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
				/*
				 * Esta CTE tiene como objetivo calcular la suma semanal de las horas extras (RE) para cada empleado. Aplica 
				 * una lógica para limitar las horas extras diarias (un máximo de 2 horas) y la suma semanal total (un máximo 
				 * de 8 horas), y solo considera los días laborales de lunes a viernes.
				 * */
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
    			/*
    			 * Propósito General de la CTE re_mensual: Esta CTE tiene como objetivo calcular la suma total de 
    			 * las horas extras (RE) para cada empleado durante todo el mes, aplicando un límite máximo mensual 
    			 * a estas horas extras.
				 * */
		        SELECT rs.reg_cod_personal,
						LEAST(
							SUM(rs.re_semanal_suma),
							'32:00:00'::interval
						) AS re_mensual_suma
		        FROM re_semanal rs
		        GROUP BY rs.reg_cod_personal
		    ),
			re_acumulada_semanal AS (
				/*
				 * Propósito General de la CTE re_acumulada_semanal: Esta CTE tiene como objetivo calcular la suma acumulada de 
				 * las horas extras (RE) día a día, pero reiniciando la acumulación al inicio de cada semana (específicamente, 
				 * de lunes a viernes). Esto permite ver cómo se acumulan las horas extras a lo largo de una semana laboral.
				 * */
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
				/*
				 * Propósito General de la CTE re_mensual_con_limited: Esta CTE toma las horas extras diarias y su acumulación 
				 * semanal (re_acumulada_semanal) y aplica una restricción diaria a la cantidad de horas extras que pueden 
				 * contribuir al total mensual, asegurando que el total semanal de horas extras pagables no exceda un límite 
				 * de 8 horas, incluso si el cálculo diario original de re era mayor.
				 * */
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
				/*
				 * Propósito General de la CTE re_acumulada_mensual: Esta CTE tiene como objetivo calcular la suma acumulada 
				 * de las horas extras (RE) día a día a lo largo de todo el mes, utilizando las horas extras que ya han 
				 * sido "limitadas" semanalmente por la CTE anterior (re_mensual_con_limited).
				 * 
				 * Resultado Final de re_acumulada_mensual: Esta CTE devuelve un conjunto de resultados con una fila por cada 
				 * día laboral (Lunes a Viernes, ya que re_mensual_con_limited solo tenía esos días) del mes para el empleado 
				 * dado, conteniendo:
				 * El código del personal.
				 * La fecha del día.
				 * La suma acumulada de horas extras (re_acumulada_mensual) para ese empleado, desde el primer día del mes 
				 * hasta el día en curso. Esta suma se reinicia para cada empleado.
				 * 
				 * Esta CTE es fundamental para tener un seguimiento diario de cómo las horas extras totales para el mes 
				 * van acumulándose, ya con los límites semanales aplicados. Esto podría ser útil para informes o para 
				 * verificar el progreso hacia el límite mensual de 32 horas (que se aplicará en una etapa posterior).
				 * */
				-- CTE que acumula las RE a lo largo del mes, respetando el límite de 08:00 horas por semana
				SELECT rml.reg_cod_personal,               -- Código de la persona
						rml.reg_fecha,                      -- Fecha de la marcación
						SUM(rml.re_con_limited) OVER (
							PARTITION BY rml.reg_cod_personal ORDER BY rml.reg_fecha
						) AS re_acumulada_mensual           -- RE acumulada mensual con el tope semanal aplicado
				FROM re_mensual_con_limited rml
			),
			ra AS (
				/*
				 * Esta CTE ra es otra pieza fundamental y muy detallada de la lógica de negocio, encargada de calcular 
				 * las "horas adicionales" (RA), que a menudo representan horas extras pagadas a una tarifa diferente 
				 * o bajo condiciones más estrictas.
				 * 
				 * Propósito General de la CTE ra: La CTE ra (que probablemente significa "Registro de Horas Adicionales") 
				 * calcula las horas adicionales para cada día, aplicando una jerarquía compleja de reglas que consideran 
				 * la fecha, las horas trabajadas, los retrasos, los tipos de ocurrencias y los umbrales de horas extras 
				 * ya acumuladas (semanal y mensualmente).
				 * */
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
										ELSE '00:00:00'::interval
									END
							-- Validación: Si la RE acumulada mensual es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
							WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval 
								THEN
									CASE
										WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
											THEN rd.reg_horas_trabajadas - '09:00:00'::interval
										ELSE '00:00:00'::interval
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
				/*
				 * Propósito General de la CTE ra_semanal_suma: Esta CTE tiene como objetivo calcular la suma total de las horas 
				 * adicionales (RA) para cada empleado por semana. A diferencia de las horas extras (RE), esta suma de ra no aplica 
				 * límites semanales ni diarios internos antes de la suma, pero sí incluye los sábados en su consideración.
				 * */
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
				/*
				 * Propósito General de la CTE ra_mensual_suma: Esta CTE tiene como objetivo calcular la suma total de las 
				 * horas adicionales (RA) para cada empleado durante todo el mes. Es la consolidación final de las horas 
				 * adicionales, sumando las acumulaciones semanales.
				 * */
		        SELECT rs.reg_cod_personal, SUM(rs.ra_semanal_suma) AS ra_mensual_suma
				FROM ra_semanal_suma rs
				GROUP BY rs.reg_cod_personal
		    ),
			ra_dividida AS (
				/*
				 * Esta CTE ra_dividida es un paso importante para clasificar las horas adicionales (ra) en diferentes 
				 * categorías, muy probablemente para aplicar distintas tarifas de pago (e.g., horas diurnas vs. horas nocturnas 
				 * o recargos).
				 * 
				 * Propósito General de la CTE ra_dividida: La CTE ra_dividida toma las horas adicionales (ra) calculadas 
				 * previamente para cada día y las segmenta en dos categorías: ra_80 y ra_100. Esta división se basa 
				 * principalmente en la hora del día (antes o después de las 19:59:59) y en si el día es sábado, además 
				 * de manejar el caso excepcional de ocurrencias estáticas.
				 * */
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
								THEN
									LEAST(ra.ra, (ra.reg_hora_salida - '19:59:59'::time)::interval)
							-- Si la hora de salida es antes de las 19:59:59, no hay RA_100
							ELSE 
								'00:00:00'::interval
						END AS ra_100
			    FROM ra  -- Utilizamos el CTE `ra` previamente calculado para obtener los valores de RA
			),
			ra_divida_semanal_suma AS (
				/*
				 * Propósito General de la CTE ra_divida_semanal_suma: Esta CTE tiene como objetivo calcular la suma semanal 
				 * de las horas adicionales tipo 80 (ra_80_semanal) y las horas adicionales tipo 100 (ra_100_semanal) para 
				 * cada empleado. 
				 * Realiza esta suma por semana, aplicando filtros específicos para los días de la semana en cada tipo de RA.
				 * */
				SELECT rd.reg_cod_personal,
						EXTRACT(WEEK FROM rd.reg_fecha) AS week,
						SUM(
							CASE
								-- Sumar directamente las horas adicionales (RA) sin límite o tope  Sumar solo si rd.ra_80 es mayor que '00:00:00'
								WHEN rd.ra_80 IS NOT NULL AND rd.ra_80 > '00:00:00'::interval 
									THEN rd.ra_80
								ELSE '00:00:00'::interval
							END
						) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal,
						SUM(
							CASE
								-- Sumar directamente las horas adicionales (RA) sin límite o tope
								WHEN rd.ra_100 IS NOT NULL 
									THEN rd.ra_100
								ELSE '00:00:00'::interval
							END
						) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal
		    	FROM ra_dividida rd
		    	GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
			),
		 	ra_dividia_mensual_suma AS (
		 		/*
		 		 * Propósito General de la CTE ra_dividia_mensual_suma: Esta CTE tiene como objetivo calcular la suma total mensual de las 
		 		 * horas adicionales tipo 80 (ra_80_mensual) y las horas adicionales tipo 100 (ra_100_mensual) para cada empleado. 
		 		 * Es la consolidación final de estas horas adicionales divididas por categoría para todo el mes.
		 		 * */
		        SELECT rs.reg_cod_personal,
						SUM(rs.ra_80_semanal) AS ra_80_mensual,
						SUM(rs.ra_100_semanal) AS ra_100_mensual
				FROM ra_divida_semanal_suma rs
				GROUP BY rs.reg_cod_personal
		    ),
			re_recalculada AS (
				/*
				 * Propósito General de la CTE re_recalculada: La CTE re_recalculada tiene como objetivo ajustar o "recalcular" 
				 * las horas extras (re) para los días en que la acumulación semanal de re ha superado el límite de 8 horas. 
				 * Esto permite que el sistema "sepa" cuánto de la re diaria original debe considerarse si ya se ha cumplido 
				 * el tope semanal en días anteriores de la misma semana.
				 * */
				SELECT ras.reg_cod_personal,
						ras.reg_fecha,
						rd.reg_horas_trabajadas,
						ras.re,
						ras.re_acumulada_semanal,
						CASE
							-- Verifica si `re_acumulada_semanal` es mayor o igual a 08:00:00
							WHEN ras.re_acumulada_semanal >= '08:00:00'::interval 
								THEN
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
				WHEN re_rec.re_recalculada <> '00:00:00'::interval 
					THEN re_rec.re_recalculada
				ELSE 
					r.re
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
					ELSE NULL
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
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------




select * from registros_entrada_salida;
select * from tolerancias_especiales;
select * from personales;
--EL UNICO LUGAR DONDE ENCUENTRO PARAMETROS POR ANHO ES AQUI
select * from turnos; --
select * from parametros; -- Tolerancia, Horas de Trabajo, etc.,
-------------------------------------------------------------------
-------------------------------------------------------------------

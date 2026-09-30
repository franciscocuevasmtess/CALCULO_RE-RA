----------------------------------------------
-- Marcaciones - Entre Fechas
----------------------------------------------

SELECT per_cod, per_nombre || ' ' || per_apellido || ' (' || per_cod || ') ' || '(' || per_ci || ')' AS full_details
FROM personales
WHERE (per_estado = 1)
ORDER BY per_cod;


-- select utilizado para encabezado(Datos del Turno)
SELECT t.tur_descripcion,
        t.tur_entrada,
        t.tur_salida,
        t.tur_tipo,
        t.tur_horas_trabajo,
        tt.tip_descripcion,
        tur_fecha_desde ,
        tur_fecha_hasta,
        p.par_valor_time as tolerancia
FROM turnos t
    INNER JOIN tipos_turnos tt ON tt.tip_cod = t.tur_tipo
    INNER JOIN parametros p ON p.par_cod = t.tur_tolerancia
WHERE t.tur_cod_personal = 8
AND t.tur_fecha_desde <= make_date(2023, 7, 1)
AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= make_date(2023, 7, 1));


-- select utilizado en la grilla de datos del funcionario
SELECT * FROM marcaciones_entre_fechas(8, '2023-06-30', '2023-07-04');
/*select *
from (select per_cod from personales where per_estado = 1) p
		join lateral marcaciones_entre_fechas(p.per_cod, '2022-01-01', CURRENT_DATE) AS res_func ON TRUE
where reg_cod_personal = 8
and reg_fecha between '2023-06-30' and '2023-07-04';*/

select * from historico_marcaciones_entre_fechas;
select count(*) as total from historico_marcaciones_entre_fechas; -- 548178
select * from log_cron_historico_marcaciones;
select *  
-- count(*) as total -- 550275
from (select per_cod from personales where per_estado = 1) p
		join lateral marcaciones_entre_fechas(p.per_cod, '2022-01-01', CURRENT_DATE) r on true;
select * from insertar_historico_marcaciones_entre_fechas();
SELECT * FROM historico_marcaciones_entre_fechas WHERE reg_cod_personal = 8 
AND reg_fecha BETWEEN '2023-06-30' AND '2023-07-04';
select * from historico_marcaciones_entre_fechas where per_cod = 8 and reg_fecha between '2023-06-30' AND '2023-07-04';





/*
[reg_fecha, reg_cod_personal, tur_entrada, tur_salida, par_valor_time, reg_hora_entrada, 
reg_hora_salida, reg_horas_trabajadas, reg_retraso, reg_horas_extras, re, re_semanal_suma, 
re_mensual_suma, dia_semana, ocurrencia_descripcion, ocurrencia_tipo, feriado_descripcion, 
tolerancia_especial]
*/



/*
---------------------------------------------------------------------
-- DROP FUNCTION public.marcaciones_entre_fechas(int4, date, date);
---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marcaciones_entre_fechas(param_reg_cod_personal integer, 
															fecha_desde date, 
															fecha_hasta date)
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
					re_semanal_suma interval, 
					re_mensual_suma interval, 
					dia_semana text, 
					ocurrencia_descripcion character varying, 
					ocurrencia_tipo character varying, 
					feriado_descripcion character varying, 
					tolerancia_especial text)
	LANGUAGE plpgsql
	AS $function$
	BEGIN
    	RETURN QUERY
    	WITH RECURSIVE calendar AS (
        	SELECT fecha_desde::DATE AS date
        	UNION ALL
        	SELECT (date + INTERVAL '1 day')::DATE
        	FROM calendar
        	WHERE date + INTERVAL '1 day' <= fecha_hasta
    	),
    	marcaciones_completas AS (
        	SELECT COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
            		COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal,
            		t.tur_entrada,
	            	t.tur_salida,
            		p.par_valor_time,
            		e.reg_hora AS reg_hora_entrada,
            		s.reg_hora AS reg_hora_salida,
					CASE
						WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_entrada
						ELSE s.reg_hora - e.reg_hora
					END AS reg_horas_trabajadas,
					CASE
						WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time) THEN e.reg_hora - (t.tur_entrada + p.par_valor_time)
						ELSE '00:00:00'::interval
					END AS reg_retraso,
					CASE
						WHEN e.reg_hora IS NULL THEN NULL::interval
						ELSE
							CASE
								WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
								WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
								ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
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
			SELECT o.ocu_cod_persona AS reg_cod_personal,
					generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
					o.ocu_descripcion,
					t.tip_descripcion AS ocurrencia_tipo
			FROM ocurrencias o
			JOIN tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
			WHERE o.ocu_cod_persona = param_reg_cod_personal
		),
		feriados_filtrados AS (
			SELECT f.fer_fecha AS reg_fecha,
				f.fer_descripcion AS feriado_descripcion
			FROM feriados f
			WHERE f.fer_fecha BETWEEN fecha_desde AND fecha_hasta
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
					OR 
					(
						te.tol_tipo = 'G' 
						AND te.tol_sed_cod = (
												SELECT per_sede 
												FROM personales 
												WHERE per_cod = param_reg_cod_personal
											)
					)
		),
		re_diaria AS (
			SELECT c.date AS reg_fecha,
					COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
					CASE
						WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
							LEAST(
								p.reg_horas_trabajadas - '08:00:00'::interval,
								'02:00:00'::interval
							)
						ELSE '00:00:00'::interval
					END AS re
			FROM calendar c
					LEFT JOIN marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
					LEFT JOIN ocurrencias_filtradas of ON c.date = of.reg_fecha
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
				r.re,
				LEAST(
					COALESCE(
						SUM(r.re) FILTER (WHERE EXTRACT(ISODOW FROM r.reg_fecha) <= 5) OVER (PARTITION BY EXTRACT(WEEK FROM r.reg_fecha)),
						'00:00:00'::interval
					),
					'08:00:00'::interval
				) AS re_semanal_suma,
				LEAST(
					SUM(
						r.re
					) OVER (PARTITION BY EXTRACT(MONTH FROM r.reg_fecha)),
					'32:00:00'::interval
				) AS re_mensual_suma,
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
				of.ocurrencia_tipo AS ocurrencia_tipo,
				ff.feriado_descripcion AS feriado_descripcion,
				CASE
					WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
					WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
					ELSE NULL
				END AS tolerancia_especial
		FROM re_diaria r
				LEFT JOIN marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
				LEFT JOIN ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha
				LEFT JOIN feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
				LEFT JOIN tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
		ORDER BY r.reg_fecha, r.reg_cod_personal;
	END;
$function$
;
*/
-- =============================================================
-- Función: marcaciones_por_mes_horas5 (con cambios SIAP)
-- Objetivo: Calcular entrada/salida, RE (horas extra) y RA (horas adicionales)
--           incorporando:
--             (1) Compensación de tardanza el MISMO DÍA (comp_hoy)
--             (2) Ventana de 8 días hábiles para “permiso particular a compensar”
--             (3) Comisionamiento por tramos (intra-jornada, post 80%, post 100%, e inhábiles)
-- Notas: Mantiene topes RE (2h/día, 8h/semana L–V, 32h/mes) y corte RA 19:59:59.
-- =============================================================

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas5_con_cambios_siap(
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
	PERFORM set_config('timezone', 'UTC', true);
	PERFORM set_config('DateStyle', 'ISO, DMY', true);

	RETURN QUERY
	WITH RECURSIVE calendar AS (
		SELECT date_trunc('month', make_date(anio, mes, 1))::date AS date
		UNION ALL
		SELECT (date + interval '1 day')::date
		FROM calendar
		WHERE date + interval '1 day' < date_trunc('month', make_date(anio, mes, 1)) + interval '1 month'
	),
	-- 1) Marcaciones + turno + tolerancia general
	marcaciones_completas AS (
		SELECT
			COALESCE(e.reg_fecha, s.reg_fecha)           AS reg_fecha,
			COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal,
			t.tur_entrada,
			t.tur_salida,
			p.par_valor_time,
			t.tur_tipo,
			e.tol_tiempo_interval,
			e.reg_hora AS reg_hora_entrada,
			s.reg_hora AS reg_hora_salida,
			CASE
				WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_entrada
				ELSE s.reg_hora - e.reg_hora
			END AS reg_horas_trabajadas,
			CASE
				WHEN t.tur_tipo = 4 THEN interval '00:00:00'
				WHEN e.reg_hora IS NOT NULL
				     AND e.reg_hora > (t.tur_entrada + p.par_valor_time + interval '00:00:59' + e.tol_tiempo_interval)
				THEN e.reg_hora - (t.tur_entrada + p.par_valor_time + e.tol_tiempo_interval)
				ELSE interval '00:00:00'
			END AS reg_retraso,
			CASE
				WHEN e.reg_hora IS NULL THEN NULL::interval
				ELSE CASE
					WHEN s.reg_hora IS NULL THEN interval '00:00:00'
					WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
					ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
				END
			END AS reg_horas_extras
		FROM marcacion_entrada_adsoluta e
		FULL JOIN marcacion_salida_adsoluta s
		  ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
		LEFT JOIN turnos t
		  ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal
		 AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
		 AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
		LEFT JOIN parametros p ON p.par_cod = t.tur_tolerancia
		WHERE COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
	),
	-- 2) Ocurrencias (expandido por día dentro del mes)
	ocurrencias_filtradas AS (
		SELECT sub.reg_cod_personal,
		       sub.reg_fecha,
		       string_agg(sub.ocu_descripcion::text, ', ' ORDER BY sub.ocu_descripcion)        AS ocu_descripcion,
		       string_agg(sub.ocurrencia_tipo::varchar, ', ' ORDER BY sub.ocurrencia_tipo)      AS ocurrencia_tipo,
		       MIN(sub.ocu_tipo)                                                                AS ocu_tipo,
		       string_agg(sub.tip_codigo::varchar, ', ' ORDER BY sub.tip_codigo)                AS tip_codigo,
		       MAX(sub.ocu_horas_estaticas)                                                    AS ocu_horas_estaticas,
		       SUM(sub.ocu_horas_extras)                                                       AS ocu_horas_extras,
		       SUM(sub.ocu_horas_adicionales)                                                  AS ocu_horas_adicionales,
		       SUM(sub.ocu_horas_adicionales_100)                                              AS ocu_horas_adicionales_100
		FROM (
			SELECT o.ocu_cod_persona AS reg_cod_personal,
			       gs::date          AS reg_fecha,
			       o.ocu_descripcion,
			       t.tip_descripcion AS ocurrencia_tipo,
			       t.tip_codigo,
			       o.ocu_tipo,
			       o.ocu_horas_estaticas,
			       o.ocu_horas_extras,
			       o.ocu_horas_adicionales,
			       o.ocu_horas_adicionales_100
			FROM ocurrencias o
			JOIN tipos_ocurrencias t ON t.tip_cod = o.ocu_tipo
			JOIN LATERAL generate_series(
				GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1))::timestamp,
				LEAST(o.ocu_fecha_hasta::date, (make_date(anio, mes, 1) + interval '1 month - 1 day')::date)::timestamp,
				interval '1 day'
			) gs
			WHERE o.ocu_cod_persona = param_reg_cod_personal
			  AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + interval '1 month - 1 day')::date
			  AND o.ocu_fecha_hasta >= make_date(anio, mes, 1)
		) sub
		WHERE NOT (
			sub.ocu_tipo = 1 AND (extract(dow FROM sub.reg_fecha) IN (0,6)) -- excluir vacaciones en sáb/dom
		)
		GROUP BY sub.reg_cod_personal, sub.reg_fecha
	),
	-- 3) Feriados del mes
	feriados_filtrados AS (
		SELECT f.fer_fecha::date AS reg_fecha,
		       f.fer_descripcion AS feriado_descripcion
		FROM feriados f
		WHERE extract(year  FROM f.fer_fecha) = anio
		  AND extract(month FROM f.fer_fecha) = mes
	),
	-- 4) Tolerancias especiales (I: individual, G: sede)
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
	-- 5) Compensaciones (resumen diario del mes)
	compensaciones_detalles_filtradas AS (
		SELECT com_cod_personal,
		       com_det_fecha::date,
		       SUM(com_det_horas_a_compensar)   AS com_det_horas_a_compensar,
		       SUM(com_det_horas_compensadas)   AS com_det_horas_compensadas,
		       SUM(com_det_horas_restantes)     AS com_det_horas_restantes,
		       string_agg(DISTINCT com_estado::varchar, ', ') AS com_estado
		FROM (
			SELECT c.com_cod_personal,
			       cd.com_det_fecha,
			       cd.com_det_horas_a_compensar,
			       cd.com_det_horas_compensadas,
			       cd.com_det_horas_restantes,
			       c.com_estado
			FROM compensaciones_detalles cd
			JOIN compensaciones_completas c ON cd.com_cod = c.com_cod
			WHERE c.com_cod_personal = param_reg_cod_personal
			  AND extract(year  FROM cd.com_det_fecha) = anio
			  AND extract(month FROM cd.com_det_fecha) = mes
		) sub
		GROUP BY com_cod_personal, com_det_fecha
	),
	-- 6) Ventana de 8 días hábiles para “permiso particular a compensar”
	--    Heurística: se detecta por tip_codigo/tip_descripcion que contenga PERM y COMP(ens)
	ventana_8dh_exp AS (
		SELECT o.ocu_cod_persona AS reg_cod_personal,
		       d::date           AS dia_habil
		FROM ocurrencias o
		JOIN tipos_ocurrencias t ON t.tip_cod = o.ocu_tipo
		CROSS JOIN LATERAL (
			SELECT d
			FROM generate_series(o.ocu_fecha_desde::date + 1, o.ocu_fecha_desde::date + 30, interval '1 day') d
			WHERE extract(isodow FROM d) BETWEEN 1 AND 5
			  AND NOT EXISTS (SELECT 1 FROM feriados f WHERE f.fer_fecha::date = d::date)
			LIMIT 8
		) s
		WHERE o.ocu_cod_persona = param_reg_cod_personal
		  AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + interval '1 month - 1 day')::date
		  AND o.ocu_fecha_hasta >= make_date(anio, mes, 1)
		  AND (
			  t.tip_codigo ILIKE '%PERM%'
		   OR t.tip_descripcion ILIKE '%permiso%'
		 )
		  AND (
			  t.tip_codigo ILIKE '%COMP%'
		   OR t.tip_descripcion ILIKE '%compens%'
		 )
	),
	-- 7) Comisionamiento: detallar tramos intra / post 80 / post 100
	comi_detalle AS (
		SELECT o.ocu_cod_persona AS reg_cod_personal,
		       gs::date          AS reg_fecha,
		       o.ocu_fecha_desde::time AS h_ini,
		       o.ocu_fecha_hasta::time AS h_fin
		FROM ocurrencias o
		JOIN tipos_ocurrencias t ON t.tip_cod = o.ocu_tipo
		JOIN LATERAL generate_series(
			GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1))::timestamp,
			LEAST(o.ocu_fecha_hasta::date, (make_date(anio, mes, 1) + interval '1 month - 1 day')::date)::timestamp,
			interval '1 day'
		) gs
		WHERE o.ocu_cod_persona = param_reg_cod_personal
		  AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + interval '1 month - 1 day')::date
		  AND o.ocu_fecha_hasta >= make_date(anio, mes, 1)
		  AND (
			    t.tip_codigo ILIKE '%COMISION%'
			 OR t.tip_descripcion ILIKE '%comision%'
			 OR t.tip_descripcion ILIKE '%comisionamiento%'
		  )
	),
	comi_partes AS (
		SELECT c.reg_cod_personal,
		       c.reg_fecha,
		       GREATEST(interval '00:00:00',
		        LEAST(c.h_fin, p.tur_salida) - GREATEST(c.h_ini, p.tur_entrada)
		       ) AS comi_intra,
		       GREATEST(interval '00:00:00',
		        LEAST(c.h_fin, time '19:59:59') - GREATEST(c.h_ini, p.tur_salida)
		       ) AS comi_post_80,
		       GREATEST(interval '00:00:00',
		        LEAST(c.h_fin, time '23:59:59') - GREATEST(c.h_ini, time '20:00:00')
		       ) AS comi_post_100
		FROM comi_detalle c
		JOIN marcaciones_completas p
		  ON p.reg_fecha = c.reg_fecha AND p.reg_cod_personal = c.reg_cod_personal
	),
	comi_agreg AS (
		SELECT reg_cod_personal, reg_fecha,
		       SUM(comi_intra)    AS comi_intra,
		       SUM(comi_post_80)  AS comi_post_80,
		       SUM(comi_post_100) AS comi_post_100
		FROM comi_partes
		GROUP BY reg_cod_personal, reg_fecha
	),
	-- 8) RE diaria con comp_hoy (tardanza se compensa el MISMO DÍA) y horas trabajadas + comisionamiento intra
	re_diaria AS (
		SELECT
			c.date AS reg_fecha,
			COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
			-- RE (horas extra) por reglas existentes + ajuste comp_hoy en el caso general
			CASE
				-- Horas estáticas (tipo 12) → se toma lo declarado como extras
				WHEN of.ocu_tipo = 12 AND of.ocu_horas_estaticas = 1 THEN of.ocu_horas_extras::interval

				-- Si hay horas pendientes de compensar, no se computa RE
				WHEN cd.com_det_horas_restantes > interval '00:00:00' THEN interval '00:00:00'

				-- Llegó tarde (> 00:00:00) sin permisos específicos (33, 26, 12, 29) → RE = 0
				WHEN p.reg_retraso > interval '00:00:00' AND NOT EXISTS (
					SELECT 1 FROM ocurrencias_filtradas x
					WHERE x.reg_fecha = c.date AND x.ocu_tipo IN (33,26,12,29)
				) THEN interval '00:00:00'

				-- Caso especial con tipo 12 y gran retraso (> 00:59:59)
				WHEN EXISTS (
					SELECT 1 FROM ocurrencias_filtradas x WHERE x.reg_fecha = c.date AND x.ocu_tipo = 12
				) AND p.reg_retraso > interval '00:59:59' THEN (
					CASE WHEN (p.reg_hora_salida - p.tur_entrada) > interval '09:00:00'
					     THEN LEAST((p.reg_hora_salida - p.tur_entrada) - interval '08:00:00', interval '02:00:00')
					     ELSE interval '00:00:00' END
				)

				-- Con permisos (33,26,12,29) sin pendientes → reglas especiales
				WHEN cd.com_det_horas_restantes = interval '00:00:00' AND EXISTS (
					SELECT 1 FROM ocurrencias_filtradas x
					WHERE x.reg_fecha = c.date AND x.ocu_tipo IN (33,26,12,29)
				) THEN (
					CASE
						WHEN of.ocu_tipo = 12 AND p.reg_retraso > interval '00:59:59' THEN (
							CASE WHEN (p.reg_hora_salida - p.tur_entrada) > interval '09:00:00'
							     THEN LEAST((p.reg_hora_salida - p.tur_entrada) - interval '08:00:00', interval '02:00:00')
							     ELSE interval '00:00:00' END
						)
						WHEN of.ocu_tipo = 29 THEN (
							CASE WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > interval '09:00:00'
							     THEN LEAST((p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - interval '08:00:00', interval '02:00:00')
							     ELSE interval '00:00:00' END
						)
						ELSE (
							CASE WHEN (p.reg_hora_salida - p.tur_entrada) > interval '09:00:00'
							     THEN LEAST((p.reg_hora_salida - p.tur_entrada) - interval '08:00:00', interval '02:00:00')
							     ELSE interval '00:00:00' END
						)
					END
				)

				-- Caso general: trabajadas (incl. comi_intra) > 9h → RE = min(trab-8h, 2h) MENOS comp_hoy
				WHEN (p.reg_horas_trabajadas + COALESCE(ca.comi_intra, interval '00:00:00')) > interval '09:00:00' THEN (
					LEAST(
						GREATEST(
							(p.reg_horas_trabajadas + COALESCE(ca.comi_intra, interval '00:00:00'))
							- interval '08:00:00'
							- LEAST(
								GREATEST(p.reg_hora_salida - p.tur_salida, interval '00:00:00'),
								COALESCE(p.reg_retraso, interval '00:00:00')
							),
							interval '00:00:00'
						),
						interval '02:00:00'
					)
				)

				ELSE interval '00:00:00'
			END AS re,

			-- Compensaciones del día (ajustadas por ventana 8DH si aplica)
			cd.com_det_horas_a_compensar AS horas_a_compensar,
			CASE WHEN EXISTS (
				SELECT 1 FROM ventana_8dh_exp v8
				WHERE v8.reg_cod_personal = COALESCE(p.reg_cod_personal, of.reg_cod_personal)
				  AND v8.dia_habil = c.date
			) THEN cd.com_det_horas_compensadas ELSE interval '00:00:00' END AS horas_compensadas,
			CASE WHEN EXISTS (
				SELECT 1 FROM ventana_8dh_exp v8
				WHERE v8.reg_cod_personal = COALESCE(p.reg_cod_personal, of.reg_cod_personal)
				  AND v8.dia_habil = c.date
			) THEN cd.com_det_horas_restantes ELSE cd.com_det_horas_a_compensar END AS horas_restantes,
			cd.com_estado::varchar AS estado_compensacion,

			-- Proyecciones para CTE RA/RA_dividida
			(p.reg_horas_trabajadas + COALESCE(ca.comi_intra, interval '00:00:00')) AS reg_horas_trabajadas,
			p.reg_hora_salida,
			p.reg_retraso,
			of.ocu_tipo,
			of.ocu_horas_estaticas,
			of.ocu_horas_extras,
			of.ocu_horas_adicionales,
			of.ocu_horas_adicionales_100,
			COALESCE(ca.comi_intra,    interval '00:00:00') AS comi_intra,
			COALESCE(ca.comi_post_80,  interval '00:00:00') AS comi_post_80,
			COALESCE(ca.comi_post_100, interval '00:00:00') AS comi_post_100
		FROM calendar c
		LEFT JOIN marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
		LEFT JOIN ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal
		LEFT JOIN compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha::date AND cd.com_cod_personal = param_reg_cod_personal
		LEFT JOIN comi_agreg ca ON c.date = ca.reg_fecha AND ca.reg_cod_personal = param_reg_cod_personal
	),
	-- 9) RE semanal / mensual, acumulados y recálculo (idéntico, respetando topes)
	re_semanal AS (
		SELECT rd.reg_cod_personal,
		       EXTRACT(WEEK FROM rd.reg_fecha) AS week,
		       LEAST(COALESCE(SUM(CASE WHEN rd.re >= interval '01:00:00' THEN LEAST(rd.re, interval '02:00:00') ELSE interval '00:00:00' END)
						 FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5), interval '00:00:00'),
		             interval '08:00:00') AS re_semanal_suma
		FROM re_diaria rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
	re_mensual AS (
		SELECT rs.reg_cod_personal,
		       LEAST(SUM(rs.re_semanal_suma), interval '32:00:00') AS re_mensual_suma
		FROM re_semanal rs
		GROUP BY rs.reg_cod_personal
	),
	re_acumulada_semanal AS (
		SELECT rd.reg_cod_personal,
		       rd.reg_fecha,
		       EXTRACT(WEEK FROM rd.reg_fecha) AS semana,
		       rd.re,
		       SUM(rd.re) OVER (PARTITION BY rd.reg_cod_personal, EXTRACT(YEAR FROM rd.reg_fecha), EXTRACT(WEEK FROM rd.reg_fecha)
		                        ORDER BY rd.reg_fecha ROWS UNBOUNDED PRECEDING) AS re_acumulada_semanal
		FROM re_diaria rd
		WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5
	),
	re_mensual_con_limited AS (
		SELECT rsa.reg_cod_personal, rsa.reg_fecha, rsa.re,
		       CASE WHEN rsa.re_acumulada_semanal > interval '08:00:00' THEN interval '00:00:00' ELSE rsa.re END AS re_con_limited
		FROM re_acumulada_semanal rsa
	),
	re_acumulada_mensual AS (
		SELECT rml.reg_cod_personal, rml.reg_fecha,
		       SUM(rml.re_con_limited) OVER (PARTITION BY rml.reg_cod_personal ORDER BY rml.reg_fecha) AS re_acumulada_mensual
		FROM re_mensual_con_limited rml
	),
	-- 10) RA (horas adicionales) según reglas existentes, usando trabajadas + comi_intra
	ra AS (
		SELECT rd.reg_cod_personal,
		       rd.reg_fecha,
		       rd.reg_hora_salida,
		       rd.reg_horas_trabajadas,  -- ya incluye comi_intra
		       rd.reg_retraso,
		       rd.ocu_tipo,
		       rd.ocu_horas_estaticas,
		       rd.ocu_horas_extras,
		       rd.ocu_horas_adicionales,
		       rd.ocu_horas_adicionales_100,
		       rd.comi_intra,
		       rd.comi_post_80,
		       rd.comi_post_100,
		       CASE
		         -- Estáticas (12): adicionales = adic + adic_100
		         WHEN rd.ocu_tipo = 12 AND rd.ocu_horas_estaticas = 1 THEN (rd.ocu_horas_adicionales::interval + rd.ocu_horas_adicionales_100::interval)
		         -- Sábado: RA = todas las horas trabajadas
		         WHEN EXTRACT(ISODOW FROM rd.reg_fecha) = 6 THEN rd.reg_horas_trabajadas
		         -- Si no hay al menos 1h de RE, no hay RA
		         WHEN rd.re < interval '01:00:00' THEN interval '00:00:00'
		         -- Si RE semanal > 8h → RA desde > 9h
		         WHEN (SELECT COALESCE(MAX(re_acumulada_semanal), interval '00:00:00') FROM re_acumulada_semanal ras
		               WHERE ras.reg_cod_personal = rd.reg_cod_personal AND ras.reg_fecha = rd.reg_fecha) > interval '08:00:00'
		           THEN CASE WHEN rd.reg_horas_trabajadas > interval '09:00:00' THEN rd.reg_horas_trabajadas - interval '09:00:00' ELSE interval '00:00:00' END
		         -- Si RE mensual entre 32:00 y 33:59 → RA desde > 9h
		         WHEN (SELECT COALESCE(MAX(re_acumulada_mensual), interval '00:00:00') FROM re_acumulada_mensual ram
		               WHERE ram.reg_cod_personal = rd.reg_cod_personal AND ram.reg_fecha = rd.reg_fecha) BETWEEN interval '32:00:00' AND interval '33:59:59'
		           THEN CASE WHEN rd.reg_horas_trabajadas > interval '09:00:00' THEN rd.reg_horas_trabajadas - interval '09:00:00' ELSE interval '00:00:00' END
		         -- Si RE mensual > 34:00 → RA desde > 9h restando 8h
		         WHEN (SELECT COALESCE(MAX(re_acumulada_mensual), interval '00:00:00') FROM re_acumulada_mensual ram
		               WHERE ram.reg_cod_personal = rd.reg_cod_personal AND ram.reg_fecha = rd.reg_fecha) > interval '34:00:00'
		           THEN CASE WHEN rd.reg_horas_trabajadas > interval '09:00:00' THEN rd.reg_horas_trabajadas - interval '08:00:00' ELSE interval '00:00:00' END
		         -- General: > 10:00 → trabajadas - 10:00
		         ELSE CASE WHEN rd.reg_horas_trabajadas > interval '10:00:00' THEN rd.reg_horas_trabajadas - interval '10:00:00' ELSE interval '00:00:00' END
		       END AS ra
		FROM re_diaria rd
	),
	-- 11) RA semanal/mensual (suma)
	ra_semanal_suma AS (
		SELECT rd.reg_cod_personal,
		       EXTRACT(WEEK FROM rd.reg_fecha) AS week,
		       SUM(CASE WHEN rd.ra IS NOT NULL THEN rd.ra ELSE interval '00:00:00' END)
		       FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_semanal_suma
		FROM ra rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
	ra_mensual_suma AS (
		SELECT rs.reg_cod_personal, SUM(rs.ra_semanal_suma) AS ra_mensual_suma
		FROM ra_semanal_suma rs
		GROUP BY rs.reg_cod_personal
	),
	-- 12) RA_80 / RA_100 con aporte de comisionamiento y días inhábiles
	ra_dividida AS (
		SELECT ra.reg_cod_personal,
		       ra.reg_fecha,
		       ra.ra,
		       ra.reg_hora_salida,
		       ra.reg_horas_trabajadas,
		       ra.ocu_tipo,
		       ra.ocu_horas_estaticas,
		       ra.ocu_horas_extras,
		       ra.ocu_horas_adicionales,
		       ra.ocu_horas_adicionales_100,
		       ra.comi_intra,
		       ra.comi_post_80,
		       ra.comi_post_100,
		       -- RA_80 base + comisionamiento post 80 (excepto inhábiles)
		       CASE
		         WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 THEN ra.ocu_horas_adicionales::interval
		         WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 THEN interval '00:00:00'
		         WHEN ra.reg_hora_salida <= time '19:59:59' THEN ra.ra + ra.comi_post_80
		         ELSE (ra.ra - (ra.reg_hora_salida - time '19:59:59')::interval) + ra.comi_post_80
		       END AS ra_80,
		       -- RA_100 base + comisionamiento post 100 y, si inhábil, todo comisionamiento
		       CASE
		         WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 THEN ra.ocu_horas_adicionales_100::interval
		         WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 THEN (ra.reg_horas_trabajadas) + ra.comi_intra + ra.comi_post_80 + ra.comi_post_100
		         WHEN ra.reg_hora_salida > time '19:59:59' THEN LEAST(ra.ra, (ra.reg_hora_salida - time '19:59:59')::interval) + ra.comi_post_100
		         ELSE interval '00:00:00' + ra.comi_post_100
		       END AS ra_100
		FROM ra
	),
	ra_divida_semanal_suma AS (
		SELECT rd.reg_cod_personal,
		       EXTRACT(WEEK FROM rd.reg_fecha) AS week,
		       SUM(CASE WHEN rd.ra_80  IS NOT NULL AND rd.ra_80  > interval '00:00:00' THEN rd.ra_80  ELSE interval '00:00:00' END)
		         FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal,
		       SUM(CASE WHEN rd.ra_100 IS NOT NULL THEN rd.ra_100 ELSE interval '00:00:00' END)
		         FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal
		FROM ra_dividida rd
		GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
	ra_dividia_mensual_suma AS (
		SELECT rs.reg_cod_personal,
		       SUM(rs.ra_80_semanal)  AS ra_80_mensual,
		       SUM(rs.ra_100_semanal) AS ra_100_mensual
		FROM ra_divida_semanal_suma rs
		GROUP BY rs.reg_cod_personal
	),
	-- 13) RE recalculada para no exceder tope semanal 8:00
	re_recalculada AS (
		SELECT ras.reg_cod_personal,
		       ras.reg_fecha,
		       rd.reg_horas_trabajadas,
		       ras.re,
		       ras.re_acumulada_semanal,
		       CASE
		         WHEN ras.re_acumulada_semanal >= interval '08:00:00' THEN (
		           CASE WHEN rd.reg_horas_trabajadas > interval '09:00:00'
		                THEN ras.re - (ras.re_acumulada_semanal - interval '08:00:00')
		                ELSE interval '00:00:00' END
		         )
		         ELSE interval '00:00:00'
		       END AS re_recalculada
		FROM re_acumulada_semanal ras
		JOIN re_diaria rd ON ras.reg_cod_personal = rd.reg_cod_personal AND ras.reg_fecha = rd.reg_fecha
	)
	SELECT
		r.reg_fecha,
		r.reg_cod_personal,
		p.tur_entrada,
		p.tur_salida,
		p.par_valor_time,
		p.reg_hora_entrada,
		p.reg_hora_salida,
		p.reg_horas_trabajadas,
		p.reg_retraso,
		p.reg_horas_extras,
		CASE WHEN re_rec.re_recalculada <> interval '00:00:00' THEN re_rec.re_recalculada ELSE r.re END AS re,
		r.horas_a_compensar,
		r.horas_compensadas,
		r.horas_restantes,
		r.estado_compensacion,
		s.re_semanal_suma,
		m.re_mensual_suma,
		ra_semanal.re_acumulada_semanal,
		ra_mensual.re_acumulada_mensual,
		-- RA total = ra_80 + ra_100 (incluye comisionamiento)
		(ra_dividida.ra_80 + ra_dividida.ra_100) AS horas_adicionales,
		ras.ra_semanal_suma,
		ma.ra_mensual_suma,
		ra_dividida.ra_80,
		ra_dividida.ra_100,
		rds.ra_80_semanal,
		rds.ra_100_semanal,
		rdm.ra_80_mensual,
		rdm.ra_100_mensual,
		btrim(CASE
			WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
			WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
			WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
			WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
			WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
			WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
			WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
			ELSE NULL END) AS dia_semana,
		of.ocu_descripcion AS ocurrencia_descripcion,
		of.ocurrencia_tipo,
		of.ocu_tipo,
		of.tip_codigo,
		ff.feriado_descripcion,
		CASE
			WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::varchar)
			WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::varchar)
			ELSE NULL
		END AS tolerancia_especial
	FROM re_diaria r
	LEFT JOIN marcaciones_completas                 p  ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
	LEFT JOIN re_recalculada                        re_rec ON r.reg_cod_personal = re_rec.reg_cod_personal AND r.reg_fecha = re_rec.reg_fecha
	LEFT JOIN ocurrencias_filtradas                 of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
	LEFT JOIN feriados_filtrados                    ff ON r.reg_fecha = ff.reg_fecha
	LEFT JOIN tolerancias_especiales_filtradas      te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
	LEFT JOIN re_semanal                            s  ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
	LEFT JOIN re_mensual                            m  ON r.reg_cod_personal = m.reg_cod_personal
	LEFT JOIN re_acumulada_semanal                  ra_semanal ON r.reg_cod_personal = ra_semanal.reg_cod_personal AND r.reg_fecha = ra_semanal.reg_fecha
	LEFT JOIN re_acumulada_mensual                  ra_mensual ON r.reg_cod_personal = ra_mensual.reg_cod_personal AND r.reg_fecha = ra_mensual.reg_fecha
	LEFT JOIN ra                                    rabase ON r.reg_cod_personal = rabase.reg_cod_personal AND r.reg_fecha = rabase.reg_fecha
	LEFT JOIN ra_dividida                           ON rabase.reg_cod_personal = ra_dividida.reg_cod_personal AND rabase.reg_fecha = ra_dividida.reg_fecha
	LEFT JOIN ra_semanal_suma                       ras ON r.reg_cod_personal = ras.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = ras.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
	LEFT JOIN ra_mensual_suma                       ma  ON r.reg_cod_personal = ma.reg_cod_personal
	LEFT JOIN ra_divida_semanal_suma                rds ON r.reg_cod_personal = rds.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = rds.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
	LEFT JOIN ra_dividia_mensual_suma               rdm ON r.reg_cod_personal = rdm.reg_cod_personal
	ORDER BY r.reg_fecha, r.reg_cod_personal;
END;
$function$;

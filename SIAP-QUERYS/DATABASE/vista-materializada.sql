-- public.vista_marcaciones_completas source

CREATE MATERIALIZED VIEW public.vista_marcaciones_completas
TABLESPACE pg_default
AS WITH marcaciones AS (
         SELECT COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal,
            e.reg_hora AS reg_hora_entrada,
            s.reg_hora AS reg_hora_salida,
            t.tur_codigo,
            t.tur_entrada,
            t.tur_salida,
            t.tur_tipo,
            p.par_cod AS tolerancia_cod,
            p.par_valor_time AS tolerancia_valor
           FROM marcacion_entrada_adsoluta e
             FULL JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
             LEFT JOIN turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha) AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
             LEFT JOIN parametros p ON p.par_cod = t.tur_tolerancia
        )
 SELECT reg_fecha,
    reg_cod_personal,
    reg_hora_entrada,
    reg_hora_salida,
    tur_codigo,
    tur_entrada,
    tur_salida,
    tur_tipo,
    tolerancia_cod,
    tolerancia_valor
   FROM marcaciones m
  ORDER BY reg_fecha, reg_cod_personal
WITH DATA;

-- View indexes:
CREATE INDEX idx_vista_marcaciones_completas ON public.vista_marcaciones_completas USING btree (reg_fecha, reg_cod_personal);
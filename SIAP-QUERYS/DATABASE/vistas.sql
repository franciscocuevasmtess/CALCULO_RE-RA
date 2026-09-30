-- public.actualizacion_generados_configuracion source

CREATE OR REPLACE VIEW public.actualizacion_generados_configuracion
AS SELECT act_cod,
    act_tipo,
    act_anho,
    act_mes,
    act_estado
   FROM actualizacion_generados;


-- public.asuetos source

CREATE OR REPLACE VIEW public.asuetos
AS SELECT ocu_cod,
    ocu_cod_persona,
    ocu_fecha_desde,
    ocu_fecha_hasta,
    ocu_hora_desde,
    ocu_hora_hasta,
    ocu_descripcion,
    ocu_tipo,
    ocu_cantidad_periodo,
    ocu_periodo,
    ocu_tipo_grupo,
    ocu_cod_referencia,
    ocu_sin_horas_extras,
    ocu_asueto,
    ocu_asueto_sin_horas,
    ocu_asueto_dia_completo,
    ocu_funcionarios_afectados
   FROM ocurrencias
  WHERE ocu_asueto = 1;


-- public.compensaciones_orden source

CREATE OR REPLACE VIEW public.compensaciones_orden
AS SELECT com_cod,
    com_cod_ocurrencia,
    com_cod_personal,
    com_fecha,
    com_cantidad_horas,
    com_fecha_inicio,
    com_fecha_fin,
    orden_compensacion(com_cod_ocurrencia::text, 188) AS orden
   FROM compensaciones
  GROUP BY com_cod, com_cod_ocurrencia, com_cod_personal, com_fecha, com_cantidad_horas, com_fecha_inicio, com_fecha_fin, (orden_compensacion(com_cod_ocurrencia::text, 188));


-- public.compensaciones_unicas source

CREATE OR REPLACE VIEW public.compensaciones_unicas
AS SELECT com_cod,
    com_cod_ocurrencia,
    com_cod_personal,
    com_fecha,
    com_cantidad_horas,
    com_fecha_inicio,
    com_fecha_fin
   FROM compensaciones
  GROUP BY com_cod, com_cod_ocurrencia, com_cod_personal, com_fecha, com_cantidad_horas, com_fecha_inicio, com_fecha_fin;


-- public.horas_funcionarios source

CREATE OR REPLACE VIEW public.horas_funcionarios
AS SELECT hor_cod,
    hor_cod_personal,
    ( SELECT (personales.per_nombre::text || ' '::text) || personales.per_apellido::text
           FROM personales
          WHERE personales.per_cod = horas_personales.hor_cod_personal) AS hor_nombre_apellido,
    hor_cod_personal AS hor_cedula,
    hor_mes,
    hor_anho,
    hor_extras,
    hor_adicional,
    hor_adicional_100,
    hor_fecha
   FROM horas_personales
  ORDER BY hor_anho DESC, hor_mes, (( SELECT (personales.per_nombre::text || ' '::text) || personales.per_apellido::text
           FROM personales
          WHERE personales.per_cod = horas_personales.hor_cod_personal));


-- public.marcacion_entrada_adsoluta source

CREATE OR REPLACE VIEW public.marcacion_entrada_adsoluta
AS WITH earliest_entries AS (
         SELECT res.reg_codigo,
            res.reg_cod_personal,
            res.reg_fecha,
            res.reg_hora,
            res.reg_tipo,
            res.reg_reloj
           FROM registros_entrada_salida res
          WHERE res.reg_hora = (( SELECT min(auxiliar.reg_hora) AS min
                   FROM registros_entrada_salida auxiliar
                  WHERE auxiliar.reg_cod_personal = res.reg_cod_personal AND auxiliar.reg_fecha = res.reg_fecha)) AND res.reg_hora < '13:00:00'::time without time zone
        )
 SELECT DISTINCT ON (ee.reg_fecha, ee.reg_cod_personal) ee.reg_codigo,
    ee.reg_cod_personal,
    ee.reg_fecha,
    ee.reg_hora,
    ee.reg_tipo,
    ee.reg_reloj,
    COALESCE(te.tol_tiempo::interval, '00:00:00'::interval) AS tol_tiempo_interval
   FROM earliest_entries ee
     LEFT JOIN LATERAL ( SELECT te_1.tol_tiempo
           FROM tolerancias_especiales te_1
          WHERE (te_1.tol_tipo::text = 'I'::text AND te_1.tol_cod_personal = ee.reg_cod_personal OR te_1.tol_tipo::text = 'G'::text AND te_1.tol_sed_cod = (( SELECT personales.per_sede
                   FROM personales
                  WHERE personales.per_cod = ee.reg_cod_personal))) AND ee.reg_fecha >= te_1.tol_fecha_desde AND ee.reg_fecha <= te_1.tol_fecha_hasta
          ORDER BY (
                CASE
                    WHEN te_1.tol_tipo::text = 'I'::text THEN 1
                    ELSE 2
                END), te_1.tol_fecha_desde DESC
         LIMIT 1) te ON true;


-- public.marcacion_entrada_adsoluta_prueba source

CREATE OR REPLACE VIEW public.marcacion_entrada_adsoluta_prueba
AS WITH earliest_entries AS (
         SELECT res.reg_codigo,
            res.reg_cod_personal,
            res.reg_fecha,
            res.reg_hora,
            res.reg_tipo,
            res.reg_reloj
           FROM registros_entrada_salida res
          WHERE res.reg_hora = (( SELECT min(auxiliar.reg_hora) AS min
                   FROM registros_entrada_salida auxiliar
                  WHERE auxiliar.reg_cod_personal = res.reg_cod_personal AND auxiliar.reg_fecha = res.reg_fecha)) AND res.reg_hora < '13:00:00'::time without time zone
        )
 SELECT ee.reg_codigo,
    ee.reg_cod_personal,
    ee.reg_fecha,
    ee.reg_hora,
    ee.reg_tipo,
    ee.reg_reloj,
    te.tol_tiempo
   FROM earliest_entries ee
     LEFT JOIN tolerancias_especiales te ON (te.tol_tipo::text = 'I'::text AND te.tol_cod_personal = ee.reg_cod_personal OR te.tol_tipo::text = 'G'::text AND te.tol_sed_cod = (( SELECT personales.per_sede
           FROM personales
          WHERE personales.per_cod = ee.reg_cod_personal))) AND ee.reg_fecha >= te.tol_fecha_desde AND ee.reg_fecha <= te.tol_fecha_hasta;


-- public.marcacion_entrada_adsoluta_prueba2 source

CREATE OR REPLACE VIEW public.marcacion_entrada_adsoluta_prueba2
AS WITH earliest_entries AS (
         SELECT res.reg_codigo,
            res.reg_cod_personal,
            res.reg_fecha,
            res.reg_hora,
            res.reg_tipo,
            res.reg_reloj
           FROM registros_entrada_salida res
          WHERE res.reg_hora = (( SELECT min(auxiliar.reg_hora) AS min
                   FROM registros_entrada_salida auxiliar
                  WHERE auxiliar.reg_cod_personal = res.reg_cod_personal AND auxiliar.reg_fecha = res.reg_fecha)) AND res.reg_hora < '13:00:00'::time without time zone
        )
 SELECT ee.reg_codigo,
    ee.reg_cod_personal,
    ee.reg_fecha,
    ee.reg_hora,
    ee.reg_tipo,
    ee.reg_reloj,
    COALESCE(te.tol_tiempo::interval, '00:00:00'::interval) AS tol_tiempo_interval
   FROM earliest_entries ee
     LEFT JOIN tolerancias_especiales te ON (te.tol_tipo::text = 'I'::text AND te.tol_cod_personal = ee.reg_cod_personal OR te.tol_tipo::text = 'G'::text AND te.tol_sed_cod = (( SELECT personales.per_sede
           FROM personales
          WHERE personales.per_cod = ee.reg_cod_personal))) AND ee.reg_fecha >= te.tol_fecha_desde AND ee.reg_fecha <= te.tol_fecha_hasta;


-- public.marcacion_entrada_salida source

CREATE OR REPLACE VIEW public.marcacion_entrada_salida
AS SELECT e.reg_fecha,
    e.reg_cod_personal,
    e.reg_hora AS reg_hora_entrada,
    s.reg_hora AS reg_hora_salida,
    s.reg_hora - e.reg_hora AS reg_horas_trabajadas,
        CASE
            WHEN e.reg_hora > (t.tur_entrada + p.par_valor_time) THEN e.reg_hora - (t.tur_entrada + p.par_valor_time)
            ELSE '00:00:00'::interval
        END AS reg_retraso
   FROM marcacion_entrada_adsoluta e
     JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
     JOIN turnos t ON e.reg_cod_personal = t.tur_cod_personal AND t.tur_fecha_desde <= e.reg_fecha AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= e.reg_fecha)
     JOIN parametros p ON p.par_cod = 1
  WHERE e.reg_cod_personal = 691 AND date_part('month'::text, e.reg_fecha) = 1::numeric::double precision AND date_part('year'::text, e.reg_fecha) = 2024::numeric::double precision
  ORDER BY e.reg_fecha, e.reg_cod_personal DESC;


-- public.marcacion_salida_adsoluta source

CREATE OR REPLACE VIEW public.marcacion_salida_adsoluta
AS SELECT DISTINCT ON (reg_fecha, reg_cod_personal) reg_codigo,
    reg_cod_personal,
    reg_fecha,
    reg_hora,
    reg_tipo,
    reg_reloj
   FROM registros_entrada_salida
  WHERE reg_hora = (( SELECT max(auxiliar.reg_hora) AS max
           FROM registros_entrada_salida auxiliar
          WHERE auxiliar.reg_cod_personal = registros_entrada_salida.reg_cod_personal AND auxiliar.reg_fecha = registros_entrada_salida.reg_fecha)) AND reg_hora >= '10:00:00'::time without time zone
  ORDER BY reg_fecha, reg_cod_personal, reg_hora DESC, reg_codigo;


-- public.marcaciones_entrada source

CREATE OR REPLACE VIEW public.marcaciones_entrada
AS SELECT reg_codigo,
    reg_cod_personal,
    reg_fecha,
    reg_hora,
    reg_tipo
   FROM registros_entrada_salida
  WHERE reg_hora = (( SELECT min(auxiliar.reg_hora) AS min
           FROM registros_entrada_salida auxiliar
          WHERE auxiliar.reg_cod_personal = registros_entrada_salida.reg_cod_personal AND auxiliar.reg_fecha = registros_entrada_salida.reg_fecha)) AND reg_tipo::text = 'I'::text
  GROUP BY reg_fecha, reg_codigo;


-- public.marcaciones_entrada_salida source

CREATE OR REPLACE VIEW public.marcaciones_entrada_salida
AS SELECT ( SELECT reloj.rel_cod_persona
           FROM codigos_reloj reloj
          WHERE reloj.rel_codigo = codigos_reloj.rel_codigo AND reloj.rel_estado = 1
         LIMIT 1) AS reg_cod_persona,
    codigos_reloj.rel_codigo AS reg_cod_reloj,
    marcacion_entrada_adsoluta.reg_fecha,
    marcacion_entrada_adsoluta.reg_hora AS reg_hora_entrada,
    marcacion_salida_adsoluta.reg_hora AS reg_hora_salida,
    turnos.tur_entrada,
        CASE
            WHEN marcacion_entrada_adsoluta.reg_hora > (turnos.tur_entrada + '00:00:01'::interval * (( SELECT date_part('epoch'::text, parametros.par_valor::interval) AS "extract"
               FROM parametros
              WHERE parametros.par_anho = split_part(marcacion_entrada_adsoluta.reg_fecha::text, '-'::text, 1)::integer AND parametros.par_cod = 1
             LIMIT 1))) THEN marcacion_entrada_adsoluta.reg_hora - (turnos.tur_entrada + '00:00:01'::interval * (( SELECT date_part('epoch'::text, parametros.par_valor::interval) AS "extract"
               FROM parametros
              WHERE parametros.par_anho = split_part(marcacion_entrada_adsoluta.reg_fecha::text, '-'::text, 1)::integer AND parametros.par_cod = 1
             LIMIT 1)))
            ELSE NULL::interval
        END AS reg_retraso,
        CASE
            WHEN marcacion_entrada_adsoluta.reg_hora < turnos.tur_entrada THEN marcacion_salida_adsoluta.reg_hora - turnos.tur_entrada
            WHEN marcacion_entrada_adsoluta.reg_hora >= turnos.tur_entrada THEN marcacion_salida_adsoluta.reg_hora - marcacion_entrada_adsoluta.reg_hora
            ELSE NULL::interval
        END AS reg_horas_total,
        CASE
            WHEN marcacion_entrada_adsoluta.reg_hora < turnos.tur_entrada THEN make_interval(secs => (date_part('epoch'::text, marcacion_salida_adsoluta.reg_hora - turnos.tur_entrada) / 60::numeric::double precision - 60::numeric::double precision * (( SELECT date_part('epoch'::text, parametros.par_valor::interval) / 60::numeric::double precision
               FROM parametros
              WHERE parametros.par_anho = split_part(marcacion_entrada_adsoluta.reg_fecha::text, '-'::text, 1)::integer AND parametros.par_cod = 2
             LIMIT 1))) * 60::numeric::double precision)
            WHEN marcacion_entrada_adsoluta.reg_hora >= turnos.tur_entrada THEN make_interval(secs => (date_part('epoch'::text, marcacion_salida_adsoluta.reg_hora - marcacion_entrada_adsoluta.reg_hora) / 60::numeric::double precision - 480::numeric::double precision) * 60::numeric::double precision)
            ELSE NULL::interval
        END AS reg_horas_extras
   FROM marcacion_entrada_adsoluta
     LEFT JOIN marcacion_salida_adsoluta ON marcacion_entrada_adsoluta.reg_fecha = marcacion_salida_adsoluta.reg_fecha AND marcacion_entrada_adsoluta.reg_cod_personal = marcacion_salida_adsoluta.reg_cod_personal AND marcacion_entrada_adsoluta.reg_codigo <> marcacion_salida_adsoluta.reg_codigo
     LEFT JOIN codigos_reloj ON marcacion_entrada_adsoluta.reg_cod_personal = codigos_reloj.rel_codigo
     LEFT JOIN turnos ON codigos_reloj.rel_cod_persona = turnos.tur_cod_personal
  WHERE marcacion_entrada_adsoluta.reg_cod_personal = 691 AND date_part('month'::text, marcacion_entrada_adsoluta.reg_fecha) = 1::numeric::double precision AND date_part('year'::text, marcacion_entrada_adsoluta.reg_fecha) = 2024::numeric::double precision
  GROUP BY codigos_reloj.rel_cod_persona, marcacion_entrada_adsoluta.reg_fecha, codigos_reloj.rel_codigo, marcacion_entrada_adsoluta.reg_hora, marcacion_salida_adsoluta.reg_hora, turnos.tur_entrada
  ORDER BY marcacion_entrada_adsoluta.reg_fecha DESC, codigos_reloj.rel_cod_persona DESC;


-- public.marcaciones_entradas_salidas source

CREATE OR REPLACE VIEW public.marcaciones_entradas_salidas
AS SELECT COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
            WHEN e.reg_hora <= (t.tur_entrada + p.par_valor_time) THEN
            CASE
                WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
            END
            ELSE '00:00:00'::interval
        END AS reg_horas_extras
   FROM marcacion_entrada_adsoluta e
     FULL JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
     LEFT JOIN turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha) AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
     LEFT JOIN parametros p ON p.par_cod = t.tur_tolerancia
  ORDER BY (COALESCE(e.reg_fecha, s.reg_fecha)), (COALESCE(e.reg_cod_personal, s.reg_cod_personal)) DESC;


-- public.meses_anho source

CREATE OR REPLACE VIEW public.meses_anho
AS SELECT meses.mes_cod,
    meses.mes_letras,
    anhos.cod,
    anhos.numero,
    anhos.numero_meses
   FROM meses
     JOIN anhos ON meses.mes_cod >= anhos.numero_meses;


-- public.novedades source

CREATE OR REPLACE VIEW public.novedades
AS SELECT ocurrencias.ocu_cod,
    ocurrencias.ocu_cod_persona,
    ocurrencias.ocu_fecha_desde,
    ocurrencias.ocu_fecha_hasta,
    ocurrencias.ocu_hora_desde,
    ocurrencias.ocu_hora_hasta,
    ocurrencias.ocu_descripcion,
    ocurrencias.ocu_tipo,
    ocurrencias.ocu_cantidad_periodo,
    ocurrencias.ocu_periodo,
    ocurrencias.ocu_tipo_grupo,
    ocurrencias.ocu_cod_referencia,
    ocurrencias.ocu_sin_horas_extras,
    ocurrencias.ocu_asueto,
    ocurrencias.ocu_dias_gastados,
    tipos_ocurrencias.tip_cod,
    tipos_ocurrencias.tip_descripcion,
    tipos_ocurrencias.tip_cantidad_maxima_mes,
    tipos_ocurrencias.tip_cantidad_maxima_anho,
    tipos_ocurrencias.tip_dias,
    tipos_ocurrencias.tip_codigo,
    tipos_ocurrencias.tip_horas_extras,
    tipos_ocurrencias.tip_sin_horas,
    tipos_ocurrencias.tip_asistencia,
    tipos_ocurrencias.tip_llegada_tardia,
    tipos_ocurrencias.tip_asueto
   FROM ocurrencias
     JOIN tipos_ocurrencias ON ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod;


-- public.ocurrencias_acumulado source

CREATE OR REPLACE VIEW public.ocurrencias_acumulado
AS SELECT ocurrencias.ocu_cod_persona,
    ocurrencias.ocu_tipo,
    sum(detalle_ocurrencias.det_dias_gastados) AS ocu_cantidad,
    detalle_ocurrencias.det_anho_gasto
   FROM ocurrencias
     JOIN detalle_ocurrencias ON ocurrencias.ocu_cod = detalle_ocurrencias.det_cod_ocurrencia
  GROUP BY ocurrencias.ocu_cod_persona, ocurrencias.ocu_tipo, detalle_ocurrencias.det_anho_gasto
  ORDER BY ocurrencias.ocu_cod_persona;


-- public.ocurrencias_fechas source

CREATE OR REPLACE VIEW public.ocurrencias_fechas
AS SELECT ocurrencias.ocu_cod,
    ocurrencias.ocu_cod_persona,
    ocurrencias.ocu_fecha_desde,
    ocurrencias.ocu_fecha_hasta,
    ocurrencias.ocu_hora_desde,
    ocurrencias.ocu_hora_hasta,
    ocurrencias.ocu_descripcion,
    ocurrencias.ocu_tipo,
    ocurrencias.ocu_cantidad_periodo,
    ocurrencias.ocu_periodo,
    ocurrencias.ocu_tipo_grupo,
    ocurrencias.ocu_tipo_grupo_sede,
    ocurrencias.ocu_funcionarios_afectados,
    ocurrencias.ocu_tipo_grupo_digito,
    ocurrencias.ocu_cod_referencia,
    ocurrencias.ocu_sin_horas_extras,
    ocurrencias.ocu_asueto,
    ocurrencias.ocu_asueto_sin_horas,
    ocurrencias.ocu_asueto_dia_completo,
    ocurrencias.ocu_dias_gastados,
    ocurrencias.ocu_compensar,
    ocurrencias.ocu_horas_compensacion,
    ocurrencias.ocu_compensa,
    ocurrencias.ocu_horas_estaticas,
    ocurrencias.ocu_horas_extras,
    ocurrencias.ocu_horas_adicionales,
    ocurrencias.ocu_horas_adicionales_100,
    ocurrencias.ocu_dia_completo,
    ocurrencias.ocu_usuario,
    fechas_ocurrencias.fecha,
    fechas_ocurrencias.anho,
    fechas_ocurrencias.mes
   FROM ocurrencias
     JOIN fechas_ocurrencias ON fechas_ocurrencias.fecha >= ocurrencias.ocu_fecha_desde AND fechas_ocurrencias.fecha <= ocurrencias.ocu_fecha_hasta;


-- public.ocurrencias_finales source

CREATE OR REPLACE VIEW public.ocurrencias_finales
AS SELECT ocu_cod,
    ocu_cod_persona,
    ocu_fecha_desde,
    ocu_fecha_hasta,
    ocu_hora_desde,
    ocu_hora_hasta,
    ocu_descripcion,
    ocu_tipo,
    ocu_cantidad_periodo,
    ocu_periodo,
    ocu_tipo_grupo,
    ocu_tipo_grupo_sede,
    ocu_funcionarios_afectados,
    ocu_tipo_grupo_digito,
    ocu_cod_referencia,
    ocu_sin_horas_extras,
    ocu_asueto,
    ocu_asueto_dia_completo,
    ocu_dias_gastados,
    ocu_compensar,
    ocu_horas_compensacion,
    ocu_compensa,
    ocu_horas_estaticas,
    ocu_horas_extras,
    ocu_horas_adicionales,
    ocu_horas_adicionales_100,
    ocu_dia_completo,
    ocu_usuario
   FROM ocurrencias
  ORDER BY ocu_cod DESC
 LIMIT 500;


-- public.ocurrencias_novedades source

CREATE OR REPLACE VIEW public.ocurrencias_novedades
AS SELECT ocu_cod,
    ocu_cod_persona,
    ocu_fecha_desde,
    ocu_fecha_hasta,
    ocu_hora_desde,
    ocu_hora_hasta,
    ocu_descripcion,
    ocu_tipo,
    ocu_cantidad_periodo,
    ocu_periodo,
    ocu_tipo_grupo,
    ocu_cod_referencia
   FROM ocurrencias
  WHERE ocu_tipo <> 1 AND ocu_tipo <> 2;


-- public.personales_activos source

CREATE OR REPLACE VIEW public.personales_activos
AS SELECT per_cod,
    categoria_cat_codigo,
    departamentos_dep_cod,
    dependencias_dep_cod,
    paises_pai_cod,
    ciudades_ciu_cod,
    profesiones_pro_cod,
    tipo_funcionario_tfun_cod,
    cargos_car_cod,
    per_nombre,
    per_apellido,
    per_ci,
    per_sexo,
    per_nacimiento,
    per_est_civil,
    per_gruposangre,
    per_domicilio,
    per_barrio,
    per_teleparticular,
    per_telecelular,
    per_email_part,
    per_email_instit,
    per_ruc,
    per_contacto_eme,
    per_tele_emer,
    per_ingreso,
    per_nombramiento,
    per_estado,
    per_usuario
   FROM personales
  WHERE per_estado = 1;


-- public.personales_dependencias source

CREATE OR REPLACE VIEW public.personales_dependencias
AS SELECT DISTINCT concat(personales_dependencia.per_nombre, ' ', personales_dependencia.per_apellido, ' (', dependencias.dep_descripcion_corta, ')') AS per_nombre_completo,
    personales_dependencia.per_cod,
    personales_dependencia.per_nombre,
    personales_dependencia.per_apellido,
    personales_dependencia.dependencias_dep_cod AS per_cod_dependencia,
    dependencias.dep_padre
   FROM dependencias
     JOIN personales_activos personales_dependencia ON personales_dependencia.dependencias_dep_cod = dependencias.dep_cod
  ORDER BY personales_dependencia.dependencias_dep_cod, personales_dependencia.per_apellido;


-- public.registro_entrada_salida_usuarios source

CREATE OR REPLACE VIEW public.registro_entrada_salida_usuarios
AS SELECT registros_entrada_salida.reg_codigo,
    registros_entrada_salida.reg_cod_personal,
    registros_entrada_salida.reg_fecha,
    registros_entrada_salida.reg_hora,
    registros_entrada_salida.reg_tipo,
    codigos_reloj.rel_cod_persona AS reg_cod_persona,
    registros_entrada_salida.reg_reloj,
    registros_entrada_salida.reg_mes,
    registros_entrada_salida.reg_anho
   FROM registros_entrada_salida
     JOIN codigos_reloj ON registros_entrada_salida.reg_cod_personal = codigos_reloj.rel_codigo AND registros_entrada_salida.reg_reloj = codigos_reloj.rel_reloj AND registros_entrada_salida.reg_fecha >= codigos_reloj.rel_fecha_desde AND registros_entrada_salida.reg_fecha <= codigos_reloj.rel_fecha_hasta;


-- public.turnos_tolerancias source

CREATE OR REPLACE VIEW public.turnos_tolerancias
AS SELECT tur_codigo,
    tur_cod_personal,
    tur_descripcion,
    tur_entrada,
    tur_salida,
    tur_estado,
    tur_fecha_desde,
    tur_fecha_hasta,
    tur_tolerancia,
    ( SELECT parametros.par_valor
           FROM parametros
          WHERE parametros.par_cod = turnos.tur_tolerancia AND parametros.par_anho::numeric::double precision = date_part('year'::text, turnos.tur_fecha_desde)) AS tur_tolerancia_base
   FROM turnos;


-- public.usuario_sistema source

CREATE OR REPLACE VIEW public.usuario_sistema
AS SELECT usu_cod,
    usu_usuario,
    usu_contrasenha,
    usu_nombre,
    usu_personal
   FROM usuarios;


-- public.vista_func_asistencia source

CREATE OR REPLACE VIEW public.vista_func_asistencia
AS SELECT DISTINCT ON (m.reg_fecha, m.reg_cod_personal) m.reg_cod_personal,
    btrim(
        CASE
            WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '1'::text THEN 'DOMINGO'::text
            WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '2'::text THEN 'LUNES'::text
            WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '3'::text THEN 'MARTES'::text
            WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '4'::text THEN 'MIÉRCOLES'::text
            WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '5'::text THEN 'JUEVES'::text
            WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '6'::text THEN 'VIERNES'::text
            WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '7'::text THEN 'SÁBADO'::text
            ELSE NULL::text
        END) AS dia_semana,
    m.reg_fecha,
    p.per_nombre AS nombre,
    p.per_apellido AS apellido,
    t.tur_entrada AS hora_entrada_programada,
    t.tur_salida AS hora_salida_programada,
    m.reg_hora_entrada AS entrada,
    m.reg_hora_salida AS salida,
    m.reg_retraso AS retraso,
    m.reg_horas_trabajadas AS horas_trabajadas,
    m.reg_horas_extras AS horas_extras
   FROM marcaciones_entradas_salidas m
     LEFT JOIN personales p ON m.reg_cod_personal = p.per_cod
     LEFT JOIN turnos t ON p.per_cod = t.tur_cod_personal
  ORDER BY m.reg_fecha, m.reg_cod_personal;
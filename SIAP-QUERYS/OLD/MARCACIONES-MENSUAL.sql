/*
 * MARCACIONES - INFORME MENSUAL
 * La funcion 'marcaciones_por_mes_horas5(anho, mes, cod_personal)' obtiene las marcaciones mensuales de los
 * funcionarios recibe tres parametros: el año, mes, codigo de personal.
 *
 * Para poder ajustar a los nuevos cambios solicitados, se crea una nueva tabla 'historico_marcaciones_mensual' 
 * donde se agregan como columnas las mismas que devuelve la funcion.
 *
 * Paso 1:
 * Insertar manualmente todas las marcaciones en la tabla historicos, para ello invocar a la 
 * funcion marcaciones_por_mes_horas5(anho, mes, cod_personal) con parametros de filtro e 
 * insertar sus datos en la tabla historico_marcaciones. Este proceso se realiza una vez para 
 * poder poblar la tabla con todas las marcaciones del mes.
 * OBSERVACION: Para poder traer todos los datos que obtiene esta funcion, al realizar mi investigacion
 * verifique que existen datos desde: JUNIO desde esa fecha se debe empezar a insertar manualmente..
	SELECT res.* 
	FROM (SELECT DISTINCT tur_cod_personal FROM turnos) personas_turnos 
		JOIN marcaciones_por_mes_horas5(2023, 7, personas_turnos.tur_cod_personal) res on true;
 *
 * Paso 2:
 * Crear funcion en la base de datos que realiza el insert de las marcaciones mensuales en la 
 * tabla historicos, esta funcion debera ser invocada posteriormente desde una tarea programada, 
 * se debe definir en que hora del dia se ejecutara el cron_job.
 *
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 * Paso 3:
 * Modificar consulta en el PHPRunner, en el AJAX donde se realiza la invocacion a la vista con los
 * parametros que ingresa el usuario desde la pantalla del reporte modificar la consulta para hacer un
 * select de la tabla historico_marcaciones en vez de invocar a la funcion actual.
 *
 * Paso 4:
 * Crear la tarea programada que invoque la funcion para insertar las marcaciones.
 * 
*/


/* Paso 1: Insertar todas las marcaciones del mes en la tabla historicos. */
INSERT INTO historico_marcaciones(nombre_reporte,
									reg_fecha,
									reg_cod_personal,
									tur_entrada, 
									tur_salida, 
									par_valor_time,
									reg_hora_entrada, 
									reg_hora_salida,
									reg_horas_trabajadas,
									reg_retraso,
									reg_horas_extras,
									re,
									horas_a_compensar, 
									horas_compensadas, 
									horas_restantes,
									estado_compensacion, 
									re_semanal_suma,
									re_mensual_suma,
									re_acumulada_semanal, 
									re_acumulada_mensual, 
									ra, 
									ra_semanal_suma, 
									ra_mensual_suma, 
									ra_80, 
									ra_100, 
									ra_80_semanal, 
									ra_100_semanal, 
									ra_80_mensual, 
									ra_100_mensual,
									dia_semana,
									ocurrencia_descripcion, 
									ocurrencia_tipo, 
									ocu_tipo, 
									tip_codigo, 
									feriado_descripcion, 
									tolerancia_especial,
									parametro1, 
									parametro2,
									fecha_registro)
SELECT 'informe_mensual',
		res.reg_fecha,
		res.reg_cod_personal,
		res.tur_entrada,
		res.tur_salida,
		res.par_valor_time,
		res.reg_hora_entrada,
		res.reg_hora_salida,
		res.reg_horas_trabajadas,
		res.reg_retraso,
		res.reg_horas_extras,
		res.re,
		res.horas_a_compensar,
		res.horas_compensadas,
		res.horas_restantes,
		res.estado_compensacion,
		res.re_semanal_suma,
		res.re_mensual_suma,
		res.re_acumulada_semanal,
		res.re_acumulada_mensual,
		res.ra,
		res.ra_semanal_suma,
		res.ra_mensual_suma,	
		res.ra_80,
		res.ra_100,
		res.ra_80_semanal,
		res.ra_100_semanal,
		res.ra_80_mensual,
		res.ra_100_mensual,
		res.dia_semana,
		res.ocurrencia_descripcion,
		res.ocurrencia_tipo,
		res.ocu_tipo,
		res.tip_codigo,
		res.feriado_descripcion,
		res.tolerancia_especial,
		2023,
		7,
		NOW()
FROM (select distinct tur_cod_personal from turnos) personas_turnos
	join marcaciones_por_mes_horas5(2023, 6, personas_turnos.tur_cod_personal) res on true;
FROM (select distinct tur_cod_personal from turnos) personas_turnos
	join marcaciones_por_mes_horas5(2023, 7, personas_turnos.tur_cod_personal) res on true;
FROM (select distinct tur_cod_personal from turnos) personas_turnos
	join marcaciones_por_mes_horas5(2023, 8, personas_turnos.tur_cod_personal) res on true;
FROM (select distinct tur_cod_personal from turnos) personas_turnos
	join marcaciones_por_mes_horas5(2023, 9, personas_turnos.tur_cod_personal) res on true;
FROM (select distinct tur_cod_personal from turnos) personas_turnos
	join marcaciones_por_mes_horas5(2023, 10, personas_turnos.tur_cod_personal) res on true;
FROM (select distinct tur_cod_personal from turnos) personas_turnos
	join marcaciones_por_mes_horas5(2023, 11, personas_turnos.tur_cod_personal) res on true;	
FROM (select distinct tur_cod_personal from turnos) personas_turnos
	join marcaciones_por_mes_horas5(2023, 12, personas_turnos.tur_cod_personal) res on true;	
	
	
	
	
/* Paso 2: Crear la funcion que inserta las marcaciones mensuales en la tabla historico. 
CAST(EXTRACT(YEAR FROM CURRENT_DATE) AS INTEGER)  -> Obtendra el año actual.
DATE_PART('month', CURRENT_TIMESTAMP)::integer  -> Obtendra el mes actual.
*/
CREATE OR REPLACE FUNCTION public.insertar_historico_marcaciones_mensual()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
	v_inicio TIMESTAMP;
	v_fin TIMESTAMP;
	v_duracion_ms INTEGER;
	v_insertados INTEGER := 0;
BEGIN
	v_inicio := clock_timestamp();  -- captura tiempo preciso
	
    -- Evita duplicados si ya fue procesado
    DELETE FROM historico_marcaciones 
	WHERE nombre_reporte = 'informe_mensual'
    AND parametro1 = CAST(EXTRACT(YEAR FROM CURRENT_DATE) AS INTEGER) 
   	AND parametro2 = DATE_PART('month', CURRENT_TIMESTAMP)::integer;
   
   	WITH ins AS (
		INSERT INTO historico_marcaciones (nombre_reporte,
			reg_fecha,
			reg_cod_personal,
			tur_entrada,
			tur_salida,
			par_valor_time,
			reg_hora_entrada,
			reg_hora_salida,
			reg_horas_trabajadas,
			reg_retraso,
			reg_horas_extras,
			re,
			horas_a_compensar,
			horas_compensadas,
			horas_restantes,
			estado_compensacion,
			re_semanal_suma,
			re_mensual_suma,
			re_acumulada_semanal,
			re_acumulada_mensual,
			ra,
			ra_semanal_suma,
			ra_mensual_suma,
			ra_80,
			ra_100,
			ra_80_semanal,
			ra_100_semanal,
			ra_80_mensual,
			ra_100_mensual,
			dia_semana,
			ocurrencia_descripcion,
			ocurrencia_tipo,
			ocu_tipo,
			tip_codigo,
			feriado_descripcion,
			tolerancia_especial,
			parametro1,
			parametro2,
			fecha_registro)
    	SELECT 'informe_mensual',
			res.reg_fecha,
			res.reg_cod_personal,
			res.tur_entrada,
			res.tur_salida,
			res.par_valor_time,
			res.reg_hora_entrada,
			res.reg_hora_salida,
			res.reg_horas_trabajadas,
			res.reg_retraso,
			res.reg_horas_extras,
			res.re,
			res.horas_a_compensar,
			res.horas_compensadas,
			res.horas_restantes,
			res.estado_compensacion,
			res.re_semanal_suma,
			res.re_mensual_suma,
			res.re_acumulada_semanal,
			res.re_acumulada_mensual,
			res.ra,
			res.ra_semanal_suma,
			res.ra_mensual_suma,
			res.ra_80,
			res.ra_100,
			res.ra_80_semanal,
			res.ra_100_semanal,
			res.ra_80_mensual,
			res.ra_100_mensual,
			res.dia_semana,
			res.ocurrencia_descripcion,
			res.ocurrencia_tipo,
			res.ocu_tipo,
			res.tip_codigo,
			res.feriado_descripcion,
			res.tolerancia_especial,
			CAST(EXTRACT(YEAR FROM CURRENT_DATE) AS INTEGER),
			DATE_PART('month', CURRENT_TIMESTAMP)::integer,
			NOW()
		FROM (select distinct tur_cod_personal from turnos) personas_turnos
			JOIN marcaciones_por_mes_horas5(CAST(EXTRACT(YEAR FROM CURRENT_DATE) AS INTEGER), 
											DATE_PART('month', CURRENT_TIMESTAMP)::integer, 
											personas_turnos.tur_cod_personal) res on true
   		
   		RETURNING 1
  	)
  	
  	SELECT COUNT(*) INTO v_insertados FROM ins;
	
	v_fin := clock_timestamp();
	v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio) + EXTRACT(SECOND FROM v_fin - v_inicio) * 1000 + EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;
	
	-- Registrar éxito
	INSERT INTO log_cron_historico_marcaciones(estado, mensaje, registros_insertados, duracion_ms, parametro1, parametro2)
 	VALUES ('EXITO', 
 			FORMAT('Proceso ejecutado correctamente para informe_mensual'),
          	v_insertados,
          	v_duracion_ms,
          	CAST(EXTRACT(YEAR FROM CURRENT_DATE) AS INTEGER), 
          	DATE_PART('month', CURRENT_TIMESTAMP)::integer);
	EXCEPTION
	WHEN OTHERS then
		v_fin := clock_timestamp();
		v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio) + EXTRACT(SECOND FROM v_fin - v_inicio) * 1000 + EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;
		
        INSERT INTO log_cron_historico_marcaciones(estado, mensaje, registros_insertados, duracion_ms) 
		VALUES ('ERROR', 
				FORMAT('Error al ejecutar para informe_mensual', SQLERRM),
            	v_insertados,
            	v_duracion_ms);
END;
$function$
;


/* Paso 3: modificar la consulta en el Formulario en el PHPRunner */
-- El query actual...
$strSQL = "SELECT * FROM marcaciones_por_mes_horas5($anho, $mes, $personales)";


-- Asi debe quedar al realizar la modificacion...
/*
$personales  -> Hace referencia al cod_personal.
$parametro1  -> Hace referencia al año pasado como parametro desde la pantalla del usuario.
$parametro2  -> Hace referencia al mes pasado como parametro desde la pantalla del usuario.
*/
SELECT * 
FROM historico_marcaciones 
WHERE nombre_reporte = 'informe_mensual'
AND reg_cod_personal = $personales 
AND parametro1 = '$parametro1'
AND parametro2 = '$parametro2';

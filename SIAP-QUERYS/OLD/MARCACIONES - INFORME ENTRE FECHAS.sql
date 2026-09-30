/*
 * MARCACIONES - INFORME ENTRE FECHAS
 * La funcion marcaciones_entre_fechas(persona_cod, fecha_desde, fecha_hasta) obtiene las marcaciones 
 * entre una fecha dada y un codigo de persona.
 *
 * Para poder ajustar a los nuevos cambios solicitados, se crea una nueva tabla 'historico_marcaciones' 
 * donde se agregan como columnas las mismas que devuelve la vista asi tambien parametros 
 * adicionales(nombre_reporte) para poder identificar para su posterior uso en la interfaz 
 * que visualiza el usuario.
 *
 * Para poder ajustar a los nuevos cambios solicitados, se crea una nueva tabla 'historico_marcaciones' 
 * donde se agregan como columnas las mismas que devuelve la funcion asi tambien parametros 
 * adicionales(nombre_reporte) para poder identificar para su posterior uso en la interfaz 
 * que visualiza el usuario.
 *
 * Paso 1:
 * Insertar manualmente todas las marcaciones entre fechas en la tabla historicos, para ello invocar a la 
 * funcion marcaciones_entre_fechas(persona_cod, fecha_desde, fecha_hasta) con parametros de filtro e 
 * insertar sus datos en la tabla historico_marcaciones. Este proceso se realiza una vez para 
 * poder poblar la tabla con todas las marcaciones del mes.
 * OBSERVACION: Para poder traer todos los datos que obtiene esta funcion, al realizar mi investigacion
 * verifique que existen datos desde: JUNIO desde esa fecha se debe empezar a insertar manualmente..
	SELECT res.* 
	FROM (select per_cod from personales where per_estado = 1) per
		join marcaciones_entre_fechas(per.per_cod, '2023-01-01', '2023-07-28') res on true;
 *
 * Paso 2:
 * Crear funcion en la base de datos que realiza el insert de las marcaciones mensuales en la 
 * tabla historicos, esta funcion debera ser invocada posteriormente desde una tarea programada, 
 * se debe definir en que hora del dia se ejecutara el cron_job.
 *
 * Paso 3:
 * Modificar consulta en el PHPRunner, en el AJAX donde se realiza la invocacion a la funcion con los
 * parametros que ingresa el usuario desde la pantalla del reporte modificar la consulta para hacer un
 * select de la tabla historico_marcaciones en vez de invocar a la funcion actual.
 *
 * Paso 4:
 * Crear la tarea programada que invoque la funcion para insertar las marcaciones.
 *
*/

select res.* 
from (select per_cod from personales where per_estado = 1) per 
	join marcaciones_entre_fechas(per.per_cod, '2023-07-01', '2023-07-28') res on true
where res.reg_cod_personal is not null;


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
									re_semanal_suma,
									re_mensual_suma,
									dia_semana,
									ocurrencia_descripcion,
									ocurrencia_tipo,
									feriado_descripcion,
									tolerancia_especial,
									fecha_registro)
SELECT 'informe_entre_fechas',
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
		re_semanal_suma,
		re_mensual_suma,
		dia_semana,
		ocurrencia_descripcion,
		ocurrencia_tipo,
		feriado_descripcion,
		tolerancia_especial,
		NOW()
FROM (select per_cod from personales where per_estado = 1) per 
	join marcaciones_entre_fechas(per.per_cod, '2023-07-01', '2023-07-28') res on true
where res.reg_cod_personal is not null;
...



CREATE OR REPLACE FUNCTION public.insertar_historico_marcaciones_entre_fechas()
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
	
    -- Evita duplicados si ya fue procesado en el dia
    DELETE FROM historico_marcaciones 
    WHERE nombre_reporte = 'informe_entre_fechas'
   	AND fecha_registro = NOW();
   
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
											re_semanal_suma,
											re_mensual_suma,
											dia_semana,
											ocurrencia_descripcion,
											ocurrencia_tipo,
											feriado_descripcion,
											tolerancia_especial,		
											fecha_registro)
    	SELECT 'informe_entre_fechas'
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
				re_semanal_suma,
				re_mensual_suma,
				dia_semana,
				ocurrencia_descripcion,
				ocurrencia_tipo,
				feriado_descripcion,
				tolerancia_especial,
				NOW()
		FROM (select per_cod from personales where per_estado = 1) per 
				join marcaciones_entre_fechas(per.per_cod, 
												SELECT DATE_TRUNC('month', CURRENT_DATE)::DATE, -- Obtiene el primer día del mes actual
												SELECT (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::DATE -- Obtiene el último día del mes actual
											) res on true
		WHERE res.reg_cod_personal is not null;
   		
   		RETURNING 1
  	)
  	
  	SELECT COUNT(*) INTO v_insertados FROM ins;
	
	v_fin := clock_timestamp();
	v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio) + EXTRACT(SECOND FROM v_fin - v_inicio) * 1000 + EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;
	
	-- Registrar éxito
	INSERT INTO log_cron_historico_marcaciones(estado, mensaje, registros_insertados, duracion_ms)
 	VALUES ('EXITO', 
 			FORMAT('Proceso ejecutado correctamente informe_entre_fechas'),
          	v_insertados,
          	v_duracion_ms);
	EXCEPTION
	-- Registrar error
	WHEN OTHERS then
		v_fin := clock_timestamp();
		v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio) + EXTRACT(SECOND FROM v_fin - v_inicio) * 1000 + EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;
		
		
        INSERT INTO log_cron_historico_marcaciones(estado, mensaje, registros_insertados, duracion_ms) 
		VALUES ('ERROR', 
				FORMAT('Error al ejecutar para informe_entre_fechas: %s', SQLERRM),
            	v_insertados,
            	v_duracion_ms);
END;
$function$
;
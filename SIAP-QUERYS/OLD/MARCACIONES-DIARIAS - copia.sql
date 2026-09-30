/*
 * MARCACIONES - INFORME DIARIO
 * La Vista 'vista_func_asistencia' obtiene todas las marcaciones del dia de los 
 * funcionarios, si se le agregan parametros de filtro[id_funcionario, fecha] se filtran
 * dichas marcaciones por esos parametros.
 *
 * Para poder ajustar a los nuevos cambios solicitados, cree una nueva tabla 'historico_marcaciones_diarias' 
 * donde se agregaran como columnas, las mismas que devuelve la vista invocada actualmente.
 *
 * Paso 1(viejo):
 * Insertar manualmente todas las marcaciones del dia en la tabla historicos, para ello invocar a la 
 * vista insertar_historico_marcaciones_diario() sin ningun parametro de filtro e insertar sus
 * datos en la tabla historico_marcaciones. Este proceso se realiza una vez para poder poblar la
 * tabla con todas las marcaciones.
 * OBSERVACION: Si se invoca a la vista 'vista_func_asistencia' obtiene todas las marcaciones sin 
 * ningun parametro se obtienen todos los registros, desde que se empezaron a insertar en esta
 * base de datos.
 *
 * Paso 1:
 * Crear una funcion en la base de datos que realiza el insert de las marcaciones diarias en la 
 * tabla historicos, esta funcion debera ser invocada posteriormente desde una tarea programada
 * cada dia, para poder insertar las marcaciones de la entrada y de la salida, se debe definir 
 * en que hora del dia se ejecutara el cron_job.
 * En resumen, esta nueva funcion invoca a la vista que obtiene las marcaciones diarias y que 
 * era utilizada desde la vista del usuario en la pantalla que muestra las marcaciones diarias.
 *
 * Paso 2:
 * Modificar consulta en el PHPRunner, en el AJAX donde se realiza la invocacion a la vista con los
 * parametros que ingresa el usuario desde la pantalla del reporte modificar la consulta para hacer un
 * select de la tabla historico_marcaciones en vez de invocar a la vista.
 *
 * Paso 4:
 * Crear la tarea programada que invoque la funcion para insertar las marcaciones.
 * 
 */


/* Paso 1: Insertar todas las marcaciones del dia en la tabla historicos. */
INSERT INTO historico_marcaciones(reg_cod_personal,
									dia_semana,
									reg_fecha,
									per_nombre,
									per_apellido,
									hora_entrada_programada,
									hora_salida_programada,
									entrada,
									salida,
									retraso,
									horas_trabajadas,
									horas_extras,
									fecha_registro)
SELECT reg_cod_personal,
		dia_semana,
		reg_fecha,
		nombre,
		apellido,
		hora_entrada_programada,
		hora_salida_programada,
		entrada,
		salida,
		retraso,
		horas_trabajadas,
		horas_extras,
		NOW()
FROM vista_func_asistencia
ORDER BY reg_fecha asc;


/* Paso 2: Crear la funcion que inserta las marcaciones. */
/*CREATE OR REPLACE FUNCTION public.insertar_historico_marcaciones_diarias()
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
   
   	WITH ins AS (
		INSERT INTO historico_marcaciones_diarias (reg_cod_personal,
													dia_semana,
													reg_fecha,
													nombre,
													apellido,
													hora_entrada_programada, 
													hora_salida_programada, 
													entrada, 
													salida,
													retraso, 
													horas_trabajadas, 
													horas_extras,
													fecha_registro)
    	SELECT reg_cod_personal,
				dia_semana,
				reg_fecha,
				nombre,
				apellido,
				hora_entrada_programada,
				hora_salida_programada,
				entrada,
				salida,
				retraso,
				horas_trabajadas,
				horas_extras,
				now()
    	FROM vista_func_asistencia
			ON CONFLICT (reg_cod_personal, dia_semana, reg_fecha) DO UPDATE
			SET	salida = EXCLUDED.salida,
				retraso = EXCLUDED.retraso,
				horas_trabajadas = EXCLUDED.horas_trabajadas,
				horas_extras = EXCLUDED.horas_extras,
				fecha_actualizacion = now()
			
   		RETURNING 1
  	)
  	
  	SELECT COUNT(*) INTO v_insertados FROM ins;
	
	v_fin := clock_timestamp();
	v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio) + EXTRACT(SECOND FROM v_fin - v_inicio) * 1000 + EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;
    
	-- Registrar éxito
	INSERT INTO log_cron_historico_marcaciones_diarias(estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion)
 	VALUES ('EXITO', 
 			FORMAT('Proceso ejecutado correctamente para INFORME-DIARIO'),
          	v_insertados,
          	v_duracion_ms,
			now()
			);
	EXCEPTION
		WHEN OTHERS then
			v_fin := clock_timestamp();
			v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio) + EXTRACT(SECOND FROM v_fin - v_inicio) * 1000 + EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;
		
        INSERT INTO log_cron_historico_marcaciones_diarias(estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion) 
		VALUES ('ERROR', 
				FORMAT('Error al ejecutar proceso para INFORME-DIARIO: %s', SQLERRM),
            	v_insertados,
            	v_duracion_ms,
				now());
END;
$function$
;*/
CREATE OR REPLACE FUNCTION public.insertar_historico_marcaciones_diarias()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
	v_inicio TIMESTAMP;
	v_fin TIMESTAMP;
	v_duracion_ms INTEGER;
	v_insertados INTEGER := 0;
	v_total_actual INTEGER;
BEGIN
	v_inicio := clock_timestamp();

	-- Verificamos si ya existen datos
	SELECT COUNT(*) INTO v_total_actual FROM historico_marcaciones_diarias;

	WITH fuente_datos AS (
		SELECT *
		FROM vista_func_asistencia
		WHERE v_total_actual = 0 -- Si no hay datos, traemos todo
			OR reg_fecha = CURRENT_DATE -- Si hay datos, solo los de hoy
	),
	ins AS (
		INSERT INTO historico_marcaciones_diarias (
			reg_cod_personal,
			dia_semana,
			reg_fecha,
			nombre,
			apellido,
			hora_entrada_programada, 
			hora_salida_programada, 
			entrada, 
			salida,
			retraso, 
			horas_trabajadas, 
			horas_extras,
			fecha_registro
		)
		SELECT 
			reg_cod_personal,
			dia_semana,
			reg_fecha,
			nombre,
			apellido,
			hora_entrada_programada,
			hora_salida_programada,
			entrada,
			salida,
			retraso,
			horas_trabajadas,
			horas_extras,
			now()
		FROM fuente_datos
		ON CONFLICT (reg_cod_personal, dia_semana, reg_fecha) DO UPDATE
		SET
			salida = EXCLUDED.salida,
			retraso = EXCLUDED.retraso,
			horas_trabajadas = EXCLUDED.horas_trabajadas,
			horas_extras = EXCLUDED.horas_extras,
			fecha_registro = now()
		RETURNING 1
	)
	SELECT COUNT(*) INTO v_insertados FROM ins;

	v_fin := clock_timestamp();
	v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio)
					+ EXTRACT(SECOND FROM v_fin - v_inicio) * 1000
					+ EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;

	INSERT INTO log_cron_historico_marcaciones_diarias (
		estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion
	) VALUES (
		'EXITO',
		'Proceso ejecutado correctamente para INFORME-DIARIO',
		v_insertados,
		v_duracion_ms,
		now()
	);

	EXCEPTION WHEN OTHERS THEN
		v_fin := clock_timestamp();
		v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio)
						+ EXTRACT(SECOND FROM v_fin - v_inicio) * 1000
						+ EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;

		INSERT INTO log_cron_historico_marcaciones_diarias (
			estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion
		) VALUES (
			'ERROR',
			FORMAT('Error al ejecutar proceso para INFORME-DIARIO: %s', SQLERRM),
			v_insertados,
			v_duracion_ms,
			now()
		);
END;
$function$;



/* Paso 3: modificar la consulta en el Formulario en el PHPRunner */
-- El query actual...
$strSQL = "
SELECT * 
FROM vista_func_asistencia 
WHERE reg_cod_personal = $personales 
AND reg_fecha = '$fecha' 
ORDER BY reg_fecha ASC
";

-- Asi debe quedar al realizar la modificacion...
SELECT * 
FROM historico_marcaciones_diario 
WHERE reg_cod_personal = $personales 
AND reg_fecha = '$fecha' 
ORDER BY reg_fecha ASC;

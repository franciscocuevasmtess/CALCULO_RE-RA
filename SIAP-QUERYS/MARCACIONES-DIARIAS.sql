/*
 * MARCACIONES - INFORME DIARIO
 * La Vista 'vista_func_asistencia' obtiene todas las marcaciones del dia de 
 * los funcionarios, Sí se le agregan parametros de filtro(id_funcionario, fecha), 
 * se filtran dichas marcaciones por esos parámetros.
 *
 * Para poder ajustar a los nuevos cambios solicitados, creé una nueva 
 * tabla: 'historico_marcaciones_diarias' donde se agregaran como columnas, las 
 * mismas que devuelve la vista invocada actualmente.
 *
 * Paso 1:
 * Crear la tabla que almacenará el historico de marcaciones diarias. 
 * Table: historico_marcaciones_diarias
 *
 * Paso 2:
 * Se crea un 'index' para que se puedan insertar los nuevos registros o actualizar los
 * existentes y evitar duplicaciones.
 * 
 * Paso 3:
 * Crear una función 'insertar_historico_marcaciones_diarias()' en la base de datos que 
 * realiza el insert de las marcaciones diarias en la tabla 'historico_marcaciones_diarias', 
 * esta función debera ser invocada posteriormente, desde una tarea programada cada día, para 
 * poder insertar las marcaciones de la entrada y de la salida.
 * Se debe definir, en que hora del día se ejecutará el esa tarea-programada.
 * En resúmen, esta nueva función, invóca a la vista que obtiene las 'marcaciones diarias' 
 * y que es utilizada actualmente desde la vista del usuario en la pantalla que muestra 
 * las marcaciones diarias.
 *
 * Paso 4:
 * Modificar consulta en el código del PHPRunner, en el AJAX, donde se realiza la invocación 
 * a la vista con los parámetros que ingresó el usuario desde la pantalla de reportes, modificar 
 * la consulta para hacer un select de la tabla: 'historico_marcaciones_diarias', en vez de invocar 
 * a la vista 'vista_func_asistencia', como esta actualmente..
 *
 * Paso 5:
 * Crear la tarea programada que invoque la función para insertar las marcaciones.
 * 
 */
 
---------------------------------------------------------------
-- TABLE: historico_marcaciones_diarias
/* 
 * Paso 1: 
 * Crear la tabla que almacenará el histórico de marcaciones diarias.
 */
---------------------------------------------------------------
CREATE TABLE public.historico_marcaciones_diarias (
id serial4 NOT NULL,
reg_cod_personal integer NULL,
dia_semana varchar(100) NULL,
reg_fecha date NULL,
nombre varchar(100) NULL,
apellido varchar(100) NULL,
hora_entrada_programada varchar(30) NULL, 
hora_salida_programada varchar(30) NULL, 
entrada varchar(30) NULL, 
salida varchar(30) NULL,
retraso varchar(30) NULL, 
horas_trabajadas varchar(30) NULL, 
horas_extras varchar(30) NULL,
fecha_registro timestamp DEFAULT now() NULL,
fecha_actualizacion timestamp NULL,
CONSTRAINT historico_marcaciones_diarias_pkey PRIMARY KEY (id)
);

---------------------------------------------------------------
-- INDEX: idx_unico_historico_marcaciones_diaria()
/* 
 * Paso 2: 
 * Crear el index para la tabla historico_marcaciones_diarias.
 */
---------------------------------------------------------------
-- CREACION DEL INDEX PARA MARCACIONES DIARIAS.
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_diaria 
ON historico_marcaciones_diarias (reg_cod_personal, dia_semana, reg_fecha);



---------------------------------------------------------------
-- FUNCTION: insertar_historico_marcaciones_diarias()
/* 
 * Paso 3: 
 * Crear la función que inserta todas las marcaciones del día 
 * en la tabla historico_marcaciones_diarias.
 */
---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insertar_historico_marcaciones_diarias()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
	v_inicio TIMESTAMP;
	v_fin TIMESTAMP;
	v_duracion_ms BIGINT;
	v_insertados INTEGER := 0;
	v_total_actual INTEGER;
	
	-- Variables para capturar detalles de la excepción.
    v_error_sqlstate TEXT;
    v_error_message TEXT;
    v_error_detail TEXT;
    v_error_hint TEXT;
	
   	-- Variables para el formato de duración.
	v_horas INTEGER;
	v_minutos INTEGER;
	v_segundos INTEGER;
	v_milisegundos_restantes INTEGER;
	v_duracion_formateada TEXT;
BEGIN
	v_inicio := clock_timestamp();

	-- Verificamos si ya existen datos en la tabla: 'historico_marcaciones_diarias'
	SELECT COUNT(*) INTO v_total_actual FROM historico_marcaciones_diarias;

	WITH fuente_datos AS (
		SELECT *
		FROM vista_func_asistencia
		WHERE v_total_actual = 0 -- Si no hay datos, traemos todo
			OR reg_fecha = CURRENT_DATE -- Si hay datos, solo los de hoy
	),
	ins AS (
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
		FROM fuente_datos
			ON CONFLICT (reg_cod_personal, dia_semana, reg_fecha) DO UPDATE
			SET	salida = EXCLUDED.salida,
				retraso = EXCLUDED.retraso,
				horas_trabajadas = EXCLUDED.horas_trabajadas,
				horas_extras = EXCLUDED.horas_extras,
				fecha_registro = now()
		
		RETURNING 1
	)
	SELECT COUNT(*) INTO v_insertados FROM ins;

	-- CÁLCULO Y FORMATO DE LA DURACIÓN ---
	v_fin := clock_timestamp();
	
	-- Calculamos la duracion total en milisegundos de manera robusta
	v_duracion_ms := EXTRACT(EPOCH FROM (v_fin - v_inicio)) * 1000;

	-- Convertimos los milisegundos a sus componentes.
	v_horas := (v_duracion_ms / (1000 * 60 * 60));
	v_minutos := ((v_duracion_ms % (1000 * 60 * 60)) / (1000 * 60));
	v_segundos := ((v_duracion_ms % (1000 * 60)) / 1000);
	v_milisegundos_restantes := (v_duracion_ms % 1000);

	v_duracion_formateada := FORMAT('%s hora%s, %s minuto%s, %s segundo%s, %s milisegundo%s', v_horas, CASE WHEN v_horas != 1 THEN 's' ELSE '' END, v_minutos, CASE WHEN v_minutos != 1 THEN 's' ELSE '' END, v_segundos, CASE WHEN v_segundos != 1 THEN 's' ELSE '' END, v_milisegundos_restantes, CASE WHEN v_milisegundos_restantes !=1 THEN 's' ELSE '' END);
	
	INSERT INTO log_cron_historico_marcaciones (estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion) 
	VALUES ('EXITO',
			FORMAT('Proceso ejecutado correctamente para INFORME-DIARIO. Duración: %s', v_duracion_formateada),
			v_insertados,
			v_duracion_ms,
			now());

	EXCEPTION WHEN OTHERS THEN
		v_fin := clock_timestamp();
		
		-- Calculamos la duración tambien en caso de error.
		v_duracion_ms := EXTRACT(EPOCH FROM (v_fin - v_inicio)) * 1000;
		
		v_horas := (v_duracion_ms / (1000 * 60 * 60));
		v_minutos := ((v_duracion_ms % (1000 * 60 * 60)) / (1000 * 60));
		v_segundos := ((v_duracion_ms % (1000 * 60)) / 1000);
		v_milisegundos_restantes := (v_duracion_ms % 1000);
	
		v_duracion_formateada := FORMAT('%s hora %s, %s minuto %s, %s segundo %s,%s milisegundo %s',v_horas, CASE WHEN v_horas != 1 THEN 's' ELSE '' END, v_minutos, CASE WHEN v_minutos != 1 THEN 's' ELSE '' END, v_segundos, CASE WHEN v_segundos != 1 THEN 's' ELSE '' END, v_milisegundos_restantes, CASE WHEN v_milisegundos_restantes != 1 THEN 's' ELSE '' END);
		
		-- ASIGNACIÓN DE DETALLES DE EXCEPCIÓN A VARIABLES LOCALES
		GET STACKED DIAGNOSTICS
			v_error_sqlstate = RETURNED_SQLSTATE,
			v_error_message = MESSAGE_TEXT,
			v_error_detail = PG_EXCEPTION_DETAIL,
			v_error_hint = PG_EXCEPTION_HINT;

		INSERT INTO log_cron_historico_marcaciones (estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion) 
		VALUES ('ERROR',
				FORMAT('Error al ejecutar proceso para INFORME-DIARIO. Duración: %s. SQLSTATE: %s, SQLERRM: %s. DETALLE: %s. SUGERENCIA: %s', v_duracion_formateada, v_error_sqlstate, v_error_message, v_error_detail, v_error_hint),
				v_insertados,
				v_duracion_ms,
				now());
END;
$function$;



---------------------------------------------------------------
--- Modificar código del formulario en el PHPRunner ---
/* 
 * Paso 4: 
 * Modificar la consulta en el Formulario en el PHPRunner.
 */
---------------------------------------------------------------

-- El query esta actualmente asi...
$strSQL = "
SELECT * 
FROM vista_func_asistencia 
WHERE reg_cod_personal = $personales 
AND reg_fecha = '$fecha' 
ORDER BY reg_fecha ASC
";

-- Asi debe quedar al realizar la modificacion...
$strSQL = "
SELECT * 
FROM historico_marcaciones_diarias 
WHERE reg_cod_personal = $personales 
AND reg_fecha = '$fecha' 
ORDER BY reg_fecha ASC
";



---------------------------------------------------------------
--- Tarea Programada ---
/* 
 * Paso 5: 
 * Crear la tarea programada que invoque la función para 
 * insertar las marcaciones.
 * Crear el cron job que invoque a esta función.
 */
---------------------------------------------------------------

-- Asegúrate de que pg_cron está habilitado
-- Los comandos en pg_cron usan la sintaxis estándar de cron: minuto hora día_mes mes día_semana
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Crear el cron job
-- Ejemplo para pruebas: cada minuto...
SELECT cron.schedule(
	'cron_marcaciones_diario_prueba', -- nombre del job
	'* * * * *',                      -- cada minuto
	$$SELECT insertar_historico_marcaciones_diarias();$$
);

-- Verificar los jobs existentes
SELECT * FROM cron.job;

-- Eliminar o modificar un cron job
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cron_marcaciones_diario_prueba';

-- Modificar: primero eliminas y luego lo creas de nuevo con nueva configuración.





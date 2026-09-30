/*
 * MARCACIONES - INFORME ENTRE FECHAS
 * La función 'marcaciones_entre_fechas($personales, '$fecha_inicio', '$fecha_fin')' obtiene las marcaciones 
 * entre una fecha dada y un código de persona.
 *
 * Para poder ajustar a los nuevos cambios solicitados, se crea una nueva 
 * tabla: 'historico_marcaciones_entre_fechas', donde se agregaran como columnas las mismas que 
 * devuelve la función invocada actualmente.
 *
 * Paso 1:
 * Crear la tabla que almacenará el historico de marcaciones entre fechas. 
 * Table: historico_marcaciones_entre_fechas
 *
 * Paso 2:
 * Se crea un 'index' para que se puedan insertar los nuevos registros o actualizar los
 * existentes y evitar duplicaciones.
 *
 * Paso 3:
 * Crear una función 'insertar_historico_marcaciones_entre_fechas()' en la base de datos que 
 * realiza el insert de las marcaciones entre fechas en la tabla 'historico_marcaciones_entre_fechas', 
 * esta función debera ser invocada posteriormente desde una tarea programada cada día, para 
 * poder actualizar con las marcaciones de la entrada y de la salida. 
 * Se debe definir, en que hora del día se ejecutará el esa tarea-programada.
 * En resúmen, esta nueva función creada, invocará a la función que obtiene las 'marcaciones entre fechas' 
 * y que es utilizada actualmente desde la vista del usuario en la pantalla que muestra 
 * las marcaciones entre fechas.
 *
 * Paso 4:
 * Modificar consulta en el código del PHPRunner, en el AJAX, donde se realiza la invocación 
 * a la función con los parámetros que ingresó el usuario desde la pantalla del reporte, modificar 
 * la consulta para hacer un select de la tabla: 'historico_marcaciones_entre_fechas' en vez de invocar 
 * a la función marcaciones_entre_fechas($personales, '$fecha_inicio', '$fecha_fin'), como esta actualmente.. 
 *
 * Paso 5:
 * Crear la tarea programada que invoque la función para insertar las marcaciones.
 *
*/

---------------------------------------------------------------
-- TABLE: historico_marcaciones_entre_fechas
/* 
 * Paso 1: 
 * Crear la tabla que almacenará el historico de marcaciones entre fechas.
 */
---------------------------------------------------------------
CREATE TABLE public.historico_marcaciones_entre_fechas (
id serial4 NOT NULL,
per_cod integer NULL,
reg_fecha date NULL,
reg_cod_personal integer NULL,
tur_entrada varchar(255) NULL,
tur_salida varchar(255) NULL,
par_valor_time varchar(255) NULL,
reg_hora_entrada varchar(255) NULL,
reg_hora_salida varchar(255) NULL,
reg_horas_trabajadas varchar(255) NULL,
reg_retraso varchar(255) NULL,
reg_horas_extras varchar(255) NULL,
re varchar(255) NULL,
re_semanal_suma varchar(255) NULL,
re_mensual_suma varchar(255) NULL,
dia_semana varchar(255) NULL,
ocurrencia_descripcion varchar(255) NULL,
ocurrencia_tipo	varchar(255) NULL,
feriado_descripcion varchar(255) NULL,
tolerancia_especial varchar(255) NULL,
fecha_registro timestamp DEFAULT now() NULL, 
fecha_actualizacion timestamp NULL,
CONSTRAINT historico_marcaciones_entre_fechas_pkey PRIMARY KEY (id)
);

---------------------------------------------------------------
-- INDEX: idx_unico_historico_marcaciones_entre_fechas()
/* 
 * Paso 2: 
 * Crear el index para la tabla historico_marcaciones_entre_fechas.
 */
---------------------------------------------------------------
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_entre_fechas 
ON historico_marcaciones_entre_fechas (per_cod, reg_fecha);


---------------------------------------------------------------
--- FUNCTION: insertar_historico_marcaciones_entre_fechas() ---
/* 
 * Paso 3: 
 * Crear la función que inserta todas las marcaciones entre fechas 
 * en la tabla historico_marcaciones_entre_fechas.
 */
---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insertar_historico_marcaciones_entre_fechas()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
	v_inicio TIMESTAMP;
	v_fin TIMESTAMP;
	v_duracion_ms INTEGER;
	v_insertados INTEGER := 0;
	v_total_actual INTEGER;
	
    -- Fechas para la carga histórica (ajustar según necesidad)
    v_fecha_desde_historica DATE := '2022-01-01'; -- Ejemplo: desde el inicio de 2022
    v_fecha_hasta_historica DATE := CURRENT_DATE;

    -- Variables para capturar detalles de la excepción
    v_error_sqlstate TEXT;
    v_error_message TEXT;
    v_error_detail TEXT;
    v_error_hint TEXT;
	
	-- Variables para el formato de duración
	v_horas INTEGER;
	v_minutos INTEGER;
	v_segundos INTEGER;
	v_milisegundos_restantes INTEGER;
	v_duracion_formateada TEXT;

BEGIN
	v_inicio := clock_timestamp();

	-- Verificamos si ya existen datos en la tabla historico_marcaciones_entre_fechas
	SELECT COUNT(*) INTO v_total_actual FROM historico_marcaciones_entre_fechas;

	-- LÓGICA DE INSERCIÓN CONDICIONAL ---
	
	IF v_total_actual = 0 THEN
		-- --- CASO 1: TABLA VACÍA (CARGA INICIAL COMPLETA) ---
		-- Insertar todos los datos históricos para todos los personales activos
		INSERT INTO historico_marcaciones_entre_fechas (per_cod,
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
														fecha_registro
													)
		SELECT	DISTINCT ON (p.per_cod, res_func.reg_fecha)
				p.per_cod,
				res_func.reg_fecha, 
				res_func.reg_cod_personal, 
				res_func.tur_entrada,
				res_func.tur_salida,
				res_func.par_valor_time,
				res_func.reg_hora_entrada,
				res_func.reg_hora_salida,
				res_func.reg_horas_trabajadas,
				res_func.reg_retraso,
				res_func.reg_horas_extras,
				res_func.re,
				res_func.re_semanal_suma,
				res_func.re_mensual_suma,
				res_func.dia_semana,
				res_func.ocurrencia_descripcion, 
				res_func.ocurrencia_tipo, 
				res_func.feriado_descripcion, 
				res_func.tolerancia_especial, 
				now()
		FROM (SELECT per_cod FROM personales WHERE per_estado = 1) AS p -- Personal activo
			JOIN LATERAL marcaciones_entre_fechas(p.per_cod, v_fecha_desde_historica, v_fecha_hasta_historica) AS res_func ON TRUE
		--WHERE res_func.reg_cod_personal IS NOT NULL -- Asegura que haya un código de personal válido
		ON CONFLICT (reg_fecha, reg_cod_personal) DO UPDATE
			SET	tur_entrada = EXCLUDED.tur_entrada,
				tur_salida = EXCLUDED.tur_salida,
				par_valor_time = EXCLUDED.par_valor_time,
				reg_hora_entrada = EXCLUDED.reg_hora_entrada,
				reg_hora_salida = EXCLUDED.reg_hora_salida,
				reg_horas_trabajadas = EXCLUDED.reg_horas_trabajadas,
				reg_retraso = EXCLUDED.reg_retraso,
				reg_horas_extras = EXCLUDED.reg_horas_extras,
				re = EXCLUDED.re,
				re_semanal_suma = EXCLUDED.re_semanal_suma,
				re_mensual_suma = EXCLUDED.re_mensual_suma,
				dia_semana = EXCLUDED.dia_semana,
				ocurrencia_descripcion = EXCLUDED.ocurrencia_descripcion,
				ocurrencia_tipo = EXCLUDED.ocurrencia_tipo,
				feriado_descripcion = EXCLUDED.feriado_descripcion,
				tolerancia_especial = EXCLUDED.tolerancia_especial,
				fecha_actualizacion = now();
				
		GET DIAGNOSTICS v_insertados = ROW_COUNT; -- Cuenta las filas insertadas/actualizadas

	ELSE
		-- CASO 2: TABLA CON DATOS (ACTUALIZACIÓN DIARIA) ---
		-- Solo insertar/actualizar los datos del día actual
		INSERT INTO historico_marcaciones_entre_fechas (per_cod,
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
		SELECT DISTINCT ON (p.per_cod, res_func.reg_fecha)
				p.per_cod,
				res_func.reg_fecha, 
				res_func.reg_cod_personal, 
				res_func.tur_entrada,
				res_func.tur_salida,
				res_func.par_valor_time,
				res_func.reg_hora_entrada,
				res_func.reg_hora_salida,
				res_func.reg_horas_trabajadas,
				res_func.reg_retraso,
				res_func.reg_horas_extras,
				res_func.re,
				res_func.re_semanal_suma,
				res_func.re_mensual_suma,
				res_func.dia_semana,
				res_func.ocurrencia_descripcion, 
				res_func.ocurrencia_tipo, 
				res_func.feriado_descripcion, 
				res_func.tolerancia_especial, 
				now()
		FROM(SELECT per_cod FROM personales WHERE per_estado = 1) AS p -- Personal activo
			JOIN LATERAL marcaciones_entre_fechas(p.per_cod, CURRENT_DATE, CURRENT_DATE) AS res_func ON TRUE
		WHERE res_func.reg_fecha = CURRENT_DATE -- Filtramos solo el día actual de los resultados de la función
		--AND res_func.reg_cod_personal IS NOT NULL -- Asegura que haya un código de personal válido
		ON CONFLICT (reg_fecha, reg_cod_personal) DO UPDATE
			SET	tur_entrada = EXCLUDED.tur_entrada,
				tur_salida = EXCLUDED.tur_salida,
				par_valor_time = EXCLUDED.par_valor_time,
				reg_hora_entrada = EXCLUDED.reg_hora_entrada,
				reg_hora_salida = EXCLUDED.reg_hora_salida,
				reg_horas_trabajadas = EXCLUDED.reg_horas_trabajadas,
				reg_retraso = EXCLUDED.reg_retraso,
				reg_horas_extras = EXCLUDED.reg_horas_extras,
				re = EXCLUDED.re,
				re_semanal_suma = EXCLUDED.re_semanal_suma,
				re_mensual_suma = EXCLUDED.re_mensual_suma,
				dia_semana = EXCLUDED.dia_semana,
				ocurrencia_descripcion = EXCLUDED.ocurrencia_descripcion,
				ocurrencia_tipo = EXCLUDED.ocurrencia_tipo,
				feriado_descripcion = EXCLUDED.feriado_descripcion,
				tolerancia_especial = EXCLUDED.tolerancia_especial,
				fecha_actualizacion = now();

		GET DIAGNOSTICS v_insertados = ROW_COUNT; -- Cuenta las filas insertadas/actualizadas

	END IF;

	--- REGISTRO DE LOG ---
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
			FORMAT('Proceso ejecutado correctamente para INFORME-MARCACIONES-ENTRE-FECHAS. Duración: %s', v_duracion_formateada),
			v_insertados,
			v_duracion_ms,
			now());

	EXCEPTION WHEN OTHERS THEN
		v_fin := clock_timestamp();
		
		-- Calculamos la duracion tambien en caso de error.
		v_duracion_ms := EXTRACT(EPOCH FROM (v_fin - v_inicio)) * 1000;
		
		v_horas := (v_duracion_ms / (1000 * 60 * 60));
		v_minutos := ((v_duracion_ms % (1000 * 60 * 60)) / (1000 * 60));
		v_segundos := ((v_duracion_ms % (1000 * 60)) / 1000);
		v_milisegundos_restantes := (v_duracion_ms % 1000);
		
		v_duracion_formateada := FORMAT('%s hora%s, %s minuto%s, %s segundo%s,%s milisegundo%s',v_horas, CASE WHEN v_horas != 1 THEN 's' ELSE '' END, v_minutos, CASE WHEN v_minutos != 1 THEN 's' ELSE '' END, v_segundos, CASE WHEN v_segundos != 1 THEN 's' ELSE '' END, v_milisegundos_restantes, CASE WHEN v_milisegundos_restantes != 1 THEN 's' ELSE '' END);
        
		-- ASIGNACIÓN DE DETALLES DE EXCEPCIÓN A VARIABLES LOCALES
        GET STACKED DIAGNOSTICS
            v_error_sqlstate = RETURNED_SQLSTATE,
            v_error_message = MESSAGE_TEXT,
            v_error_detail = PG_EXCEPTION_DETAIL,
            v_error_hint = PG_EXCEPTION_HINT;

		INSERT INTO log_cron_historico_marcaciones (estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion) 
		VALUES ('ERROR',
				FORMAT('Error al ejecutar proceso para INFORME-MARCACIONES-ENTRE-FECHAS. Duración: %s. SQLSTATE: %s, SQLERRM: %s. DETALLE: %s. SUGERENCIA: %s', v_duracion_formateada, v_error_sqlstate, v_error_message, v_error_detail, v_error_hint),
				v_insertados,
				v_duracion_ms,
				now());
END;
$function$;


---------------------------------------------------------------
--- Modificar código del formulario en el PHPRunner ---
/* 
 * Paso 2: 
 * Modificar la consulta en el Formulario en el PHPRunner.
 */
---------------------------------------------------------------

-- El query esta actualmente asi...
$strSQL = "
SELECT * 
FROM marcaciones_entre_fechas($personales,'$fecha_inicio','$fecha_fin' )";

-- Asi debe quedar al realizar la modificación...
$strSQL = "
SELECT * 
FROM historico_marcaciones_entre_fechas
WHERE per_cod = $personales
AND reg_fecha BETWEEN '$fecha_inicio' AND '$fecha_fin'";




---------------------------------------------------------------
--- Tarea Programada ---
/* 
 * Paso 5: 
 * Crear la tarea programada que invoque la funcion para 
 * insertar las marcaciones.
 * Crear el cron job que invoque a esta funcion.
 */
---------------------------------------------------------------

-- Asegúrate de que pg_cron está habilitado
-- Los comandos en pg_cron usan la sintaxis estándar de cron: minuto hora día_mes mes día_semana
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Crear el cron job
-- Ejemplo para pruebas: cada minuto
SELECT cron.schedule(
	'cron_marcaciones_entre_fechas_prueba', -- nombre del job
	'* * * * *',                      -- cada minuto
	$$SELECT insertar_historico_marcaciones_entre_fechas();$$
);

-- Verificar los jobs existentes
SELECT * FROM cron.job;

-- Eliminar o modificar un cron job
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cron_marcaciones_entre_fechas_prueba';

-- Modificar: primero eliminas y luego lo creas de nuevo con nueva configuración.

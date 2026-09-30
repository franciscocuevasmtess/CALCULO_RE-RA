/*
 * MARCACIONES - MARCACIONES RESUMEN GENERAL
 * La función 'horas_extras_mensuales($anho, $mes)' obtiene todo el resumen general de las 
 * marcaciones de los funcionarios.
 *
 * Para poder ajustar a los nuevos cambios solicitados, se crea una nueva 
 * tabla: 'historico_marcaciones_resumen_general', donde se agregaran como columnas, las mismas que 
 * devuelve la función invocada actualmente.
 *
 * Paso 1:
 * Crear la tabla que almacenara el historico de marcaciones resumen general. 
 * Table: historico_marcaciones_resumen_general
 *
 * Paso 2:
 * Se crea un 'index' para que se puedan insertar los nuevos registros o actualizar los
 * existentes y evitar duplicaciones.
 *
 * Paso 3:
 * Crear una función 'insertar_historico_marcaciones_resumen_general()' en la base de datos que 
 * realiza el insert del resumen de marcaciones-resumen-mensual en la tabla 'historico_marcaciones_resumen_general', 
 * esta función debera ser invocada posteriormente desde una tarea programada cada día, para 
 * poder actualizar con las marcaciones de la entrada y de la salida. 
 * Se debe definir, en que hora del día se ejecutará el esa tarea-programada.
 * En resúmen, esta nueva función creada, invocará a la funció que obtiene el 'resumen de marcaciones' 
 * y que es utilizada actualmente desde la vista del usuario en la pantalla que muestra 
 * las marcaciones resumen general.
 *
 * Paso 4:
 * Modificar consulta en el código del PHPRunner, en el AJAX donde se realiza la invocación 
 * a la función con los parámetros que ingreso el usuario desde la pantalla del reporte, modificar 
 * la consulta para hacer un select de la tabla: 'historico_marcaciones_resumen_general' en vez de invocar 
 * a la función horas_extras_mensuales($anho, $mes), como esta actualmente.
 *
 * Paso 5:
 * Crear la tarea programada que invoque la función para insertar las marcaciones..
 * 
 */
 
---------------------------------------------------------------
-- TABLE: historico_marcaciones_resumen_general
/* 
 * Paso 1: 
 * Crear la tabla que almacenará el historico de marcacione resumen general.
 */
---------------------------------------------------------------
CREATE TABLE public.historico_marcaciones_resumen_general (
id serial4 NOT NULL,
anho INTEGER NULL,
mes INTEGER NULL,
reg_cod_personal integer NULL,
per_nombre varchar(255) NULL,
per_apellido varchar(255) NULL,
per_ci varchar(255) NULL,
re_mensual_suma varchar(255) NULL,
ra_80_mensual varchar(255) NULL,
ra_100_mensual varchar(255) NULL,
anho INTEGER NOT NULL,
mes INTEGER NOT NULL,
fecha_registro timestamp DEFAULT now() NULL, 
fecha_actualizacion timestamp NULL,
CONSTRAINT historico_marcaciones_resumen_general_pkey PRIMARY KEY (id)
);


---------------------------------------------------------------
-- INDEX: idx_unico_historico_marcaciones_resumen_general()
/* 
 * Paso 2: 
 * Crear el index para la tabla historico_marcaciones_resumen_general.
 */
---------------------------------------------------------------
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_resumen_general 
ON historico_marcaciones_resumen_general (anho, mes, reg_cod_personal);




--------------------------------------------------------------------
--- FUNCTION: insertar_historico_marcaciones_resumen_general() ---
/* 
 * Paso 3: 
 * Crear la funcion que inserta todo los resumen de marcaciones 
 * en la tabla historico_marcaciones_resumen_general.
 */
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insertar_historico_marcaciones_resumen_general()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
	v_inicio TIMESTAMP;
	v_fin TIMESTAMP;
	v_duracion_ms INTEGER;
	v_insertados INTEGER := 0;
	v_total_actual INTEGER;
	v_current_anho INTEGER;
	v_current_mes INTEGER;
	
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

	-- Verificamos si ya existen datos en la tabla historico_marcaciones_resumen_general
	SELECT COUNT(*) INTO v_total_actual FROM historico_marcaciones_resumen_general;

	-- Obtenemos el año y el mes actuales solo una vez
	v_current_anho := EXTRACT(YEAR FROM CURRENT_DATE);
	v_current_mes := EXTRACT(MONTH FROM CURRENT_DATE);
	
	-- LÓGICA DE INSERCIÓN CONDICIONAL
	
	IF v_total_actual = 0 THEN
		-- --- CASO 1: TABLA VACÍA (CARGA INICIAL COMPLETA) ---
		-- Insertar todos los datos históricos (todos los años, todos los meses)
		INSERT INTO historico_marcaciones_resumen_general (anho,
															mes,
															reg_cod_personal,
															per_nombre,
															per_apellido,
															per_ci,
															re_mensual_suma,
															ra_80_mensual,
															ra_100_mensual,
															fecha_registro)
		SELECT a.anho,
				m.mes,
				hxm.reg_cod_personal,
				hxm.per_nombre,
				hxm.per_apellido,
				hxm.per_ci,
				hxm.re_mensual_suma,
				hxm.ra_80_mensual,
				hxm.ra_100_mensual,
				now()
		FROM
			-- Generamos todas las combinaciones de años y meses que necesitamos para la carga inicial
			(SELECT numero AS anho FROM anhos) AS a
			CROSS JOIN (SELECT mes_cod as mes FROM meses) AS m
			-- Llamamos a la función horas_extras_mensuales para cada combinación de año y mes
			LEFT JOIN LATERAL public.horas_extras_mensuales(a.anho, m.mes) AS hxm ON TRUE
		--WHERE hxm.reg_cod_personal IS NOT NULL -- Asegura que haya un código de personal válido devuelto por la función
		ON CONFLICT (anho, mes, reg_cod_personal) DO UPDATE
		SET re_mensual_suma = EXCLUDED.re_mensual_suma,
			ra_80_mensual = EXCLUDED.ra_80_mensual,
			ra_100_mensual = EXCLUDED.ra_100_mensual,
			fecha_actualizacion = now();

		GET DIAGNOSTICS v_insertados = ROW_COUNT; -- Cuenta las filas insertadas/actualizadas

	ELSE
		-- CASO 2: TABLA CON DATOS (ACTUALIZACIÓN MENSUAL) ---
		-- Solo insertar/actualizar los datos del mes y año actuales
		INSERT INTO historico_marcaciones_resumen_general (reg_cod_personal,
															anho,
															mes,
															per_nombre,
															per_apellido,
															per_ci,
															re_mensual_suma,
															ra_80_mensual,
															ra_100_mensual,
															fecha_registro)
		SELECT hxm.reg_cod_personal,
				v_current_anho AS anho, -- Usamos el año actual
				v_current_mes AS mes,   -- Usamos el mes actual
				hxm.per_nombre,
				hxm.per_apellido,
				hxm.per_ci,
				hxm.re_mensual_suma,
				hxm.ra_80_mensual,
				hxm.ra_100_mensual,
				now()
		FROM
			-- Creación de un "contexto" para llamar a la función con el año y mes actuales
			(SELECT 1) AS dummy_table -- Una tabla dummy para poder usar LEFT JOIN LATERAL
			LEFT JOIN LATERAL public.horas_extras_mensuales(v_current_anho, v_current_mes) AS hxm ON TRUE
		--WHERE hxm.reg_cod_personal IS NOT NULL -- Asegura que haya un código de personal válido devuelto por la función
		ON CONFLICT (reg_cod_personal, anho, mes) DO UPDATE
		SET re_mensual_suma = EXCLUDED.re_mensual_suma,
			ra_80_mensual = EXCLUDED.ra_80_mensual,
			ra_100_mensual = EXCLUDED.ra_100_mensual,
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
			FORMAT('Proceso ejecutado correctamente para INFORME-MARCACIONES-RESUMEN-GENERAL. Duración: %s', v_duracion_formateada),
			v_insertados,
			v_duracion_ms,
			now());

	EXCEPTION WHEN OTHERS THEN
		v_fin := clock_timestamp();
		
		-- Calculamos la duración también en caso de error.
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
				FORMAT('Error al ejecutar proceso para INFORME-MARCACIONES-RESUMEN-GENERAL. Duración: %s. SQLSTATE: %s, SQLERRM: %s. DETALLE: %s. SUGERENCIA: %s', v_duracion_formateada, v_error_sqlstate, v_error_message, v_error_detail, v_error_hint),
				v_insertados,
				v_duracion_ms,
				now());
	
END;
$function$;


---------------------------------------------------------------
--- Modificar codigo del formulario en el PHPRunner ---
/* 
 * Paso 4: 
 * Modificar la consulta en el Formulario en el PHPRunner.
 */
---------------------------------------------------------------

-- El query esta actualmente asi...
$strSQL = "
SELECT * 
FROM horas_extras_mensuales($anho, $mes)
ORDER BY re_mensual_suma, ra_80_mensual, ra_100_mensual asc";


-- Asi debe quedar al realizar la modificacion...
$strSQL = "
SELECT * 
FROM historico_marcaciones_resumen_general
WHERE anho = $anho 
AND mes = $mes
ORDER BY re_mensual_suma, ra_80_mensual, ra_100_mensual asc
";



---------------------------------------------------------------
--- Tarea Programada ---
/* 
 * Paso 5: 
 * Crear la tarea programada que invoque la funcion para 
 * insertar el resumen de marcaciones.
 * Crear el cron job que invoque a esta funcion.
 */
---------------------------------------------------------------

-- Asegúrate de que pg_cron está habilitado
-- Los comandos en pg_cron usan la sintaxis estándar de cron: minuto hora día_mes mes día_semana
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Crear el cron job
-- Ejemplo para pruebas: cada minuto
SELECT cron.schedule(
	'cron_diario_marcaciones_resumen_general_prueba', -- nombre del job
	'* * * * *',                      -- cada minuto
	$$SELECT insertar_historico_marcaciones_resumen_general();$$
);

-- Verificar los jobs existentes
SELECT * FROM cron.job;

-- Eliminar o modificar un cron job
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cron_diario_marcaciones_resumen_general_prueba';

-- Modificar: primero eliminas y luego lo creas de nuevo con nueva configuración.




























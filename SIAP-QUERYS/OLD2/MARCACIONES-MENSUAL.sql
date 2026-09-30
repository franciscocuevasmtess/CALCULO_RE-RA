/*
 * MARCACIONES - INFORME MENSUAL
 * La función 'marcaciones_por_mes_horas5(anho, mes, cod_personal)' obtiene las marcaciones mensuales 
 * de los funcionarios, recibe tres parámetros: año, mes, código_funcionario.
 *
 * Para poder ajustar a los nuevos cambios solicitados, se crea una nueva 
 * tabla: 'historico_marcaciones_mensual', donde se agregan como columnas las mismas que 
 * devuelve la función.
 *
 * Paso 1:
 * Crear la tabla que almacenará el histórico de marcaciones mensual. 
 * Table: historico_marcaciones_mensual
 *
 * Paso 2:
 * Se crea un 'index' para que se puedan insertar los nuevos registros o actualizar los
 * existentes y evitar duplicaciones.
 *
 * Paso 3:
 * Crear una función 'insertar_historico_marcaciones_mensual()' en la base de datos que 
 * realiza el insert de las marcaciones mensuales en la tabla 'historico_marcaciones_mensual', 
 * esta función deberá ser invocada posteriormente desde una tarea programada cada día, para 
 * poder actualizar con las marcaciones de la entrada y de la salida.
 * Se debe definir, en que hora del día se ejecutará el esa tarea-programada.
 * En resúmen, esta nueva función creada, invocará a la función que obtiene las 'marcaciones mensuales' 
 * y que es utilizada actualmente desde la vista del usuario en la pantalla que muestra 
 * las marcaciones mensuales.
 *
 * Paso 4:
 * Modificar consulta en el código del PHPRunner, en el AJAX, donde se realiza la invocación 
 * a la función con los parámetros que ingresó el usuario desde la pantalla de reportes, modificar 
 * la consulta para hacer un select de la tabla: 'historico_marcaciones_mensual' en vez de invocar 
 * a la función marcaciones_por_mes_horas5($anho, $mes, $personales), como esta actualmente..
 *
 * Paso 5:
 * Crear la tarea programada que invoque la función para insertar las marcaciones.
 * 
*/

---------------------------------------------------------------
-- TABLE: historico_marcaciones_mensual
/* 
 * Paso 1: 
 * Crear la tabla que almacenará el historico de marcaciones mensuales.
 */
---------------------------------------------------------------
CREATE TABLE public.historico_marcaciones_mensual (
id serial4 NOT NULL,
per_cod integer NULL,
anho INTEGER NULL,
mes_cod INTEGER NULL,
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
horas_a_compensar varchar(255) NULL,
horas_compensadas varchar(255) NULL,
horas_restantes varchar(255) NULL,
estado_compensacion varchar(255) NULL,
re_semanal_suma varchar(255) NULL,
re_mensual_suma varchar(255) NULL,
re_acumulada_semanal varchar(255) NULL,
re_acumulada_mensual varchar(255) NULL,
ra varchar(255) NULL,
ra_semanal_suma varchar(255) NULL,
ra_mensual_suma varchar(255) NULL,
ra_80 varchar(255) NULL,
ra_100 varchar(255) NULL,
ra_80_semanal varchar(255) NULL,
ra_100_semanal varchar(255) NULL,
ra_80_mensual varchar(255) NULL,
ra_100_mensual varchar(255) NULL,
dia_semana varchar(255) NULL,
ocurrencia_descripcion varchar(255) NULL,
ocurrencia_tipo	varchar(255) NULL,
ocu_tipo varchar(255) NULL,
tip_codigo varchar(255) NULL,
feriado_descripcion varchar(255) NULL,
tolerancia_especial varchar(255) NULL,
fecha_registro timestamp DEFAULT now() NULL, 
fecha_actualizacion timestamp NULL,
CONSTRAINT historico_marcaciones_mensual_pkey PRIMARY KEY (id)
);

---------------------------------------------------------------
-- INDEX: idx_unico_historico_marcaciones_mensual()
/* 
 * Paso 2: 
 * Crear el index para la tabla historico_marcaciones_mensual.
 */
---------------------------------------------------------------
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_mensual 
ON historico_marcaciones_mensual (reg_fecha,reg_cod_personal);

-- CREACION DEL INDEX PARA MARCACIONES MENSUAL.
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_mensual 
--ON historico_marcaciones_mensual (reg_fecha,reg_cod_personal);
ON historico_marcaciones_mensual (per_cod, mes_cod, anho, reg_fecha);



---------------------------------------------------------------
-- FUNCTION: insertar_historico_marcaciones_mensual()
/* 
 * Paso 3: 
 * Crear la función que inserta todas las marcaciones del mes 
 * en la tabla historico_marcaciones_mensual.
 */
---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insertar_historico_marcaciones_mensual()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
	v_inicio TIMESTAMP;
	v_fin TIMESTAMP;
	v_duracion_ms BIGINT;
	v_insertados INTEGER := 0;
	v_total_actual INTEGER;
	v_current_anho INTEGER; -- Variable para el año actual
	v_current_mes INTEGER;  -- Variable para el mes actual
	
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

	-- Verificamos si ya existen datos en la tabla: 'historico_marcaciones_mensual'
	SELECT COUNT(*) INTO v_total_actual FROM historico_marcaciones_mensual;

	-- Obtenemos el año y el mes actuales solo una vez
	v_current_anho := EXTRACT(YEAR FROM CURRENT_DATE);
	v_current_mes := EXTRACT(MONTH FROM CURRENT_DATE);
	
	-- LÓGICA DE INSERCIÓN CONDICIONAL
	
	IF v_total_actual = 0 THEN
		-- CASO 1: TABLA VACÍA (CARGA INICIAL COMPLETA).
		-- Insertar todos los datos históricos (todos los años, meses, personales)
		INSERT INTO historico_marcaciones_mensual (reg_fecha, 
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
													reg_anho,
													reg_mes,
													fecha_registro
												)
		SELECT DISTINCT ON (res_func.reg_fecha, res_func.reg_cod_personal)
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
				res_func.horas_a_compensar, 
				res_func.horas_compensadas, 
				res_func.horas_restantes,
				res_func.estado_compensacion, 
				res_func.re_semanal_suma, 
				res_func.re_mensual_suma, 
				res_func.re_acumulada_semanal,
				res_func.re_acumulada_mensual, 
				res_func.ra, 
				res_func.ra_semanal_suma, 
				res_func.ra_mensual_suma, 
				res_func.ra_80, 
				res_func.ra_100,
				res_func.ra_80_semanal, 
				res_func.ra_100_semanal, 
				res_func.ra_80_mensual, 
				res_func.ra_100_mensual, 
				res_func.dia_semana,
				res_func.ocurrencia_descripcion, 
				res_func.ocurrencia_tipo, 
				res_func.ocu_tipo, 
				res_func.tip_codigo,
				res_func.feriado_descripcion, 
				res_func.tolerancia_especial, 
				EXTRACT(YEAR FROM res_func.reg_fecha)::INTEGER,
				EXTRACT(MONTH FROM res_func.reg_fecha)::INTEGER,
				now()
		FROM (SELECT per_cod FROM personales WHERE per_estado = 1) AS p -- Personal activo
				CROSS JOIN (SELECT mes_cod FROM meses) AS m -- Todos los meses (del 1 al 12)
				CROSS JOIN (SELECT numero AS anho FROM anhos) AS a -- Todos los años cargados (ej. 2022 a 2025)
				JOIN LATERAL marcaciones_por_mes_horas5(a.anho, m.mes_cod, p.per_cod) AS res_func ON TRUE
		WHERE res_func.reg_cod_personal IS NOT null -- Asegura que haya un código de personal válido
			ON CONFLICT (reg_fecha,reg_cod_personal) DO UPDATE
			SET reg_hora_salida = EXCLUDED.reg_hora_salida,
				reg_horas_trabajadas = EXCLUDED.reg_horas_trabajadas,
				reg_retraso = EXCLUDED.reg_retraso,
				reg_horas_extras = EXCLUDED.reg_horas_extras,
				re = EXCLUDED.re,
				horas_a_compensar = EXCLUDED.horas_a_compensar,	
				horas_compensadas = EXCLUDED.horas_compensadas,	
				horas_restantes	= EXCLUDED.horas_restantes,
				estado_compensacion = EXCLUDED.estado_compensacion,	
				re_semanal_suma = EXCLUDED.re_semanal_suma,
				re_mensual_suma = EXCLUDED.re_mensual_suma,	
				re_acumulada_semanal = EXCLUDED.re_acumulada_semanal,	
				re_acumulada_mensual = EXCLUDED.re_acumulada_mensual,
				ra = EXCLUDED.ra,
				ra_semanal_suma = EXCLUDED.ra_semanal_suma,	
				ra_mensual_suma	= EXCLUDED.ra_mensual_suma,
				ra_80 = EXCLUDED.ra_80,	
				ra_100 = EXCLUDED.ra_100,	
				ra_80_semanal = EXCLUDED.ra_80_semanal,	
				ra_100_semanal = EXCLUDED.ra_100_semanal,
				ra_80_mensual = EXCLUDED.ra_80_mensual,	
				ra_100_mensual = EXCLUDED.ra_100_mensual,	
				dia_semana = EXCLUDED.dia_semana,	
				ocurrencia_descripcion = EXCLUDED.ocurrencia_descripcion,	
				ocurrencia_tipo = EXCLUDED.ocurrencia_tipo,
				ocu_tipo = EXCLUDED.ocu_tipo,	
				tip_codigo = EXCLUDED.tip_codigo,	
				feriado_descripcion	= EXCLUDED.feriado_descripcion,
				tolerancia_especial = EXCLUDED.tolerancia_especial,
				fecha_actualizacion = now();

		GET DIAGNOSTICS v_insertados = ROW_COUNT; -- Cuenta las filas insertadas/actualizadas

	ELSE
		-- CASO 2: TABLA CON DATOS (ACTUALIZACIÓN DIARIA)
		-- Solo insertar/actualizar los datos del día actual
		INSERT INTO historico_marcaciones_mensual (reg_fecha, 
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
													reg_anho,
													reg_mes,
													fecha_registro
												)
		SELECT DISTINCT ON (res_func.reg_fecha, res_func.reg_cod_personal)
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
				res_func.horas_a_compensar, 
				res_func.horas_compensadas, 
				res_func.horas_restantes,
				res_func.estado_compensacion, 
				res_func.re_semanal_suma, 
				res_func.re_mensual_suma, 
				res_func.re_acumulada_semanal,
				res_func.re_acumulada_mensual, 
				res_func.ra, 
				res_func.ra_semanal_suma, 
				res_func.ra_mensual_suma, 
				res_func.ra_80, 
				res_func.ra_100,
				res_func.ra_80_semanal, 
				res_func.ra_100_semanal, 
				res_func.ra_80_mensual, 
				res_func.ra_100_mensual, 
				res_func.dia_semana,
				res_func.ocurrencia_descripcion, 
				res_func.ocurrencia_tipo, 
				res_func.ocu_tipo, 
				res_func.tip_codigo,
				res_func.feriado_descripcion, 
				res_func.tolerancia_especial, 
				EXTRACT(YEAR FROM res_func.reg_fecha)::INTEGER,
				EXTRACT(MONTH FROM res_func.reg_fecha)::INTEGER,
				now()
		FROM(SELECT per_cod FROM personales WHERE per_estado = 1) AS p -- Personal activo
			JOIN LATERAL marcaciones_por_mes_horas5(v_current_anho, v_current_mes, p.per_cod) AS res_func ON TRUE
		WHERE res_func.reg_fecha = CURRENT_DATE -- Filtramos solo el día actual de los resultados de la función
		AND res_func.reg_cod_personal IS NOT NULL -- Asegura que haya un código de personal válido
			ON CONFLICT (reg_fecha,reg_cod_personal) DO UPDATE
			SET	reg_hora_salida = EXCLUDED.reg_hora_salida,
				reg_horas_trabajadas = EXCLUDED.reg_horas_trabajadas,
				reg_retraso = EXCLUDED.reg_retraso,
				reg_horas_extras = EXCLUDED.reg_horas_extras,
				re = EXCLUDED.re,
				horas_a_compensar = EXCLUDED.horas_a_compensar,	
				horas_compensadas = EXCLUDED.horas_compensadas,	
				horas_restantes	= EXCLUDED.horas_restantes,
				estado_compensacion = EXCLUDED.estado_compensacion,	
				re_semanal_suma = EXCLUDED.re_semanal_suma,
				re_mensual_suma = EXCLUDED.re_mensual_suma,	
				re_acumulada_semanal = EXCLUDED.re_acumulada_semanal,	
				re_acumulada_mensual = EXCLUDED.re_acumulada_mensual,
				ra = EXCLUDED.ra,
				ra_semanal_suma = EXCLUDED.ra_semanal_suma,	
				ra_mensual_suma	= EXCLUDED.ra_mensual_suma,
				ra_80 = EXCLUDED.ra_80,	
				ra_100 = EXCLUDED.ra_100,	
				ra_80_semanal = EXCLUDED.ra_80_semanal,	
				ra_100_semanal = EXCLUDED.ra_100_semanal,
				ra_80_mensual = EXCLUDED.ra_80_mensual,	
				ra_100_mensual = EXCLUDED.ra_100_mensual,	
				dia_semana = EXCLUDED.dia_semana,	
				ocurrencia_descripcion = EXCLUDED.ocurrencia_descripcion,	
				ocurrencia_tipo = EXCLUDED.ocurrencia_tipo,
				ocu_tipo = EXCLUDED.ocu_tipo,	
				tip_codigo = EXCLUDED.tip_codigo,	
				feriado_descripcion	= EXCLUDED.feriado_descripcion,
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
			FORMAT('Proceso ejecutado correctamente para INFORME-MENSUAL. Duración: %s', v_duracion_formateada),
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
		
		v_duracion_formateada := FORMAT('%s hora %s, %s minuto %s, %s segundo %s,%s milisegundo %s',v_horas, CASE WHEN v_horas != 1 THEN 's' ELSE '' END, v_minutos, CASE WHEN v_minutos != 1 THEN 's' ELSE '' END, v_segundos, CASE WHEN v_segundos != 1 THEN 's' ELSE '' END, v_milisegundos_restantes, CASE WHEN v_milisegundos_restantes != 1 THEN 's' ELSE '' END);
		
		-- ASIGNACIÓN DE DETALLES DE EXCEPCIÓN A VARIABLES LOCALES
        GET STACKED DIAGNOSTICS
            v_error_sqlstate = RETURNED_SQLSTATE,
            v_error_message = MESSAGE_TEXT,
            v_error_detail = PG_EXCEPTION_DETAIL,
            v_error_hint = PG_EXCEPTION_HINT;

		INSERT INTO log_cron_historico_marcaciones (estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion) 
		VALUES ('ERROR',
				FORMAT('Error al ejecutar proceso para INFORME-MENSUAL. Duración: %s. SQLSTATE: %s, SQLERRM: %s. DETALLE: %s. SUGERENCIA: %s', v_duracion_formateada, v_error_sqlstate, v_error_message, v_error_detail, v_error_hint),
				v_insertados,
				v_duracion_ms,
				now());
END;
$function$;



---------------------------------------------------------------
--- Modificar codigo del formulario en el PHPRunner ---
/* 
 * Paso 3: 
 * Modificar la consulta en el Formulario en el PHPRunner.
 */
---------------------------------------------------------------

-- El query esta actualmente asi...
$strSQL = "SELECT * FROM marcaciones_por_mes_horas5($anho, $mes, $personales)";
/*
$personales  -> Hace referencia al cod_personal.
$parametro1  -> Hace referencia al año pasado como parametro desde la pantalla del usuario.
$parametro2  -> Hace referencia al mes pasado como parametro desde la pantalla del usuario.
*/


-- Asi debe quedar al realizar la modificacion...
$strSQL = "
SELECT * 
FROM historico_marcaciones_mensual 
WHERE reg_anho = $anho 
AND reg_mes = $mes 
AND reg_cod_personal = $personales";



---------------------------------------------------------------
--- Tarea Programada ---
/* 
 * Paso 4: 
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
	'cron_mensual_marcaciones_prueba', -- nombre del job
	'* * * * *',                      -- cada minuto
	$$SELECT insertar_historico_marcaciones_mensual();$$
);

-- Verificar los jobs existentes
SELECT * FROM cron.job;

-- Eliminar o modificar un cron job
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cron_mensual_marcaciones_prueba';

-- Modificar: primero eliminas y luego lo creas de nuevo con nueva configuración.

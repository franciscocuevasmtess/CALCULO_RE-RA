-- TABLA DE LOG DE LAS EJECUCIONES DE LA TAREA PROGRAMADA --
CREATE TABLE public.log_cron_historico_marcaciones (
id serial4 NOT NULL,
fecha_ejecucion timestamp DEFAULT CURRENT_TIMESTAMP NULL,
estado text NULL,
mensaje text NULL,
registros_insertados int4 NULL,
duracion_ms varchar NULL,
CONSTRAINT log_cron_historico_marcaciones_pkey PRIMARY KEY (id)
);



-- TABLA DE HISTORICO MARCACIONES DIARIAS. --
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


-- TABLA DE HISTORICO MARCACIONES ENTRE FECHAS --
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


-- TABLA DE HISTORICO MARCACIONES MENSUAL. --
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
--reg_anho INTEGER NULL,
--reg_mes INTEGER NULL,
fecha_registro timestamp DEFAULT now() NULL, 
fecha_actualizacion timestamp NULL,
CONSTRAINT historico_marcaciones_mensual_pkey PRIMARY KEY (id)
);







-- TABLA DE HISTORICO MARCACIONES RESUMEN GENERAL --
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
fecha_registro timestamp DEFAULT now() NULL, 
fecha_actualizacion timestamp NULL,
CONSTRAINT historico_marcaciones_resumen_general_pkey PRIMARY KEY (id)
);



-- CREACION DEL INDEX PARA MARCACIONES DIARIAS.
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_diaria 
ON historico_marcaciones_diarias (reg_cod_personal, dia_semana, reg_fecha);



-- CREACION DEL INDEX PARA MARCACIONES MENSUAL.
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_mensual 
--ON historico_marcaciones_mensual (reg_fecha,reg_cod_personal);
ON historico_marcaciones_mensual (per_cod, mes_cod, anho, reg_fecha);




-- CREACION DEL INDEX PARA MARCACIONES ENTRE FECHAS.
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_entre_fechas 
ON historico_marcaciones_entre_fechas (per_cod, reg_fecha);



-- CREACION DEL INDEX PARA RESUMEN GENERAL.
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_resumen_general 
--ON historico_marcaciones_resumen_general (reg_cod_personal,anho,mes);
ON historico_marcaciones_resumen_general (anho, mes, reg_cod_personal);


-- CREACION DE LA FUNCION PARA INSERTAR EN LA TABLA historico_marcaciones_diarias. --
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
	
	--- variables para capturar detalles de la excepción ---
    v_error_sqlstate TEXT;
    v_error_message TEXT;
    v_error_detail TEXT;
    v_error_hint TEXT;
   
   	-- variables para el formato de duracion --
	v_horas INTEGER;
	v_minutos INTEGER;
	v_segundos INTEGER;
	v_milisegundos_restantes INTEGER;
	v_duracion_formateada TEXT;
BEGIN
	v_inicio := clock_timestamp();

	-- Verificamos si ya existen datos en la tabla historico_marcaciones_diarias
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
		
		-- Calculamos la duracion tambien en caso de error.
		v_duracion_ms := EXTRACT(EPOCH FROM (v_fin - v_inicio)) * 1000;
		
		v_horas := (v_duracion_ms / (1000 * 60 * 60));
		v_minutos := ((v_duracion_ms % (1000 * 60 * 60)) / (1000 * 60));
		v_segundos := ((v_duracion_ms % (1000 * 60)) / 1000);
		v_milisegundos_restantes := (v_duracion_ms % 1000);
	
		v_duracion_formateada := FORMAT('%s hora %s, %s minuto %s, %s segundo %s,%s milisegundo %s',v_horas, CASE WHEN v_horas != 1 THEN 's' ELSE '' END, v_minutos, CASE WHEN v_minutos != 1 THEN 's' ELSE '' END, v_segundos, CASE WHEN v_segundos != 1 THEN 's' ELSE '' END, v_milisegundos_restantes, CASE WHEN v_milisegundos_restantes != 1 THEN 's' ELSE '' END);
		
		--- ASIGNACIÓN DE DETALLES DE EXCEPCIÓN A VARIABLES LOCALES ---
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



-- CREACION DE LA FUNCION PARA INSERTAR EN LA TABLA historico_marcaciones_mensual. --
CREATE OR REPLACE FUNCTION public.insertar_historico_marcaciones_mensual()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
	v_inicio TIMESTAMP;
	v_fin TIMESTAMP;
	v_duracion_ms INTEGER;
	v_insertados INTEGER := 0;
	v_total_actual INTEGER;
	v_current_anho INTEGER; -- Variable para el año actual
	v_current_mes INTEGER;  -- Variable para el mes actual
	
	--- variables para capturar detalles de la excepción ---
    v_error_sqlstate TEXT;
    v_error_message TEXT;
    v_error_detail TEXT;
    v_error_hint TEXT;
	
	-- variables para el formato de duracion --
	v_horas INTEGER;
	v_minutos INTEGER;
	v_segundos INTEGER;
	v_milisegundos_restantes INTEGER;
	v_duracion_formateada TEXT;
BEGIN
	v_inicio := clock_timestamp();

	-- Verificamos si ya existen datos en la tabla historico_marcaciones_mensual
	SELECT COUNT(*) INTO v_total_actual FROM historico_marcaciones_mensual;

	-- Obtenemos el año y el mes actuales solo una vez
	v_current_anho := EXTRACT(YEAR FROM CURRENT_DATE);
	v_current_mes := EXTRACT(MONTH FROM CURRENT_DATE);
	
	-- LÓGICA DE INSERCIÓN CONDICIONAL ---
	
	IF v_total_actual = 0 THEN
		-- --- CASO 1: TABLA VACÍA (CARGA INICIAL COMPLETA) ---
		-- Insertar todos los datos históricos (todos los años, meses, personales)
		INSERT INTO historico_marcaciones_mensual (per_cod,
													anho,
													mes_cod,
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
													fecha_registro
												)
		SELECT --DISTINCT ON (res_func.reg_fecha, res_func.reg_cod_personal)
				DISTINCT ON (p.per_cod, m.mes_cod, a.anho, res_func.reg_fecha)
				p.per_cod,
				a.anho,
				m.mes_cod,
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
				--EXTRACT(YEAR FROM res_func.reg_fecha)::INTEGER,
				--EXTRACT(MONTH FROM res_func.reg_fecha)::INTEGER,
				--a.anho,
				--m.mes_cod,
				now()
		FROM (SELECT per_cod FROM personales WHERE per_estado = 1) AS p -- Personal activo
				CROSS JOIN (SELECT mes_cod FROM meses) AS m -- Todos los meses (del 1 al 12)
				CROSS JOIN (SELECT numero AS anho FROM anhos) AS a -- Todos los años cargados (ej. 2022 a 2025)
				JOIN LATERAL marcaciones_por_mes_horas5(a.anho, m.mes_cod, p.per_cod) AS res_func ON TRUE
		--WHERE res_func.reg_cod_personal IS NOT null -- Asegura que haya un código de personal válido
			--ON CONFLICT (reg_fecha,reg_cod_personal) DO update
			ON CONFLICT (per_cod, mes_cod, anho, reg_fecha) DO UPDATE
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
		-- CASO 2: TABLA CON DATOS (ACTUALIZACIÓN DIARIA) ---
		-- Solo insertar/actualizar los datos del día actual
		INSERT INTO historico_marcaciones_mensual (per_cod,
													anho,
													mes_cod,
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
													--reg_anho,
													--reg_mes,
													fecha_registro
												)
		SELECT --DISTINCT ON (res_func.reg_fecha, res_func.reg_cod_personal)
				DISTINCT ON (p.per_cod, m.mes_cod, a.anho, res_func.reg_fecha)
				p.per_cod,
				v_current_anho,
				v_current_mes,
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
				--EXTRACT(YEAR FROM res_func.reg_fecha)::INTEGER,
				--EXTRACT(MONTH FROM res_func.reg_fecha)::INTEGER,
				--v_current_anho,
				--v_current_mes,
				now()
		FROM(SELECT per_cod FROM personales WHERE per_estado = 1) AS p -- Personal activo
			JOIN LATERAL marcaciones_por_mes_horas5(v_current_anho, v_current_mes, p.per_cod) AS res_func ON TRUE
		WHERE res_func.reg_fecha = CURRENT_DATE -- Filtramos solo el día actual de los resultados de la función
		--AND res_func.reg_cod_personal IS NOT NULL -- Asegura que haya un código de personal válido
			--ON CONFLICT (reg_fecha,reg_cod_personal) DO update
			ON CONFLICT (per_cod, mes_cod, anho, reg_fecha) DO update
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
		
		v_duracion_formateada := FORMAT('%s hora%s, %s minuto%s, %s segundo%s, %s milisegundo%s',v_horas, CASE WHEN v_horas != 1 THEN 's' ELSE '' END, v_minutos, CASE WHEN v_minutos != 1 THEN 's' ELSE '' END, v_segundos, CASE WHEN v_segundos != 1 THEN 's' ELSE '' END, v_milisegundos_restantes, CASE WHEN v_milisegundos_restantes != 1 THEN 's' ELSE '' END);
		
		--- ASIGNACIÓN DE DETALLES DE EXCEPCIÓN A VARIABLES LOCALES ---
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
	
	-- Variables para el formato de duracion --
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
		SELECT	--DISTINCT ON (res_func.reg_fecha, res_func.reg_cod_personal)
				DISTINCT ON (p.per_cod, res_func.reg_fecha)
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
		--ON CONFLICT (reg_fecha, reg_cod_personal) DO UPDATE
		ON CONFLICT (per_cod, reg_fecha) DO UPDATE	
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
														fecha_registro
													)
		SELECT 	--DISTINCT ON (res_func.reg_fecha, res_func.reg_cod_personal)
				DISTINCT ON (p.per_cod, res_func.reg_fecha)	
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
		
		v_duracion_formateada := FORMAT('%s hora %s, %s minuto %s, %s segundo %s,%s milisegundo %s',v_horas, CASE WHEN v_horas != 1 THEN 's' ELSE '' END, v_minutos, CASE WHEN v_minutos != 1 THEN 's' ELSE '' END, v_segundos, CASE WHEN v_segundos != 1 THEN 's' ELSE '' END, v_milisegundos_restantes, CASE WHEN v_milisegundos_restantes != 1 THEN 's' ELSE '' END);
        
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
	
	--- variables para capturar detalles de la excepción
	v_error_sqlstate TEXT;
	v_error_message TEXT;
	v_error_detail TEXT;
	v_error_hint TEXT;
	
	-- variables para el formato de duracion --
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
		SELECT --a.numero AS anho,
				--m.mes_cod AS mes,
				a.anho,
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
		--ON CONFLICT (reg_cod_personal, anho, mes) DO UPDATE
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
		--ON CONFLICT (reg_cod_personal, anho, mes) DO UPDATE
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
		
		-- Calculamos la duracion tambien en caso de error.
		v_duracion_ms := EXTRACT(EPOCH FROM (v_fin - v_inicio)) * 1000;
		
		v_horas := (v_duracion_ms / (1000 * 60 * 60));
		v_minutos := ((v_duracion_ms % (1000 * 60 * 60)) / (1000 * 60));
		v_segundos := ((v_duracion_ms % (1000 * 60)) / 1000);
		v_milisegundos_restantes := (v_duracion_ms % 1000);
		
		v_duracion_formateada := FORMAT('%s hora %s, %s minuto %s, %s segundo %s,%s milisegundo %s',v_horas, CASE WHEN v_horas != 1 THEN 's' ELSE '' END, v_minutos, CASE WHEN v_minutos != 1 THEN 's' ELSE '' END, v_segundos, CASE WHEN v_segundos != 1 THEN 's' ELSE '' END, v_milisegundos_restantes, CASE WHEN v_milisegundos_restantes != 1 THEN 's' ELSE '' END);
		
		--- ASIGNACIÓN DE DETALLES DE EXCEPCIÓN A VARIABLES LOCALES ---
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




------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------
-- drop function insertar_historico_marcaciones_diarias();
-- drop function insertar_historico_marcaciones_mensual();
-- drop function insertar_historico_marcaciones_entre_fechas();
-- drop function insertar_historico_marcaciones_resumen_general();
-- drop table log_cron_historico_marcaciones;
-- drop table historico_marcaciones_diarias;
-- drop table historico_marcaciones_mensual;
-- drop table historico_marcaciones_entre_fechas;
-- drop table historico_marcaciones_resumen_general;


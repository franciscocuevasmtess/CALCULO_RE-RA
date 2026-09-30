/*
-- public.historico_horas_extras_mensuales definition
-- Drop table
-- DROP TABLE public.historico_horas_extras_mensuales;
CREATE TABLE public.historico_horas_extras_mensuales (
	id serial4 NOT NULL,
	anho int4 NOT NULL,
	mes int4 NOT NULL,
	reg_cod_personal varchar(20) NULL,
	per_ci varchar(20) NULL,
	per_nombre varchar(100) NULL,
	per_apellido varchar(100) NULL,
	re_mensual_suma varchar(250) NULL,
	ra_80_mensual varchar(250) NULL,
	ra_100_mensual varchar(250) NULL,
	fecha_registro timestamp DEFAULT now() NULL,
	CONSTRAINT historico_horas_extras_mensuales_pkey PRIMARY KEY (id)
);


-- public.log_cron_horas_extras definition
-- Drop table
-- DROP TABLE public.log_cron_horas_extras;
CREATE TABLE public.log_cron_horas_extras (
	id serial4 NOT NULL,
	fecha_ejecucion timestamp DEFAULT CURRENT_TIMESTAMP NULL,
	estado text NULL,
	mensaje text NULL,
	registros_insertados int4 NULL,
	duracion_ms varchar NULL,
	p_anho int4 NULL,
	p_mes int4 NULL,
	CONSTRAINT log_cron_horas_extras_pkey PRIMARY KEY (id)
);


-- DROP FUNCTION public.insertar_horas_extras_historico(int4, int4);
CREATE OR REPLACE FUNCTION public.insertar_horas_extras_historico(p_anho integer, p_mes integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
	v_inicio TIMESTAMP;
	v_fin TIMESTAMP;
	v_duracion_ms INTEGER;
	v_insertados INTEGER := 0;
	-- v_duracion INTERVAL;
	-- v_duracion_hhmmss VARCHAR := '';
BEGIN
	v_inicio := clock_timestamp();  -- captura tiempo preciso
	
    -- Evita duplicados si ya fue procesado
    DELETE FROM historico_horas_extras_mensuales 
    WHERE anho = p_anho 
   	AND mes = p_mes;
   
   	WITH ins AS (
		INSERT INTO historico_horas_extras_mensuales (reg_cod_personal, per_ci, per_nombre, per_apellido, re_mensual_suma, ra_80_mensual, ra_100_mensual, mes, anho)
    	SELECT reg_cod_personal, per_ci, per_nombre, per_apellido, re_mensual_suma, ra_80_mensual, ra_100_mensual, p_mes, p_anho
    	FROM horas_extras_mensuales(p_anho, p_mes)
   		
   		RETURNING 1
  	)
  	
  	SELECT COUNT(*) INTO v_insertados FROM ins;
	
	v_fin := clock_timestamp();
	v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio) + EXTRACT(SECOND FROM v_fin - v_inicio) * 1000 + EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;
	--v_duracion := v_fin - v_inicio;
    --v_duracion_hhmmss := LPAD(EXTRACT(HOUR FROM v_duracion)::TEXT, 2, '0') || ':' ||
    --                     LPAD(EXTRACT(MINUTE FROM v_duracion)::TEXT, 2, '0') || ':' ||
    --                     LPAD(TRUNC(EXTRACT(SECOND FROM v_duracion))::TEXT, 2, '0');
                        
	-- Registrar éxito
	INSERT INTO log_cron_horas_extras(estado, mensaje, registros_insertados, duracion_ms, p_anho, p_mes)
 	VALUES ('EXITO', 
 			FORMAT('Proceso ejecutado correctamente para %s-%s', p_anho, p_mes),
          	v_insertados,
          	v_duracion_ms,
          	--v_duracion_hhmmss,
          	p_anho, 
          	p_mes);
EXCEPTION
	WHEN OTHERS then
		v_fin := clock_timestamp();
		v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio) + EXTRACT(SECOND FROM v_fin - v_inicio) * 1000 + EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;
		--v_duracion := v_fin - v_inicio;
        --v_duracion_hhmmss := LPAD(EXTRACT(HOUR FROM v_duracion)::TEXT, 2, '0') || ':' ||
        --                     LPAD(EXTRACT(MINUTE FROM v_duracion)::TEXT, 2, '0') || ':' ||
        --                     LPAD(TRUNC(EXTRACT(SECOND FROM v_duracion))::TEXT, 2, '0');
		
        INSERT INTO log_cron_horas_extras(estado, mensaje, registros_insertados, duracion_ms, p_anho, p_mes) 
		VALUES ('ERROR', 
				FORMAT('Error al ejecutar para %s-%s: %s', p_anho, p_mes, SQLERRM),
            	v_insertados,
            	v_duracion_ms,
            	--v_duracion_hhmmss,
            	p_anho, 
            	p_mes);
END;
$function$
;
*/

/*
-- NUEVA TABLA DE HISTORICO MARCACIONES.
CREATE TABLE public.historico_marcaciones_diarias (
id serial4 NOT NULL,
nombre_reporte varchar(100) NULL,
--parametro1 varchar(100) NULL, 
--parametro2 varchar(100) NULL, 
--parametro3 varchar(100) NULL, 
reg_cod_personal integer NULL,
dia_semana varchar(100) NULL,
reg_fecha date NULL,
per_nombre varchar(100) NULL,
per_apellido varchar(100) NULL,
--per_ci varchar(100) NULL,*
hora_entrada_programada varchar(100) NULL, 
hora_salida_programada varchar(100) NULL, 
entrada varchar(100) NULL, 
salida varchar(100) NULL,
retraso varchar(100) NULL, 
horas_trabajadas varchar(100) NULL, 
horas_extras varchar(100) NULL,
--re_semanal_suma varchar(100) NULL,
--tur_entrada varchar(100) NULL, 
--tur_salida varchar(100) NULL, 
--par_valor_time varchar(100) NULL,
--reg_hora_entrada varchar(100) NULL, 
--reg_hora_salida varchar(100) NULL,
--reg_horas_trabajadas varchar(100) NULL,
--reg_retraso varchar(100) NULL,
--reg_horas_extras varchar(100) NULL,
--re varchar(100) NULL,
--re_mensual_suma varchar(100) NULL,
--re_acumulada_semanal varchar(100) NULL, 
--re_acumulada_mensual varchar(100) NULL, 
--horas_a_compensar varchar(100) NULL, 
--horas_compensadas varchar(100) NULL, 
--horas_restantes varchar(100) NULL, 
--estado_compensacion varchar(100) NULL, 
--ra varchar(100) NULL, 
--ra_semanal_suma varchar(100) NULL, 
--ra_mensual_suma varchar(100) NULL, 
--ra_80 varchar(100) NULL, 
--ra_100 varchar(100) NULL, 
--ra_80_semanal varchar(100) NULL, 
--ra_100_semanal varchar(100) NULL, 
--ra_80_mensual varchar(100) NULL, 
--ra_100_mensual varchar(100) NULL,
--ocurrencia_descripcion varchar(100) NULL, 
--ocurrencia_tipo varchar(100) NULL, 
--ocu_tipo varchar(100) NULL, 
--tip_codigo varchar(100) NULL, 
--feriado_descripcion varchar(100) NULL, 
--tolerancia_especial varchar(100) NULL,
--fecha_registro timestamp DEFAULT now() NULL, 

CONSTRAINT historico_marcaciones_pkey PRIMARY KEY (id)
);

CREATE TABLE public.log_cron_historico_marcaciones (
id serial4 NOT NULL,
fecha_ejecucion timestamp DEFAULT CURRENT_TIMESTAMP NULL,
estado text NULL,
mensaje text NULL,
registros_insertados int4 NULL,
duracion_ms varchar NULL,
parametro1 varchar NULL, 
parametro2 varchar NULL, 
parametro3 varchar NULL, 
CONSTRAINT log_cron_historico_marcaciones_pkey PRIMARY KEY (id)
);
*/

-- TABLA DE HISTORICO MARCACIONES DIARIAS.
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

-- TABLA DE LOG DE LAS EJECUCIONES DEL CRON-JOB
CREATE TABLE public.log_cron_historico_marcaciones (
id serial4 NOT NULL,
fecha_ejecucion timestamp DEFAULT CURRENT_TIMESTAMP NULL,
estado text NULL,
mensaje text NULL,
registros_insertados int4 NULL,
duracion_ms varchar NULL,
CONSTRAINT log_cron_historico_marcaciones_diarias_pkey PRIMARY KEY (id)
);

-- CREACION DEL INDEX PARA MARCACIONES DIARIAS.
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_diaria 
ON historico_marcaciones_diarias (reg_cod_personal, dia_semana, reg_fecha);


-- TABLA DE HISTORICO MARCACIONES MENSUAL.
CREATE TABLE public.historico_marcaciones_mensual (
id serial4 NOT NULL,
reg_fecha date NULL,
reg_cod_personal integer NULL,
tur_entrada varchar(60) NULL,
tur_salida varchar(60) NULL,
par_valor_time varchar(100) NULL,
reg_hora_entrada varchar(60) NULL,
reg_hora_salida varchar(60) NULL,
reg_horas_trabajadas varchar(60) NULL,
reg_retraso varchar(100) NULL,
reg_horas_extras varchar(100) NULL,
re varchar(100) NULL,
horas_a_compensar varchar(100) NULL,
horas_compensadas varchar(100) NULL,
horas_restantes varchar(100) NULL,
estado_compensacion varchar(100) NULL,
re_semanal_suma varchar(100) NULL,
re_mensual_suma varchar(100) NULL,
re_acumulada_semanal varchar(100) NULL,
re_acumulada_mensual varchar(100) NULL,
ra varchar(100) NULL,
ra_semanal_suma varchar(100) NULL,
ra_mensual_suma varchar(100) NULL,
ra_80 varchar(100) NULL,
ra_100 varchar(100) NULL,
ra_80_semanal varchar(100) NULL,
ra_100_semanal varchar(100) NULL,
ra_80_mensual varchar(100) NULL,
ra_100_mensual varchar(100) NULL,
dia_semana varchar(60) NULL,
ocurrencia_descripcion varchar(100) NULL,
ocurrencia_tipo	ocu_tipo varchar(100) NULL,
tip_codigo varchar(100) NULL,
feriado_descripcion varchar(100) NULL,
tolerancia_especial varchar(100) NULL,
fecha_registro timestamp DEFAULT now() NULL, 
CONSTRAINT historico_marcaciones_mensual_pkey PRIMARY KEY (id)
);


-- CREACION DEL INDEX PARA MARCACIONES MENSUAL.
CREATE UNIQUE INDEX idx_unico_historico_marcaciones_mensual 
ON historico_marcaciones_mensual (reg_cod_personal, dia_semana, reg_fecha);










-- DROP FUNCTION public.insertar_historico_diarias();
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

	-- Verificamos si ya existen datos en la tabla historico_marcaciones_diarias
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

	INSERT INTO log_cron_historico_marcaciones (
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

		INSERT INTO log_cron_historico_marcaciones (
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
------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------




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
													fecha_registro
												)
		SELECT res_func.reg_fecha, 
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
				now()
		FROM (SELECT per_cod FROM personales WHERE per_estado = 1) AS p -- Personal activo
				CROSS JOIN
					(SELECT mes_cod FROM meses) AS m -- Todos los meses (del 1 al 12)
				CROSS JOIN
					(SELECT numero AS anho FROM anhos) AS a -- Todos los años cargados (ej. 2022 a 2025)
				JOIN LATERAL marcaciones_por_mes_horas5(a.anho, m.mes_cod, p.per_cod) AS res_func ON TRUE
		WHERE res_func.reg_cod_personal IS NOT NULL -- Asegura que haya un código de personal válido
			--ON CONFLICT (reg_fecha, reg_cod_personal, tur_entrada, tur_salida, par_valor_time, reg_hora_entrada) DO UPDATE
			--SET reg_hora_salida = EXCLUDED.reg_hora_salida,
			--	reg_horas_trabajadas = EXCLUDED.reg_horas_trabajadas,
			--	reg_retraso = EXCLUDED.reg_retraso,
			--	fecha_registro = now()
				
		RETURNING 1;

		GET DIAGNOSTICS v_insertados = ROW_COUNT; -- Cuenta las filas insertadas/actualizadas

	ELSE
		-- CASO 2: TABLA CON DATOS (ACTUALIZACIÓN DIARIA) ---
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
													fecha_registro
												)
		SELECT res_func.reg_fecha, 
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
				now()
		FROM(SELECT per_cod FROM personales WHERE per_estado = 1) AS p -- Personal activo
			JOIN LATERAL marcaciones_por_mes_horas5(v_current_anho, v_current_mes, p.per_cod) AS res_func ON TRUE
		WHERE res_func.reg_fecha = CURRENT_DATE -- Filtramos solo el día actual de los resultados de la función
		AND res_func.reg_cod_personal IS NOT NULL -- Asegura que haya un código de personal válido
		ON CONFLICT (reg_cod_personal, dia_semana, reg_fecha) DO UPDATE
			SET
				reg_hora_salida = EXCLUDED.reg_hora_salida,
				reg_horas_trabajadas = EXCLUDED.reg_horas_trabajadas,
				reg_retraso = EXCLUDED.reg_retraso,
				fecha_registro = now()
		
		RETURNING 1;

		GET DIAGNOSTICS v_insertados = ROW_COUNT; -- Cuenta las filas insertadas/actualizadas

	END IF;

	--- REGISTRO DE LOG ---
	v_fin := clock_timestamp();
	v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio)
					+ EXTRACT(SECOND FROM v_fin - v_inicio) * 1000
					+ EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;

	INSERT INTO log_cron_historico_marcaciones (estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion) 
	VALUES ('EXITO',
			'Proceso ejecutado correctamente para INFORME-MENSUAL',
			v_insertados,
			v_duracion_ms,
			now()
	);

	EXCEPTION WHEN OTHERS THEN
		v_fin := clock_timestamp();
		v_duracion_ms := EXTRACT(MILLISECOND FROM v_fin - v_inicio)
						+ EXTRACT(SECOND FROM v_fin - v_inicio) * 1000
						+ EXTRACT(MINUTE FROM v_fin - v_inicio) * 60 * 1000;

		INSERT INTO log_cron_historico_marcaciones (estado, mensaje, registros_insertados, duracion_ms, fecha_ejecucion) 
		VALUES ('ERROR',
				FORMAT('Error al ejecutar proceso para INFORME-MENSUAL: %s', SQLERRM),
				v_insertados,
				v_duracion_ms,
				now()
		);
END;
$function$;

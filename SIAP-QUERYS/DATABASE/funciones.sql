-- DROP FUNCTION public.actualizar_detalles_compensaciones();

CREATE OR REPLACE FUNCTION public.actualizar_detalles_compensaciones()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    comp RECORD;
    detalle RECORD;
    minutos_compensados INTERVAL;
    minutos_pendientes INTERVAL;
BEGIN
    FOR comp IN 
        SELECT * 
        FROM public.compensaciones_completas 
        WHERE com_estado = 'pendiente'
    LOOP
        minutos_pendientes := comp.com_horas_a_compensar - comp.com_horas_compensadas;

        FOR detalle IN 
            SELECT * 
            FROM public.vista_marcaciones_completas
            WHERE reg_cod_personal = comp.com_cod_personal
            AND reg_fecha >= comp.com_fecha_generacion
            AND minutos_pendientes > '00:00:00'
        LOOP
            minutos_compensados := 
                CASE
                    WHEN detalle.reg_hora_salida > detalle.tur_salida THEN detalle.reg_hora_salida - detalle.tur_salida
                    ELSE '00:00:00'::interval
                END;

            IF minutos_compensados > minutos_pendientes THEN
                minutos_compensados := minutos_pendientes;
            END IF;

            -- Insertar en compensaciones_detalles
            INSERT INTO public.compensaciones_detalles (com_cod, com_det_fecha, com_det_horas_a_compensar, com_det_horas_compensadas, com_det_horas_restantes)
            VALUES (comp.com_cod, detalle.reg_fecha, comp.com_horas_a_compensar, minutos_compensados, minutos_pendientes - minutos_compensados);

            -- Actualizar minutos pendientes y compensados
            minutos_pendientes := minutos_pendientes - minutos_compensados;
            UPDATE public.compensaciones_completas
            SET com_horas_compensadas = com_horas_compensadas + minutos_compensados
            WHERE com_cod = comp.com_cod AND com_cod_personal = comp.com_cod_personal;
        END LOOP;

        -- Verificar si la compensación está completa
        IF minutos_pendientes <= '00:00:00' THEN
            UPDATE public.compensaciones_completas
            SET com_estado = 'compensado'
            WHERE com_cod = comp.com_cod AND com_cod_personal = comp.com_cod_personal;
        END IF;
    END LOOP;
END;
$function$
;

-- DROP FUNCTION public.actualizar_detalles_compensaciones_personal(int4);

CREATE OR REPLACE FUNCTION public.actualizar_detalles_compensaciones_personal(param_cod_personal integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    comp RECORD;
    detalle RECORD;
    minutos_compensados INTERVAL;
    minutos_pendientes INTERVAL;
BEGIN
    -- Iterar sobre cada compensación pendiente
    FOR comp IN 
        SELECT * 
        FROM public.compensaciones_completas 
        WHERE com_estado = 'pendiente' AND com_cod_personal = param_cod_personal
        ORDER BY com_fecha_generacion -- Asegurar que las compensaciones se procesan en orden cronológico
    LOOP
        -- Determinar los minutos pendientes de compensación
        IF comp.com_ultimo_dia_compensado IS NOT NULL THEN
            SELECT COALESCE(comp.com_minutos_pendientes, comp.com_horas_a_compensar - comp.com_horas_compensadas) INTO minutos_pendientes;
        ELSE
            minutos_pendientes := comp.com_horas_a_compensar - comp.com_horas_compensadas;
        END IF;

        -- Procesar las marcaciones desde el último día compensado
        FOR detalle IN 
            SELECT * 
            FROM public.vista_marcaciones_completas
            WHERE reg_cod_personal = comp.com_cod_personal
            AND reg_fecha >= COALESCE(comp.com_ultimo_dia_compensado + INTERVAL '1 day', comp.com_fecha_generacion)
            AND minutos_pendientes > '00:00:00'
        LOOP
            -- Validación: Si ya existe una compensación para este día y este personal, no hacer nada
			IF EXISTS (
			    SELECT 1
			    FROM public.compensaciones_detalles cd
			    WHERE cd.com_cod_personal = comp.com_cod_personal
			    AND cd.com_det_fecha = detalle.reg_fecha
			) THEN
			    CONTINUE; -- Saltar a la siguiente iteración, no duplicar el registro para el mismo día
			END IF;

            -- Solo compensar si ambos reg_hora_entrada y reg_hora_salida están presentes
            IF detalle.reg_hora_entrada IS NOT NULL AND detalle.reg_hora_salida IS NOT NULL THEN
                
                -- Si el tipo de turno es 4 (Director General), calcular las horas trabajadas y compensar si es mayor a 8 horas
                IF detalle.tur_tipo = 4 THEN
                    -- Calcular las horas trabajadas restando la hora de entrada de la hora de salida
                    minutos_compensados := 
                        CASE
                            WHEN (detalle.reg_hora_salida - detalle.reg_hora_entrada) > '08:00:00'::interval THEN
                                detalle.reg_hora_salida - detalle.reg_hora_entrada - '08:00:00'::interval
                            ELSE
                                '00:00:00'::interval
                        END;
                ELSE
                    -- El cálculo de compensación habitual para otros tipos de turno
                    minutos_compensados := 
                        CASE
                            WHEN detalle.reg_hora_salida > detalle.tur_salida THEN detalle.reg_hora_salida - detalle.tur_salida
                            ELSE '00:00:00'::interval
                        END;
                END IF;

                -- Si los minutos compensados son mayores a los minutos pendientes, ajustar el valor
                IF minutos_compensados > minutos_pendientes THEN
                    minutos_compensados := minutos_pendientes;
                END IF;

                -- Insertar en compensaciones_detalles
                -- Nueva validación: no insertar registros con compensaciones de 00:00:00
                IF minutos_compensados > '00:00:00' THEN
                    -- Insertar en compensaciones_detalles solo si hay algo que compensar
                    INSERT INTO public.compensaciones_detalles (com_cod, com_det_fecha, com_det_horas_a_compensar, com_det_horas_compensadas, com_det_horas_restantes, com_cod_personal, com_cod_ocurrencia)
                    VALUES (comp.com_cod, detalle.reg_fecha, comp.com_horas_a_compensar, minutos_compensados, minutos_pendientes - minutos_compensados, comp.com_cod_personal, comp.com_cod_ocurrencia);

                    -- Actualizar los minutos pendientes y compensados
                    minutos_pendientes := minutos_pendientes - minutos_compensados;
                    UPDATE public.compensaciones_completas
                    SET com_horas_compensadas = com_horas_compensadas + minutos_compensados,
                        com_ultimo_dia_compensado = detalle.reg_fecha,
                        com_minutos_pendientes = minutos_pendientes
                    WHERE com_cod = comp.com_cod AND com_cod_personal = comp.com_cod_personal;

                    -- Verificar si la compensación está completa
                    IF minutos_pendientes <= '00:00:00' THEN
                        UPDATE public.compensaciones_completas
                        SET com_estado = 'compensado'
                        WHERE com_cod = comp.com_cod AND com_cod_personal = comp.com_cod_personal;
                        EXIT; -- Salir del bucle ya que la compensación está completa
                    END IF;
                END IF; -- Fin de la validación de 00:00:00
            END IF;
        END LOOP;

        -- Si minutos_pendientes es menor o igual a cero, continuar con la siguiente compensación
        IF minutos_pendientes <= '00:00:00' THEN
            CONTINUE;
        END IF;
    END LOOP;
END;
$function$
;

-- DROP FUNCTION public.actualizar_detalles_compensaciones_todos();

CREATE OR REPLACE FUNCTION public.actualizar_detalles_compensaciones_todos()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    emp RECORD;
BEGIN
    FOR emp IN 
        SELECT DISTINCT com_cod_personal 
        FROM public.compensaciones_completas 
        WHERE com_estado = 'pendiente'
    LOOP
        PERFORM actualizar_detalles_compensaciones_personal(emp.com_cod_personal);
    END LOOP;
END;
$function$
;

-- DROP FUNCTION public.actualizar_fecha_fin_compensacion(int4);

CREATE OR REPLACE FUNCTION public.actualizar_fecha_fin_compensacion(codigo_parametro integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE compensaciones
    SET com_fecha_fin = fecha_fin_compensacion(codigo_parametro)
    WHERE com_cod_ocurrencia = codigo_parametro;
END;
$function$
;

-- DROP FUNCTION public.actualizar_fecha_inicio_compensacion(int4);

CREATE OR REPLACE FUNCTION public.actualizar_fecha_inicio_compensacion(codigo_parametro integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE compensaciones
    SET com_fecha_inicio = fecha_inicio_compensacion(codigo_parametro)
    WHERE com_cod_ocurrencia = codigo_parametro;
    
    RETURN 0;
END;
$function$
;

-- DROP FUNCTION public.actualizar_observaciones_asistencia();

CREATE OR REPLACE FUNCTION public.actualizar_observaciones_asistencia()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Establece los nuevos valores de obs_inicio y obs_fin basados en obs_fecha_desde y obs_fecha_hasta
    NEW.obs_inicio := TO_CHAR(NEW.obs_fecha_desde, 'YYYYMM');
    NEW.obs_fin := TO_CHAR(NEW.obs_fecha_hasta, 'YYYYMM');
    RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.actualizar_ocu_tipo_grupo_digito();

CREATE OR REPLACE FUNCTION public.actualizar_ocu_tipo_grupo_digito()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Asigna un valor a ocu_tipo_grupo_digito basado en la condición de ocu_tipo_grupo
    NEW.ocu_tipo_grupo_digito := CASE
        WHEN NEW.ocu_tipo_grupo = 'G' THEN 1
        ELSE 0
    END;
    RETURN NEW;
END;
$function$
;

-- DROP PROCEDURE public.actualizar_turnos();

CREATE OR REPLACE PROCEDURE public.actualizar_turnos()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    UPDATE turnos
    SET tur_entrada_horas = tur_entrada, 
        tur_salida_horas = tur_salida
    WHERE tur_horas = 0;
END;
$procedure$
;

-- DROP FUNCTION public.asignar_ocu_tipo_grupo_digito();

CREATE OR REPLACE FUNCTION public.asignar_ocu_tipo_grupo_digito()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Asigna un valor a ocu_tipo_grupo_digito basado en la condición de ocu_tipo_grupo
    NEW.ocu_tipo_grupo_digito := CASE
        WHEN NEW.ocu_tipo_grupo = 'G' THEN 1
        ELSE 0
    END;
    RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.before_insert_observaciones_asistencia();

CREATE OR REPLACE FUNCTION public.before_insert_observaciones_asistencia()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Ajustamos los valores de obs_inicio y obs_fin antes de insertar
    NEW.obs_inicio := TO_CHAR(NEW.obs_fecha_desde, 'YYYYMM');
    NEW.obs_fin := TO_CHAR(NEW.obs_fecha_hasta, 'YYYYMM');
    RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.calcular_resto(time, time, time);

CREATE OR REPLACE FUNCTION public.calcular_resto(actual time without time zone, adicion time without time zone, limite time without time zone)
 RETURNS time without time zone
 LANGUAGE plpgsql
AS $function$
DECLARE
    hora_final TIME;
BEGIN
    -- Ajustamos valores nulos a '00:00'
    actual := COALESCE(actual, '00:00');
    adicion := COALESCE(adicion, '00:00');
    limite := COALESCE(limite, '00:00');

    -- Calculamos hora_final según las condiciones
    IF actual + adicion <= limite THEN
        hora_final := adicion;
    ELSIF actual + adicion > limite THEN
        hora_final := (adicion - ((actual + adicion) - limite));
    END IF;

    -- Si hora_final es '00:00', retornamos null
    IF hora_final = '00:00' THEN
        RETURN NULL;
    ELSE
        RETURN hora_final; -- Devuelve el tiempo como 'HH:MI'
    END IF;
END;
$function$
;

-- DROP FUNCTION public.calculo_resto_horas(time, time, time, time, varchar);

CREATE OR REPLACE FUNCTION public.calculo_resto_horas(cien_parametro time without time zone, extras_parametro time without time zone, adicional_parametro time without time zone, compensacion_parametro time without time zone, calculo character varying)
 RETURNS time without time zone
 LANGUAGE plpgsql
AS $function$
DECLARE
    saldo_extras TIME := '00:00';
    saldo_adicional TIME := '00:00';
    saldo_cien TIME := '00:00';
    saldo_compensacion TIME := '00:00';
    total_calculo TIME := '00:00';
    total_saldo TIME := '00:00';
    total_descontar TIME := '00:00';
BEGIN
    -- No existe una tabla temporal en el código original
    -- Insertar en tabla temporal omitido en la traducción

    total_calculo := compensacion_parametro + adicional_parametro + extras_parametro;
    total_descontar := cien_parametro + extras_parametro + compensacion_parametro;
    total_saldo := total_calculo - total_descontar;
    saldo_compensacion := compensacion_parametro;

    IF total_saldo > '00:00' THEN
        saldo_adicional := total_saldo;
        IF calculo = 'adicional' THEN
            RETURN saldo_adicional;
        END IF;
    END IF;

    IF adicional_parametro > saldo_compensacion THEN
        saldo_adicional := adicional_parametro - saldo_compensacion;
        saldo_compensacion := '00:00';
    ELSE
        saldo_adicional := '00:00';
        saldo_compensacion := saldo_compensacion - adicional_parametro;
    END IF;

    IF calculo = 'adicional' THEN
        RETURN saldo_adicional;
    END IF;

    IF saldo_compensacion > '00:00' THEN
        IF extras_parametro > saldo_compensacion THEN
            saldo_extras := extras_parametro - saldo_compensacion;
            saldo_compensacion := '00:00';
        ELSE
            saldo_extras := '00:00';
            saldo_compensacion := saldo_compensacion - extras_parametro;
        END IF;
    END IF;

    IF calculo = 'extras' THEN
        RETURN saldo_extras;
    END IF;

    IF saldo_compensacion > '00:00' THEN
        IF cien_parametro > saldo_compensacion THEN
            saldo_cien := cien_parametro - saldo_compensacion;
            saldo_compensacion := '00:00';
        ELSE
            saldo_cien := '00:00';
            saldo_compensacion := saldo_compensacion - cien_parametro;
        END IF;
    END IF;

    IF calculo = 'cien' THEN
        RETURN saldo_cien;
    END IF;

    RETURN saldo_compensacion;
END;
$function$
;

-- DROP FUNCTION public.cantidad_faltas(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.cantidad_faltas(funcionario_parametro integer, anho_parametro integer, falta_parametro integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN (
        SELECT COALESCE(SUM(fal_cantidad), 0)
        FROM faltas
        WHERE fal_cod_personal = funcionario_parametro
        AND fal_cod_tipo = falta_parametro
        AND fal_anho = anho_parametro
    );
END;
$function$
;

-- DROP FUNCTION public.cantidad_permisos_gastados(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.cantidad_permisos_gastados(funcionario_parametro integer, ocurrencia_parametro integer, anho_parametro integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN (
        SELECT COALESCE(SUM(det_dias_gastados), 0)
        FROM (
            SELECT * FROM ocurrencias
            JOIN tipos_ocurrencias ON ocu_tipo = tip_cod OR ocu_tipo = tip_cod_tipo_sumatoria
            JOIN detalle_ocurrencias ON ocu_cod = det_cod_ocurrencia
            AND ocu_cod_persona = funcionario_parametro
            AND ocu_tipo = ocurrencia_parametro
            AND det_anho_gasto = anho_parametro
            GROUP BY det_cod
        ) AS datos
    );
END;
$function$
;

-- DROP FUNCTION public.codigo_funcionario(int4);

CREATE OR REPLACE FUNCTION public.codigo_funcionario(funcionario_parametro integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN (
        SELECT rel_codigo
        FROM codigos_reloj
        WHERE rel_cod_persona = funcionario_parametro
    );
END;
$function$
;

-- DROP FUNCTION public.codigo_turno();

CREATE OR REPLACE FUNCTION public.codigo_turno()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN (
        SELECT COALESCE(MAX(tur_cod_personal), 0) + 1 FROM turnos
    );
END;
$function$
;

-- DROP FUNCTION public.condicion_marcaciones_minima(int4, date);

CREATE OR REPLACE FUNCTION public.condicion_marcaciones_minima(funcionario_parametro integer, fecha_parametro date)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    result INT;
BEGIN
    SELECT COUNT(*) INTO result FROM (
        SELECT COUNT(*) AS contador
        FROM (
            SELECT *
            FROM (
                SELECT * FROM codigos_reloj WHERE rel_cod_persona = funcionario_parametro
            ) AS codigos_reloj
            JOIN (
                SELECT * FROM registros_entrada_salida
                WHERE EXTRACT(YEAR FROM reg_fecha) = EXTRACT(YEAR FROM fecha_parametro)
                AND EXTRACT(MONTH FROM reg_fecha) = EXTRACT(MONTH FROM fecha_parametro)
            ) AS registros_entrada_salida_comparacion
            ON registros_entrada_salida_comparacion.reg_cod_personal::INTEGER = codigos_reloj.rel_codigo::INTEGER
            AND registros_entrada_salida_comparacion.reg_reloj::INTEGER = codigos_reloj.rel_reloj::INTEGER
            AND registros_entrada_salida_comparacion.reg_fecha = fecha_parametro
        ) AS datos
        GROUP BY reg_hora
    ) AS datos_final;

    RETURN COALESCE(result, 0);
END;
$function$
;

-- DROP FUNCTION public.dia_habil(date);

CREATE OR REPLACE FUNCTION public.dia_habil(fecha_parametro date)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    dias_habiles INT;
    feriados INT;
    cantidad_dias INT;
BEGIN
    -- Asigna 1 si es un día entre lunes y viernes (excluyendo sábados y domingos)
    dias_habiles := CASE WHEN EXTRACT(DOW FROM fecha_parametro) BETWEEN 1 AND 5 THEN 1 ELSE 0 END;

    -- Cuenta si el día es un feriado
    SELECT COUNT(*) INTO feriados FROM feriados WHERE fer_fecha = fecha_parametro;

    -- Calcula si es un día hábil descontando los feriados
    cantidad_dias := dias_habiles - feriados;

    RETURN cantidad_dias;
END;
$function$
;

-- DROP FUNCTION public.dias_entre_fechas(int4, date, date);

CREATE OR REPLACE FUNCTION public.dias_entre_fechas(dia_parametro integer, fecha_inicio_parametro date, fecha_fin_parametro date)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    cantidad INT;
BEGIN
    cantidad := (
        SELECT COUNT(*) FROM generate_series(fecha_inicio_parametro, fecha_fin_parametro, interval '1 day') as fecha
        WHERE EXTRACT(DOW FROM fecha) = dia_parametro
    );

    RETURN COALESCE(cantidad, 0);
END;
$function$
;

-- DROP FUNCTION public.dias_entre_semana(date, date);

CREATE OR REPLACE FUNCTION public.dias_entre_semana(a date, b date)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    fecha_actual DATE;
    total_dias INT := 0;
BEGIN
    -- Asegurar que a siempre sea menor que b
    IF a > b THEN
        fecha_actual := a;
        a := b;
        b := fecha_actual;
    END IF;

    -- Inicializar fecha_actual
    fecha_actual := a;

    -- Contar todos los días entre a y b que no son sábado ni domingo
    WHILE fecha_actual <= b LOOP
        IF EXTRACT(DOW FROM fecha_actual) BETWEEN 1 AND 5 THEN
            total_dias := total_dias + 1;
        END IF;
        fecha_actual := fecha_actual + INTERVAL '1 day';
    END LOOP;

    RETURN total_dias;
END;
$function$
;

-- DROP FUNCTION public.dias_gastados(int4, date, date);

CREATE OR REPLACE FUNCTION public.dias_gastados(tipo_dia_parametro integer, fecha_inicio_parametro date, fecha_fin_parametro date)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    dias_habiles INT;
    feriados INT;
    cantidad_dias INT;
BEGIN
    -- Cuenta todos los días
    IF tipo_dia_parametro = 1 THEN
        cantidad_dias := fecha_fin_parametro - fecha_inicio_parametro + 1;
        RETURN cantidad_dias;
    END IF;

    -- Cuenta sólo días hábiles y resta los feriados
    IF tipo_dia_parametro = 2 THEN
        -- Llama a una función que cuenta los días hábiles
        dias_habiles := dias_entre_semana(fecha_inicio_parametro, fecha_fin_parametro);
        -- Cuenta los feriados entre las dos fechas
        SELECT COUNT(*) INTO feriados FROM feriados WHERE fer_fecha BETWEEN fecha_inicio_parametro AND fecha_fin_parametro;
        cantidad_dias := dias_habiles - feriados;
        RETURN cantidad_dias;
    END IF;
END;
$function$
;

-- DROP FUNCTION public.dias_habiles(date, date);

CREATE OR REPLACE FUNCTION public.dias_habiles(fecha_inicio_parametro date, fecha_fin_parametro date)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    domingos INT;
    sabados INT;
    feriados INT;
    cantidad_dias INT;
BEGIN
    -- Calcula los domingos y sábados entre las fechas
    domingos := dias_entre_fechas(1, fecha_inicio_parametro, fecha_fin_parametro);
    sabados := dias_entre_fechas(7, fecha_inicio_parametro, fecha_fin_parametro);

    -- Cuenta los feriados entre las fechas
    SELECT COUNT(*) INTO feriados FROM feriados WHERE fer_fecha BETWEEN fecha_inicio_parametro AND fecha_fin_parametro;
    
    -- Calcula la cantidad total de días hábiles
    cantidad_dias := (fecha_fin_parametro - fecha_inicio_parametro + 1) - feriados - domingos - sabados;

    RETURN cantidad_dias;
END;
$function$
;

-- DROP FUNCTION public.edad_calculada(date);

CREATE OR REPLACE FUNCTION public.edad_calculada(fecha_nacimiento date)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    edad INT;
BEGIN
    SELECT EXTRACT(YEAR FROM AGE(current_date, fecha_nacimiento)) INTO edad;
    IF edad IS NULL THEN
        RETURN 0;
    ELSE
        RETURN edad;
    END IF;
END;
$function$
;

-- DROP FUNCTION public.estado_codigos_reloj(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.estado_codigos_reloj(funcionario_parametro integer, anho_parametro integer, mes_parametro integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    valor INT;
BEGIN
    SELECT CASE 
        WHEN SUM(1) = SUM(
            CASE 
                WHEN (
                    SELECT COUNT(*) 
                    FROM codigos_reloj 
                    WHERE codigos_reloj.rel_cod_persona = funcionario_parametro 
                        AND fecha BETWEEN codigos_reloj.rel_fecha_desde AND codigos_reloj.rel_fecha_hasta
                ) = (
                    SELECT COUNT(*) 
                    FROM codigos_reloj 
                    WHERE codigos_reloj.rel_cod_persona = funcionario_parametro
                )
                THEN 1
                ELSE 0
            END
        )
        THEN 0
        ELSE 1
    END
    INTO valor
    FROM fechas
    WHERE EXTRACT(YEAR FROM fecha) = anho_parametro 
        AND EXTRACT(MONTH FROM fecha) = mes_parametro;

    RETURN valor;
END;
$function$
;

-- DROP FUNCTION public.estado_turnos(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.estado_turnos(funcionario_parametro integer, anho_parametro integer, mes_parametro integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    valor INT;
BEGIN
    SELECT CASE 
        WHEN SUM(1) = SUM(
            CASE 
                WHEN (
                    SELECT COUNT(*) 
                    FROM turnos 
                    WHERE tur_cod_personal = funcionario_parametro 
                        AND fecha BETWEEN tur_fecha_desde AND tur_fecha_hasta
                ) > 0
                THEN 1
                ELSE 0
            END
        )
        THEN 0
        ELSE 1
    END
    INTO valor
    FROM fechas
    WHERE EXTRACT(YEAR FROM fecha) = anho_parametro 
        AND EXTRACT(MONTH FROM fecha) = mes_parametro;

    RETURN valor;
END;
$function$
;

-- DROP FUNCTION public.fecha_fin_compensacion(int4);

CREATE OR REPLACE FUNCTION public.fecha_fin_compensacion(codigo_parametro integer)
 RETURNS date
 LANGUAGE plpgsql
AS $function$
DECLARE
    fecha_fin date;
BEGIN
    -- Ejemplo de lógica para calcular fecha_fin
    SELECT com_fecha + INTERVAL '10 day' INTO fecha_fin
    FROM compensaciones
    WHERE com_cod_ocurrencia = codigo_parametro
    LIMIT 1;

    RETURN fecha_fin;
END;
$function$
;

-- DROP FUNCTION public.fecha_inicio_compensacion(int4);

CREATE OR REPLACE FUNCTION public.fecha_inicio_compensacion(codigo_parametro integer)
 RETURNS date
 LANGUAGE plpgsql
AS $function$
DECLARE
    fecha_inicio date;
BEGIN
    SELECT MIN(com_fecha) INTO fecha_inicio
    FROM compensaciones
    WHERE com_cod_ocurrencia = codigo_parametro;

    RETURN fecha_inicio;
END;
$function$
;

-- DROP FUNCTION public.fn_regenerar_compensacion();

CREATE OR REPLACE FUNCTION public.fn_regenerar_compensacion()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- Variables para almacenar los valores anteriores de la compensación
    v_com_fecha_generacion DATE;
    v_com_mes INT;
    v_com_anio INT;
BEGIN
    -- Recuperamos los valores anteriores de la compensación desde la tabla compensaciones_completas
    SELECT com_fecha_generacion, com_mes, com_anio
    INTO v_com_fecha_generacion, v_com_mes, v_com_anio
    FROM public.compensaciones_completas
    WHERE com_cod_ocurrencia = OLD.ocu_cod;

    -- Eliminamos la compensación completa existente para esta ocurrencia
    DELETE FROM public.compensaciones_completas
    WHERE com_cod_ocurrencia = OLD.ocu_cod;

    -- Insertamos una nueva compensación con el estado 'pendiente' y los valores anteriores
    INSERT INTO public.compensaciones_completas (
        com_cod_personal,
        com_fecha_generacion,
        com_mes,
        com_anio,
        com_horas_a_compensar,
        com_estado,
        com_cod_ocurrencia
    )
    VALUES (
        NEW.ocu_cod_persona,
        v_com_fecha_generacion, -- Fecha de generación anterior
        v_com_mes, -- Mes anterior
        v_com_anio, -- Año anterior
        NEW.ocu_horas_compensacion::interval, -- Usamos el valor actualizado de ocu_horas_compensacion
        'pendiente',
        NEW.ocu_cod
    );

    -- Llamar a la función de actualización de compensaciones para el personal correspondiente
    PERFORM actualizar_detalles_compensaciones_personal(NEW.ocu_cod_persona);

    RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.formato_numero_documento(varchar);

CREATE OR REPLACE FUNCTION public.formato_numero_documento(numero_documento_parametro character varying)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    es_numerico boolean;
    documento_formateado varchar(55);
BEGIN
    -- Verifica si el número de documento es numérico
    es_numerico := numerico(numero_documento_parametro);

    -- Formatea el número de documento si es numérico
    IF es_numerico THEN
        documento_formateado := TO_CHAR(numero_documento_parametro::numeric, 'FM999G999G999G999G990', 'de_DE');
    ELSE
        documento_formateado := numero_documento_parametro;
    END IF;

    RETURN documento_formateado;
END;
$function$
;

-- DROP FUNCTION public.generar_calendario_ocurrencia(int4, int4);

CREATE OR REPLACE FUNCTION public.generar_calendario_ocurrencia(codigo_ocurrencia_parametro integer, dias_parametro integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    codigo_personal_parametro integer;
    fecha_hasta_parametro date;
    horas_parametro time;
    resultado integer;
    limite integer;
BEGIN
    -- Obtener los valores iniciales
    SELECT ocu_cod_persona INTO codigo_personal_parametro
    FROM ocurrencias
    WHERE ocu_cod = codigo_ocurrencia_parametro;
    
    SELECT ocu_fecha_hasta INTO fecha_hasta_parametro
    FROM ocurrencias
    WHERE ocu_cod = codigo_ocurrencia_parametro;
    
    SELECT ocu_horas_compensacion INTO horas_parametro
    FROM ocurrencias
    WHERE ocu_cod = codigo_ocurrencia_parametro;
    
    limite := dias_parametro * 2;
    
    -- Eliminar compensaciones existentes
    DELETE FROM compensaciones
    WHERE com_cod_ocurrencia = codigo_ocurrencia_parametro;
    
    -- Insertar nuevas compensaciones
    INSERT INTO compensaciones (com_cod_ocurrencia, com_fecha, com_cod_personal, com_cantidad_horas)
    SELECT
        codigo_ocurrencia_parametro,
        fecha,
        codigo_personal_parametro,
        horas_parametro
    FROM (
        SELECT fecha
        FROM (
            SELECT fecha
            FROM (
                SELECT 
                    (fecha_hasta_parametro + INTERVAL '1 day' * num_sumar)::date AS fecha,
                    dia_habil((fecha_hasta_parametro + INTERVAL '1 day' * num_sumar)::date) AS habil
                FROM numeros
                ORDER BY num_cod
                LIMIT limite
            ) AS listado
            WHERE habil = 1
            ORDER BY fecha
            LIMIT dias_parametro
        ) AS listado
    ) AS listado;
    
    -- Actualizar fechas de compensación
    PERFORM actualizar_fecha_fin_compensacion(codigo_ocurrencia_parametro);
    PERFORM actualizar_fecha_inicio_compensacion(codigo_ocurrencia_parametro);
    
    -- Actualizar orden de compensaciones
    UPDATE compensaciones
    SET com_orden = orden(com_cod_ocurrencia, com_cod_personal)
    WHERE com_cod_personal = codigo_personal_parametro;
    
    RETURN 0;
END;
$function$
;

-- DROP FUNCTION public.generar_enlace_compensacion(varchar, varchar);

CREATE OR REPLACE FUNCTION public.generar_enlace_compensacion(listado character varying, texto character varying)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    resultado VARCHAR(1000);
BEGIN
    SELECT string_agg('<a href=''ocurrencias_view.php?editid1=' || ocu_cod || ''' target=''_blank''>' || texto || '</a>', ', ')
    INTO resultado
    FROM ocurrencias
    WHERE position(',' || ocu_cod || ',' IN ',' || listado || ',') > 0;

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.generar_faltas(int4, int4);

CREATE OR REPLACE FUNCTION public.generar_faltas(anho_parametro integer, mes_parametro integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    funcionarios TEXT;
    funcionarios_maximo INT;
    contador INT;
BEGIN
    -- Inicializar contador
    contador := 1;

    -- Obtener lista de funcionarios activos
    SELECT string_agg(per_cod::TEXT, ',') INTO funcionarios
    FROM personales
    WHERE per_estado = 1;

    -- Obtener el valor máximo de per_cod para funcionarios activos
    SELECT MAX(per_cod) INTO funcionarios_maximo
    FROM personales
    WHERE per_estado = 1;

    -- Eliminar faltas del mes y año especificados
    DELETE FROM faltas
    WHERE fal_mes = mes_parametro AND fal_anho = anho_parametro;

    -- Loop para procesar cada funcionario
    WHILE contador <= funcionarios_maximo LOOP
        IF position(',' || contador::TEXT || ',' IN ',' || funcionarios || ',') > 0 THEN
            PERFORM marcaciones_faltas_funcionarios(contador, anho_parametro, mes_parametro);
        END IF;
        contador := contador + 1;
    END LOOP;
END;
$function$
;

-- DROP FUNCTION public.generar_horas(int4, int4);

CREATE OR REPLACE FUNCTION public.generar_horas(anho_parametro integer, mes_parametro integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    funcionarios TEXT;
    funcionarios_maximo INT;
    contador INT;
BEGIN
    -- Inicializar contador
    contador := 1;

    -- Obtener lista de funcionarios activos
    SELECT string_agg(per_cod::TEXT, ',') INTO funcionarios
    FROM personales
    WHERE per_estado = 1;

    -- Obtener el valor máximo de per_cod para funcionarios activos
    SELECT MAX(per_cod) INTO funcionarios_maximo
    FROM personales
    WHERE per_estado = 1;

    -- Eliminar horas_personales del mes y año especificados
    DELETE FROM horas_personales
    WHERE hor_mes = mes_parametro AND hor_anho = anho_parametro;

    -- Loop para procesar cada funcionario
    WHILE contador <= funcionarios_maximo LOOP
        IF position(',' || contador::TEXT || ',' IN ',' || funcionarios || ',') > 0 THEN
            PERFORM marcaciones_horas(contador, anho_parametro, mes_parametro);
        END IF;
        contador := contador + 1;
    END LOOP;
END;
$function$
;

-- DROP PROCEDURE public.guardar_historial_mensual(int4, int4);

CREATE OR REPLACE PROCEDURE public.guardar_historial_mensual(IN anio integer, IN mes integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    empleado RECORD;
BEGIN
    -- Validar que el mes y año sean válidos
    IF anio IS NULL OR mes IS NULL OR mes < 1 OR mes > 12 THEN
        RAISE EXCEPTION 'Año o mes inválido';
    END IF;
   
   	IF EXISTS (
	    SELECT 1 FROM historial_marcaciones
	    WHERE periodo_year = anio AND periodo_month = mes
	    LIMIT 1
	) THEN
	    RAISE NOTICE 'El mes %-% ya fue procesado. Saltando...', anio, mes;
	    RETURN;
	END IF;


    -- Iterar por cada empleado que tenga marcaciones en ese mes
    FOR empleado IN
    	SELECT DISTINCT COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal
		FROM personales p 
			JOIN marcacion_entrada_adsoluta e ON e.reg_cod_personal = p.per_cod 
			FULL JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
		WHERE p.per_estado = 1
		AND EXTRACT(MONTH FROM COALESCE(e.reg_fecha, s.reg_fecha))::int = mes
		AND EXTRACT(YEAR FROM COALESCE(e.reg_fecha, s.reg_fecha))::int = anio
    LOOP
        -- Llamar a la función parametrizada para este empleado
        INSERT INTO historial_marcaciones (
            periodo_year,
            periodo_month,
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
            tolerancia_especial
        )
        SELECT
            anio,
            mes,
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
            tolerancia_especial
        FROM marcaciones_por_mes_horas5_parametrizada(anio, mes, empleado.reg_cod_personal);

        -- Opcional: Mostrar progreso (solo en logs)
        --RAISE NOTICE 'Procesado empleado % para %-%', empleado.reg_cod_personal, anio, mes;
    END LOOP;

    COMMIT; -- Asegura que todo se guarde
END;
$procedure$
;

-- DROP FUNCTION public.horario_maternidad_resto(time, time, date, int4);

CREATE OR REPLACE FUNCTION public.horario_maternidad_resto(hora_salida_parametro time without time zone, horas_parametro time without time zone, fecha_parametro date, funcionario_parametro integer)
 RETURNS time without time zone
 LANGUAGE plpgsql
AS $function$
DECLARE
    hora_restante TIME;
    hora_maternidad TIME;
BEGIN
    SELECT ocu_hora_desde INTO hora_maternidad
    FROM ocurrencias
    WHERE ocu_tipo = 15
      AND ocu_cod_persona = funcionario_parametro
      AND fecha_parametro BETWEEN ocu_fecha_desde AND ocu_fecha_hasta;

    IF hora_maternidad IS NULL THEN
        hora_maternidad := hora_salida_parametro;
    END IF;

    SELECT horas_parametro - (hora_salida_parametro - hora_maternidad) INTO hora_restante;

    IF hora_restante < TIME '00:00:00' THEN
        hora_restante := TIME '00:00:00';
    END IF;

    RETURN hora_restante;
END;
$function$
;

-- DROP FUNCTION public.horario_salida_especial(int4, date);

CREATE OR REPLACE FUNCTION public.horario_salida_especial(funcionario_parametro integer, fecha_parametro date)
 RETURNS time without time zone
 LANGUAGE plpgsql
AS $function$
DECLARE
    hora_salida TIME;
BEGIN
    SELECT ocurrencias.ocu_hora_desde
    INTO hora_salida
    FROM ocurrencias
    JOIN tipos_ocurrencias ON ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod
    WHERE tipos_ocurrencias.tip_horario_compensatorio = 1
      AND fecha_parametro BETWEEN ocurrencias.ocu_fecha_desde AND ocurrencias.ocu_fecha_hasta
      AND ocurrencias.ocu_cod_persona = funcionario_parametro
    LIMIT 1;

    RETURN hora_salida;
END;
$function$
;

-- DROP FUNCTION public.horas_compensadas(int4, date);

CREATE OR REPLACE FUNCTION public.horas_compensadas(personal_parametro integer, fecha_parametro date)
 RETURNS time without time zone
 LANGUAGE plpgsql
AS $function$
DECLARE
    horas_compensadas TIME;
BEGIN
    SELECT
        CASE
            WHEN SUM(EXTRACT(EPOCH FROM com_horas_en_dia)) >= EXTRACT(EPOCH FROM com_horas_por_compensar)
            THEN (SUM(EXTRACT(EPOCH FROM com_horas_en_dia)) - EXTRACT(EPOCH FROM com_horas_por_compensar)) * INTERVAL '1 second'
            ELSE com_horas_en_dia
        END
    INTO horas_compensadas
    FROM compensaciones_limite_horas_diarias AS compensaciones_sumatoria
    WHERE compensaciones_sumatoria.com_cod_personal = personal_parametro
      AND compensaciones_sumatoria.com_fecha <= fecha_parametro;

    RETURN horas_compensadas;
END;
$function$
;

-- DROP FUNCTION public.horas_extras_mensuales(int4, int4);

CREATE OR REPLACE FUNCTION public.horas_extras_mensuales(anio integer, mes integer)
 RETURNS TABLE(reg_cod_personal integer, per_nombre character varying, per_apellido character varying, per_ci character varying, re_mensual_suma interval, ra_80_mensual interval, ra_100_mensual interval)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        p.per_cod AS reg_cod_personal,
        p.per_nombre,
        p.per_apellido,
        p.per_ci,
        COALESCE(result.re_mensual_suma, '00:00:00'::interval) AS re_mensual_suma,
        COALESCE(result.ra_80_mensual, '00:00:00'::interval) AS ra_80_mensual,
        COALESCE(result.ra_100_mensual, '00:00:00'::interval) AS ra_100_mensual
    FROM 
        personales p
    LEFT JOIN LATERAL (
        SELECT 
            sub.re_mensual_suma, 
            sub.ra_80_mensual, 
            sub.ra_100_mensual
        FROM marcaciones_por_mes_horas(anio, mes, p.per_cod) AS sub
        WHERE sub.re_mensual_suma IS NOT NULL 
          AND sub.ra_80_mensual IS NOT NULL 
          AND sub.ra_100_mensual IS NOT NULL
        LIMIT 1
    ) AS result ON true
    WHERE 
       p.per_estado = 1 -- Considerando que "1" indica activo
    ORDER BY 
        p.per_cod;
END;
$function$
;

-- DROP FUNCTION public.horas_extras_mensuales2(int4, int4);

CREATE OR REPLACE FUNCTION public.horas_extras_mensuales2(anio integer, mes integer)
 RETURNS TABLE(reg_cod_personal integer, per_nombre character varying, per_apellido character varying, per_ci character varying, re_mensual_suma interval)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
    marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
                WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval) THEN e.reg_hora - (t.tur_entrada + p.par_valor_time)
                ELSE '00:00:00'::interval
            END AS reg_retraso,
            CASE
                WHEN e.reg_hora IS NULL THEN NULL::interval
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
           END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
    ),
    ocurrencias_filtradas AS (
        SELECT 
            subquery.reg_cod_personal,
            subquery.reg_fecha,
            STRING_AGG(subquery.ocu_descripcion::character varying, ', ' ORDER BY subquery.ocu_descripcion) AS ocu_descripcion,
            STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo) AS ocurrencia_tipo,
            MIN(subquery.ocu_tipo) AS ocu_tipo
        FROM (
            SELECT 
                o.ocu_cod_persona AS reg_cod_personal,
                generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
                o.ocu_descripcion,
                t.tip_descripcion AS ocurrencia_tipo,
                o.ocu_tipo
            FROM 
                ocurrencias o
            JOIN 
                tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
        ) AS subquery
        GROUP BY 
            subquery.reg_cod_personal, subquery.reg_fecha
    ),
    compensaciones_detalles_filtradas AS (
        SELECT 
            com_cod_personal,
            com_det_fecha,
            SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,
            SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,
            SUM(com_det_horas_restantes) AS com_det_horas_restantes,
            STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado
        FROM (
            SELECT 
                c.com_cod_personal,
                cd.com_det_fecha,
                cd.com_det_horas_a_compensar,
                cd.com_det_horas_compensadas,
                cd.com_det_horas_restantes,
                c.com_estado
            FROM 
                compensaciones_detalles cd
            JOIN 
                compensaciones_completas c ON cd.com_cod = c.com_cod
            WHERE 
                EXTRACT(YEAR FROM cd.com_det_fecha) = anio
                AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes
        ) sub
        GROUP BY 
            com_cod_personal, 
            com_det_fecha
    ),
    re_diaria AS (
       SELECT 
            c.date AS reg_fecha,
            COALESCE(p.reg_cod_personal,0) AS reg_cod_personal,
            CASE
                WHEN cd.com_det_horas_restantes IS NOT NULL THEN '00:00:00'::interval
                WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
                    SELECT 1
                    FROM ocurrencias_filtradas of
                    WHERE of.reg_fecha = c.date
                    AND of.ocu_tipo IN (33, 26, 12)
                ) THEN '00:00:00'::interval
                WHEN p.reg_retraso > '01:00:00'::interval AND EXISTS (
                    SELECT 1
                    FROM ocurrencias_filtradas of
                    WHERE of.reg_fecha = c.date
                    AND of.ocu_tipo IN (33, 26, 12)
                ) THEN
                    CASE
                        WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                            LEAST(
                                (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                                '02:00:00'::interval
                            )
                        ELSE '00:00:00'::interval
                    END
                WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                    LEAST(
                        p.reg_horas_trabajadas - '08:00:00'::interval,
                        '02:00:00'::interval
                    )
                ELSE '00:00:00'::interval
            END AS re
        FROM 
            calendar c
        LEFT JOIN 
            marcaciones_completas p ON c.date = p.reg_fecha
        LEFT JOIN 
            ocurrencias_filtradas of ON c.date = of.reg_fecha AND p.reg_cod_personal = of.reg_cod_personal
        LEFT JOIN 
            compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND p.reg_cod_personal = cd.com_cod_personal
    ),
    re_semanal AS (
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '08:00:00'::interval
            ) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    re_mensual AS (
        SELECT 
            rs.reg_cod_personal,
            LEAST(
                SUM(rs.re_semanal_suma),
                '32:00:00'::interval
            ) AS suma_re_mensual
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    )
    SELECT 
        rs.reg_cod_personal,
        p.per_nombre,
        p.per_apellido,
        p.per_ci,
        rs.suma_re_mensual AS re_mensual_suma
    FROM re_mensual rs
    JOIN personales p ON rs.reg_cod_personal = p.per_cod
    GROUP BY rs.reg_cod_personal, p.per_nombre, p.per_apellido, p.per_ci, rs.suma_re_mensual;
END;
$function$
;

-- DROP FUNCTION public.horas_extras_mensuales3(int4, int4);

CREATE OR REPLACE FUNCTION public.horas_extras_mensuales3(anio integer, mes integer)
 RETURNS TABLE(reg_cod_personal integer, per_nombre character varying, per_apellido character varying, per_ci character varying, re_mensual_suma interval)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
    marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
                WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval) THEN e.reg_hora - (t.tur_entrada + p.par_valor_time)
                ELSE '00:00:00'::interval
            END AS reg_retraso,
            CASE
                WHEN e.reg_hora IS NULL THEN NULL::interval
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
            END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
    ),
    ocurrencias_filtradas AS (
        SELECT 
            subquery.reg_cod_personal,
            subquery.reg_fecha,
            STRING_AGG(subquery.ocu_descripcion::character varying, ', ' ORDER BY subquery.ocu_descripcion) AS ocu_descripcion,
            STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo) AS ocurrencia_tipo,
            MIN(subquery.ocu_tipo) AS ocu_tipo
        FROM (
            SELECT 
                o.ocu_cod_persona AS reg_cod_personal,
                generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
                o.ocu_descripcion,
                t.tip_descripcion AS ocurrencia_tipo,
                o.ocu_tipo
            FROM 
                ocurrencias o
            JOIN 
                tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
        ) AS subquery
        GROUP BY 
            subquery.reg_cod_personal, subquery.reg_fecha
    ),
    feriados_filtrados AS (
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
    ),
    tolerancias_especiales_filtradas AS (
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I') 
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = te.tol_cod_personal))
    ),
    compensaciones_detalles_filtradas AS (
        SELECT 
            com_cod_personal,
            com_det_fecha,
            SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,
            SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,
            SUM(com_det_horas_restantes) AS com_det_horas_restantes,
            STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado
        FROM (
            SELECT 
                c.com_cod_personal,
                cd.com_det_fecha,
                cd.com_det_horas_a_compensar,
                cd.com_det_horas_compensadas,
                cd.com_det_horas_restantes,
                c.com_estado
            FROM 
                compensaciones_detalles cd
            JOIN 
                compensaciones_completas c ON cd.com_cod = c.com_cod
            WHERE 
                EXTRACT(YEAR FROM cd.com_det_fecha) = anio
                AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes
        ) sub
        GROUP BY 
            com_cod_personal, 
            com_det_fecha
    ),
    re_diaria AS (
        SELECT 
            c.date AS reg_fecha,
            p.reg_cod_personal,
            CASE
                WHEN cd.com_det_horas_restantes IS NOT NULL THEN '00:00:00'::interval
                WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
                    SELECT 1
                    FROM ocurrencias_filtradas of
                    WHERE of.reg_fecha = c.date
                    AND of.ocu_tipo IN (33, 26, 12)
                    AND of.reg_cod_personal = p.reg_cod_personal
                ) THEN '00:00:00'::interval
                WHEN p.reg_retraso > '01:00:00'::interval AND EXISTS (
                    SELECT 1
                    FROM ocurrencias_filtradas of
                    WHERE of.reg_fecha = c.date
                    AND of.ocu_tipo IN (33, 26, 12)
                    AND of.reg_cod_personal = p.reg_cod_personal
                ) THEN
                    CASE
                        WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                            LEAST(
                                (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                                '02:00:00'::interval
                            )
                        ELSE '00:00:00'::interval
                    END
                WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                    LEAST(
                        p.reg_horas_trabajadas - '08:00:00'::interval,
                        '02:00:00'::interval
                    )
                ELSE '00:00:00'::interval
            END AS re
        FROM 
            calendar c
        LEFT JOIN 
            marcaciones_completas p ON c.date = p.reg_fecha
        LEFT JOIN 
            compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND p.reg_cod_personal = cd.com_cod_personal
        LEFT JOIN 
            ocurrencias_filtradas of ON c.date = of.reg_fecha AND p.reg_cod_personal = of.reg_cod_personal
    ),
    re_semanal AS (
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '08:00:00'::interval
            ) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    re_mensual AS (
        SELECT 
            rs.reg_cod_personal,
            LEAST(
                SUM(rs.re_semanal_suma),
                '32:00:00'::interval
            ) AS re_mensual_suma
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    )
    SELECT 
        rs.reg_cod_personal,
        p.per_nombre,
        p.per_apellido,
        p.per_ci,
        rs.re_mensual_suma
    FROM re_mensual rs
    JOIN personales p ON rs.reg_cod_personal = p.per_cod
    ORDER BY rs.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.horas_funcionario(int4, date, time);

CREATE OR REPLACE FUNCTION public.horas_funcionario(funcionario_parametro integer, fecha_parametro date, horas_parametro time without time zone)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    cantidad_fechas INT;
BEGIN
    SELECT COUNT(*)
    INTO cantidad_fechas
    FROM horas_diarias
    WHERE hor_cod_personal = funcionario_parametro AND hor_fecha = fecha_parametro;

    IF cantidad_fechas > 0 THEN
        UPDATE horas_diarias
        SET hor_horas = CASE 
                            WHEN horas_parametro < TIME '00:00:00' THEN NULL
                            ELSE horas_parametro
                        END
        WHERE hor_cod_personal = funcionario_parametro AND hor_fecha = fecha_parametro AND hor_actualizar = 1;
    ELSE
        INSERT INTO horas_diarias (hor_cod_personal, hor_horas, hor_fecha)
        VALUES (
            funcionario_parametro,
            CASE 
                WHEN horas_parametro < TIME '00:00:00' THEN NULL
                ELSE horas_parametro
            END,
            fecha_parametro
        );
    END IF;

    RETURN 0;
END;
$function$
;

-- DROP FUNCTION public.horas_funcionarios(int4, date, time, time);

CREATE OR REPLACE FUNCTION public.horas_funcionarios(funcionario_parametro integer, fecha_parametro date, horas_parametro time without time zone, horas_100_parametro time without time zone)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    cantidad_fechas INT;
BEGIN
    SELECT COUNT(*)
    INTO cantidad_fechas
    FROM horas_diarias
    WHERE hor_cod_personal = funcionario_parametro AND hor_fecha = fecha_parametro;

    IF cantidad_fechas > 0 THEN
        UPDATE horas_diarias
        SET hor_horas = CASE 
                            WHEN horas_parametro < TIME '00:00:00' THEN NULL
                            ELSE horas_parametro
                        END,
            hor_horas_100 = CASE 
                            WHEN horas_100_parametro < TIME '00:00:00' THEN NULL
                            ELSE horas_100_parametro
                        END
        WHERE hor_cod_personal = funcionario_parametro AND hor_fecha = fecha_parametro AND hor_actualizar = 1;
    ELSE
        INSERT INTO horas_diarias (hor_cod_personal, hor_horas, hor_horas_100, hor_fecha)
        VALUES (
            funcionario_parametro,
            CASE 
                WHEN horas_parametro < TIME '00:00:00' THEN NULL
                ELSE horas_parametro
            END,
            CASE 
                WHEN horas_100_parametro < TIME '00:00:00' THEN NULL
                ELSE horas_100_parametro
            END,
            fecha_parametro
        );
    END IF;

    RETURN 0;
END;
$function$
;

-- DROP FUNCTION public.insert_compensaciones_completas();

CREATE OR REPLACE FUNCTION public.insert_compensaciones_completas()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO compensaciones_completas (
        com_cod_personal,
        com_fecha_generacion,
        com_mes,
        com_anio,
        com_horas_a_compensar,
        com_cod_ocurrencia
    )
    SELECT
        ocu_cod_persona,
        ocu_fecha_desde,  -- Fecha de generación como ocu_fecha_desde
        EXTRACT(MONTH FROM ocu_fecha_desde)::int,  -- Mes de ocu_fecha_desde
        EXTRACT(YEAR FROM ocu_fecha_desde)::int,  -- Año de ocu_fecha_desde
        ocu_horas_compensacion::interval,
        CASE 
            WHEN ocu_cod IS NOT NULL THEN ocu_cod 
            ELSE NULL 
        END  -- com_cod_ocurrencia puede ser NULL
    FROM
        ocurrencias
    WHERE
        ocu_horas_compensacion IS NOT NULL;
END;
$function$
;

-- DROP FUNCTION public.insertar_faltas(int4, int4, int4, int4, int4);

CREATE OR REPLACE FUNCTION public.insertar_faltas(funcionario_parametro integer, anho_parametro integer, mes_parametro integer, tipo_parametro integer, cantidad_parametro integer)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO faltas (
        fal_cod_personal,
        fal_cod_tipo,
        fal_cantidad,
        fal_anho,
        fal_mes,
        fal_fecha_actualizacion
    )
    VALUES (
        funcionario_parametro,
        tipo_parametro,
        cantidad_parametro,
        anho_parametro,
        mes_parametro,
        CURRENT_DATE
    );

    RETURN '0';
END;
$function$
;

-- DROP FUNCTION public.insertar_horas(int4, int4, int4, time, time, time);

CREATE OR REPLACE FUNCTION public.insertar_horas(funcionario_parametro integer, anho_parametro integer, mes_parametro integer, horas_extras_parametro time without time zone, horas_adicionales_parametro time without time zone, horas_adicionales_100_parametro time without time zone)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO horas_personales (
        hor_cod_personal,
        hor_anho,
        hor_mes,
        hor_extras,
        hor_adicional,
        hor_adicional_100,
        hor_fecha
    )
    VALUES (
        funcionario_parametro,
        anho_parametro,
        mes_parametro,
        horas_extras_parametro,
        horas_adicionales_parametro,
        horas_adicionales_100_parametro,
        CURRENT_DATE
    );

    RETURN '0';
END;
$function$
;

-- DROP FUNCTION public.insertar_marcacion(int4, date, time, int4, int4);

CREATE OR REPLACE FUNCTION public.insertar_marcacion(reg_cod_personal_parametro integer, reg_fecha_parametro date, reg_hora_parametro time without time zone, reg_tipo_parametro integer, reg_reloj_parametro integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    cantidad_actual INT;
BEGIN
    SELECT count(*)
    INTO cantidad_actual
    FROM registros_entrada_salida
    WHERE reg_cod_personal = reg_cod_personal_parametro
      AND reg_fecha = reg_fecha_parametro
      AND reg_hora = reg_hora_parametro::time
      AND reg_reloj = reg_reloj_parametro;

    IF cantidad_actual = 0 THEN
        INSERT INTO registros_entrada_salida (
            reg_cod_personal,
            reg_fecha,
            reg_hora,
            reg_tipo,
            reg_reloj
        ) VALUES (
            reg_cod_personal_parametro,
            reg_fecha_parametro,
            reg_hora_parametro,
            reg_tipo_parametro,
            reg_reloj_parametro
        );
    END IF;
END;
$function$
;

-- DROP FUNCTION public.insertar_ocu_tipo_grupo_digito();

CREATE OR REPLACE FUNCTION public.insertar_ocu_tipo_grupo_digito()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Asigna un valor a ocu_tipo_grupo_digito basado en la condición de ocu_tipo_grupo
    NEW.ocu_tipo_grupo_digito := CASE
        WHEN NEW.ocu_tipo_grupo = 'G' THEN 1
        ELSE 0
    END;
    RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_entre_fechas(int4, date, date);

CREATE OR REPLACE FUNCTION public.marcaciones_entre_fechas(param_reg_cod_personal integer, fecha_desde date, fecha_hasta date)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, re_semanal_suma interval, re_mensual_suma interval, dia_semana text, ocurrencia_descripcion character varying, ocurrencia_tipo character varying, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            fecha_desde::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' <= fecha_hasta
    ),
    marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
            END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
    ocurrencias_filtradas AS (
        SELECT 
            o.ocu_cod_persona AS reg_cod_personal,
            generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
            o.ocu_descripcion,
            t.tip_descripcion AS ocurrencia_tipo
        FROM 
            ocurrencias o
        JOIN 
            tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
        WHERE 
            o.ocu_cod_persona = param_reg_cod_personal
    ),
    feriados_filtrados AS (
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            f.fer_fecha BETWEEN fecha_desde AND fecha_hasta
    ),
    tolerancias_especiales_filtradas AS (
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
    ),
    re_diaria AS (
        SELECT 
            c.date AS reg_fecha,
            COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
            CASE
                WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                    LEAST(
                        p.reg_horas_trabajadas - '08:00:00'::interval,
                        '02:00:00'::interval
                    )
                ELSE '00:00:00'::interval
            END AS re
        FROM 
            calendar c
        LEFT JOIN 
            marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
        LEFT JOIN 
            ocurrencias_filtradas of ON c.date = of.reg_fecha
    )
    SELECT 
        r.reg_fecha,
        r.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
        r.re,
        LEAST(
		    COALESCE(
		        SUM(r.re) FILTER (WHERE EXTRACT(ISODOW FROM r.reg_fecha) <= 5) OVER (PARTITION BY EXTRACT(WEEK FROM r.reg_fecha)),
		        '00:00:00'::interval
		    ),
		    '08:00:00'::interval
		) AS re_semanal_suma,
        LEAST(
            SUM(
                r.re
            ) OVER (PARTITION BY EXTRACT(MONTH FROM r.reg_fecha)),
            '32:00:00'::interval
        ) AS re_mensual_suma,
        btrim(
            CASE
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
                ELSE NULL
            END
        ) AS dia_semana,
        of.ocu_descripcion AS ocurrencia_descripcion,
        of.ocurrencia_tipo AS ocurrencia_tipo,
        ff.feriado_descripcion AS feriado_descripcion,
        CASE
            WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
            WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
            ELSE NULL
        END AS tolerancia_especial
    FROM 
        re_diaria r
    LEFT JOIN 
        marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha
    LEFT JOIN 
        feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
    LEFT JOIN 
        tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
    ORDER BY 
        r.reg_fecha, r.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_informe_diario(date);

CREATE OR REPLACE FUNCTION public.marcaciones_informe_diario(fecha_parametro date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    CREATE TEMP TABLE marcaciones_temp AS
    SELECT
        personales.per_cod AS reg_cod_persona,
        CONCAT(personales.per_nombre, ' ', personales.per_apellido) AS reg_funcionario_nombre,
        fecha_parametro AS reg_fecha,
        registro_entrada.reg_reloj AS reg_reloj_entrada,
        CASE
            WHEN registro_entrada.reg_hora > (turnos.tur_entrada + parametros.par_valor::interval)
            THEN registro_entrada.reg_hora - (turnos.tur_entrada + parametros.par_valor::interval)
        END AS reg_retraso,
        registro_salida.reg_reloj AS reg_reloj_salida,
        registro_entrada.reg_hora AS reg_hora_entrada,
        registro_salida.reg_hora AS reg_hora_salida,
        reg_observacion,
        reg_observacion_desde,
        reg_observacion_hasta
    FROM
        personales_activos
        LEFT JOIN codigos_reloj ON personales.per_cod = codigos_reloj.rel_cod_persona
        LEFT JOIN (
            SELECT
                DISTINCT ON (reg_cod_personal)
                reg_hora,
                reg_cod_personal,
                reg_reloj
            FROM
                registros_entrada_salida
            WHERE
                reg_fecha = fecha_parametro
            ORDER BY
                reg_cod_personal,
                reg_hora
        ) AS registro_entrada ON registro_entrada.reg_cod_personal = codigos_reloj.rel_codigo AND registro_entrada.reg_reloj = codigos_reloj.rel_reloj
        AND fecha_parametro BETWEEN codigos_reloj.rel_fecha_desde AND codigos_reloj.rel_fecha_hasta
        LEFT JOIN (
            SELECT
                DISTINCT ON (reg_cod_personal)
                reg_hora,
                reg_cod_personal,
                reg_reloj
            FROM
                registros_entrada_salida
            WHERE
                reg_fecha = fecha_parametro
            ORDER BY
                reg_cod_personal,
                reg_hora DESC
        ) AS registro_salida ON registro_salida.reg_cod_personal = codigos_reloj.rel_codigo AND registro_salida.reg_reloj = codigos_reloj.rel_reloj
        AND fecha_parametro BETWEEN codigos_reloj.rel_fecha_desde AND codigos_reloj.rel_fecha_hasta
        LEFT JOIN turnos ON personales.per_cod = turnos.tur_cod_personal
            AND turnos.tur_fecha_hasta >= fecha_parametro
            AND turnos.tur_fecha_desde <= fecha_parametro
        CROSS JOIN (SELECT ''::text AS reg_observacion, ''::text AS reg_observacion_desde, ''::text AS reg_observacion_hasta) AS empty_observaciones;

    RETURN;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    )
    SELECT 
        c.date AS reg_fecha,
        p.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras
    FROM 
        calendar c
    LEFT JOIN (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha) AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ) p ON c.date = p.reg_fecha
    ORDER BY 
        c.date, p.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_horas(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, horas_a_compensar interval, horas_compensadas interval, horas_restantes interval, estado_compensacion character varying, re_semanal_suma interval, re_mensual_suma interval, re_acumulada_semanal interval, re_acumulada_mensual interval, ra interval, ra_semanal_suma interval, ra_mensual_suma interval, ra_80 interval, ra_100 interval, ra_80_semanal interval, ra_100_semanal interval, ra_80_mensual interval, ra_100_mensual interval, dia_semana text, ocurrencia_descripcion text, ocurrencia_tipo text, ocu_tipo integer, tip_codigo character varying, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
BEGIN
	PERFORM set_config('timezone', 'UTC', true);
    PERFORM set_config('DateStyle', 'ISO, DMY', true);
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal,
            t.tur_entrada,
            t.tur_salida,
            p.par_valor_time,
			t.tur_tipo,
			e.tol_tiempo_interval,	
            e.reg_hora AS reg_hora_entrada,
            s.reg_hora AS reg_hora_salida,
            CASE
                WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_entrada
                ELSE s.reg_hora - e.reg_hora
            END AS reg_horas_trabajadas,
            CASE
		       WHEN t.tur_tipo = 4 THEN '00:00:00'::interval
		       WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval + e.tol_tiempo_interval ) 
		       THEN e.reg_hora - (t.tur_entrada + p.par_valor_time + e.tol_tiempo_interval)
		    ELSE '00:00:00'::interval
		END AS reg_retraso,
            CASE
                WHEN e.reg_hora IS NULL THEN NULL::interval
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
            END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
ocurrencias_filtradas AS (
    SELECT 
        subquery.reg_cod_personal,
        subquery.reg_fecha,
        STRING_AGG(subquery.ocu_descripcion::text, ', ' ORDER BY subquery.ocu_descripcion)::text AS ocu_descripcion, 
        STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo)::text AS ocurrencia_tipo, 
        MIN(subquery.ocu_tipo) AS ocu_tipo,
        STRING_AGG(subquery.tip_codigo::character varying, ', ' ORDER BY subquery.tip_codigo)::character varying AS tip_codigo, 
        MAX(subquery.ocu_horas_estaticas) AS ocu_horas_estaticas,
        SUM(subquery.ocu_horas_extras) AS ocu_horas_extras,
        SUM(subquery.ocu_horas_adicionales) AS ocu_horas_adicionales,
        SUM(subquery.ocu_horas_adicionales_100) AS ocu_horas_adicionales_100
    FROM (
        SELECT 
            o.ocu_cod_persona AS reg_cod_personal,
              generate_series(
                GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1)), 
                LEAST(
                    CASE 
                        -- Mantener tus condiciones existentes
                        WHEN o.ocu_fecha_desde = o.ocu_fecha_hasta THEN o.ocu_fecha_hasta
                        ELSE o.ocu_fecha_hasta
                    END,
                    (make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date
                ) ,  -- Añadimos un día al límite superior
                '1 day'
            )::date AS reg_fecha,
            o.ocu_descripcion,
            t.tip_descripcion AS ocurrencia_tipo,
            t.tip_codigo,
            o.ocu_tipo,
            o.ocu_horas_estaticas,
            o.ocu_horas_extras,
            o.ocu_horas_adicionales,
            o.ocu_horas_adicionales_100
        FROM 
            ocurrencias o
        JOIN 
            tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
        WHERE 
            o.ocu_cod_persona = param_reg_cod_personal
            AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date
            AND o.ocu_fecha_hasta >= make_date(anio, mes, 1)
        ) AS subquery
    WHERE 
        NOT (
            subquery.ocu_tipo = 1 AND 
            (EXTRACT(DOW FROM subquery.reg_fecha::date) = 6 OR EXTRACT(DOW FROM subquery.reg_fecha::date) = 0)
        ) -- Excluir sábados (6) y domingos (0) para vacaciones
    GROUP BY 
        subquery.reg_cod_personal, 
        subquery.reg_fecha
), 
    feriados_filtrados AS (
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
    ),
tolerancias_especiales_filtradas AS (
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
    ), 
    compensaciones_detalles_filtradas AS (
        SELECT 
            com_cod_personal,
            com_det_fecha,
            SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,
            SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,
            SUM(com_det_horas_restantes) AS com_det_horas_restantes,
            STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado
        FROM (
            SELECT 
                c.com_cod_personal,
                cd.com_det_fecha,
                cd.com_det_horas_a_compensar,
                cd.com_det_horas_compensadas,
                cd.com_det_horas_restantes,
                c.com_estado
            FROM 
                compensaciones_detalles cd
            JOIN 
                compensaciones_completas c ON cd.com_cod = c.com_cod
            WHERE 
                c.com_cod_personal = param_reg_cod_personal
                AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio
                AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes
        ) sub
        GROUP BY 
            com_cod_personal, 
            com_det_fecha
    ),
re_diaria AS (
    SELECT 
        c.date AS reg_fecha,
        COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
        CASE
			-- Escenario excepcional HORAS ESTATICAS
			WHEN of.ocu_tipo = 12 AND of.ocu_horas_estaticas = 1 THEN of.ocu_horas_extras::interval	
            -- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras
            WHEN cd.com_det_horas_restantes > '00:00:00'::interval THEN '00:00:00'::interval

            -- Escenario 2: Si la persona llegó tarde (más de 1 hora) y no tiene permisos específicos, no se calculan horas extras
            WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN '00:00:00'::interval

  			-- Nuevo Escenario: Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
            WHEN EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo = 12
            ) AND p.reg_retraso > '00:59:59'::interval THEN
                CASE
                    WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                        LEAST(
                            (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                            '02:00:00'::interval
                        )
                    ELSE '00:00:00'::interval
                END

            -- Escenario 3: Si no hay horas pendientes, pero hay permisos específicos, calcular horas extras con reglas especiales
            WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN
                CASE
					WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval THEN
			            CASE
			                WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
			                    LEAST(
			                        (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
			                        '02:00:00'::interval
			                    )
			                ELSE '00:00:00'::interval
			            END
                    WHEN of.ocu_tipo = 29 THEN
                        CASE
                            WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > '09:00:00'::interval THEN
                                LEAST(
                                    (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - '08:00:00'::interval,
                                    '02:00:00'::interval
                                )
                            ELSE '00:00:00'::interval
                        END
                    ELSE
                        CASE
                            WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                                LEAST(
                                    (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                                    '02:00:00'::interval
                                )
                            ELSE '00:00:00'::interval
                        END
                END

            -- Escenario 4: Si no hay horas pendientes ni permisos, y además es parte de una seguidilla de días, no calcular horas extras
            WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN '00:00:00'::interval

            -- Escenario 5: Si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
            WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                LEAST(
                    p.reg_horas_trabajadas - '08:00:00'::interval,
                    '02:00:00'::interval
                )

            -- En caso contrario, las horas extras son 00:00:00
            ELSE '00:00:00'::interval
        END AS re,
        cd.com_det_horas_a_compensar AS horas_a_compensar,
        cd.com_det_horas_compensadas AS horas_compensadas,
        cd.com_det_horas_restantes AS horas_restantes,
        cd.com_estado::character varying AS estado_compensacion,
		p.reg_horas_trabajadas,
		p.reg_hora_salida,
		p.reg_retraso,
		of.ocu_tipo,
		of.ocu_horas_estaticas,
		of.ocu_horas_extras,
		of.ocu_horas_adicionales,
		of.ocu_horas_adicionales_100
    FROM 
        calendar c
    LEFT JOIN 
        marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal
    LEFT JOIN 
        compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal
),re_semanal AS (
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '08:00:00'::interval
            ) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    re_mensual AS (
        SELECT 
            rs.reg_cod_personal,
            LEAST(
                SUM(rs.re_semanal_suma),
                '32:00:00'::interval
            ) AS re_mensual_suma
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    ),
re_acumulada_semanal AS (
    -- CTE que acumula las RE semanalmente, reiniciando cada lunes (EXTRACT(ISODOW) = 1)
    SELECT 
        rd.reg_cod_personal,
        rd.reg_fecha,
        EXTRACT(WEEK FROM rd.reg_fecha) AS semana,
        rd.re,
        SUM(rd.re) OVER (PARTITION BY rd.reg_cod_personal, EXTRACT(YEAR FROM rd.reg_fecha), EXTRACT(WEEK FROM rd.reg_fecha) 
                         ORDER BY rd.reg_fecha ROWS UNBOUNDED PRECEDING) AS re_acumulada_semanal
    FROM 
        re_diaria rd
    WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5  -- Considerar solo días de lunes a viernes
	),
re_mensual_con_limited AS (
    -- Aplica un límite de 08:00 horas por semana a las RE
    SELECT
        rsa.reg_cod_personal,               -- Código de la persona
        rsa.reg_fecha,                      -- Fecha de la marcación
        rsa.re,
        -- Suma diaria limitada por la acumulación semanal (máximo 08:00 horas por semana)
        CASE
		    -- Si la acumulación semanal es mayor o igual a 08:00:00, no sumamos más horas
		    WHEN rsa.re_acumulada_semanal > '08:00:00'::interval THEN '00:00:00'::interval
		    -- Si la acumulación semanal es menor a 08:00:00, sumamos las horas RE restantes
		    ELSE rsa.re
		END AS re_con_limited
    FROM 
        re_acumulada_semanal rsa
),

re_acumulada_mensual AS (
    -- CTE que acumula las RE a lo largo del mes, respetando el límite de 08:00 horas por semana
    SELECT
        rml.reg_cod_personal,               -- Código de la persona
        rml.reg_fecha,                      -- Fecha de la marcación
        SUM(rml.re_con_limited) OVER (
            PARTITION BY rml.reg_cod_personal ORDER BY rml.reg_fecha
        ) AS re_acumulada_mensual           -- RE acumulada mensual con el tope semanal aplicado
    FROM 
        re_mensual_con_limited rml
),
ra AS (
    SELECT
        rd.reg_cod_personal,
        rd.reg_fecha,
		rd.reg_hora_salida,
        rd.reg_horas_trabajadas,
		rd.reg_retraso,  
		rd.ocu_tipo,
		rd.ocu_horas_estaticas,
		rd.ocu_horas_extras,
		rd.ocu_horas_adicionales,
		rd.ocu_horas_adicionales_100,
        -- Cálculo de horas adicionales (RA) basado en las validaciones de RE semanal y mensual
        CASE
			-- Escenario excepcional HORAS ESTATICAS
			WHEN rd.ocu_tipo = 12 AND rd.ocu_horas_estaticas = 1 THEN rd.ocu_horas_adicionales::interval+rd.ocu_horas_adicionales_100::interval
			-- Si es sábado, el RA será el total de horas trabajadas sin importar el retraso
			WHEN EXTRACT(ISODOW FROM rd.reg_fecha) = 6 THEN rd.reg_horas_trabajadas
			--si no hay re 
			WHEN rd.re < '01:00:00'::interval THEN '00:00:00'::interval		
 			-- Si tiene retraso mayor a 00:00:59 y no es sábado, no sumamos horas RA
			--WHEN rd.reg_retraso > '00:00:59'::interval THEN '00:00:00'::interval
            -- Validación: Si la RE acumulada semanal es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
            WHEN ras.re_acumulada_semanal > '08:00:00'::interval THEN
                CASE
                    WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
					THEN rd.reg_horas_trabajadas  - '08:00:00'::interval
                    ELSE '00:00:00'::interval
                END
            -- Validación: Si la RE acumulada mensual es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
            WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval THEN
               CASE
                    WHEN rd.reg_horas_trabajadas > '09:00:00'::interval THEN rd.reg_horas_trabajadas - '09:00:00'::interval
                   ELSE '00:00:00'::interval
                END
            -- Validación para RE mensual mayor a 34 horas
            WHEN ram.re_acumulada_mensual > '34:00:00'::interval THEN
               CASE
                    WHEN rd.reg_horas_trabajadas > '09:00:00'::interval THEN rd.reg_horas_trabajadas - '08:00:00'::interval
                   ELSE '00:00:00'::interval
                END
            -- Cálculo general: Si ninguna de las validaciones anteriores aplica, se calcula RA si las horas trabajadas son más de 10:00:00
            ELSE
                CASE
                    WHEN rd.reg_horas_trabajadas > '10:00:00'::interval THEN rd.reg_horas_trabajadas - '10:00:00'::interval
                    ELSE '00:00:00'::interval
                END
        END AS ra	 
    FROM 
        re_diaria rd
    LEFT JOIN 
        re_acumulada_semanal ras ON rd.reg_cod_personal = ras.reg_cod_personal AND rd.reg_fecha = ras.reg_fecha
    LEFT JOIN 
        re_acumulada_mensual ram ON rd.reg_cod_personal = ram.reg_cod_personal AND rd.reg_fecha = ram.reg_fecha
),
ra_semanal_suma AS (
    SELECT 
        rd.reg_cod_personal,
        EXTRACT(WEEK FROM rd.reg_fecha) AS week,
        SUM(
            CASE
                -- Sumar directamente las horas adicionales (RA) sin límite o tope
                WHEN rd.ra IS NOT NULL THEN rd.ra
                ELSE '00:00:00'::interval
            END
        ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_semanal_suma
    FROM ra rd
    GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
),
   ra_mensual_suma AS (
        SELECT 
    		rs.reg_cod_personal,
    		SUM(rs.ra_semanal_suma) AS ra_mensual_suma
		FROM 
    		ra_semanal_suma rs
		GROUP BY 
    	rs.reg_cod_personal
    ),
	ra_dividida AS (
	    SELECT
	        ra.reg_cod_personal,
	        ra.reg_fecha,
	        ra.ra,  -- El valor de RA calculado previamente
	        ra.reg_hora_salida, -- Hora de salida
			ra.reg_horas_trabajadas,
			ra.ocu_tipo,
			ra.ocu_horas_estaticas,
			ra.ocu_horas_extras,
			ra.ocu_horas_adicionales,
			ra.ocu_horas_adicionales_100,
	        
	        -- Cálculo de RA_80 (hasta las 19:59:59)
	        CASE
				--Calculo excepcional ocu tipo 12  horas estaticas
				WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 THEN ra.ocu_horas_adicionales::interval
 				-- Si es sábado, RA_80 es siempre '00:00:00'
            	WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 THEN '00:00:00'::interval
	            -- Si la hora de salida es menor o igual a las 19:59:59, todo RA se contabiliza en RA_80
	            WHEN ra.reg_hora_salida <= '19:59:59'::time THEN ra.ra
	            -- Si la hora de salida es después de las 19:59:59, calculamos cuánto tiempo adicional fue antes de las 19:59:59
	            ELSE 
	                 ra.ra - (ra.reg_hora_salida - '19:59:59'::time)::interval
	        END AS ra_80,
	        
	        -- Cálculo de RA_100 (después de las 19:59:59)
	        CASE
				--Calculo excepcional ocu tipo 12  horas estaticas
				WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 THEN ra.ocu_horas_adicionales_100::interval
				-- Si es sábado (día de la semana = 6) y hay horas trabajadas, todo RA se asigna a RA_100
            	WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 THEN ra.reg_horas_trabajadas
	            -- Si la hora de salida es después de las 19:59:59, calculamos RA_100
	            WHEN ra.reg_hora_salida > '19:59:59'::time THEN
	              LEAST(ra.ra, (ra.reg_hora_salida - '19:59:59'::time)::interval)
	            -- Si la hora de salida es antes de las 19:59:59, no hay RA_100
	            ELSE '00:00:00'::interval
	        END AS ra_100
	
	    FROM 
	        ra  -- Utilizamos el CTE `ra` previamente calculado para obtener los valores de RA
	),
ra_divida_semanal_suma AS (
    SELECT 
        rd.reg_cod_personal,
        EXTRACT(WEEK FROM rd.reg_fecha) AS week,
        SUM(
            CASE
                -- Sumar directamente las horas adicionales (RA) sin límite o tope  Sumar solo si rd.ra_80 es mayor que '00:00:00'
                WHEN rd.ra_80 IS NOT NULL AND rd.ra_80 > '00:00:00'::interval THEN rd.ra_80
                ELSE '00:00:00'::interval
            END
        ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal,
		SUM(
            CASE
                -- Sumar directamente las horas adicionales (RA) sin límite o tope
                WHEN rd.ra_100 IS NOT NULL THEN rd.ra_100
                ELSE '00:00:00'::interval
            END
        ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal
    	FROM ra_dividida rd
    	GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
 	ra_dividia_mensual_suma AS (
        SELECT 
    		rs.reg_cod_personal,
    		SUM(rs.ra_80_semanal) AS ra_80_mensual,
			SUM(rs.ra_100_semanal) AS ra_100_mensual
		FROM 
    		ra_divida_semanal_suma rs
		GROUP BY 
    	rs.reg_cod_personal
    ),
re_recalculada AS (
    SELECT
        ras.reg_cod_personal,
        ras.reg_fecha,
        rd.reg_horas_trabajadas,
        ras.re,
        ras.re_acumulada_semanal,
        CASE
            -- Verifica si `re_acumulada_semanal` es mayor o igual a 08:00:00
            WHEN ras.re_acumulada_semanal >= '08:00:00'::interval THEN
                CASE
                    WHEN rd.reg_horas_trabajadas > '09:00:00'::interval THEN
                        ras.re - (ras.re_acumulada_semanal - '08:00:00'::interval)
                    ELSE
                        '00:00:00'::interval
                END
            ELSE
                -- Si `re_acumulada_semanal` no es mayor o igual a 08:00:00, simplemente devuelve `re` original
                '00:00:00'::interval
        END AS re_recalculada
    FROM
        re_acumulada_semanal ras
    JOIN
        re_diaria rd ON ras.reg_cod_personal = rd.reg_cod_personal AND ras.reg_fecha = rd.reg_fecha
)
    SELECT 
        r.reg_fecha,
        r.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
          -- Utilizamos 're_recalculada' si es diferente de '00:00:00', de lo contrario, usamos 'r.re'
        CASE
            WHEN re_rec.re_recalculada <> '00:00:00'::interval THEN re_rec.re_recalculada
            ELSE r.re
        END AS re,
        r.horas_a_compensar,
        r.horas_compensadas,
        r.horas_restantes,
        r.estado_compensacion,
        s.re_semanal_suma,
        m.re_mensual_suma,
		ra_semanal.re_acumulada_semanal, 
		ra_mensual.re_acumulada_mensual,
		ra.ra AS horas_adicionales,
		ras.ra_semanal_suma,
		ma.ra_mensual_suma,
 		ra_dividida.ra_80,  
    	ra_dividida.ra_100,  
		rds.ra_80_semanal,
		rds.ra_100_semanal,
		rdm.ra_80_mensual,
		rdm.ra_100_mensual,
        btrim(
            CASE
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
                ELSE NULL
            END
        ) AS dia_semana,
        of.ocu_descripcion AS ocurrencia_descripcion,
        of.ocurrencia_tipo,
		of.ocu_tipo,
		of.tip_codigo,
        ff.feriado_descripcion,
        CASE
            WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            ELSE NULL
        END AS tolerancia_especial
    FROM 
        re_diaria r
    LEFT JOIN 
        marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
 	LEFT JOIN 
        re_recalculada re_rec ON r.reg_cod_personal = re_rec.reg_cod_personal AND r.reg_fecha = re_rec.reg_fecha
    LEFT JOIN 
        ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
    LEFT JOIN 
        feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
    LEFT JOIN 
        tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
    LEFT JOIN 
        re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
    LEFT JOIN 
        re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
	LEFT JOIN 
    	re_acumulada_semanal ra_semanal ON r.reg_cod_personal = ra_semanal.reg_cod_personal AND r.reg_fecha = ra_semanal.reg_fecha
	LEFT JOIN 
    	re_acumulada_mensual ra_mensual ON r.reg_cod_personal = ra_mensual.reg_cod_personal AND r.reg_fecha = ra_mensual.reg_fecha
	LEFT JOIN 
    	ra ra ON r.reg_cod_personal = ra.reg_cod_personal AND r.reg_fecha = ra.reg_fecha
	LEFT JOIN 
    	ra_dividida ON ra.reg_cod_personal = ra_dividida.reg_cod_personal AND ra.reg_fecha = ra_dividida.reg_fecha
	LEFT JOIN 
    	ra_semanal_suma ras ON r.reg_cod_personal = ras.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = ras.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
	 LEFT JOIN 
        ra_mensual_suma ma ON r.reg_cod_personal = ma.reg_cod_personal
	LEFT JOIN 
    	ra_divida_semanal_suma rds ON r.reg_cod_personal = rds.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = rds.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
   LEFT JOIN 
        ra_dividia_mensual_suma rdm ON r.reg_cod_personal = rdm.reg_cod_personal
    ORDER BY 
        r.reg_fecha, r.reg_cod_personal;
END; 
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_horas2(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas2(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, horas_a_compensar interval, horas_compensadas interval, horas_restantes interval, estado_compensacion character varying, re_semanal_suma interval, re_mensual_suma interval, dia_semana text, ocurrencia_descripcion character varying, ocurrencia_tipo character varying, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
    marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
            END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
    ocurrencias_filtradas AS (
        SELECT 
            o.ocu_cod_persona AS reg_cod_personal,
            generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
            o.ocu_descripcion,
            t.tip_descripcion AS ocurrencia_tipo,
            t.tip_cod AS ocurrencia_codigo
        FROM 
            ocurrencias o
        JOIN 
            tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
        WHERE 
            o.ocu_cod_persona = param_reg_cod_personal
    ),
    feriados_filtrados AS (
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
    ),
    tolerancias_especiales_filtradas AS (
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
    ),
    compensaciones_detalles_filtradas AS (
        SELECT 
            c.com_cod_personal,
            cd.com_det_fecha,
            cd.com_det_horas_a_compensar,
            cd.com_det_horas_compensadas,
            cd.com_det_horas_restantes,
            c.com_estado
        FROM 
            compensaciones_detalles cd
        JOIN 
            compensaciones_completas c ON cd.com_cod = c.com_cod
        WHERE 
            c.com_cod_personal = param_reg_cod_personal
            AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio
            AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes
    ),
    re_diaria AS (
        SELECT 
            c.date AS reg_fecha,
            COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
            CASE
                WHEN cd.com_det_horas_restantes IS NOT NULL THEN '00:00:00'::interval
                WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
                    SELECT 1
                    FROM ocurrencias_filtradas of
                    WHERE of.reg_fecha = c.date
                    AND of.ocurrencia_codigo IN (33, 26, 12)
                ) THEN '00:00:00'::interval
                WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                    LEAST(
                        p.reg_horas_trabajadas - '08:00:00'::interval,
                        '02:00:00'::interval
                    )
                ELSE '00:00:00'::interval
            END AS re,
            cd.com_det_horas_a_compensar AS horas_a_compensar,
            cd.com_det_horas_compensadas AS horas_compensadas,
            cd.com_det_horas_restantes AS horas_restantes,
            cd.com_estado AS estado_compensacion
        FROM 
            calendar c
        LEFT JOIN 
            marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
        LEFT JOIN 
            ocurrencias_filtradas of ON c.date = of.reg_fecha
        LEFT JOIN 
            compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND c.date = p.reg_fecha
    ),
    re_semanal AS (
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '08:00:00'::interval
            ) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    re_mensual AS (
        SELECT 
            rs.reg_cod_personal,
            LEAST(
                SUM(rs.re_semanal_suma),
                '32:00:00'::interval
            ) AS re_mensual_suma
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    )
    SELECT 
        r.reg_fecha,
        r.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
        r.re,
        r.horas_a_compensar,
        r.horas_compensadas,
        r.horas_restantes,
        r.estado_compensacion,
        s.re_semanal_suma,
        m.re_mensual_suma,
        btrim(
            CASE
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
                ELSE NULL
            END
        ) AS dia_semana,
        of.ocu_descripcion AS ocurrencia_descripcion,
        of.ocurrencia_tipo AS ocurrencia_tipo,
        ff.feriado_descripcion AS feriado_descripcion,
        CASE
            WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
            WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
            ELSE NULL
        END AS tolerancia_especial
    FROM 
        re_diaria r
    LEFT JOIN 
        marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
    LEFT JOIN 
        feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
    LEFT JOIN 
        tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
    LEFT JOIN 
        re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
    LEFT JOIN 
        re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
    ORDER BY 
        r.reg_fecha, r.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_horas3(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas3(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, horas_a_compensar interval, horas_compensadas interval, horas_restantes interval, estado_compensacion character varying, re_semanal_suma interval, re_mensual_suma interval, dia_semana text, ocurrencia_descripcion text, ocurrencia_tipo text, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
    marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
                WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval) THEN e.reg_hora - (t.tur_entrada + p.par_valor_time)
                ELSE '00:00:00'::interval
            END AS reg_retraso,
            CASE
                WHEN e.reg_hora IS NULL THEN NULL::interval
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
            END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
    ocurrencias_filtradas AS (
        SELECT 
            subquery.reg_cod_personal,
            subquery.reg_fecha,
            STRING_AGG(subquery.ocu_descripcion::character varying, ', ' ORDER BY subquery.ocu_descripcion) AS ocu_descripcion,
			STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo) AS ocurrencia_tipo,
            MIN(subquery.ocu_tipo) AS ocu_tipo
        FROM (
            SELECT 
                o.ocu_cod_persona AS reg_cod_personal,
                generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
                o.ocu_descripcion,
				t.tip_descripcion AS ocurrencia_tipo,
                o.ocu_tipo
                
            FROM 
                ocurrencias o
            JOIN 
                tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
            WHERE 
                o.ocu_cod_persona = param_reg_cod_personal
        ) AS subquery
        GROUP BY 
            subquery.reg_cod_personal, subquery.reg_fecha
    ),
    feriados_filtrados AS (
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
    ),
    tolerancias_especiales_filtradas AS (
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
    ),
    compensaciones_detalles_filtradas AS (
        SELECT 
            com_cod_personal,
            com_det_fecha,
            SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,
            SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,
            SUM(com_det_horas_restantes) AS com_det_horas_restantes,
            STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado
        FROM (
            SELECT 
                c.com_cod_personal,
                cd.com_det_fecha,
                cd.com_det_horas_a_compensar,
                cd.com_det_horas_compensadas,
                cd.com_det_horas_restantes,
                c.com_estado
            FROM 
                compensaciones_detalles cd
            JOIN 
                compensaciones_completas c ON cd.com_cod = c.com_cod
            WHERE 
                c.com_cod_personal = param_reg_cod_personal
                AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio
                AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes
        ) sub
        GROUP BY 
            com_cod_personal, 
            com_det_fecha
    ),
re_diaria AS (
    SELECT 
        c.date AS reg_fecha,
        COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
        CASE
            -- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras
            WHEN cd.com_det_horas_restantes > '00:00:00'::interval THEN '00:00:00'::interval

            -- Escenario 2: Si la persona llegó tarde (más de 1 hora) y no tiene permisos específicos, no se calculan horas extras
            WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN '00:00:00'::interval

  			-- Nuevo Escenario: Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
            WHEN EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo = 12
            ) AND p.reg_retraso > '00:59:59'::interval THEN
                CASE
                    WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                        LEAST(
                            (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                            '02:00:00'::interval
                        )
                    ELSE '00:00:00'::interval
                END

            -- Escenario 3: Si no hay horas pendientes, pero hay permisos específicos, calcular horas extras con reglas especiales
            WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN
                CASE
					WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval THEN
			            CASE
			                WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
			                    LEAST(
			                        (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
			                        '02:00:00'::interval
			                    )
			                ELSE '00:00:00'::interval
			            END
                    WHEN of.ocu_tipo = 29 THEN
                        CASE
                            WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > '09:00:00'::interval THEN
                                LEAST(
                                    (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - '08:00:00'::interval,
                                    '02:00:00'::interval
                                )
                            ELSE '00:00:00'::interval
                        END
                    ELSE
                        CASE
                            WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                                LEAST(
                                    (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                                    '02:00:00'::interval
                                )
                            ELSE '00:00:00'::interval
                        END
                END

            -- Escenario 4: Si no hay horas pendientes ni permisos, y además es parte de una seguidilla de días, no calcular horas extras
            WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN '00:00:00'::interval

            -- Escenario 5: Si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
            WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                LEAST(
                    p.reg_horas_trabajadas - '08:00:00'::interval,
                    '02:00:00'::interval
                )

            -- En caso contrario, las horas extras son 00:00:00
            ELSE '00:00:00'::interval
        END AS re,
        cd.com_det_horas_a_compensar AS horas_a_compensar,
        cd.com_det_horas_compensadas AS horas_compensadas,
        cd.com_det_horas_restantes AS horas_restantes,
        cd.com_estado::character varying AS estado_compensacion
    FROM 
        calendar c
    LEFT JOIN 
        marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal
    LEFT JOIN 
        compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal
),re_semanal AS (
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '08:00:00'::interval
            ) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    re_mensual AS (
        SELECT 
            rs.reg_cod_personal,
            LEAST(
                SUM(rs.re_semanal_suma),
                '32:00:00'::interval
            ) AS re_mensual_suma
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    )
    SELECT 
        r.reg_fecha,
        r.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
        r.re,
        r.horas_a_compensar,
        r.horas_compensadas,
        r.horas_restantes,
        r.estado_compensacion,
        s.re_semanal_suma,
        m.re_mensual_suma,
        btrim(
            CASE
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
                ELSE NULL
            END
        ) AS dia_semana,
        of.ocu_descripcion AS ocurrencia_descripcion,
        of.ocurrencia_tipo,
        ff.feriado_descripcion,
        CASE
            WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            ELSE NULL
        END AS tolerancia_especial
    FROM 
        re_diaria r
    LEFT JOIN 
        marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
    LEFT JOIN 
        feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
    LEFT JOIN 
        tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
    LEFT JOIN 
        re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
    LEFT JOIN 
        re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
    ORDER BY 
        r.reg_fecha, r.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_horas5(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas5(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, horas_a_compensar interval, horas_compensadas interval, horas_restantes interval, estado_compensacion character varying, re_semanal_suma interval, re_mensual_suma interval, re_acumulada_semanal interval, re_acumulada_mensual interval, ra interval, ra_semanal_suma interval, ra_mensual_suma interval, ra_80 interval, ra_100 interval, ra_80_semanal interval, ra_100_semanal interval, ra_80_mensual interval, ra_100_mensual interval, dia_semana text, ocurrencia_descripcion text, ocurrencia_tipo text, ocu_tipo integer, tip_codigo character varying, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
BEGIN
	PERFORM set_config('timezone', 'UTC', true);
    PERFORM set_config('DateStyle', 'ISO, DMY', true);
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal,
            t.tur_entrada,
            t.tur_salida,
            p.par_valor_time,
			t.tur_tipo,
			e.tol_tiempo_interval,	
            e.reg_hora AS reg_hora_entrada,
            s.reg_hora AS reg_hora_salida,
            CASE
                WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_entrada
                ELSE s.reg_hora - e.reg_hora
            END AS reg_horas_trabajadas,
            CASE
		       WHEN t.tur_tipo = 4 THEN '00:00:00'::interval
		       WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval + e.tol_tiempo_interval ) 
		       THEN e.reg_hora - (t.tur_entrada + p.par_valor_time + e.tol_tiempo_interval)
		    ELSE '00:00:00'::interval
		END AS reg_retraso,
            CASE
                WHEN e.reg_hora IS NULL THEN NULL::interval
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
            END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
ocurrencias_filtradas AS (
    SELECT 
        subquery.reg_cod_personal,
        subquery.reg_fecha,
        STRING_AGG(subquery.ocu_descripcion::text, ', ' ORDER BY subquery.ocu_descripcion)::text AS ocu_descripcion, 
        STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo)::text AS ocurrencia_tipo, 
        MIN(subquery.ocu_tipo) AS ocu_tipo,
        STRING_AGG(subquery.tip_codigo::character varying, ', ' ORDER BY subquery.tip_codigo)::character varying AS tip_codigo, 
        MAX(subquery.ocu_horas_estaticas) AS ocu_horas_estaticas,
        SUM(subquery.ocu_horas_extras) AS ocu_horas_extras,
        SUM(subquery.ocu_horas_adicionales) AS ocu_horas_adicionales,
        SUM(subquery.ocu_horas_adicionales_100) AS ocu_horas_adicionales_100
    FROM (
        SELECT 
            o.ocu_cod_persona AS reg_cod_personal,
              generate_series(
                GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1)), 
                LEAST(
                    CASE 
                        -- Mantener tus condiciones existentes
                        WHEN o.ocu_fecha_desde = o.ocu_fecha_hasta THEN o.ocu_fecha_hasta
                        ELSE o.ocu_fecha_hasta
                    END,
                    (make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date
                ) ,  -- Añadimos un día al límite superior
                '1 day'
            )::date AS reg_fecha,
            o.ocu_descripcion,
            t.tip_descripcion AS ocurrencia_tipo,
            t.tip_codigo,
            o.ocu_tipo,
            o.ocu_horas_estaticas,
            o.ocu_horas_extras,
            o.ocu_horas_adicionales,
            o.ocu_horas_adicionales_100
        FROM 
            ocurrencias o
        JOIN 
            tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
        WHERE 
            o.ocu_cod_persona = param_reg_cod_personal
            AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date
            AND o.ocu_fecha_hasta >= make_date(anio, mes, 1)
        ) AS subquery
    WHERE 
        NOT (
            subquery.ocu_tipo = 1 AND 
            (EXTRACT(DOW FROM subquery.reg_fecha::date) = 6 OR EXTRACT(DOW FROM subquery.reg_fecha::date) = 0)
        ) -- Excluir sábados (6) y domingos (0) para vacaciones
    GROUP BY 
        subquery.reg_cod_personal, 
        subquery.reg_fecha
), 
    feriados_filtrados AS (
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
    ),
tolerancias_especiales_filtradas AS (
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
    ), 
    compensaciones_detalles_filtradas AS (
        SELECT 
            com_cod_personal,
            com_det_fecha,
            SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,
            SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,
            SUM(com_det_horas_restantes) AS com_det_horas_restantes,
            STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado
        FROM (
            SELECT 
                c.com_cod_personal,
                cd.com_det_fecha,
                cd.com_det_horas_a_compensar,
                cd.com_det_horas_compensadas,
                cd.com_det_horas_restantes,
                c.com_estado
            FROM 
                compensaciones_detalles cd
            JOIN 
                compensaciones_completas c ON cd.com_cod = c.com_cod
            WHERE 
                c.com_cod_personal = param_reg_cod_personal
                AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio
                AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes
        ) sub
        GROUP BY 
            com_cod_personal, 
            com_det_fecha
    ),
re_diaria AS (
    SELECT 
        c.date AS reg_fecha,
        COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
        CASE
			-- Escenario excepcional HORAS ESTATICAS
			WHEN of.ocu_tipo = 12 AND of.ocu_horas_estaticas = 1 THEN of.ocu_horas_extras::interval	
            -- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras
            WHEN cd.com_det_horas_restantes > '00:00:00'::interval THEN '00:00:00'::interval

            -- Escenario 2: Si la persona llegó tarde (más de 1 hora) y no tiene permisos específicos, no se calculan horas extras
            WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN '00:00:00'::interval

  			-- Nuevo Escenario: Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
            WHEN EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo = 12
            ) AND p.reg_retraso > '00:59:59'::interval THEN
                CASE
                    WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                        LEAST(
                            (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                            '02:00:00'::interval
                        )
                    ELSE '00:00:00'::interval
                END

            -- Escenario 3: Si no hay horas pendientes, pero hay permisos específicos, calcular horas extras con reglas especiales
            WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN
                CASE
					WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval THEN
			            CASE
			                WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
			                    LEAST(
			                        (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
			                        '02:00:00'::interval
			                    )
			                ELSE '00:00:00'::interval
			            END
                    WHEN of.ocu_tipo = 29 THEN
                        CASE
                            WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > '09:00:00'::interval THEN
                                LEAST(
                                    (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - '08:00:00'::interval,
                                    '02:00:00'::interval
                                )
                            ELSE '00:00:00'::interval
                        END
                    ELSE
                        CASE
                            WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                                LEAST(
                                    (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                                    '02:00:00'::interval
                                )
                            ELSE '00:00:00'::interval
                        END
                END

            -- Escenario 4: Si no hay horas pendientes ni permisos, y además es parte de una seguidilla de días, no calcular horas extras
            WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN '00:00:00'::interval

            -- Escenario 5: Si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
            WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                LEAST(
                    p.reg_horas_trabajadas - '08:00:00'::interval,
                    '02:00:00'::interval
                )

            -- En caso contrario, las horas extras son 00:00:00
            ELSE '00:00:00'::interval
        END AS re,
        cd.com_det_horas_a_compensar AS horas_a_compensar,
        cd.com_det_horas_compensadas AS horas_compensadas,
        cd.com_det_horas_restantes AS horas_restantes,
        cd.com_estado::character varying AS estado_compensacion,
		p.reg_horas_trabajadas,
		p.reg_hora_salida,
		p.reg_retraso,
		of.ocu_tipo,
		of.ocu_horas_estaticas,
		of.ocu_horas_extras,
		of.ocu_horas_adicionales,
		of.ocu_horas_adicionales_100
    FROM 
        calendar c
    LEFT JOIN 
        marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal
    LEFT JOIN 
        compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal
),re_semanal AS (
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '08:00:00'::interval
            ) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    re_mensual AS (
        SELECT 
            rs.reg_cod_personal,
            LEAST(
                SUM(rs.re_semanal_suma),
                '32:00:00'::interval
            ) AS re_mensual_suma
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    ),
re_acumulada_semanal AS (
    -- CTE que acumula las RE semanalmente, reiniciando cada lunes (EXTRACT(ISODOW) = 1)
    SELECT 
        rd.reg_cod_personal,
        rd.reg_fecha,
        EXTRACT(WEEK FROM rd.reg_fecha) AS semana,
        rd.re,
        SUM(rd.re) OVER (PARTITION BY rd.reg_cod_personal, EXTRACT(YEAR FROM rd.reg_fecha), EXTRACT(WEEK FROM rd.reg_fecha) 
                         ORDER BY rd.reg_fecha ROWS UNBOUNDED PRECEDING) AS re_acumulada_semanal
    FROM 
        re_diaria rd
    WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5  -- Considerar solo días de lunes a viernes
	),
re_mensual_con_limited AS (
    -- Aplica un límite de 08:00 horas por semana a las RE
    SELECT
        rsa.reg_cod_personal,               -- Código de la persona
        rsa.reg_fecha,                      -- Fecha de la marcación
        rsa.re,
        -- Suma diaria limitada por la acumulación semanal (máximo 08:00 horas por semana)
        CASE
		    -- Si la acumulación semanal es mayor o igual a 08:00:00, no sumamos más horas
		    WHEN rsa.re_acumulada_semanal > '08:00:00'::interval THEN '00:00:00'::interval
		    -- Si la acumulación semanal es menor a 08:00:00, sumamos las horas RE restantes
		    ELSE rsa.re
		END AS re_con_limited
    FROM 
        re_acumulada_semanal rsa
),

re_acumulada_mensual AS (
    -- CTE que acumula las RE a lo largo del mes, respetando el límite de 08:00 horas por semana
    SELECT
        rml.reg_cod_personal,               -- Código de la persona
        rml.reg_fecha,                      -- Fecha de la marcación
        SUM(rml.re_con_limited) OVER (
            PARTITION BY rml.reg_cod_personal ORDER BY rml.reg_fecha
        ) AS re_acumulada_mensual           -- RE acumulada mensual con el tope semanal aplicado
    FROM 
        re_mensual_con_limited rml
),
ra AS (
    SELECT
        rd.reg_cod_personal,
        rd.reg_fecha,
		rd.reg_hora_salida,
        rd.reg_horas_trabajadas,
		rd.reg_retraso,  
		rd.ocu_tipo,
		rd.ocu_horas_estaticas,
		rd.ocu_horas_extras,
		rd.ocu_horas_adicionales,
		rd.ocu_horas_adicionales_100,
        -- Cálculo de horas adicionales (RA) basado en las validaciones de RE semanal y mensual
        CASE
			-- Escenario excepcional HORAS ESTATICAS
			WHEN rd.ocu_tipo = 12 AND rd.ocu_horas_estaticas = 1 THEN rd.ocu_horas_adicionales::interval+rd.ocu_horas_adicionales_100::interval
			-- Si es sábado, el RA será el total de horas trabajadas sin importar el retraso
			WHEN EXTRACT(ISODOW FROM rd.reg_fecha) = 6 THEN rd.reg_horas_trabajadas
			--si no hay re 
			WHEN rd.re < '01:00:00'::interval THEN '00:00:00'::interval		
 			-- Si tiene retraso mayor a 00:00:59 y no es sábado, no sumamos horas RA
			--WHEN rd.reg_retraso > '00:00:59'::interval THEN '00:00:00'::interval
            -- Validación: Si la RE acumulada semanal es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
            WHEN ras.re_acumulada_semanal > '08:00:00'::interval THEN
                CASE
                    WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
					THEN rd.reg_horas_trabajadas  - '08:00:00'::interval
                    ELSE '00:00:00'::interval
                END
            -- Validación: Si la RE acumulada mensual es mayor o igual a 08:00:00, calculamos RA restando desde 09:00:00
            WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval THEN
               CASE
                    WHEN rd.reg_horas_trabajadas > '09:00:00'::interval THEN rd.reg_horas_trabajadas - '09:00:00'::interval
                   ELSE '00:00:00'::interval
                END
            -- Validación para RE mensual mayor a 34 horas
            WHEN ram.re_acumulada_mensual > '34:00:00'::interval THEN
               CASE
                    WHEN rd.reg_horas_trabajadas > '09:00:00'::interval THEN rd.reg_horas_trabajadas - '08:00:00'::interval
                   ELSE '00:00:00'::interval
                END
            -- Cálculo general: Si ninguna de las validaciones anteriores aplica, se calcula RA si las horas trabajadas son más de 10:00:00
            ELSE
                CASE
                    WHEN rd.reg_horas_trabajadas > '10:00:00'::interval THEN rd.reg_horas_trabajadas - '10:00:00'::interval
                    ELSE '00:00:00'::interval
                END
        END AS ra	 
    FROM 
        re_diaria rd
    LEFT JOIN 
        re_acumulada_semanal ras ON rd.reg_cod_personal = ras.reg_cod_personal AND rd.reg_fecha = ras.reg_fecha
    LEFT JOIN 
        re_acumulada_mensual ram ON rd.reg_cod_personal = ram.reg_cod_personal AND rd.reg_fecha = ram.reg_fecha
),
ra_semanal_suma AS (
    SELECT 
        rd.reg_cod_personal,
        EXTRACT(WEEK FROM rd.reg_fecha) AS week,
        SUM(
            CASE
                -- Sumar directamente las horas adicionales (RA) sin límite o tope
                WHEN rd.ra IS NOT NULL THEN rd.ra
                ELSE '00:00:00'::interval
            END
        ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_semanal_suma
    FROM ra rd
    GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
),
   ra_mensual_suma AS (
        SELECT 
    		rs.reg_cod_personal,
    		SUM(rs.ra_semanal_suma) AS ra_mensual_suma
		FROM 
    		ra_semanal_suma rs
		GROUP BY 
    	rs.reg_cod_personal
    ),
	ra_dividida AS (
	    SELECT
	        ra.reg_cod_personal,
	        ra.reg_fecha,
	        ra.ra,  -- El valor de RA calculado previamente
	        ra.reg_hora_salida, -- Hora de salida
			ra.reg_horas_trabajadas,
			ra.ocu_tipo,
			ra.ocu_horas_estaticas,
			ra.ocu_horas_extras,
			ra.ocu_horas_adicionales,
			ra.ocu_horas_adicionales_100,
	        
	        -- Cálculo de RA_80 (hasta las 19:59:59)
	        CASE
				--Calculo excepcional ocu tipo 12  horas estaticas
				WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 THEN ra.ocu_horas_adicionales::interval
 				-- Si es sábado, RA_80 es siempre '00:00:00'
            	WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 THEN '00:00:00'::interval
	            -- Si la hora de salida es menor o igual a las 19:59:59, todo RA se contabiliza en RA_80
	            WHEN ra.reg_hora_salida <= '19:59:59'::time THEN ra.ra
	            -- Si la hora de salida es después de las 19:59:59, calculamos cuánto tiempo adicional fue antes de las 19:59:59
	            ELSE 
	                 ra.ra - (ra.reg_hora_salida - '19:59:59'::time)::interval
	        END AS ra_80,
	        
	        -- Cálculo de RA_100 (después de las 19:59:59)
	        CASE
				--Calculo excepcional ocu tipo 12  horas estaticas
				WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 THEN ra.ocu_horas_adicionales_100::interval
				-- Si es sábado (día de la semana = 6) y hay horas trabajadas, todo RA se asigna a RA_100
            	WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 THEN ra.reg_horas_trabajadas
	            -- Si la hora de salida es después de las 19:59:59, calculamos RA_100
	            WHEN ra.reg_hora_salida > '19:59:59'::time THEN
	              LEAST(ra.ra, (ra.reg_hora_salida - '19:59:59'::time)::interval)
	            -- Si la hora de salida es antes de las 19:59:59, no hay RA_100
	            ELSE '00:00:00'::interval
	        END AS ra_100
	
	    FROM 
	        ra  -- Utilizamos el CTE `ra` previamente calculado para obtener los valores de RA
	),
ra_divida_semanal_suma AS (
    SELECT 
        rd.reg_cod_personal,
        EXTRACT(WEEK FROM rd.reg_fecha) AS week,
        SUM(
            CASE
                -- Sumar directamente las horas adicionales (RA) sin límite o tope  Sumar solo si rd.ra_80 es mayor que '00:00:00'
                WHEN rd.ra_80 IS NOT NULL AND rd.ra_80 > '00:00:00'::interval THEN rd.ra_80
                ELSE '00:00:00'::interval
            END
        ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal,
		SUM(
            CASE
                -- Sumar directamente las horas adicionales (RA) sin límite o tope
                WHEN rd.ra_100 IS NOT NULL THEN rd.ra_100
                ELSE '00:00:00'::interval
            END
        ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal
    	FROM ra_dividida rd
    	GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
	),
 	ra_dividia_mensual_suma AS (
        SELECT 
    		rs.reg_cod_personal,
    		SUM(rs.ra_80_semanal) AS ra_80_mensual,
			SUM(rs.ra_100_semanal) AS ra_100_mensual
		FROM 
    		ra_divida_semanal_suma rs
		GROUP BY 
    	rs.reg_cod_personal
    ),
re_recalculada AS (
    SELECT
        ras.reg_cod_personal,
        ras.reg_fecha,
        rd.reg_horas_trabajadas,
        ras.re,
        ras.re_acumulada_semanal,
        CASE
            -- Verifica si `re_acumulada_semanal` es mayor o igual a 08:00:00
            WHEN ras.re_acumulada_semanal >= '08:00:00'::interval THEN
                CASE
                    WHEN rd.reg_horas_trabajadas > '09:00:00'::interval THEN
                        ras.re - (ras.re_acumulada_semanal - '08:00:00'::interval)
                    ELSE
                        '00:00:00'::interval
                END
            ELSE
                -- Si `re_acumulada_semanal` no es mayor o igual a 08:00:00, simplemente devuelve `re` original
                '00:00:00'::interval
        END AS re_recalculada
    FROM
        re_acumulada_semanal ras
    JOIN
        re_diaria rd ON ras.reg_cod_personal = rd.reg_cod_personal AND ras.reg_fecha = rd.reg_fecha
)
    SELECT 
        r.reg_fecha,
        r.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
          -- Utilizamos 're_recalculada' si es diferente de '00:00:00', de lo contrario, usamos 'r.re'
        CASE
            WHEN re_rec.re_recalculada <> '00:00:00'::interval THEN re_rec.re_recalculada
            ELSE r.re
        END AS re,
        r.horas_a_compensar,
        r.horas_compensadas,
        r.horas_restantes,
        r.estado_compensacion,
        s.re_semanal_suma,
        m.re_mensual_suma,
		ra_semanal.re_acumulada_semanal, 
		ra_mensual.re_acumulada_mensual,
		ra.ra AS horas_adicionales,
		ras.ra_semanal_suma,
		ma.ra_mensual_suma,
 		ra_dividida.ra_80,  
    	ra_dividida.ra_100,  
		rds.ra_80_semanal,
		rds.ra_100_semanal,
		rdm.ra_80_mensual,
		rdm.ra_100_mensual,
        btrim(
            CASE
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
                ELSE NULL
            END
        ) AS dia_semana,
        of.ocu_descripcion AS ocurrencia_descripcion,
        of.ocurrencia_tipo,
		of.ocu_tipo,
		of.tip_codigo,
        ff.feriado_descripcion,
        CASE
            WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            ELSE NULL
        END AS tolerancia_especial
    FROM 
        re_diaria r
    LEFT JOIN 
        marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
 	LEFT JOIN 
        re_recalculada re_rec ON r.reg_cod_personal = re_rec.reg_cod_personal AND r.reg_fecha = re_rec.reg_fecha
    LEFT JOIN 
        ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
    LEFT JOIN 
        feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
    LEFT JOIN 
        tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
    LEFT JOIN 
        re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
    LEFT JOIN 
        re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
	LEFT JOIN 
    	re_acumulada_semanal ra_semanal ON r.reg_cod_personal = ra_semanal.reg_cod_personal AND r.reg_fecha = ra_semanal.reg_fecha
	LEFT JOIN 
    	re_acumulada_mensual ra_mensual ON r.reg_cod_personal = ra_mensual.reg_cod_personal AND r.reg_fecha = ra_mensual.reg_fecha
	LEFT JOIN 
    	ra ra ON r.reg_cod_personal = ra.reg_cod_personal AND r.reg_fecha = ra.reg_fecha
	LEFT JOIN 
    	ra_dividida ON ra.reg_cod_personal = ra_dividida.reg_cod_personal AND ra.reg_fecha = ra_dividida.reg_fecha
	LEFT JOIN 
    	ra_semanal_suma ras ON r.reg_cod_personal = ras.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = ras.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
	 LEFT JOIN 
        ra_mensual_suma ma ON r.reg_cod_personal = ma.reg_cod_personal
	LEFT JOIN 
    	ra_divida_semanal_suma rds ON r.reg_cod_personal = rds.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = rds.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
   LEFT JOIN 
        ra_dividia_mensual_suma rdm ON r.reg_cod_personal = rdm.reg_cod_personal
    ORDER BY 
        r.reg_fecha, r.reg_cod_personal;
END; 
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_horas5_parametrizada(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas5_parametrizada(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, horas_a_compensar interval, horas_compensadas interval, horas_restantes interval, estado_compensacion character varying, re_semanal_suma interval, re_mensual_suma interval, re_acumulada_semanal interval, re_acumulada_mensual interval, ra interval, ra_semanal_suma interval, ra_mensual_suma interval, ra_80 interval, ra_100 interval, ra_80_semanal interval, ra_100_semanal interval, ra_80_mensual interval, ra_100_mensual interval, dia_semana text, ocurrencia_descripcion text, ocurrencia_tipo text, ocu_tipo integer, tip_codigo character varying, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    param RECORD;
BEGIN
	-- Obtener los parámetros del año solicitado.
    SELECT * INTO param
    FROM calculo_parametros
    WHERE periodo_year = anio
    LIMIT 1;
	
    IF param IS NULL THEN
        RAISE EXCEPTION 'No hay parámetros para el año %', anio;
    END IF;
   	
	
   	/*
	 * Estas líneas establecen configuraciones de sesión para la función. 
	 * Aseguran que la manipulación de fechas y tiempos sea consistente (UTC 
	 * para la zona horaria y DMY para el estilo de fecha) sin importar la 
	 * configuración global del servidor o del cliente.
	*/
	-- Configura la zona horaria a UTC para la sesión actual. Importante 
	-- para consistencia en cálculos de tiempo.
	PERFORM set_config('timezone', 'UTC', true);
	
	-- Configura el estilo de fecha a ISO, DMY (Día-Mes-Año).
    PERFORM set_config('DateStyle', 'ISO, DMY', true);
	
	-- Indica que el resultado de la siguiente consulta (que contiene 
	-- múltiples CTEs) será el resultado devuelto por la función.
    RETURN QUERY
	
	-- CTEs (Common Table Expressions - Bloques WITH):
	-- Aquí es donde reside la mayor parte de la lógica. 
	-- Cada CTE prepara un conjunto de datos intermedio que luego 
	-- se utiliza en CTEs posteriores o en la consulta final.
	
	/*
	 * calendar (Generador de Fechas del Mes):
	 - Crea una tabla temporal calendar que contiene todas las fechas día por día 
	 para el "mes y año" especificados en los parámetros de la función. 
	 Es fundamental para asegurar que el informe incluya todos los días del mes, 
	 incluso aquellos sin marcaciones.
	*/
    WITH RECURSIVE calendar AS (
        SELECT DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date	-- Selecciona el primer día del mes dado por 'anio' y 'mes'
        UNION ALL								-- Une con los siguientes días de forma recursiva
        SELECT (date + INTERVAL '1 day')::DATE	-- Suma un día a la fecha anterior
        FROM calendar
        WHERE date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'	-- Condición para detener la recursión: hasta el último día del mes
    ),
	/*
	 * marcaciones_completas (Marcaciones con Turnos y Cálculos Básicos):
	 - Centraliza las marcaciones de entrada y salida, les asocia el turno correspondiente 
	 y sus tolerancias, y realiza los cálculos iniciales de reg_horas_trabajadas, 
	 reg_retraso (con un ajuste de 59 segundos de gracia y tolerancia especial) y reg_horas_extras. 
	 Todo esto, filtrado para el param_reg_cod_personal de la función.
	*/
	marcaciones_completas AS (
        SELECT COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha, 						-- Fecha consolidada (de entrada o salida)
    			COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal, 	-- Código de personal consolidado
    			t.tur_entrada,															-- Hora de entrada programada del turno
    			t.tur_salida,															-- Hora de salida programada del turno
    			p.par_valor_time,														-- Valor del parámetro de tolerancia general
				t.tur_tipo,																-- Tipo de turno
				e.tol_tiempo_interval,													-- Tolerancia especial (obtenida de marcacion_entrada_adsoluta)
    			e.reg_hora AS reg_hora_entrada,											-- Hora de la marcación de entrada
    			s.reg_hora AS reg_hora_salida,											-- Hora de la marcación de salida
				-- Cálculo de Horas Trabajadas (igual que en la vista marcaciones_entradas_salidas)
    			CASE
        			WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada 
        				THEN s.reg_hora - t.tur_entrada
        			ELSE 
        				s.reg_hora - e.reg_hora
    			END AS reg_horas_trabajadas,
				-- Cálculo de Retraso (ajustado para incluir tolerancia especial y un segundo de gracia)
    			CASE
       				WHEN t.tur_tipo = 4 
       					THEN '00:00:00'::interval
       				WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval + e.tol_tiempo_interval) 
       					THEN e.reg_hora - (t.tur_entrada + p.par_valor_time + e.tol_tiempo_interval)
    				ELSE 
    					'00:00:00'::interval
				END AS reg_retraso,
				-- Cálculo de Horas Extras Iniciales (igual que en la vista marcaciones_entradas_salidas)
    			CASE
        			WHEN e.reg_hora IS NULL 
        				THEN NULL::interval
        			ELSE
            		CASE
                		WHEN s.reg_hora IS NULL 
                			THEN '00:00:00'::interval
                		WHEN e.reg_hora <= t.tur_entrada 
                			THEN s.reg_hora - t.tur_salida
                		ELSE 
                			s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
            		END
    			END AS reg_horas_extras
        FROM marcacion_entrada_adsoluta e
			FULL JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
			LEFT JOIN turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
				AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
				AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
			LEFT JOIN parametros p ON p.par_cod = t.tur_tolerancia
        WHERE COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
	/*
	 * ocurrencias_filtradas (Eventos y Ausencias):
	 - Identifica y consolida todas las "ocurrencias" (permisos, licencias, vacaciones, etc.) 
	 aplicables a un empleado durante el mes. Utiliza generate_series para "expandir" las 
	 ocurrencias de rango de fechas a días individuales y luego las agrupa para manejar 
	 múltiples ocurrencias en un mismo día. 
	 Excluye fines de semana para ciertos tipos de ocurrencia (ej. vacaciones).
	*/
	ocurrencias_filtradas AS (
		SELECT subquery.reg_cod_personal,	-- Código del personal
				subquery.reg_fecha,			-- Fecha del día específico. Generada por 'generate_series' para cada día de la ocurrencia dentro del mes.
				STRING_AGG(subquery.ocu_descripcion::text, ', ' ORDER BY subquery.ocu_descripcion)::text AS ocu_descripcion,	-- Agrupa descripciones de ocurrencias por día
    			STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo)::text AS ocurrencia_tipo,	-- Agrupa tipos de ocurrencias por día
				MIN(subquery.ocu_tipo) AS ocu_tipo,
				STRING_AGG(subquery.tip_codigo::character varying, ', ' ORDER BY subquery.tip_codigo)::character varying AS tip_codigo,	-- Agrupa códigos de tipo (ej. "VAC", "PER")
				MAX(subquery.ocu_horas_estaticas) AS ocu_horas_estaticas, 				-- Máximo de horas estáticas
				SUM(subquery.ocu_horas_extras) AS ocu_horas_extras,						-- Suma de horas extras de ocurrencias
				SUM(subquery.ocu_horas_adicionales) AS ocu_horas_adicionales, 			-- Suma de horas adicionales de ocurrencias (RA 80%)
				SUM(subquery.ocu_horas_adicionales_100) AS ocu_horas_adicionales_100 	-- Suma de horas adicionales de ocurrencias (RA 100%)
		FROM (
			SELECT o.ocu_cod_persona AS reg_cod_personal,
					
					-- Genera una serie de fechas (día a día) para cada ocurrencia, 
            		-- limitando el rango a la intersección entre la duración de la ocurrencia 
            		-- y el mes de interés (anio, mes).
					generate_series(
        					GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1)), -- Inicia desde la fecha de inicio de la ocurrencia o el inicio del mes, el que sea posterior
        						LEAST(
            						CASE 
                						-- Mantener tus condiciones existentes
                						WHEN o.ocu_fecha_desde = o.ocu_fecha_hasta 
                							THEN o.ocu_fecha_hasta
                					ELSE 
                						o.ocu_fecha_hasta
            						END,
            						(make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date -- Termina en la fecha de fin de la ocurrencia o el fin del mes, el que sea anterior
        						) ,  -- Añadimos un día al límite superior
        						'1 day'
    				)::date AS reg_fecha, 					-- Genera una fila por cada día que la ocurrencia está vigente en el mes
					o.ocu_descripcion,						-- Descripción original de la ocurrencia.
					t.tip_descripcion AS ocurrencia_tipo,	-- Descripción textual del tipo de ocurrencia (ej. "Vacaciones").
					t.tip_codigo,							-- Código del tipo de ocurrencia (ej. "VAC").
					o.ocu_tipo,								-- Código numérico del tipo de ocurrencia.
					o.ocu_horas_estaticas,					-- Horas estáticas asociadas a la ocurrencia.
					o.ocu_horas_extras,						-- Horas extras asociadas a la ocurrencia.
					o.ocu_horas_adicionales,				-- Horas adicionales (RA 80%) asociadas a la ocurrencia.
					o.ocu_horas_adicionales_100				-- Horas adicionales (RA 100%) asociadas a la ocurrencia.
			FROM ocurrencias o
					JOIN tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod -- Une con los tipos de ocurrencias para obtener descripciones
			WHERE o.ocu_cod_persona = param_reg_cod_personal -- Filtra para el empleado específico
    		AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date -- Ocurrencia debe iniciar en o antes del fin del mes
    		AND o.ocu_fecha_hasta >= make_date(anio, mes, 1) -- Ocurrencia debe terminar en o después del inicio del mes
        ) AS subquery
		WHERE NOT (
    			subquery.ocu_tipo = 1 -- Excluye ciertos tipos de ocurrencia (ej. si ocu_tipo 1 es vacaciones)
    			AND 
    			(EXTRACT(DOW FROM subquery.reg_fecha::date) = 6 -- Que caen en sábado (DOW=6)
    			OR 
    			EXTRACT(DOW FROM subquery.reg_fecha::date) = 0) -- O domingo (DOW=0)
			) -- Esto implica que para 'ocu_tipo = 1', los fines de semana no se cuentan como parte de la ocurrencia(Excluir sábados (6) y domingos (0) para vacaciones).
		GROUP BY subquery.reg_cod_personal, subquery.reg_fecha -- Agrupa para consolidar múltiples ocurrencias en un mismo día.
	),
	/*
	 * feriados_filtrados (Días Feriados):
	 - Obtiene una lista de todos los días feriados dentro del mes y año especificados.
	*/
    feriados_filtrados AS (
        SELECT f.fer_fecha AS reg_fecha, 					-- Fecha del feriado
    			f.fer_descripcion AS feriado_descripcion 	-- Descripción del feriado
		FROM feriados f
		WHERE EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes -- Filtra feriados para el año y mes dados.
    ),
	/*
	 * tolerancias_especiales_filtradas (Tolerancias Individuales/Grupo):
	 - Obtiene todas las tolerancias especiales (sean individuales o por grupo/sede) que podrían 
	 afectar al empleado durante el mes.
	*/
	tolerancias_especiales_filtradas AS (
        SELECT te.tol_cod_personal,	-- Código del personal para tolerancia individual
    			te.tol_fecha_desde,	-- Fecha de inicio de vigencia
    			te.tol_fecha_hasta,	-- Fecha de fin de vigencia
    			te.tol_descripcion,	-- Descripción de la tolerancia
    			te.tol_tiempo,		-- Valor de tiempo de la tolerancia
    			te.tol_tipo,		-- Tipo de tolerancia ('I' para Individual, 'G' para Grupo)
    			te.tol_sed_cod		-- Código de la sede para tolerancia de grupo
		FROM tolerancias_especiales te
		WHERE (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal) -- Filtra por tolerancias individuales del empleado
    		OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal)) -- O tolerancias de grupo que apliquen a la sede del empleado
    ),
	/*
	 * compensaciones_detalles_filtradas (Detalles de Compensaciones):
	 -  Consolida los detalles de compensación (horas a compensar, compensadas, restantes, estado) para 
	 el empleado en el mes dado.
	 Agrega los detalles de compensaciones (horas a compensar, compensadas, restantes, estado) por día 
	 para el empleado y mes. Esto es clave para determinar si las horas extras deben ser calculadas 
	 o si están sujetas a un esquema de compensación.
	*/
    compensaciones_detalles_filtradas AS (
        SELECT com_cod_personal,	-- Código del personal.
    			com_det_fecha,		-- Fecha del detalle de la compensación.
    			SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,	-- Suma todas las horas "a compensar" para un empleado en un día específico.
    			SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,	-- Suma todas las horas "ya compensadas" para un empleado en un día específico.
    			SUM(com_det_horas_restantes) AS com_det_horas_restantes,		-- Suma todas las horas "restantes por compensar" para un empleado en un día específico.
    			STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado	-- Concatena de forma única todos los estados de compensación para un empleado en un día específico.
		FROM ( 
				-- Esta subconsulta interna selecciona los detalles de compensación y su estado,
        		-- filtrando por el empleado y el mes/año (alias como 'sub').
				SELECT c.com_cod_personal,				-- Código del personal.
        				cd.com_det_fecha,				-- Fecha específica del detalle de compensación.
        				cd.com_det_horas_a_compensar,	-- Horas inicialmente a compensar.
        				cd.com_det_horas_compensadas,	-- Horas que ya han sido compensadas.
        				cd.com_det_horas_restantes,		-- Horas que aún quedan por compensar.
        				c.com_estado					-- Estado general de la compensación (ej. 'Pendiente', 'Cerrado').
    			FROM compensaciones_detalles cd	-- Tabla que contiene los registros de compensación detallados por fecha.
    				JOIN compensaciones_completas c ON cd.com_cod = c.com_cod	-- Une con la tabla maestra de compensaciones para obtener el código de personal y el estado general.
    			WHERE c.com_cod_personal = param_reg_cod_personal	-- Filtra por el código de personal del empleado.
        		AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio	-- Filtra por el año de la fecha del detalle.
        		AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes	-- Filtra por el mes de la fecha del detalle.
				) sub
		GROUP BY com_cod_personal, com_det_fecha -- Agrupa los resultados por empleado y por fecha. Esto consolida todos los registros de compensación que afectan a un mismo día para un empleado dado.
    ),
	/*
	 * re_diaria (Cálculo Diario de RE - Recargo Extra/Horas Extras):
	 - Calcula el valor final de las re (horas de recargo extra) para cada día del mes. 
	 Aplica una serie de reglas de negocio condicionales que consideran:
	 + Si hay horas estáticas por ocurrencia (tipo 12).
	 + Si el empleado tiene horas restantes por compensar (no se calculan extras).
	 + Si el empleado llegó con retraso (y si ese retraso es justificado por cierto tipo de ocurrencia).
	 + Las horas trabajadas reales y las horas de entrada/salida vs. el turno programado.
	 + Se asume que los tipos de ocurrencia 33, 26, 12, 29 representan permisos o situaciones 
	 que "justifican" el retraso o impactan el cálculo de RE.
	*/
	re_diaria AS (
		SELECT c.date AS reg_fecha, -- Fecha del calendario (cada día del mes).
				COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal, -- Código de personal consolidado
				-- Lógica compleja para calcular `re` (horas extras finales por día)
				-- Esta es la parte central que determina las "horas extra" o "recargo extra" según varias reglas de negocio.
				CASE
					-- Escenario excepcional: HORAS ESTATICAS (ocu_tipo = 12 y ocu_horas_estaticas = 1)
					-- Si la ocurrencia es de tipo 12 (ej. un tipo especial de permiso o evento) Y se ha marcado con 'ocu_horas_estaticas = 1' (indicando que las horas extra ya están predefinidas por la ocurrencia).
					WHEN of.ocu_tipo = 12 AND of.ocu_horas_estaticas = 1 
						THEN of.ocu_horas_extras::interval	-- Las RE son las horas extras definidas en la ocurrencia
    				
					-- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras (RE es 0)
					-- Si el empleado tiene un saldo positivo de horas restantes a compensar.
    				WHEN cd.com_det_horas_restantes > '00:00:00'::interval 
    					THEN '00:00:00'::interval
    				
					-- Escenario 2: Si la persona llegó tarde (retraso > 0) y NO tiene permisos específicos (tipos 33, 26, 12, 29), no se calculan horas extras
					-- Verifica si el empleado tuvo un retraso en la entrada Y no hay ninguna ocurrencia específica (33, 26, 12, 29) que justifique ese retraso.
					WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN '00:00:00'::interval

    				-- Nuevo Escenario (específico para ocu_tipo = 12 y retraso > 59 segundos) Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
					-- Si existe una ocurrencia del tipo 12 Y el retraso en la marcación es significativo (más de 59 segundos).
					WHEN EXISTS (
        					SELECT 1
        					FROM ocurrencias_filtradas of
        					WHERE of.reg_fecha = c.date
        					AND of.ocu_tipo = 12
    					) AND p.reg_retraso > '00:59:59'::interval 
    					THEN
        					CASE
								-- Si las horas trabajadas desde la entrada del turno (programado) hasta la salida real son más de 9 horas.
            					WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
            						THEN
                						LEAST(
                    						(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval, -- Las horas extra son el exceso sobre 8 horas (calculado desde la entrada del turno, no la marcación real).
                    						param.max_re_diario -- Pero se topan a un máximo de 2 horas.
                						)
            					ELSE 
            						'00:00:00'::interval -- Si no se cumple la condición de las 9 horas, no hay extras.
        					END
					
    				-- Escenario 3: No hay horas pendientes DE COMPENSAR, PERO hay permisos específicos (tipos 33, 26, 12, 29), calcular horas extras con reglas especiales
					-- Si no hay horas restantes a compensar Y existe alguna ocurrencia específica que podría afectar el cálculo de horas extras.
					WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN
        			CASE
						WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval 
							THEN -- Misma lógica que el "Nuevo Escenario" de arriba
	            				CASE
	                				WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
	                					THEN
	                    					LEAST(
	                        					(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
												param.max_re_diario
	                    					)
	                				ELSE 
	                					'00:00:00'::interval
	            				END
            			WHEN of.ocu_tipo = 29 
            				THEN -- Lógica específica para ocu_tipo 29 (ej. permiso de salida)
								-- Aquí se ajusta el cálculo de las horas trabajadas restando las horas compensadas (`cd.com_det_horas_compensadas`).
                				CASE
                    				WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > '09:00:00'::interval 
                    					THEN
                        					LEAST(
                            					(p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - '08:00:00'::interval,
                            					param.max_re_diario
                        					)
                    				ELSE 
                    					'00:00:00'::interval
                				END
            				ELSE -- Lógica general para otros tipos de ocurrencia
                				CASE
                    				WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
                    					THEN
                        					LEAST(
                            					(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                            					param.max_re_diario
                        					)
                    				ELSE 
                    					'00:00:00'::interval
                				END
        					END
						
						-- Escenario 4: No hay horas pendientes NI permisos, y es parte de una seguidilla de días (esta condición es un poco confusa en su redacción SQL, puede estar incompleta o mal interpretada aquí), no calcular horas extras
               			-- La condición `NOT EXISTS (SELECT 1 FROM ocurrencias_filtradas of WHERE of.reg_fecha = c.date AND of.ocu_tipo IN (33, 26, 12, 29))` se repite desde el escenario 2.
						WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (
        						SELECT 1
        						FROM ocurrencias_filtradas of
        						WHERE of.reg_fecha = c.date
        						AND of.ocu_tipo IN (33, 26, 12, 29)
    						) 
    						THEN '00:00:00'::interval

    					-- Escenario 5: Cálculo general de RE si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
						-- Este es el caso "por defecto" para calcular las horas extras si ninguna de las condiciones especiales anteriores se cumplió.
						WHEN p.reg_horas_trabajadas > '09:00:00'::interval
    						THEN
        						LEAST(
            						p.reg_horas_trabajadas - '08:00:00'::interval,
            						param.max_re_diario
        						) -- Si trabajó más de 9 horas, las extras son el exceso sobre 8 horas, topado a 2 horas.

						-- En caso contrario (si ninguna de las condiciones anteriores se cumple), las horas extras son 00:00:00
    					ELSE 
    						'00:00:00'::interval
					END AS re,
					cd.com_det_horas_a_compensar AS horas_a_compensar,			-- Muestra las horas pendientes que deben ser compensadas para el día.
					cd.com_det_horas_compensadas AS horas_compensadas,			-- Muestra las horas que ya han sido compensadas para el día.
					cd.com_det_horas_restantes AS horas_restantes,				-- Muestra el saldo de horas restantes por compensar (o a favor/en contra) para el día.
					cd.com_estado::character varying AS estado_compensacion,	-- Muestra el estado (o los estados, si hay varios únicos) de las compensaciones para el día.
					p.reg_horas_trabajadas,										-- Muestra las horas de trabajo calculadas para el día.
					p.reg_hora_salida,											-- Muestra la hora de salida registrada por el empleado.
					p.reg_retraso,												-- Muestra el tiempo de retraso en la entrada del empleado.
					of.ocu_tipo,												-- Muestra el tipo de ocurrencia principal para el día (si aplica).
					of.ocu_horas_estaticas,										-- Indica si las horas extras de la ocurrencia son estáticas/predefinidas.
					of.ocu_horas_extras,										-- Muestra las horas extras especificadas en la ocurrencia.
					of.ocu_horas_adicionales,									-- Muestra las horas adicionales (ej. recargo al 80%) de la ocurrencia.
					of.ocu_horas_adicionales_100								-- Muestra las horas adicionales (ej. recargo al 100%) de la ocurrencia.
		FROM calendar c -- Se une con el calendario para asegurar que todas las fechas del mes estén presentes
			LEFT JOIN marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal -- Se unen las marcaciones del empleado
			LEFT JOIN ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal -- Se unen las ocurrencias del empleado
			LEFT JOIN compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal -- Se unen los detalles de compensación
	),
	/*
	 * CTE re_semanal. 
	 Esta CTE es crucial para agrupar las horas de recargo extra (re) calculadas diariamente y consolidarlas 
	 a nivel semanal, aplicando límites máximos tanto diarios como semanales.
	*/
	re_semanal AS (
        SELECT rd.reg_cod_personal, -- Código del personal.
				EXTRACT(WEEK FROM rd.reg_fecha) AS week, -- Número de semana del año para la fecha del registro. Esta columna se usa para agrupar los datos semanalmente.
				LEAST( -- LEAST asegura que el resultado no exceda el 'max_re_semanal'.
					COALESCE( -- COALESCE maneja el caso donde SUM podría devolver NULL (si no hay días que cumplan el filtro), convirtiéndolo a '00:00:00'.
						SUM( -- Suma los valores de RE para todos los días de la semana que cumplen la condición.
							CASE
								WHEN rd.re >= '01:00:00' -- Si las RE calculadas para el día son de 1 hora o más...
									THEN LEAST(rd.re, param.max_re_diario)
								ELSE -- ...entonces toma el valor de 're' o el 'max_re_diario', el que sea menor. Esto limita las RE diarias.
									'00:00:00'::interval
							END
						) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) = ANY(ARRAY(
							-- FILTRO: Esta parte asegura que solo se sumen las RE de los días laborables definidos en los parámetros.
							-- EXTRACT(ISODOW FROM rd.reg_fecha): Devuelve el día de la semana como un entero (1=Lunes, 7=Domingo según ISO 8601).
							-- ARRAY(SELECT jsonb_array_elements_text(param.dias_laborables)::int): Esto asume que 'param.dias_laborables'
							-- es un campo JSONB que contiene un array de enteros (ej. '[1,2,3,4,5]' para L-V).
							-- 'jsonb_array_elements_text' extrae cada elemento del array JSON como texto, y '::int' lo convierte a entero.
							-- ANY(...): Compara si el día de la semana actual es uno de los días laborables definidos.
							SELECT jsonb_array_elements_text(param.dias_laborables)::int
						))),
						'00:00:00'::interval -- Si el SUM retorna NULL (ej. no hay días laborables con RE), se convierte a 0 horas.
					),
					param.max_re_semanal -- El resultado de la suma diaria topada se compara con 'max_re_semanal', y se toma el valor menor. Esto aplica el límite semanal.
				) AS re_semanal_suma
        FROM re_diaria rd -- Se toma como fuente de datos la CTE 're_diaria', que ya calculó las RE por día.
        -- Agrupación:
		GROUP BY 
			rd.reg_cod_personal, -- Agrupa por empleado.
			EXTRACT(WEEK FROM rd.reg_fecha) -- Agrupa por semana. Esto crea una fila por cada empleado por cada semana del mes.
    ),
	/*
	 * CTE re_mensual.
	 - Se encarga de la consolidación final de las horas de recargo extra.
	 - Da el monto definitivo de las horas de recargo extra para el período de un mes para cada 
	  empleado, después de haber pasado por todas las reglas de negocio diarias y semanales.
	*/
    re_mensual AS (
        SELECT rs.reg_cod_personal, -- Código del personal.
				LEAST( -- LEAST asegura que el resultado no exceda el 'max_re_mensual'.
					SUM(rs.re_semanal_suma), -- Suma las horas semanales de RE consolidadas en 're_semanal' para el empleado.
					param.max_re_mensual -- El resultado de la suma se compara con 'param.max_re_mensual', y se toma el valor menor. Esto aplica el límite mensual.
				) AS re_mensual_suma
        FROM re_semanal rs -- Se toma como fuente de datos la CTE 're_semanal', que ya calculó las RE por semana (y aplicó límites diarios y semanales).
        GROUP BY 
			rs.reg_cod_personal -- Agrupa por empleado. Esto consolida todas las semanas de un empleado en una única fila mensual.
    ),
	/*
	 * CTE re_acumulada_semanal
	  Proporciona un "subtotal en curso" de las horas de recargo extra para cada día laboral de un 
	  empleado, reiniciándose al comienzo de cada semana.
	*/
	re_acumulada_semanal AS (
		-- CTE que acumula las RE semanalmente, reiniciando cada lunes (EXTRACT(ISODOW) = 1)
		SELECT rd.reg_cod_personal, 						-- Código del personal.
				rd.reg_fecha, 								-- Fecha del día específico.
				EXTRACT(WEEK FROM rd.reg_fecha) AS semana, 	-- Número de semana del año para la fecha. Útil para particionar la acumulación.
				rd.re,										-- Horas de recargo extra (RE) para ese día.
				SUM(rd.re) OVER (
					PARTITION BY 
						rd.reg_cod_personal, 				-- La suma se calcula de forma independiente para cada empleado.
						EXTRACT(YEAR FROM rd.reg_fecha), 	-- Y para cada año (para manejar el cambio de año correctamente si el mes cubre dos años).
						EXTRACT(WEEK FROM rd.reg_fecha) 	-- Y crucialmente, la suma se reinicia para cada nueva semana.
					ORDER BY 
						rd.reg_fecha -- La suma se acumula ordenando los días por fecha (del más antiguo al más reciente).
						ROWS UNBOUNDED PRECEDING) AS re_acumulada_semanal -- Suma desde el inicio de la partición (el primer día de la semana) hasta la fila actual.
		FROM re_diaria rd -- Se toma como fuente de datos la CTE 're_diaria', que tiene las RE diarias.
		WHERE EXTRACT(ISODOW FROM rd.reg_fecha) = ANY(ARRAY(
			-- FILTRO: Considerar solo días laborables para la acumulación semanal.
            -- Esto significa que si 're_diaria' produjo RE para un fin de semana (dependiendo de tu lógica),
            -- esta CTE las ignora en esta acumulación semanal.
            -- Se asume que 'param.dias_laborables' es un array de enteros que define los días laborables (1=Lunes, 7=Domingo).
			SELECT jsonb_array_elements_text(param.dias_laborables)::int
		))  -- Considerar solo días de lunes a viernes
	),
	/*
	 * CTE re_mensual_con_limited. 
	 - Esta CTE refina aún más el cálculo de las horas extras (re) aplicando el límite semanal a nivel 
	 diario, basándose en la acumulación diaria dentro de la semana.
	*/
	re_mensual_con_limited AS (
		-- Aplica un límite de 08:00 horas por semana a las RE
		SELECT rsa.reg_cod_personal,		-- Código de la persona
				rsa.reg_fecha,				-- Fecha de la marcación
				rsa.re,						-- Horas de recargo extra (RE) calculadas para ese día (sin límite semanal aún).
				-- Suma diaria limitada por la acumulación semanal (máximo 08:00 horas por semana)
				CASE
					-- Si la acumulación semanal es mayor o igual a 08:00:00, no sumamos más horas
					WHEN rsa.re_acumulada_semanal > param.max_re_semanal THEN '00:00:00'::interval
					-- Si la acumulación semanal es menor a 08:00:00, sumamos las horas RE restantes
					ELSE rsa.re
				END AS re_con_limited
		FROM re_acumulada_semanal rsa -- Se toma como fuente de datos la CTE 're_acumulada_semanal', que tiene las RE diarias y su acumulación semanal.
	),
	/*
	 * CTE re_acumulada_mensual. 
	 - Esta CTE es el paso final para obtener un acumulado de las horas de recargo extra a lo largo de todo el 
	 mes, incorporando todas las reglas de negocio anteriores (diarias, semanales y límites).
	*/
	re_acumulada_mensual AS (
		-- CTE que acumula las RE a lo largo del mes, respetando el límite de 08:00 horas por semana
		SELECT rml.reg_cod_personal,               	-- Código de la persona
				rml.reg_fecha,                      -- Fecha de la marcación
				SUM(rml.re_con_limited) OVER (
					PARTITION BY 
						rml.reg_cod_personal 	-- La suma se calcula de forma independiente para cada empleado.
					ORDER BY 
						rml.reg_fecha			-- La suma se acumula ordenando los días por fecha (del más antiguo al más reciente) dentro del mes.
				) AS re_acumulada_mensual       -- El marco de la ventana por defecto es 'RANGE UNBOUNDED PRECEDING', lo que suma desde el inicio de la partición hasta la fila actual.
		FROM re_mensual_con_limited rml			-- Se toma como fuente de datos la CTE 're_mensual_con_limited', que ya tiene las RE diarias ajustadas por el límite semanal.
	),
	/*
	 * CTE ra 
	 - Es donde se calcula el "Recargo Adicional" (RA), que a menudo se refiere a horas extras con una tasa de pago más 
	 alta (ej. 80% o 100% de recargo) o a horas trabajadas más allá de un cierto umbral, una vez que las horas "normales" 
	 de recargo extra (re) ya han sido consideradas y limitadas. La lógica aquí es bastante compleja, ya que depende 
	 de múltiples factores y reglas de negocio.
	*/
	ra AS (
		SELECT rd.reg_cod_personal,				-- Código del personal.
				rd.reg_fecha,					-- Fecha del día.
				rd.reg_hora_salida,				-- Hora de salida registrada.
				rd.reg_horas_trabajadas,		-- Horas trabajadas para el día.
				rd.reg_retraso,					-- Retraso en la entrada para el día.
				rd.ocu_tipo,					-- Tipo de ocurrencia principal para el día.
				rd.ocu_horas_estaticas,			-- Indicador de horas estáticas en ocurrencia.
				rd.ocu_horas_extras,			-- Horas extras predefinidas en ocurrencia.
				rd.ocu_horas_adicionales,		-- Horas adicionales (80%) predefinidas en ocurrencia.
				rd.ocu_horas_adicionales_100,	-- Horas adicionales (100%) predefinidas en ocurrencia.
				
				-- ra:
				-- Calcula el valor final de las horas de Recargo Adicional (RA) para cada día,
				-- aplicando una jerarquía compleja de reglas de negocio que consideran ocurrencias,
				-- días de la semana, retrasos y acumulados semanales/mensuales de RE.
				CASE
					-- Escenario 1: HORAS ESTATICAS (ocu_tipo = 12 y ocu_horas_estaticas = 1)
					-- Si la ocurrencia es de tipo 12 Y se ha marcado con 'ocu_horas_estaticas = 1'.
					WHEN rd.ocu_tipo = 12 AND rd.ocu_horas_estaticas = 1 
						THEN rd.ocu_horas_adicionales::interval + rd.ocu_horas_adicionales_100::interval
						-- Las RA son la suma de las horas adicionales predefinidas en la ocurrencia (RA 80% + RA 100%).
						
					-- Escenario 2: Si es sábado
					-- Si el día de la semana es Sábado (ISODOW = 6).
					WHEN EXTRACT(ISODOW FROM rd.reg_fecha) = 6 
						THEN rd.reg_horas_trabajadas
						-- Las RA son las horas trabajadas totales del sábado. Esto implica que todo lo trabajado un sábado se considera "recargo adicional".
						
					-- Escenario 3: Si no hay RE calculadas para el día (menos de 1 hora de RE).
					WHEN rd.re < '01:00:00'::interval 
						THEN '00:00:00'::interval
						-- Si no hubo al menos 1 hora de Recargo Extra (RE), no hay Recargo Adicional (RA).
						
					-- Si tiene retraso mayor a 00:00:59 y no es sábado, no sumamos horas RA
					--WHEN rd.reg_retraso > '00:00:59'::interval THEN '00:00:00'::interval
					
					-- Escenario 5: Validación para RE acumulada semanal (si supera el límite semanal)
					-- Si la acumulación semanal de RE (hasta este día) ya es mayor que el límite semanal (param.max_re_semanal).
					WHEN ras.re_acumulada_semanal > param.max_re_semanal 
						THEN
							CASE
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval -- Si las horas trabajadas superan las 9 horas.
									THEN rd.reg_horas_trabajadas  - '08:00:00'::interval -- Las RA son las horas trabajadas que exceden las 8 horas (diferente al cálculo normal de RE que resta 9h).
								ELSE 
									'00:00:00'::interval
							END
					
					-- Escenario 6: Validación para RE acumulada mensual (entre 32 y 33:59:59 horas)
					-- Si la acumulación mensual de RE (hasta este día) está en este rango específico.
					WHEN ram.re_acumulada_mensual BETWEEN '32:00:00'::interval AND '33:59:59'::interval THEN
					   CASE
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval -- Si las horas trabajadas superan las 9 horas.
								THEN rd.reg_horas_trabajadas - '09:00:00'::interval -- Las RA son las horas trabajadas que exceden las 9 horas.
							ELSE 
								'00:00:00'::interval
						END
					
					-- Validación para RE mensual mayor a 34 horas
					
					-- Escenario 7: Validación para RE mensual mayor a 34 horas
					-- Si la acumulación mensual de RE (hasta este día) supera las 34 horas.
					WHEN ram.re_acumulada_mensual > '34:00:00'::interval THEN
					   CASE
							WHEN rd.reg_horas_trabajadas > '09:00:00'::interval -- Si las horas trabajadas superan las 9 horas.
								THEN rd.reg_horas_trabajadas - '08:00:00'::interval -- Las RA son las horas trabajadas que exceden las 8 horas.
						   ELSE 
							'00:00:00'::interval
						END
					
					-- Escenario 8: Cálculo general (si ninguna de las validaciones anteriores aplica)
					-- Si ninguna de las condiciones anteriores se cumple.
					ELSE
						CASE
							WHEN rd.reg_horas_trabajadas > param.limite_ra_normal -- Si las horas trabajadas superan un límite normal para RA (ej. 10:00:00).
								THEN rd.reg_horas_trabajadas - param.limite_ra_normal -- Las RA son el excedente sobre ese límite normal.
							ELSE 
								'00:00:00'::interval
						END
				END AS ra -- Fin de la lógica CASE para la columna 'ra'.
		FROM re_diaria rd -- Fuente principal de datos diarios.
			LEFT JOIN re_acumulada_semanal ras ON rd.reg_cod_personal = ras.reg_cod_personal AND rd.reg_fecha = ras.reg_fecha -- Une para acceder a la RE acumulada semanal.
			LEFT JOIN re_acumulada_mensual ram ON rd.reg_cod_personal = ram.reg_cod_personal AND rd.reg_fecha = ram.reg_fecha -- Une para acceder a la RE acumulada mensual.
	),
	/*
	 * Esta CTE da el monto total de las horas de recargo adicional acumuladas por cada empleado 
	 por semana, excluyendo los domingos.
	*/
	ra_semanal_suma AS (
		SELECT rd.reg_cod_personal, -- Código del personal.
				EXTRACT(WEEK FROM rd.reg_fecha) AS week, -- Número de semana del año para la fecha del registro. Esta columna se usa para agrupar los datos semanalmente.
				
				-- ra_semanal_suma:
				-- Calcula la suma total de las horas de Recargo Adicional (RA) para la semana.
				SUM( -- SUMa los valores de RA para todos los días de la semana que cumplen la condición.
					CASE
						-- Si rd.ra tiene un valor (es decir, no es NULL), sumarlo directamente.
						-- Esto implica que, a diferencia de 're', no se aplica un límite diario o un umbral mínimo de 1 hora para RA a nivel de suma semanal en este punto.
						WHEN rd.ra IS NOT NULL 
							THEN rd.ra
						ELSE 
							'00:00:00'::interval -- Si rd.ra es NULL (no hubo RA para ese día), se considera 0.
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_semanal_suma
				-- FILTRO: Esta parte asegura que solo se sumen las RA de los días de Lunes a Sábado.
				-- EXTRACT(ISODOW FROM rd.reg_fecha): Devuelve el día de la semana como un entero (1=Lunes, 7=Domingo según ISO 8601).
				-- <= 6: Incluye Lunes (1), Martes (2), Miércoles (3), Jueves (4), Viernes (5), y Sábado (6). Los Domingos (7) quedan excluidos de esta suma.
		
		FROM ra rd -- Se toma como fuente de datos la CTE 'ra', que ya calculó las RA por día con sus reglas complejas.
		
		-- Agrupación:
		GROUP BY 
			rd.reg_cod_personal, -- Agrupa por empleado.
			EXTRACT(WEEK FROM rd.reg_fecha) -- Agrupa por semana. Esto crea una fila por cada empleado por cada semana del mes.
	),
	/*
	 * CTE ra_mensual_suma. 
	 - Esta es una CTE sencilla y directa que consolida el Recargo Adicional (ra) al nivel mensual.
	 - Da el monto total de las horas de recargo adicional que un empleado ha acumulado durante el 
	 mes, sumando sus totales semanales.
	*/
	ra_mensual_suma AS (
        SELECT rs.reg_cod_personal, -- Código del personal.
				
				-- ra_mensual_suma:
				-- Calcula la suma total de las horas de Recargo Adicional (RA) para todo el mes.
				SUM(rs.ra_semanal_suma) AS ra_mensual_suma
				-- Simplemente suma los totales de RA de cada semana (calculados en 'ra_semanal_suma') para cada empleado.
				-- No se aplica ningún límite mensual en esta CTE, lo que sugiere que si hay un límite para RA,
				-- se aplicaría en una CTE posterior o en la consulta final que use este resultado.
		
		FROM ra_semanal_suma rs -- Se toma como fuente de datos la CTE 'ra_semanal_suma', que ya calculó las RA por semana.
		
		-- Agrupación:
		GROUP BY 
			rs.reg_cod_personal -- Agrupa por empleado. Esto consolida todas las semanas de un empleado en una única fila mensual.
    ),
	ra_dividida AS (
	    SELECT ra.reg_cod_personal,				-- Código del personal.
				ra.reg_fecha,					-- Fecha del día.
				ra.ra,							-- El valor total de RA calculado previamente para el día.
				ra.reg_hora_salida,				-- Hora de salida registrada del empleado.
				ra.reg_horas_trabajadas,		-- Horas trabajadas para el día.
				ra.ocu_tipo,					-- Tipo de ocurrencia principal.
				ra.ocu_horas_estaticas,			-- Indicador de horas estáticas.
				ra.ocu_horas_extras,			-- Horas extras predefinidas.
				ra.ocu_horas_adicionales,		-- Horas adicionales (80%) predefinidas en ocurrencia.
				ra.ocu_horas_adicionales_100,	-- Horas adicionales (100%) predefinidas en ocurrencia.
				
				-- ra_80 (Cálculo de Recargo Adicional al 80%)
				-- Determina la porción del RA total que se clasifica como RA al 80%.
				-- La lógica principal se basa en si la hora de salida está antes o después de 'param.hora_tope_ra_80'.
				CASE
					-- Escenario 1: Cálculo excepcional para ocurrencia tipo 12 con horas estáticas.
					-- Si la ocurrencia es de tipo 12 Y tiene horas estáticas, el RA_80 es directamente 'ocu_horas_adicionales'.
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales::interval
					
					-- Escenario 2: Si es sábado, RA_80 es siempre '00:00:00'.
					-- Esto implica que, para los sábados, todas las RA se asignan a RA_100 (ver la lógica de ra_100 más abajo).
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN '00:00:00'::interval
					
					-- Escenario 3: Si la hora de salida es antes o igual a 'param.hora_tope_ra_80' (ej. 19:59:59).
					WHEN ra.reg_hora_salida <= param.hora_tope_ra_80 
						THEN ra.ra -- Todo el RA calculado para el día se considera RA_80.
						
					-- Escenario 4: Si la hora de salida es después de 'param.hora_tope_ra_80'.
					ELSE 
						-- Calcula el RA que cae *antes* de la hora tope.
						-- Esto se hace restando el tiempo que el empleado trabajó *después* de la hora tope (reg_hora_salida - param.hora_tope_ra_80)
						-- del total de RA. El resultado es la porción de RA que está antes de la hora tope.
						ra.ra - (ra.reg_hora_salida - param.hora_tope_ra_80)::interval
				END AS ra_80,
	        
				-- ra_100 (Cálculo de Recargo Adicional al 100%):
				-- Determina la porción del RA total que se clasifica como RA al 100%.
				-- La lógica principal se basa en si la hora de salida está después de 'param.hora_tope_ra_80'.
				CASE
					-- Escenario 1: Cálculo excepcional para ocurrencia tipo 12 con horas estáticas.
					-- Si la ocurrencia es de tipo 12 Y tiene horas estáticas, el RA_100 es directamente 'ocu_horas_adicionales_100'.
					WHEN ra.ocu_tipo = 12 AND ra.ocu_horas_estaticas = 1 
						THEN ra.ocu_horas_adicionales_100::interval
					
					-- Escenario 2: Si es sábado (día de la semana = 6) y hay horas trabajadas.
					-- Toda las horas trabajadas en sábado se consideran RA_100. Esto complementa la regla de RA_80 para sábados.
					WHEN EXTRACT(ISODOW FROM ra.reg_fecha) = 6 
						THEN ra.reg_horas_trabajadas
					
					-- Escenario 3: Si la hora de salida es después de 'param.hora_tope_ra_80'.
					WHEN ra.reg_hora_salida > param.hora_tope_ra_80 
						THEN
							-- Calcula cuánto tiempo de RA cae *después* de la hora tope.
							-- LEAST(ra.ra, ...): Asegura que el RA_100 no sea más que el RA total del día.
							-- (ra.reg_hora_salida - param.hora_tope_ra_80): Calcula el tiempo transcurrido desde la hora tope hasta la salida real.
							-- El RA_100 es el mínimo entre el RA total del día y el tiempo trabajado después de la hora tope.
							LEAST(ra.ra, (ra.reg_hora_salida - param.hora_tope_ra_80)::interval)
					
					-- Escenario 4: Si la hora de salida es antes o igual a 'param.hora_tope_ra_80'.
					ELSE 
						'00:00:00'::interval -- No hay RA_100 si la salida es antes de la hora tope.
				END AS ra_100
	
	    FROM ra  -- Utilizamos el CTE `ra` previamente calculado para obtener los valores de RA.
	),
	/*
	 * CTE ra_divida_semanal_suma. 
	 - Esta CTE es el siguiente paso lógico después de ra_dividida, ya que consolida los recargos 
	 adicionales (ra_80 y ra_100) a nivel semanal, aplicando filtros específicos para los días 
	 de la semana.
	*/
	ra_divida_semanal_suma AS (
		SELECT rd.reg_cod_personal,							-- Código del personal.
				EXTRACT(WEEK FROM rd.reg_fecha) AS week, 	-- Número de semana del año para la fecha del registro. Se usa para agrupar semanalmente.
				
				-- ra_80_semanal (Suma semanal de Recargo Adicional al 80%):
				-- Totaliza las horas de RA al 80% para la semana, considerando solo días laborables (Lunes a Viernes).
				SUM( -- Suma los valores de RA_80 para los días que cumplen las condiciones.
					CASE
						-- Condición: Solo suma rd.ra_80 si no es NULL Y es mayor que '00:00:00' (es decir, tiene un valor positivo de RA_80).
						WHEN rd.ra_80 IS NOT NULL AND rd.ra_80 > '00:00:00'::interval 
							THEN rd.ra_80
						ELSE 
							'00:00:00'::interval -- Si no cumple la condición o es NULL/cero, se considera 0 para la suma.
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5) AS ra_80_semanal,
				-- FILTRO: Esta parte es crucial: solo incluye RA_80 de Lunes a Viernes (ISODOW 1 a 5).
				-- Implica que las RA_80 de fines de semana (Sábados y Domingos) no se contabilizan en esta suma.
				
				-- ra_100_semanal (Suma semanal de Recargo Adicional al 100%):
				-- Totaliza las horas de RA al 100% para la semana, incluyendo días laborables y Sábados.
				SUM( -- Suma los valores de RA_100 para los días que cumplen las condiciones.
					CASE
						-- Condición: Si rd.ra_100 no es NULL, sumarlo directamente.
						-- A diferencia de RA_80, no hay un filtro para '> 00:00:00' aquí, lo que podría implicar que incluso pequeñas cantidades de RA_100 se suman.
						WHEN rd.ra_100 IS NOT NULL 
							THEN rd.ra_100
						ELSE 
							'00:00:00'::interval	-- Si es NULL, se considera 0.
					END
				) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 6) AS ra_100_semanal
				-- FILTRO: Esta parte es crucial: solo incluye RA_100 de Lunes a Sábado (ISODOW 1 a 6).
				-- Esto es coherente con la lógica de 'ra_dividida' donde los sábados se asignaban completamente a RA_100.
				-- Los Domingos (7) quedan excluidos de esta suma.
		
    	FROM ra_dividida rd -- Se toma como fuente de datos la CTE 'ra_dividida', que ya dividió las RA en 80% y 100%.
    	
		-- Agrupación:
		GROUP BY 
			rd.reg_cod_personal, -- Agrupa por empleado.
			EXTRACT(WEEK FROM rd.reg_fecha) -- Agrupa por semana. Esto crea una fila por cada empleado por cada semana del mes.
	),
	/*
	 * CTE ra_divida_mensual_suma. 
	 - Esta es la CTE final en la cadena de cálculo del Recargo Adicional, consolidando los totales semanales al nivel 
	 mensual para cada tipo de recargo (80% y 100%).
	*/
 	ra_dividia_mensual_suma AS (
        SELECT rs.reg_cod_personal,	-- Código del personal.
				
				-- ra_80_mensual (Suma mensual de Recargo Adicional al 80%):
				-- Totaliza las horas de RA al 80% para todo el mes.
				SUM(rs.ra_80_semanal) AS ra_80_mensual,
				-- Simplemente suma los totales de RA_80 de cada semana (calculados en 'ra_divida_semanal_suma') para cada empleado.
				-- No se aplica ningún límite mensual en esta CTE para RA_80.
		
				-- ra_100_mensual (Suma mensual de Recargo Adicional al 100%):
				-- Propósito: Totaliza las horas de RA al 100% para todo el mes.
				SUM(rs.ra_100_semanal) AS ra_100_mensual
				-- Simplemente suma los totales de RA_100 de cada semana (calculados en 'ra_divida_semanal_suma') para cada empleado.
				-- No se aplica ningún límite mensual en esta CTE para RA_100.
		
		FROM ra_divida_semanal_suma rs	-- Se toma como fuente de datos la CTE 'ra_divida_semanal_suma', que ya calculó las RA 80% y 100% por semana.
		GROUP BY 
			rs.reg_cod_personal	-- Agrupa por empleado. Esto consolida todas las semanas de un empleado en una única fila mensual para ambos tipos de RA.
    ),
	/*
	 * CTE re_recalculada. 
	 - Esta CTE parece intentar ajustar o "recular" el valor de re para un día si el acumulado semanal ya ha alcanzado 
	 o superado un límite, evitando así un posible "doble conteo" o la aplicación incorrecta de horas extras cuando ya 
	 se ha llegado al tope semanal.
	*/
	re_recalculada AS (
		SELECT ras.reg_cod_personal,		-- Código del personal.
				ras.reg_fecha,				-- Fecha del día.
				rd.reg_horas_trabajadas,	-- Horas trabajadas para el día.
				ras.re,						-- Horas de recargo extra (RE) para ese día (sin recalcular aún).
				ras.re_acumulada_semanal,	-- Acumulado semanal de RE hasta este día.
				
				-- re_recalculada
				-- Recalcula o ajusta el valor de 're' para un día, específicamente si el acumulado semanal
				-- de RE ha alcanzado o superado el límite 'param.max_re_semanal'.
				CASE
					-- Verifica si `re_acumulada_semanal` es mayor o igual a 08:00:00
					
					-- Condición Principal: Verifica si el acumulado semanal de RE (hasta este día) es mayor o igual al límite semanal (param.max_re_semanal).
					WHEN ras.re_acumulada_semanal >= param.max_re_semanal 
						THEN
							CASE
								-- Si las horas trabajadas en este día superan las 9 horas.
								WHEN rd.reg_horas_trabajadas > '09:00:00'::interval 
									THEN
										-- Lógica de ajuste: Resta el "exceso" semanal del RE de este día.
										-- 'ras.re': El RE original calculado para este día.
										-- '(ras.re_acumulada_semanal - param.max_re_semanal)': Calcula cuánto se ha excedido el límite semanal con la acumulación hasta este día.
										-- El resultado es el RE de este día menos el exceso, potencialmen
										ras.re - (ras.re_acumulada_semanal - param.max_re_semanal)
								ELSE
									'00:00:00'::interval
							END
					ELSE
						-- Si el acumulado semanal de RE aún NO ha alcanzado el límite semanal, entonces 're_recalculada' es 0.
						-- Esta lógica es un poco inusual, ya que normalmente querrías mantener el 're' original en este caso.
						-- Si el propósito es solo "ajustar si se pasa del límite", esta parte debería ser 'ras.re'.
						'00:00:00'::interval
				END AS re_recalculada
		FROM re_acumulada_semanal ras	-- Fuente principal, que proporciona el RE diario y su acumulado semanal.
			JOIN re_diaria rd ON ras.reg_cod_personal = rd.reg_cod_personal AND ras.reg_fecha = rd.reg_fecha
			-- Se une con 're_diaria' para obtener 'reg_horas_trabajadas', que no está directamente en 're_acumulada_semanal'.
	)
    SELECT r.reg_fecha,				-- Fecha del registro
			r.reg_cod_personal,		-- Código del personal
			p.tur_entrada, 			-- Hora de entrada del turno programado
			p.tur_salida,			-- Hora de salida del turno programado
			p.par_valor_time,		-- Valor del parámetro de tolerancia del turno
			p.reg_hora_entrada,		-- Hora de la marcación de entrada
			p.reg_hora_salida,		-- Hora de la marcación de salida
			p.reg_horas_trabajadas,	-- Horas trabajadas calculadas
			p.reg_retraso,			-- Retraso calculado
			p.reg_horas_extras,		-- Horas extras iniciales
			
			-- re:
			-- Horas de Recargo Extra (RE) para el día, con prioridad a la versión 'recalculada' si existe un ajuste.
			CASE
				-- Si 're_recalculada' (la versión ajustada por límite semanal) no es '00:00:00' (es decir, hay un ajuste efectivo)...
				WHEN re_rec.re_recalculada <> '00:00:00'::interval 
					THEN re_rec.re_recalculada -- ...entonces usa el valor ajustado.
				ELSE 
					r.re -- De lo contrario, usa el valor original de 're' del día (calculado en 're_diaria').
			END AS re, -- Proviene de la CTE 're_recalculada' (alias 're_rec') o de 're_diaria' (alias 'r').
			
			r.horas_a_compensar,	-- Horas a compensar (de compensaciones)
			r.horas_compensadas,	-- Horas ya compensadas
			r.horas_restantes,		-- Horas restantes por compensar
			r.estado_compensacion,	-- Estado de la compensación (ej. 'PENDIENTE', 'COMPENSADO').
			s.re_semanal_suma, 		-- Suma total de las horas de Recargo Extra (RE) para la semana, con límites diarios y semanales aplicados. Proviene de la CTE 're_semanal' (alias 's').
			m.re_mensual_suma, 		-- Suma total de las horas de Recargo Extra (RE) para el mes, con límite mensual aplicado. Proviene de 're_mensual'
			ra_semanal.re_acumulada_semanal, -- Suma acumulada diaria de RE dentro de cada semana.
			ra_mensual.re_acumulada_mensual, -- Suma acumulada diaria de RE a lo largo de todo el mes.
			ra.ra AS horas_adicionales,	-- Horas de Recargo Adicional (RA) para el día, aplicando múltiples reglas de negocio complejas.
			ras.ra_semanal_suma,		-- Suma total de las horas de Recargo Adicional (RA) para la semana, excluyendo domingos.
			ma.ra_mensual_suma,			-- Suma total de las horas de Recargo Adicional (RA) para el mes.
			ra_dividida.ra_80,  		-- Porción de las horas de Recargo Adicional (RA) que se pagarán con un 80% de recargo.
			ra_dividida.ra_100,  		-- Porción de las horas de Recargo Adicional (RA) que se pagarán con un 100% de recargo.
			rds.ra_80_semanal,			-- Suma semanal de las horas de RA al 80%, considerando solo de Lunes a Viernes.
			rds.ra_100_semanal,			-- Suma semanal de las horas de RA al 100%, considerando de Lunes a Sábado.
			rdm.ra_80_mensual,			-- Suma mensual de las horas de RA al 80%.
			rdm.ra_100_mensual,			-- Suma mensual de las horas de RA al 100%.
			btrim(
				CASE
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
					ELSE NULL
				END
			) AS dia_semana,
			of.ocu_descripcion AS ocurrencia_descripcion,	-- Descripción de la ocurrencia aplicada al registro (ej. 'Permiso', 'Vacaciones').
			of.ocurrencia_tipo,	-- Tipo general de la ocurrencia.
			of.ocu_tipo,		-- Código numérico del tipo de ocurrencia.
			of.tip_codigo,		-- Código del tipo de la ocurrencia.
			ff.feriado_descripcion,	-- Descripción del feriado si la fecha del registro coincide con un feriado.
			CASE
				WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				ELSE NULL
			END AS tolerancia_especial	-- Descripción y tiempo de una tolerancia especial si aplica a la fecha del registro.
	FROM re_diaria r	-- La CTE re_diaria actúa como la tabla base, asegurando que cada fila en el resultado corresponda a un registro diario de un empleado.
		LEFT JOIN marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
		LEFT JOIN re_recalculada re_rec ON r.reg_cod_personal = re_rec.reg_cod_personal AND r.reg_fecha = re_rec.reg_fecha
		LEFT JOIN ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
		LEFT JOIN feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
		LEFT JOIN tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
		LEFT JOIN re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
		LEFT JOIN re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
		LEFT JOIN re_acumulada_semanal ra_semanal ON r.reg_cod_personal = ra_semanal.reg_cod_personal AND r.reg_fecha = ra_semanal.reg_fecha
		LEFT JOIN re_acumulada_mensual ra_mensual ON r.reg_cod_personal = ra_mensual.reg_cod_personal AND r.reg_fecha = ra_mensual.reg_fecha
		LEFT JOIN ra ra ON r.reg_cod_personal = ra.reg_cod_personal AND r.reg_fecha = ra.reg_fecha
		LEFT JOIN ra_dividida ON ra.reg_cod_personal = ra_dividida.reg_cod_personal AND ra.reg_fecha = ra_dividida.reg_fecha
		LEFT JOIN ra_semanal_suma ras ON r.reg_cod_personal = ras.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = ras.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		LEFT JOIN ra_mensual_suma ma ON r.reg_cod_personal = ma.reg_cod_personal
		LEFT JOIN ra_divida_semanal_suma rds ON r.reg_cod_personal = rds.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = rds.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		LEFT JOIN ra_dividia_mensual_suma rdm ON r.reg_cod_personal = rdm.reg_cod_personal
    ORDER BY r.reg_fecha, r.reg_cod_personal;
END; 
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_horas5_parametrizada_prueba(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas5_parametrizada_prueba(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, horas_a_compensar interval, horas_compensadas interval, horas_restantes interval, estado_compensacion character varying, dia_semana text, ocurrencia_descripcion text, ocurrencia_tipo text, ocu_tipo integer, tip_codigo character varying, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    param RECORD;
BEGIN
	-- Obtener los parámetros del año solicitado.
    SELECT * INTO param
    FROM calculo_parametros
    WHERE periodo_year = anio
    LIMIT 1;
	
    IF param IS NULL THEN
        RAISE EXCEPTION 'No hay parámetros para el año %', anio;
    END IF;
   	
	/*
	 * Estas líneas establecen configuraciones de sesión para la función. 
	 * Aseguran que la manipulación de fechas y tiempos sea consistente (UTC 
	 * para la zona horaria y DMY para el estilo de fecha) sin importar la 
	 * configuración global del servidor o del cliente.
	*/
	-- Configura la zona horaria a UTC para la sesión actual. Importante 
	-- para consistencia en cálculos de tiempo.
	PERFORM set_config('timezone', 'UTC', true);
	
	-- Configura el estilo de fecha a ISO, DMY (Día-Mes-Año).
    PERFORM set_config('DateStyle', 'ISO, DMY', true);
	
	-- Indica que el resultado de la siguiente consulta (que contiene 
	-- múltiples CTEs) será el resultado devuelto por la función.
    RETURN QUERY
	
	-- CTEs (Common Table Expressions - Bloques WITH):
	-- Aquí es donde reside la mayor parte de la lógica. 
	-- Cada CTE prepara un conjunto de datos intermedio que luego 
	-- se utiliza en CTEs posteriores o en la consulta final.
	
	/*
	 * calendar (Generador de Fechas del Mes):
	 - Crea una tabla temporal calendar que contiene todas las fechas día por día 
	 para el "mes y año" especificados en los parámetros de la función. 
	 Es fundamental para asegurar que el informe incluya todos los días del mes, 
	 incluso aquellos sin marcaciones.
	*/
    WITH RECURSIVE calendar AS (
        SELECT DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date	-- Selecciona el primer día del mes dado por 'anio' y 'mes'
        UNION ALL								-- Une con los siguientes días de forma recursiva
        SELECT (date + INTERVAL '1 day')::DATE	-- Suma un día a la fecha anterior
        FROM calendar
        WHERE date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'	-- Condición para detener la recursión: hasta el último día del mes
    ),
	/*
	 * marcaciones_completas (Marcaciones con Turnos y Cálculos Básicos):
	 - Centraliza las marcaciones de entrada y salida, les asocia el turno correspondiente 
	 y sus tolerancias, y realiza los cálculos iniciales de reg_horas_trabajadas, 
	 reg_retraso (con un ajuste de 59 segundos de gracia y tolerancia especial) y reg_horas_extras. 
	 Todo esto, filtrado para el param_reg_cod_personal de la función.
	*/
	marcaciones_completas AS (
        SELECT COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha, 						-- Fecha consolidada (de entrada o salida)
    			COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal, 	-- Código de personal consolidado
    			t.tur_entrada,															-- Hora de entrada programada del turno
    			t.tur_salida,															-- Hora de salida programada del turno
    			p.par_valor_time,														-- Valor del parámetro de tolerancia general
				t.tur_tipo,																-- Tipo de turno
				e.tol_tiempo_interval,													-- Tolerancia especial (obtenida de marcacion_entrada_adsoluta)
    			e.reg_hora AS reg_hora_entrada,											-- Hora de la marcación de entrada
    			s.reg_hora AS reg_hora_salida,											-- Hora de la marcación de salida
				-- Cálculo de Horas Trabajadas (igual que en la vista marcaciones_entradas_salidas)
    			CASE
        			WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada 
        				THEN s.reg_hora - t.tur_entrada
        			ELSE 
        				s.reg_hora - e.reg_hora
    			END AS reg_horas_trabajadas,
				-- Cálculo de Retraso (ajustado para incluir tolerancia especial y un segundo de gracia)
    			CASE
       				WHEN t.tur_tipo = 4 
       					THEN '00:00:00'::interval
       				WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval + e.tol_tiempo_interval) 
       					THEN e.reg_hora - (t.tur_entrada + p.par_valor_time + e.tol_tiempo_interval)
    				ELSE 
    					'00:00:00'::interval
				END AS reg_retraso,
				-- Cálculo de Horas Extras Iniciales (igual que en la vista marcaciones_entradas_salidas)
    			CASE
        			WHEN e.reg_hora IS NULL 
        				THEN NULL::interval
        			ELSE
            		CASE
                		WHEN s.reg_hora IS NULL 
                			THEN '00:00:00'::interval
                		WHEN e.reg_hora <= t.tur_entrada 
                			THEN s.reg_hora - t.tur_salida
                		ELSE 
                			s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
            		END
    			END AS reg_horas_extras
        FROM marcacion_entrada_adsoluta e
			FULL JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
			LEFT JOIN turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
				AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
				AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
			LEFT JOIN parametros p ON p.par_cod = t.tur_tolerancia
        WHERE COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
	/*
	 * ocurrencias_filtradas (Eventos y Ausencias):
	 - Identifica y consolida todas las "ocurrencias" (permisos, licencias, vacaciones, etc.) 
	 aplicables a un empleado durante el mes. Utiliza generate_series para "expandir" las 
	 ocurrencias de rango de fechas a días individuales y luego las agrupa para manejar 
	 múltiples ocurrencias en un mismo día. 
	 Excluye fines de semana para ciertos tipos de ocurrencia (ej. vacaciones).
	*/
	ocurrencias_filtradas AS (
		SELECT subquery.reg_cod_personal,	-- Código del personal
				subquery.reg_fecha,			-- Fecha del día específico. Generada por 'generate_series' para cada día de la ocurrencia dentro del mes.
				STRING_AGG(subquery.ocu_descripcion::text, ', ' ORDER BY subquery.ocu_descripcion)::text AS ocu_descripcion,	-- Agrupa descripciones de ocurrencias por día
    			STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo)::text AS ocurrencia_tipo,	-- Agrupa tipos de ocurrencias por día
				MIN(subquery.ocu_tipo) AS ocu_tipo,
				STRING_AGG(subquery.tip_codigo::character varying, ', ' ORDER BY subquery.tip_codigo)::character varying AS tip_codigo,	-- Agrupa códigos de tipo (ej. "VAC", "PER")
				MAX(subquery.ocu_horas_estaticas) AS ocu_horas_estaticas, 				-- Máximo de horas estáticas
				SUM(subquery.ocu_horas_extras) AS ocu_horas_extras,						-- Suma de horas extras de ocurrencias
				SUM(subquery.ocu_horas_adicionales) AS ocu_horas_adicionales, 			-- Suma de horas adicionales de ocurrencias (RA 80%)
				SUM(subquery.ocu_horas_adicionales_100) AS ocu_horas_adicionales_100 	-- Suma de horas adicionales de ocurrencias (RA 100%)
		FROM (
			SELECT o.ocu_cod_persona AS reg_cod_personal,
					
					-- Genera una serie de fechas (día a día) para cada ocurrencia, 
            		-- limitando el rango a la intersección entre la duración de la ocurrencia 
            		-- y el mes de interés (anio, mes).
					generate_series(
						GREATEST(o.ocu_fecha_desde::date, make_date(anio, mes, 1)), -- Inicia desde la fecha de inicio de la ocurrencia o el inicio del mes, el que sea posterior
							LEAST(
								CASE 
									-- Mantener tus condiciones existentes
									WHEN o.ocu_fecha_desde = o.ocu_fecha_hasta 
										THEN o.ocu_fecha_hasta
								ELSE 
									o.ocu_fecha_hasta
								END,
								(make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date -- Termina en la fecha de fin de la ocurrencia o el fin del mes, el que sea anterior
							) ,  -- Añadimos un día al límite superior
							'1 day'
    				)::date AS reg_fecha, 					-- Genera una fila por cada día que la ocurrencia está vigente en el mes
					o.ocu_descripcion,						-- Descripción original de la ocurrencia.
					t.tip_descripcion AS ocurrencia_tipo,	-- Descripción textual del tipo de ocurrencia (ej. "Vacaciones").
					t.tip_codigo,							-- Código del tipo de ocurrencia (ej. "VAC").
					o.ocu_tipo,								-- Código numérico del tipo de ocurrencia.
					o.ocu_horas_estaticas,					-- Horas estáticas asociadas a la ocurrencia.
					o.ocu_horas_extras,						-- Horas extras asociadas a la ocurrencia.
					o.ocu_horas_adicionales,				-- Horas adicionales (RA 80%) asociadas a la ocurrencia.
					o.ocu_horas_adicionales_100				-- Horas adicionales (RA 100%) asociadas a la ocurrencia.
			FROM ocurrencias o
					JOIN tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod -- Une con los tipos de ocurrencias para obtener descripciones
			WHERE o.ocu_cod_persona = param_reg_cod_personal -- Filtra para el empleado específico
    		AND o.ocu_fecha_desde <= (make_date(anio, mes, 1) + INTERVAL '1 month - 1 day')::date -- Ocurrencia debe iniciar en o antes del fin del mes
    		AND o.ocu_fecha_hasta >= make_date(anio, mes, 1) -- Ocurrencia debe terminar en o después del inicio del mes
        ) AS subquery
		WHERE NOT (
    			subquery.ocu_tipo = 1 -- Excluye ciertos tipos de ocurrencia (ej. si ocu_tipo 1 es vacaciones)
    			AND 
    			(EXTRACT(DOW FROM subquery.reg_fecha::date) = 6 -- Que caen en sábado (DOW=6)
    			OR 
    			EXTRACT(DOW FROM subquery.reg_fecha::date) = 0) -- O domingo (DOW=0)
			) -- Esto implica que para 'ocu_tipo = 1', los fines de semana no se cuentan como parte de la ocurrencia(Excluir sábados (6) y domingos (0) para vacaciones).
		GROUP BY subquery.reg_cod_personal, subquery.reg_fecha -- Agrupa para consolidar múltiples ocurrencias en un mismo día.
	),
	/*
	 * feriados_filtrados (Días Feriados):
	 - Obtiene una lista de todos los días feriados dentro del mes y año especificados.
	*/
    feriados_filtrados AS (
        SELECT f.fer_fecha AS reg_fecha, 					-- Fecha del feriado
    			f.fer_descripcion AS feriado_descripcion 	-- Descripción del feriado
		FROM feriados f
		WHERE EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes -- Filtra feriados para el año y mes dados.
    ),
	/*
	 * tolerancias_especiales_filtradas (Tolerancias Individuales/Grupo):
	 - Obtiene todas las tolerancias especiales (sean individuales o por grupo/sede) que podrían 
	 afectar al empleado durante el mes.
	*/
	tolerancias_especiales_filtradas AS (
        SELECT te.tol_cod_personal,	-- Código del personal para tolerancia individual
    			te.tol_fecha_desde,	-- Fecha de inicio de vigencia
    			te.tol_fecha_hasta,	-- Fecha de fin de vigencia
    			te.tol_descripcion,	-- Descripción de la tolerancia
    			te.tol_tiempo,		-- Valor de tiempo de la tolerancia
    			te.tol_tipo,		-- Tipo de tolerancia ('I' para Individual, 'G' para Grupo)
    			te.tol_sed_cod		-- Código de la sede para tolerancia de grupo
		FROM tolerancias_especiales te
		WHERE (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal) -- Filtra por tolerancias individuales del empleado
    		OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal)) -- O tolerancias de grupo que apliquen a la sede del empleado
    ),
	/*
	 * compensaciones_detalles_filtradas (Detalles de Compensaciones):
	 -  Consolida los detalles de compensación (horas a compensar, compensadas, restantes, estado) para 
	 el empleado en el mes dado.
	 Agrega los detalles de compensaciones (horas a compensar, compensadas, restantes, estado) por día 
	 para el empleado y mes. Esto es clave para determinar si las horas extras deben ser calculadas 
	 o si están sujetas a un esquema de compensación.
	*/
    compensaciones_detalles_filtradas AS (
        SELECT com_cod_personal,	-- Código del personal.
    			com_det_fecha,		-- Fecha del detalle de la compensación.
    			SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,	-- Suma todas las horas "a compensar" para un empleado en un día específico.
    			SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,	-- Suma todas las horas "ya compensadas" para un empleado en un día específico.
    			SUM(com_det_horas_restantes) AS com_det_horas_restantes,		-- Suma todas las horas "restantes por compensar" para un empleado en un día específico.
    			STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado	-- Concatena de forma única todos los estados de compensación para un empleado en un día específico.
		FROM ( 
				-- Esta subconsulta interna selecciona los detalles de compensación y su estado,
        		-- filtrando por el empleado y el mes/año (alias como 'sub').
				SELECT c.com_cod_personal,				-- Código del personal.
        				cd.com_det_fecha,				-- Fecha específica del detalle de compensación.
        				cd.com_det_horas_a_compensar,	-- Horas inicialmente a compensar.
        				cd.com_det_horas_compensadas,	-- Horas que ya han sido compensadas.
        				cd.com_det_horas_restantes,		-- Horas que aún quedan por compensar.
        				c.com_estado					-- Estado general de la compensación (ej. 'Pendiente', 'Cerrado').
    			FROM compensaciones_detalles cd	-- Tabla que contiene los registros de compensación detallados por fecha.
    				JOIN compensaciones_completas c ON cd.com_cod = c.com_cod	-- Une con la tabla maestra de compensaciones para obtener el código de personal y el estado general.
    			WHERE c.com_cod_personal = param_reg_cod_personal	-- Filtra por el código de personal del empleado.
        		AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio	-- Filtra por el año de la fecha del detalle.
        		AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes	-- Filtra por el mes de la fecha del detalle.
				) sub
		GROUP BY com_cod_personal, com_det_fecha -- Agrupa los resultados por empleado y por fecha. Esto consolida todos los registros de compensación que afectan a un mismo día para un empleado dado.
    ),
	/*
	 * re_diaria (Cálculo Diario de RE - Recargo Extra/Horas Extras):
	 - Calcula el valor final de las re (horas de recargo extra) para cada día del mes. 
	 Aplica una serie de reglas de negocio condicionales que consideran:
	 + Si hay horas estáticas por ocurrencia (tipo 12).
	 + Si el empleado tiene horas restantes por compensar (no se calculan extras).
	 + Si el empleado llegó con retraso (y si ese retraso es justificado por cierto tipo de ocurrencia).
	 + Las horas trabajadas reales y las horas de entrada/salida vs. el turno programado.
	 + Se asume que los tipos de ocurrencia 33, 26, 12, 29 representan permisos o situaciones 
	 que "justifican" el retraso o impactan el cálculo de RE.
	*/
	re_diaria AS (
		SELECT c.date AS reg_fecha, -- Fecha del calendario (cada día del mes).
				COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal, -- Código de personal consolidado
				-- Lógica compleja para calcular `re` (horas extras finales por día)
				-- Esta es la parte central que determina las "horas extra" o "recargo extra" según varias reglas de negocio.
				CASE
					-- Escenario excepcional: HORAS ESTATICAS (ocu_tipo = 12 y ocu_horas_estaticas = 1)
					-- Si la ocurrencia es de tipo 12 (ej. un tipo especial de permiso o evento) Y se ha marcado con 'ocu_horas_estaticas = 1' (indicando que las horas extra ya están predefinidas por la ocurrencia).
					WHEN of.ocu_tipo = 12 AND of.ocu_horas_estaticas = 1 
						THEN of.ocu_horas_extras::interval	-- Las RE son las horas extras definidas en la ocurrencia
    				
					-- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras (RE es 0)
					-- Si el empleado tiene un saldo positivo de horas restantes a compensar.
    				WHEN cd.com_det_horas_restantes > '00:00:00'::interval 
    					THEN '00:00:00'::interval
    				
					-- Escenario 2: Si la persona llegó tarde (retraso > 0) y NO tiene permisos específicos (tipos 33, 26, 12, 29), no se calculan horas extras
					-- Verifica si el empleado tuvo un retraso en la entrada Y no hay ninguna ocurrencia específica (33, 26, 12, 29) que justifique ese retraso.
					WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN '00:00:00'::interval

    				-- Nuevo Escenario (específico para ocu_tipo = 12 y retraso > 59 segundos) Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
					-- Si existe una ocurrencia del tipo 12 Y el retraso en la marcación es significativo (más de 59 segundos).
					WHEN EXISTS (
        					SELECT 1
        					FROM ocurrencias_filtradas of
        					WHERE of.reg_fecha = c.date
        					AND of.ocu_tipo = 12
    					) AND p.reg_retraso > '00:59:59'::interval 
    					THEN
        					CASE
								-- Si las horas trabajadas desde la entrada del turno (programado) hasta la salida real son más de 9 horas.
            					WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
            						THEN
                						LEAST(
                    						(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval, -- Las horas extra son el exceso sobre 8 horas (calculado desde la entrada del turno, no la marcación real).
                    						param.max_re_diario -- Pero se topan a un máximo de 2 horas.
                						)
            					ELSE 
            						'00:00:00'::interval -- Si no se cumple la condición de las 9 horas, no hay extras.
        					END
					
    				-- Escenario 3: No hay horas pendientes DE COMPENSAR, PERO hay permisos específicos (tipos 33, 26, 12, 29), calcular horas extras con reglas especiales
					-- Si no hay horas restantes a compensar Y existe alguna ocurrencia específica que podría afectar el cálculo de horas extras.
					WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
        				SELECT 1
        				FROM ocurrencias_filtradas of
        				WHERE of.reg_fecha = c.date
        				AND of.ocu_tipo IN (33, 26, 12, 29)
    				) THEN
        			CASE
						WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval 
							THEN -- Misma lógica que el "Nuevo Escenario" de arriba
	            				CASE
	                				WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
	                					THEN
	                    					LEAST(
	                        					(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
												param.max_re_diario
	                    					)
	                				ELSE 
	                					'00:00:00'::interval
	            				END
            			WHEN of.ocu_tipo = 29 
            				THEN -- Lógica específica para ocu_tipo 29 (ej. permiso de salida)
								-- Aquí se ajusta el cálculo de las horas trabajadas restando las horas compensadas (`cd.com_det_horas_compensadas`).
                				CASE
                    				WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > '09:00:00'::interval 
                    					THEN
                        					LEAST(
                            					(p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - '08:00:00'::interval,
                            					param.max_re_diario
                        					)
                    				ELSE 
                    					'00:00:00'::interval
                				END
            				ELSE -- Lógica general para otros tipos de ocurrencia
                				CASE
                    				WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval 
                    					THEN
                        					LEAST(
                            					(p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                            					param.max_re_diario
                        					)
                    				ELSE 
                    					'00:00:00'::interval
                				END
        					END
						
						-- Escenario 4: No hay horas pendientes NI permisos, y es parte de una seguidilla de días (esta condición es un poco confusa en su redacción SQL, puede estar incompleta o mal interpretada aquí), no calcular horas extras
               			-- La condición `NOT EXISTS (SELECT 1 FROM ocurrencias_filtradas of WHERE of.reg_fecha = c.date AND of.ocu_tipo IN (33, 26, 12, 29))` se repite desde el escenario 2.
						WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (
        						SELECT 1
        						FROM ocurrencias_filtradas of
        						WHERE of.reg_fecha = c.date
        						AND of.ocu_tipo IN (33, 26, 12, 29)
    						) 
    						THEN '00:00:00'::interval

    					-- Escenario 5: Cálculo general de RE si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
						-- Este es el caso "por defecto" para calcular las horas extras si ninguna de las condiciones especiales anteriores se cumplió.
						WHEN p.reg_horas_trabajadas > '09:00:00'::interval
    						THEN
        						LEAST(
            						p.reg_horas_trabajadas - '08:00:00'::interval,
            						param.max_re_diario
        						) -- Si trabajó más de 9 horas, las extras son el exceso sobre 8 horas, topado a 2 horas.

						-- En caso contrario (si ninguna de las condiciones anteriores se cumple), las horas extras son 00:00:00
    					ELSE 
    						'00:00:00'::interval
					END AS re,
					cd.com_det_horas_a_compensar AS horas_a_compensar,			-- Muestra las horas pendientes que deben ser compensadas para el día.
					cd.com_det_horas_compensadas AS horas_compensadas,			-- Muestra las horas que ya han sido compensadas para el día.
					cd.com_det_horas_restantes AS horas_restantes,				-- Muestra el saldo de horas restantes por compensar (o a favor/en contra) para el día.
					cd.com_estado::character varying AS estado_compensacion,	-- Muestra el estado (o los estados, si hay varios únicos) de las compensaciones para el día.
					p.reg_horas_trabajadas,										-- Muestra las horas de trabajo calculadas para el día.
					p.reg_hora_salida,											-- Muestra la hora de salida registrada por el empleado.
					p.reg_retraso,												-- Muestra el tiempo de retraso en la entrada del empleado.
					of.ocu_tipo,												-- Muestra el tipo de ocurrencia principal para el día (si aplica).
					of.ocu_horas_estaticas,										-- Indica si las horas extras de la ocurrencia son estáticas/predefinidas.
					of.ocu_horas_extras,										-- Muestra las horas extras especificadas en la ocurrencia.
					of.ocu_horas_adicionales,									-- Muestra las horas adicionales (ej. recargo al 80%) de la ocurrencia.
					of.ocu_horas_adicionales_100								-- Muestra las horas adicionales (ej. recargo al 100%) de la ocurrencia.
		FROM calendar c -- Se une con el calendario para asegurar que todas las fechas del mes estén presentes
			LEFT JOIN marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal -- Se unen las marcaciones del empleado
			LEFT JOIN ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal -- Se unen las ocurrencias del empleado
			LEFT JOIN compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal -- Se unen los detalles de compensación
	)
	SELECT r.reg_fecha,				-- Fecha del registro
			r.reg_cod_personal,		-- Código del personal
			p.tur_entrada, 			-- Hora de entrada del turno programado
			p.tur_salida,			-- Hora de salida del turno programado
			p.par_valor_time,		-- Valor del parámetro de tolerancia del turno
			p.reg_hora_entrada,		-- Hora de la marcación de entrada
			p.reg_hora_salida,		-- Hora de la marcación de salida
			p.reg_horas_trabajadas,	-- Horas trabajadas calculadas
			p.reg_retraso,			-- Retraso calculado
			p.reg_horas_extras,		-- Horas extras iniciales
			
			-- re:
			-- Horas de Recargo Extra (RE) para el día, con prioridad a la versión 'recalculada' si existe un ajuste.
			/*CASE
				-- Si 're_recalculada' (la versión ajustada por límite semanal) no es '00:00:00' (es decir, hay un ajuste efectivo)...
				WHEN re_rec.re_recalculada <> '00:00:00'::interval 
					THEN re_rec.re_recalculada -- ...entonces usa el valor ajustado.
				else*/ 
					r.re -- De lo contrario, usa el valor original de 're' del día (calculado en 're_diaria').
			/*END*/ AS re, -- Proviene de la CTE 're_recalculada' (alias 're_rec') o de 're_diaria' (alias 'r').
			
			r.horas_a_compensar,	-- Horas a compensar (de compensaciones)
			r.horas_compensadas,	-- Horas ya compensadas
			r.horas_restantes,		-- Horas restantes por compensar
			r.estado_compensacion,	-- Estado de la compensación (ej. 'PENDIENTE', 'COMPENSADO').
			--s.re_semanal_suma, 		-- Suma total de las horas de Recargo Extra (RE) para la semana, con límites diarios y semanales aplicados. Proviene de la CTE 're_semanal' (alias 's').
			--m.re_mensual_suma, 		-- Suma total de las horas de Recargo Extra (RE) para el mes, con límite mensual aplicado. Proviene de 're_mensual'
			--ra_semanal.re_acumulada_semanal, -- Suma acumulada diaria de RE dentro de cada semana.
			--ra_mensual.re_acumulada_mensual, -- Suma acumulada diaria de RE a lo largo de todo el mes.
			--ra.ra AS horas_adicionales,	-- Horas de Recargo Adicional (RA) para el día, aplicando múltiples reglas de negocio complejas.
			--ras.ra_semanal_suma,		-- Suma total de las horas de Recargo Adicional (RA) para la semana, excluyendo domingos.
			--ma.ra_mensual_suma,			-- Suma total de las horas de Recargo Adicional (RA) para el mes.
			--ra_dividida.ra_80,  		-- Porción de las horas de Recargo Adicional (RA) que se pagarán con un 80% de recargo.
			--ra_dividida.ra_100,  		-- Porción de las horas de Recargo Adicional (RA) que se pagarán con un 100% de recargo.
			--rds.ra_80_semanal,			-- Suma semanal de las horas de RA al 80%, considerando solo de Lunes a Viernes.
			--rds.ra_100_semanal,			-- Suma semanal de las horas de RA al 100%, considerando de Lunes a Sábado.
			--rdm.ra_80_mensual,			-- Suma mensual de las horas de RA al 80%.
			--rdm.ra_100_mensual,			-- Suma mensual de las horas de RA al 100%.
			btrim(
				CASE
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
					WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
					ELSE NULL
				END
			) AS dia_semana,
			of.ocu_descripcion AS ocurrencia_descripcion,	-- Descripción de la ocurrencia aplicada al registro (ej. 'Permiso', 'Vacaciones').
			of.ocurrencia_tipo,	-- Tipo general de la ocurrencia.
			of.ocu_tipo,		-- Código numérico del tipo de ocurrencia.
			of.tip_codigo,		-- Código del tipo de la ocurrencia.
			ff.feriado_descripcion,	-- Descripción del feriado si la fecha del registro coincide con un feriado.
			CASE
				WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
				ELSE NULL
			END AS tolerancia_especial	-- Descripción y tiempo de una tolerancia especial si aplica a la fecha del registro.
	FROM re_diaria r	-- La CTE re_diaria actúa como la tabla base, asegurando que cada fila en el resultado corresponda a un registro diario de un empleado.
		LEFT JOIN marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
		--LEFT JOIN re_recalculada re_rec ON r.reg_cod_personal = re_rec.reg_cod_personal AND r.reg_fecha = re_rec.reg_fecha
		LEFT JOIN ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
		LEFT JOIN feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
		LEFT JOIN tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
		--LEFT JOIN re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
		--LEFT JOIN re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
		--LEFT JOIN re_acumulada_semanal ra_semanal ON r.reg_cod_personal = ra_semanal.reg_cod_personal AND r.reg_fecha = ra_semanal.reg_fecha
		--LEFT JOIN re_acumulada_mensual ra_mensual ON r.reg_cod_personal = ra_mensual.reg_cod_personal AND r.reg_fecha = ra_mensual.reg_fecha
	--	LEFT JOIN ra ra ON r.reg_cod_personal = ra.reg_cod_personal AND r.reg_fecha = ra.reg_fecha
		--LEFT JOIN ra_dividida ON ra.reg_cod_personal = ra_dividida.reg_cod_personal AND ra.reg_fecha = ra_dividida.reg_fecha
		--LEFT JOIN ra_semanal_suma ras ON r.reg_cod_personal = ras.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = ras.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		--LEFT JOIN ra_mensual_suma ma ON r.reg_cod_personal = ma.reg_cod_personal
		--LEFT JOIN ra_divida_semanal_suma rds ON r.reg_cod_personal = rds.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = rds.week AND EXTRACT(ISODOW FROM r.reg_fecha) <= 6
		--LEFT JOIN ra_dividia_mensual_suma rdm ON r.reg_cod_personal = rdm.reg_cod_personal
    ORDER BY r.reg_fecha, r.reg_cod_personal;
END; 
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_horas_prueba(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas_prueba(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, ra interval, horas_a_compensar interval, horas_compensadas interval, horas_restantes interval, estado_compensacion character varying, re_semanal_suma interval, re_mensual_suma interval, ra_semanal_suma interval, ra_mensual_suma interval, dia_semana text, ocurrencia_descripcion text, ocurrencia_tipo text, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
    marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
                WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval) THEN e.reg_hora - (t.tur_entrada + p.par_valor_time)
                ELSE '00:00:00'::interval
            END AS reg_retraso,
            CASE
                WHEN e.reg_hora IS NULL THEN NULL::interval
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
            END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
    ocurrencias_filtradas AS (
        SELECT 
            subquery.reg_cod_personal,
            subquery.reg_fecha,
            STRING_AGG(subquery.ocu_descripcion::character varying, ', ' ORDER BY subquery.ocu_descripcion) AS ocu_descripcion,
			STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo) AS ocurrencia_tipo,
            MIN(subquery.ocu_tipo) AS ocu_tipo
        FROM (
            SELECT 
                o.ocu_cod_persona AS reg_cod_personal,
                generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
                o.ocu_descripcion,
				t.tip_descripcion AS ocurrencia_tipo,
                o.ocu_tipo
                
            FROM 
                ocurrencias o
            JOIN 
                tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
            WHERE 
                o.ocu_cod_persona = param_reg_cod_personal
        ) AS subquery
        GROUP BY 
            subquery.reg_cod_personal, subquery.reg_fecha
    ),
    feriados_filtrados AS (
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
    ),
    tolerancias_especiales_filtradas AS (
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
    ),
    compensaciones_detalles_filtradas AS (
        SELECT 
            com_cod_personal,
            com_det_fecha,
            SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,
            SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,
            SUM(com_det_horas_restantes) AS com_det_horas_restantes,
            STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado
        FROM (
            SELECT 
                c.com_cod_personal,
                cd.com_det_fecha,
                cd.com_det_horas_a_compensar,
                cd.com_det_horas_compensadas,
                cd.com_det_horas_restantes,
                c.com_estado
            FROM 
                compensaciones_detalles cd
            JOIN 
                compensaciones_completas c ON cd.com_cod = c.com_cod
            WHERE 
                c.com_cod_personal = param_reg_cod_personal
                AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio
                AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes
        ) sub
        GROUP BY 
            com_cod_personal, 
            com_det_fecha
    ),
	re_diaria AS (
    SELECT 
        c.date AS reg_fecha,
        COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
        CASE
            -- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras
            WHEN cd.com_det_horas_restantes > '00:00:00'::interval THEN '00:00:00'::interval

            -- Escenario 2: Si la persona llegó tarde (más de 1 hora) y no tiene permisos específicos, no se calculan horas extras
            WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN '00:00:00'::interval

  			-- Nuevo Escenario: Si existe una ocurrencia del tipo 12 y el retraso es mayor a 00:59:59, aplicar un cálculo especial
            WHEN EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo = 12
            ) AND p.reg_retraso > '00:59:59'::interval THEN
                CASE
                    WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                        LEAST(
                            (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                            '02:00:00'::interval
                        )
                    ELSE '00:00:00'::interval
                END

            -- Escenario 3: Si no hay horas pendientes, pero hay permisos específicos, calcular horas extras con reglas especiales
            WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN
                CASE
					WHEN of.ocu_tipo = 12 AND p.reg_retraso > '00:59:59'::interval THEN
			            CASE
			                WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
			                    LEAST(
			                        (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
			                        '02:00:00'::interval
			                    )
			                ELSE '00:00:00'::interval
			            END
                    WHEN of.ocu_tipo = 29 THEN
                        CASE
                            WHEN (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) > '09:00:00'::interval THEN
                                LEAST(
                                    (p.reg_hora_salida - (p.tur_entrada + cd.com_det_horas_compensadas)) - '08:00:00'::interval,
                                    '02:00:00'::interval
                                )
                            ELSE '00:00:00'::interval
                        END
                    ELSE
                        CASE
                            WHEN (p.reg_hora_salida - p.tur_entrada) > '09:00:00'::interval THEN
                                LEAST(
                                    (p.reg_hora_salida - p.tur_entrada) - '08:00:00'::interval,
                                    '02:00:00'::interval
                                )
                            ELSE '00:00:00'::interval
                        END
                END

            -- Escenario 4: Si no hay horas pendientes ni permisos, y además es parte de una seguidilla de días, no calcular horas extras
            WHEN cd.com_det_horas_restantes = '00:00:00'::interval AND NOT EXISTS (
                SELECT 1
                FROM ocurrencias_filtradas of
                WHERE of.reg_fecha = c.date
                AND of.ocu_tipo IN (33, 26, 12, 29)
            ) THEN '00:00:00'::interval

            -- Escenario 5: Si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
            WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                LEAST(
                    p.reg_horas_trabajadas - '08:00:00'::interval,
                    '02:00:00'::interval
                )

            -- En caso contrario, las horas extras son 00:00:00
            ELSE '00:00:00'::interval
        END AS re,
	  -- Cálculo de horas adicionales solo si RE es mayor o igual a 02:00:00 y se han trabajado más de 10 horas
		CASE
		    -- Solo calcular si RE es mayor o igual a 02:00:00 y si las horas trabajadas son más de 10 horas
		    WHEN LEAST(
		            p.reg_horas_trabajadas - '08:00:00'::interval,
		            '02:00:00'::interval
		        ) >= '02:00:00'::interval 
		    AND p.reg_horas_trabajadas > '10:00:00'::interval
		    THEN 
		        -- Calcular la diferencia entre las horas trabajadas y 10 horas, sin tope de 1 hora
		        p.reg_horas_trabajadas - '10:00:00'::interval
		    ELSE
		        '00:00:00'::interval -- Si no se cumplen las condiciones, las horas adicionales son 00:00:00
		END AS ra,
        cd.com_det_horas_a_compensar AS horas_a_compensar,
        cd.com_det_horas_compensadas AS horas_compensadas,
        cd.com_det_horas_restantes AS horas_restantes,
        cd.com_estado::character varying AS estado_compensacion
    FROM 
        calendar c
    LEFT JOIN 
        marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON c.date = of.reg_fecha AND of.reg_cod_personal = param_reg_cod_personal
    LEFT JOIN 
        compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal
),
   re_semanal AS (
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '08:00:00'::interval
            ) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    re_mensual AS (
        SELECT 
            rs.reg_cod_personal,
            LEAST(
                SUM(rs.re_semanal_suma),
                '32:00:00'::interval
            ) AS re_mensual_suma
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    ),
	ra_semanal AS (
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.ra >= '01:00:00' THEN LEAST(rd.ra, '01:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '05:00:00'::interval
            ) AS ra_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    ra_mensual AS (
        SELECT 
            ra.reg_cod_personal,
            LEAST(
                SUM(ra.ra_semanal_suma),
                '20:00:00'::interval
            ) AS ra_mensual_suma
        FROM ra_semanal ra
        GROUP BY ra.reg_cod_personal
    )
    SELECT 
        r.reg_fecha,
        r.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
        r.re,
		r.ra,
        r.horas_a_compensar,
        r.horas_compensadas,
        r.horas_restantes,
        r.estado_compensacion,
        s.re_semanal_suma,
        m.re_mensual_suma,
		sa.ra_semanal_suma,
        ma.ra_mensual_suma,
        btrim(
            CASE
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
                ELSE NULL
            END
        ) AS dia_semana,
        of.ocu_descripcion AS ocurrencia_descripcion,
        of.ocurrencia_tipo,
        ff.feriado_descripcion,
        CASE
            WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            ELSE NULL
        END AS tolerancia_especial
    FROM 
        re_diaria r
    LEFT JOIN 
        marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
    LEFT JOIN 
        feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
    LEFT JOIN 
        tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
    LEFT JOIN 
        re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
    LEFT JOIN 
        re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
    LEFT JOIN 
        ra_semanal sa ON r.reg_cod_personal = sa.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = sa.week
    LEFT JOIN 
        ra_mensual ma ON r.reg_cod_personal = ma.reg_cod_personal
    ORDER BY 
        r.reg_fecha, r.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_horas_prueba2(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_horas_prueba2(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, horas_a_compensar interval, horas_compensadas interval, horas_restantes interval, estado_compensacion character varying, re_semanal_suma interval, re_mensual_suma interval, re_acumulada_semanal interval, re_acumulada_mensual interval, dia_semana text, ocurrencia_descripcion text, ocurrencia_tipo text, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        -- Generamos el calendario con todos los días del mes
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),

    marcaciones_completas AS (
        -- Consulta para obtener las marcaciones completas de entrada y salida
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
                WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time + '00:00:59'::interval) THEN e.reg_hora - (t.tur_entrada + p.par_valor_time)
                ELSE '00:00:00'::interval
            END AS reg_retraso,
            CASE
                WHEN e.reg_hora IS NULL THEN NULL::interval
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
            END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),

    ocurrencias_filtradas AS (
        -- Consulta para filtrar las ocurrencias del empleado
        SELECT 
            subquery.reg_cod_personal,
            subquery.reg_fecha,
            STRING_AGG(subquery.ocu_descripcion::character varying, ', ' ORDER BY subquery.ocu_descripcion) AS ocu_descripcion,
            STRING_AGG(subquery.ocurrencia_tipo::character varying, ', ' ORDER BY subquery.ocurrencia_tipo) AS ocurrencia_tipo,
            MIN(subquery.ocu_tipo) AS ocu_tipo
        FROM (
            SELECT 
                o.ocu_cod_persona AS reg_cod_personal,
                generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
                o.ocu_descripcion,
                t.tip_descripcion AS ocurrencia_tipo,
                o.ocu_tipo
            FROM 
                ocurrencias o
            JOIN 
                tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
            WHERE 
                o.ocu_cod_persona = param_reg_cod_personal
        ) AS subquery
        GROUP BY 
            subquery.reg_cod_personal, subquery.reg_fecha
    ),

    feriados_filtrados AS (
        -- Filtramos los feriados
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
    ),

    tolerancias_especiales_filtradas AS (
        -- Consulta para obtener las tolerancias especiales
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
    ),

     compensaciones_detalles_filtradas AS (
        SELECT 
            com_cod_personal,
            com_det_fecha,
            SUM(com_det_horas_a_compensar) AS com_det_horas_a_compensar,
            SUM(com_det_horas_compensadas) AS com_det_horas_compensadas,
            SUM(com_det_horas_restantes) AS com_det_horas_restantes,
            STRING_AGG(DISTINCT com_estado::character varying, ', ') AS com_estado
        FROM (
            SELECT 
                c.com_cod_personal,
                cd.com_det_fecha,
                cd.com_det_horas_a_compensar,
                cd.com_det_horas_compensadas,
                cd.com_det_horas_restantes,
                c.com_estado
            FROM 
                compensaciones_detalles cd
            JOIN 
                compensaciones_completas c ON cd.com_cod = c.com_cod
            WHERE 
                c.com_cod_personal = param_reg_cod_personal
                AND EXTRACT(YEAR FROM cd.com_det_fecha) = anio
                AND EXTRACT(MONTH FROM cd.com_det_fecha) = mes
        ) sub
        GROUP BY 
            com_cod_personal, 
            com_det_fecha
    ),

    re_diaria AS (
        -- Cálculo de las horas extras diarias (RE)
        SELECT 
            c.date AS reg_fecha,
            p.reg_cod_personal,
            CASE
                -- Escenario 1: Si hay horas pendientes de compensar, no se calculan horas extras
                WHEN cd.com_det_horas_restantes > '00:00:00'::interval THEN '00:00:00'::interval
                -- Escenario 2: Si la persona llegó tarde (más de 1 hora) y no tiene permisos específicos, no se calculan horas extras
                WHEN p.reg_retraso > '00:00:00'::interval AND NOT EXISTS (
                    SELECT 1
                    FROM ocurrencias_filtradas of
                    WHERE of.reg_fecha = c.date
                    AND of.ocu_tipo IN (33, 26, 12, 29)
                ) THEN '00:00:00'::interval
                -- Escenario 5: Si ninguna de las condiciones anteriores aplica, se calculan las horas extras según las reglas generales
                WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                    LEAST(
                        p.reg_horas_trabajadas - '08:00:00'::interval,
                        '02:00:00'::interval
                    )
                -- En caso contrario, las horas extras son 00:00:00
                ELSE '00:00:00'::interval
            END AS re
        FROM 
            calendar c
        LEFT JOIN 
            marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
        LEFT JOIN 
            ocurrencias_filtradas of ON c.date = of.reg_fecha AND p.reg_cod_personal = of.reg_cod_personal
        LEFT JOIN 
            compensaciones_detalles_filtradas cd ON c.date = cd.com_det_fecha AND cd.com_cod_personal = param_reg_cod_personal
    ),

    re_acumulada_semanal AS (
        -- Acumular RE por semana
        SELECT 
            rd.reg_cod_personal,
            rd.reg_fecha,
            EXTRACT(WEEK FROM rd.reg_fecha) AS semana,
            rd.re,
            SUM(rd.re) OVER (PARTITION BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha) ORDER BY rd.reg_fecha) AS re_acumulada_semanal
        FROM 
            re_diaria rd
    ),

    re_acumulada_mensual AS (
        -- Acumular RE a lo largo del mes
        SELECT 
            rd.reg_cod_personal,
            rd.reg_fecha,
            rd.re,
            SUM(rd.re) OVER (PARTITION BY rd.reg_cod_personal ORDER BY rd.reg_fecha) AS re_acumulada_mensual
        FROM 
            re_diaria rd
    ),

    re_semanal AS (
        -- Calcular la suma semanal de RE, con un límite de 8 horas semanales
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '08:00:00'::interval
            ) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),

    re_mensual AS (
        -- Calcular la suma mensual de RE, con un límite de 32 horas
        SELECT 
            rs.reg_cod_personal,
            LEAST(
                SUM(rs.re_semanal_suma),
                '32:00:00'::interval
            ) AS re_mensual_suma
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    )

    SELECT 
        r.reg_fecha,
        r.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
        r.re,
        ra_semanal.re_acumulada_semanal, -- RE acumulada semanalmente
        ra_mensual.re_acumulada_mensual, -- RE acumulada mensualmente
        r.horas_a_compensar,
        r.horas_compensadas,
        r.horas_restantes,
        r.estado_compensacion,
        s.re_semanal_suma,
        m.re_mensual_suma,
           btrim(
            CASE
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
                ELSE NULL
            END
        ) AS dia_semana,
        of.ocu_descripcion AS ocurrencia_descripcion,
        of.ocurrencia_tipo,
        ff.feriado_descripcion,
        CASE
            WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::character varying)
            ELSE NULL
        END AS tolerancia_especial
    FROM 
        re_diaria r
    LEFT JOIN 
        marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
    LEFT JOIN 
        feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
    LEFT JOIN 
        tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
    LEFT JOIN 
        re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
    LEFT JOIN 
        re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
   LEFT JOIN 
        re_acumulada_semanal ra_semanal ON r.reg_cod_personal = ra_semanal.reg_cod_personal AND r.reg_fecha = ra_semanal.reg_fecha
    LEFT JOIN 
        re_acumulada_mensual ra_mensual ON r.reg_cod_personal = ra_mensual.reg_cod_personal AND r.reg_fecha = ra_mensual.reg_fecha
   ORDER BY 
        r.reg_fecha, r.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_prueba(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_prueba(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, re_semanal_suma interval, re_mensual_suma interval)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
    marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha) AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    )
    SELECT 
        c.date AS reg_fecha,
        p.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
        CASE
            WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                LEAST(
                    CEIL(EXTRACT(EPOCH FROM p.reg_horas_trabajadas - '09:00:00'::interval) / 3600) * '01:00:00'::interval,
                    '02:00:00'::interval
                )
            ELSE '00:00:00'::interval
        END AS re,
        SUM(
            CASE
                WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                    LEAST(
                        CEIL(EXTRACT(EPOCH FROM p.reg_horas_trabajadas - '09:00:00'::interval) / 3600) * '01:00:00'::interval,
                        '02:00:00'::interval
                    )
                ELSE '00:00:00'::interval
            END
        ) FILTER (WHERE EXTRACT(ISODOW FROM p.reg_fecha) <= 5) OVER (PARTITION BY EXTRACT(WEEK FROM p.reg_fecha)) AS re_semanal_suma,
        LEAST(
            SUM(
                CASE
                    WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                        LEAST(
                            CEIL(EXTRACT(EPOCH FROM p.reg_horas_trabajadas - '09:00:00'::interval) / 3600) * '01:00:00'::interval,
                            '02:00:00'::interval
                        )
                    ELSE '00:00:00'::interval
                END
            ) OVER (PARTITION BY EXTRACT(MONTH FROM p.reg_fecha)),
            '32:00:00'::interval
        ) AS re_mensual_suma
    FROM 
        calendar c
    LEFT JOIN 
        marcaciones_completas p ON c.date = p.reg_fecha
    ORDER BY 
        c.date, p.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_prueba2(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_prueba2(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, re_semanal_suma interval, re_mensual_suma interval, dia_semana text, ocurrencia_descripcion character varying, ocurrencia_tipo character varying, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
    marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
              	ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
                END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
         LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
    ocurrencias_filtradas AS (
        SELECT 
            o.ocu_cod_persona AS reg_cod_personal,
            generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
            o.ocu_descripcion,
            t.tip_descripcion AS ocurrencia_tipo
        FROM 
            ocurrencias o
        JOIN 
            tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
        WHERE 
            o.ocu_cod_persona = param_reg_cod_personal
    ),
    feriados_filtrados AS (
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
    ),
    tolerancias_especiales_filtradas AS (
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
    ),
    re_diaria AS (
        SELECT 
            c.date AS reg_fecha,
            COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
            CASE
                WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                    LEAST(
                        p.reg_horas_trabajadas - '08:00:00'::interval,
                        '02:00:00'::interval
                    )
                ELSE '00:00:00'::interval
            END AS re
        FROM 
            calendar c
        LEFT JOIN 
            marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
        LEFT JOIN 
            ocurrencias_filtradas of ON c.date = of.reg_fecha
    )
    SELECT 
        r.reg_fecha,
        r.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
        r.re,
        LEAST(
		    COALESCE(
		        SUM(r.re) FILTER (WHERE EXTRACT(ISODOW FROM r.reg_fecha) <= 5) OVER (PARTITION BY EXTRACT(WEEK FROM r.reg_fecha)),
		        '00:00:00'::interval
		    ),
		    '08:00:00'::interval
		) AS re_semanal_suma,
        LEAST(
		    SUM(
		        CASE
		            WHEN r.re >= '01:00:00' THEN LEAST(r.re, '02:00:00'::interval)
		            ELSE '00:00:00'::interval
		        END
		    ) OVER (PARTITION BY EXTRACT(MONTH FROM r.reg_fecha)),
		    '32:00:00'::interval
		) AS re_mensual_sumaa,
        btrim(
            CASE
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
                ELSE NULL
            END
        ) AS dia_semana,
        of.ocu_descripcion AS ocurrencia_descripcion,
        of.ocurrencia_tipo AS ocurrencia_tipo,
        ff.feriado_descripcion AS feriado_descripcion,
        CASE
            WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
            WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
            ELSE NULL
        END AS tolerancia_especial
    FROM 
        re_diaria r
    LEFT JOIN 
        marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha
    LEFT JOIN 
        feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
    LEFT JOIN 
        tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
    ORDER BY 
        r.reg_fecha, r.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.marcaciones_por_mes_prueba3(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.marcaciones_por_mes_prueba3(anio integer, mes integer, param_reg_cod_personal integer)
 RETURNS TABLE(reg_fecha date, reg_cod_personal integer, tur_entrada time without time zone, tur_salida time without time zone, par_valor_time interval, reg_hora_entrada time without time zone, reg_hora_salida time without time zone, reg_horas_trabajadas interval, reg_retraso interval, reg_horas_extras interval, re interval, re_semanal_suma interval, re_mensual_suma interval, dia_semana text, ocurrencia_descripcion character varying, ocurrencia_tipo character varying, feriado_descripcion character varying, tolerancia_especial text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE calendar AS (
        SELECT 
            DATE_TRUNC('month', make_date(anio, mes, 1))::DATE AS date
        UNION ALL
        SELECT 
            (date + INTERVAL '1 day')::DATE
        FROM 
            calendar
        WHERE 
            date + INTERVAL '1 day' < DATE_TRUNC('month', make_date(anio, mes, 1)) + INTERVAL '1 month'
    ),
    marcaciones_completas AS (
        SELECT 
            COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha,
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
                ELSE
                    CASE
                        WHEN s.reg_hora IS NULL THEN '00:00:00'::interval
                        WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida
                        ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada))
                    END
            END AS reg_horas_extras
        FROM 
            marcacion_entrada_adsoluta e
        FULL JOIN 
            marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
        LEFT JOIN 
            turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal 
            AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha)
            AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha))
        LEFT JOIN 
            parametros p ON p.par_cod = t.tur_tolerancia
        WHERE 
            COALESCE(e.reg_cod_personal, s.reg_cod_personal) = param_reg_cod_personal
    ),
    ocurrencias_filtradas AS (
        SELECT 
            o.ocu_cod_persona AS reg_cod_personal,
            generate_series(o.ocu_fecha_desde, o.ocu_fecha_hasta, '1 day') AS reg_fecha,
            o.ocu_descripcion,
            t.tip_descripcion AS ocurrencia_tipo
        FROM 
            ocurrencias o
        JOIN 
            tipos_ocurrencias t ON o.ocu_tipo = t.tip_cod
        WHERE 
            o.ocu_cod_persona = param_reg_cod_personal
    ),
    feriados_filtrados AS (
        SELECT 
            f.fer_fecha AS reg_fecha,
            f.fer_descripcion AS feriado_descripcion
        FROM 
            feriados f
        WHERE 
            EXTRACT(YEAR FROM f.fer_fecha) = anio AND EXTRACT(MONTH FROM f.fer_fecha) = mes
    ),
    tolerancias_especiales_filtradas AS (
        SELECT 
            te.tol_cod_personal,
            te.tol_fecha_desde,
            te.tol_fecha_hasta,
            te.tol_descripcion,
            te.tol_tiempo,
            te.tol_tipo,
            te.tol_sed_cod
        FROM 
            tolerancias_especiales te
        WHERE 
            (te.tol_tipo = 'I' AND te.tol_cod_personal = param_reg_cod_personal)
            OR (te.tol_tipo = 'G' AND te.tol_sed_cod = (SELECT per_sede FROM personales WHERE per_cod = param_reg_cod_personal))
    ),
    re_diaria AS (
        SELECT 
            c.date AS reg_fecha,
            COALESCE(p.reg_cod_personal, of.reg_cod_personal) AS reg_cod_personal,
            CASE
                WHEN p.reg_horas_trabajadas > '09:00:00'::interval THEN
                    LEAST(
                        p.reg_horas_trabajadas - '08:00:00'::interval,
                        '02:00:00'::interval
                    )
                ELSE '00:00:00'::interval
            END AS re
        FROM 
            calendar c
        LEFT JOIN 
            marcaciones_completas p ON c.date = p.reg_fecha AND p.reg_cod_personal = param_reg_cod_personal
        LEFT JOIN 
            ocurrencias_filtradas of ON c.date = of.reg_fecha
    ),
    re_semanal AS (
        SELECT 
            rd.reg_cod_personal,
            EXTRACT(WEEK FROM rd.reg_fecha) AS week,
            LEAST(
                COALESCE(
                    SUM(
                        CASE
                            WHEN rd.re >= '01:00:00' THEN LEAST(rd.re, '02:00:00'::interval)
                            ELSE '00:00:00'::interval
                        END
                    ) FILTER (WHERE EXTRACT(ISODOW FROM rd.reg_fecha) <= 5),
                    '00:00:00'::interval
                ),
                '08:00:00'::interval
            ) AS re_semanal_suma
        FROM re_diaria rd
        GROUP BY rd.reg_cod_personal, EXTRACT(WEEK FROM rd.reg_fecha)
    ),
    re_mensual AS (
        SELECT 
            rs.reg_cod_personal,
            LEAST(
                SUM(rs.re_semanal_suma),
                '32:00:00'::interval
            ) AS re_mensual_suma
        FROM re_semanal rs
        GROUP BY rs.reg_cod_personal
    )
    SELECT 
        r.reg_fecha,
        r.reg_cod_personal,
        p.tur_entrada,
        p.tur_salida,
        p.par_valor_time,
        p.reg_hora_entrada,
        p.reg_hora_salida,
        p.reg_horas_trabajadas,
        p.reg_retraso,
        p.reg_horas_extras,
        CASE
            WHEN r.re >= '01:00:00' THEN r.re
            ELSE '00:00:00'::interval
        END AS re,
        s.re_semanal_suma,
        m.re_mensual_suma,
        btrim(
            CASE
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '1' THEN 'DOMINGO'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '2' THEN 'LUNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '3' THEN 'MARTES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '4' THEN 'MIÉRCOLES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '5' THEN 'JUEVES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '6' THEN 'VIERNES'
                WHEN to_char(r.reg_fecha::timestamp with time zone, 'd') = '7' THEN 'SÁBADO'
                ELSE NULL
            END
        ) AS dia_semana,
        of.ocu_descripcion AS ocurrencia_descripcion,
        of.ocurrencia_tipo AS ocurrencia_tipo,
        ff.feriado_descripcion AS feriado_descripcion,
        CASE
            WHEN te.tol_tipo = 'I' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
            WHEN te.tol_tipo = 'G' AND r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta THEN CONCAT(te.tol_descripcion, ' - ', te.tol_tiempo::text)
            ELSE NULL
        END AS tolerancia_especial
    FROM 
        re_diaria r
    LEFT JOIN 
        marcaciones_completas p ON r.reg_fecha = p.reg_fecha AND r.reg_cod_personal = p.reg_cod_personal
    LEFT JOIN 
        ocurrencias_filtradas of ON r.reg_fecha = of.reg_fecha AND r.reg_cod_personal = of.reg_cod_personal
    LEFT JOIN 
        feriados_filtrados ff ON r.reg_fecha = ff.reg_fecha
    LEFT JOIN 
        tolerancias_especiales_filtradas te ON r.reg_fecha BETWEEN te.tol_fecha_desde AND te.tol_fecha_hasta
    LEFT JOIN 
        re_semanal s ON r.reg_cod_personal = s.reg_cod_personal AND EXTRACT(WEEK FROM r.reg_fecha) = s.week
    LEFT JOIN 
        re_mensual m ON r.reg_cod_personal = m.reg_cod_personal
    ORDER BY 
        r.reg_fecha, r.reg_cod_personal;
END;
$function$
;

-- DROP FUNCTION public.mes_a_letras(int4);

CREATE OR REPLACE FUNCTION public.mes_a_letras(mes_parametro integer)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    mes_letras VARCHAR(50);
BEGIN
    SELECT mes_letras INTO mes_letras
    FROM meses
    WHERE mes_cod = mes_parametro;

    RETURN mes_letras;
END;
$function$
;

-- DROP FUNCTION public.numerico(bpchar);

CREATE OR REPLACE FUNCTION public.numerico(str character)
 RETURNS character
 LANGUAGE plpgsql
AS $function$
DECLARE
    i INTEGER DEFAULT 1;
    len INTEGER;
    ret CHAR(255) DEFAULT '';
    c CHAR(1);
BEGIN
    -- Reemplazar '?' con ''
    str := replace(str, '?', '');
    
    -- Reemplazar ' ' con '?'
    str := replace(str, ' ', '?');
    
    -- Obtener la longitud de la cadena
    len := char_length(str);
    
    -- Reemplazar '.' con ','
    str := replace(str, '.', ',');
    
    -- Iterar sobre la cadena
    WHILE i <= len LOOP
        c := substr(str, i, 1);
        IF c ~ '[0-9]' THEN
            ret := ret || c;
        END IF;
        i := i + 1;
    END LOOP;
    
    -- Reemplazar '?' con ' '
    ret := replace(ret, '?', ' ');
    
    RETURN ret;
END;
$function$
;

-- DROP FUNCTION public.obtener_datos_funcionario(int4, int4, int4);

CREATE OR REPLACE FUNCTION public.obtener_datos_funcionario(anho integer, mes integer, id_funcionario integer)
 RETURNS TABLE(idfuncionario integer, dia_semana text, fechamarcacion date, hora_entrada_programada time without time zone, hora_salida_programada time without time zone, entrada time without time zone, salida time without time zone, horas_trabajadas interval, re interval, re_semanal_suma interval, re_mensual_suma interval, observacion_entrada character varying, horas_extras interval)
 LANGUAGE plpgsql
AS $function$
DECLARE
    fecha_inicio DATE := DATE_TRUNC('MONTH', MAKE_DATE(anho, mes, 1));
    fecha_fin DATE := (DATE_TRUNC('MONTH', MAKE_DATE(anho, mes, 1)) + INTERVAL '1 MONTH');
BEGIN
    -- Verificar que el mes esté dentro del rango válido (1-12)
    IF mes < 1 OR mes > 12 THEN
        RAISE EXCEPTION 'El mes especificado debe estar entre 1 y 12';
    END IF;

    RETURN QUERY
    SELECT
        vfa.reg_cod_personal AS idfuncionario,
        vfa.dia_semana,
        vfa.reg_fecha AS fechamarcacion,
        vfa.hora_entrada_programada,
        vfa.hora_salida_programada,
        vfa.entrada::time,
        vfa.salida::time,
        vfa.horas_trabajadas,
        CASE
            WHEN vfa.horas_trabajadas > '09:00:00'::interval THEN
                LEAST(
                    CEIL(EXTRACT(EPOCH FROM vfa.horas_trabajadas - '09:00:00'::interval) / 3600) * '01:00:00'::interval,
                    '02:00:00'::interval
                )
            ELSE '00:00:00'::interval
        END AS re,
        SUM(
            CASE
                WHEN vfa.horas_trabajadas > '09:00:00'::interval THEN
                    LEAST(
                        CEIL(EXTRACT(EPOCH FROM vfa.horas_trabajadas - '09:00:00'::interval) / 3600) * '01:00:00'::interval,
                        '02:00:00'::interval
                    )
                ELSE '00:00:00'::interval
            END
        ) FILTER (WHERE EXTRACT(ISODOW FROM vfa.reg_fecha) <= 5) OVER (PARTITION BY EXTRACT(WEEK FROM vfa.reg_fecha)) AS re_semanal_suma,
        LEAST(
            SUM(
                CASE
                    WHEN vfa.horas_trabajadas > '09:00:00'::interval THEN
                        LEAST(
                            CEIL(EXTRACT(EPOCH FROM vfa.horas_trabajadas - '09:00:00'::interval) / 3600) * '01:00:00'::interval,
                            '02:00:00'::interval
                        )
                    ELSE '00:00:00'::interval
                END
            ) OVER (PARTITION BY EXTRACT(MONTH FROM vfa.reg_fecha)),
            '32:00:00'::interval
        ) AS re_mensual_suma,
        CAST(NULL AS VARCHAR) AS observacion_entrada, -- Placeholder para las observaciones
        vfa.horas_extras
    FROM
        public.vista_func_asistencia vfa
    WHERE
        vfa.reg_cod_personal = id_funcionario
        AND vfa.reg_fecha >= fecha_inicio
        AND vfa.reg_fecha < fecha_fin;
END;
$function$
;

-- DROP FUNCTION public.orden(int4, int4);

CREATE OR REPLACE FUNCTION public.orden(codigo_parametro integer, funcionario_parametro integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    listado_1 TEXT;
    listado_2 TEXT;
    listado_3 TEXT;
    listado_4 TEXT;
    listado_5 TEXT;
    listado_final TEXT;
    resultado INTEGER;
BEGIN
    -- Obtener el primer listado de compensaciones
    SELECT orden_compensacion(codigo_parametro::TEXT, funcionario_parametro)
    INTO listado_1;
    listado_final := listado_1;

    IF listado_1 IS NOT NULL THEN
        -- Obtener el segundo listado concatenando el primero
        SELECT concat_ws(',', orden_compensacion(listado_1, funcionario_parametro), listado_1)
        INTO listado_2;
        listado_final := listado_2;

        IF listado_2 IS NOT NULL THEN
            -- Obtener el tercer listado concatenando el segundo
            SELECT concat_ws(',', orden_compensacion(listado_2, funcionario_parametro), listado_2)
            INTO listado_3;
            listado_final := listado_3;

            IF listado_3 IS NOT NULL THEN
                -- Obtener el cuarto listado concatenando el tercero
                SELECT concat_ws(',', orden_compensacion(listado_3, funcionario_parametro), listado_3)
                INTO listado_4;
                listado_final := listado_4;

                IF listado_4 IS NOT NULL THEN
                    -- Obtener el quinto listado concatenando el cuarto
                    SELECT concat_ws(',', orden_compensacion(listado_4, funcionario_parametro), listado_4)
                    INTO listado_5;
                    listado_final := listado_5;
                END IF;
            END IF;
        END IF;
    END IF;

    -- Calcular el resultado contando las compensaciones en el listado final
    SELECT count(*) + 1
    INTO resultado
    FROM (
        SELECT DISTINCT com_cod_ocurrencia
        FROM compensaciones
        WHERE position(com_cod_ocurrencia::TEXT IN listado_final) > 0
    ) AS datos;

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.orden_compensacion(text, int4);

CREATE OR REPLACE FUNCTION public.orden_compensacion(codigo_parametro text, funcionario_parametro integer)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    resultado TEXT;
BEGIN
    SELECT STRING_AGG(nivel_2.com_cod_ocurrencia::TEXT, ',')
    INTO resultado
    FROM (
        SELECT com_cod_ocurrencia, com_fecha_inicio, com_fecha_fin
        FROM compensaciones
        WHERE com_cod_personal = funcionario_parametro
        GROUP BY com_cod_ocurrencia, com_fecha_inicio, com_fecha_fin
    ) AS nivel_1
    JOIN (
        SELECT com_cod_ocurrencia, com_fecha_inicio, com_fecha_fin
        FROM compensaciones
        WHERE com_cod_personal = funcionario_parametro
        GROUP BY com_cod_ocurrencia, com_fecha_inicio, com_fecha_fin
    ) AS nivel_2 ON POSITION(nivel_1.com_cod_ocurrencia::TEXT IN codigo_parametro) > 0
    AND nivel_1.com_cod_ocurrencia <> nivel_2.com_cod_ocurrencia
    AND (
        nivel_2.com_fecha_inicio <= nivel_1.com_fecha_inicio
        AND (
            nivel_2.com_fecha_inicio BETWEEN nivel_1.com_fecha_inicio AND nivel_1.com_fecha_fin
            OR nivel_2.com_fecha_fin BETWEEN nivel_1.com_fecha_inicio AND nivel_1.com_fecha_fin
            OR nivel_1.com_fecha_inicio BETWEEN nivel_2.com_fecha_inicio AND nivel_2.com_fecha_fin
        )
    );

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    resultado VARCHAR(500);
BEGIN
    SELECT string_agg(ocurrencias.ocu_descripcion, ',') INTO resultado FROM (
        SELECT CONCAT('{', (SELECT tipos_ocurrencias.tip_codigo FROM tipos_ocurrencias WHERE tipos_ocurrencias.tip_cod = ocurrencias.ocu_tipo), '} ', ocurrencias.ocu_descripcion) AS ocu_descripcion,
               ocu_fecha_desde,
               ocu_fecha_hasta,
               ocu_tipo_grupo,
               ocu_cod_persona,
               ocu_tipo,
               ocu_cod_referencia,
               (
                   SELECT tip_dias FROM tipos_ocurrencias WHERE ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod
               ) AS ocu_tipo_dia
        FROM ocurrencias
    ) AS ocurrencias
    WHERE ((NOT (ocurrencias.ocu_tipo = 14 AND ocurrencias.ocu_cod_referencia IS NOT NULL)) AND ocurrencias.ocu_tipo <> 15)
      AND ((ocurrencias.ocu_cod_persona = funcionario_parametro OR ocu_tipo_grupo = 'G')
      AND (ocurrencias.ocu_fecha_desde <= fecha_parametro)
      AND (ocurrencias.ocu_fecha_hasta >= fecha_parametro)
      AND ((DAYOFWEEK(fecha_parametro) <> 7 AND DAYOFWEEK(fecha_parametro) <> 1) OR FIND_IN_SET(DAYOFWEEK(fecha_parametro), ocurrencias.ocu_dias))
      AND ((SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) < 1 OR ocu_tipo_dia <> 2 OR ocurrencias.ocu_tipo = 2));
    
    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_codigo(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_codigo(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    resultado VARCHAR(500);
BEGIN
    SELECT string_agg(
               ocurrencias.ocu_tipo::VARCHAR, ','
           ) INTO resultado
    FROM (
        SELECT 
            ocu_fecha_desde,
            ocu_fecha_hasta,
            ocu_tipo_grupo,
            ocu_cod_persona,
            ocu_tipo,
            ocu_hora_desde,
            ocu_hora_hasta,
            ocu_cod_referencia, 
            (
                SELECT tip_dias FROM tipos_ocurrencias WHERE ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod
            ) AS ocu_tipo_dia
        FROM ocurrencias
    ) AS ocurrencias
    WHERE (
        (NOT (ocurrencias.ocu_tipo = 14 AND ocurrencias.ocu_cod_referencia IS NOT NULL)) AND 
        ocurrencias.ocu_tipo <> 15 AND 
        (
            ocurrencias.ocu_cod_persona = funcionario_parametro OR 
            ocu_tipo_grupo = 'G'
        ) AND 
        (
            ocurrencias.ocu_fecha_desde <= fecha_parametro AND 
            ocurrencias.ocu_fecha_hasta >= fecha_parametro AND 
            (
                (DAYOFWEEK(fecha_parametro) <> 7 AND DAYOFWEEK(fecha_parametro) <> 1 AND ((SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) < 1)) OR 
                ocu_tipo_dia <> 2 OR 
                ocurrencias.ocu_tipo = 2
            )
        )
    );

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_datos(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_datos(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    resultado VARCHAR(5000);
BEGIN
    SELECT CONCAT(
        string_agg(
            COALESCE(ocurrencias.ocu_descripcion, ''), ',' 
        ), '#',
        string_agg(
            COALESCE(ocurrencias.ocu_tipo::VARCHAR, ''), ','
        ), '#',
        string_agg(
            COALESCE(ocurrencias.ocu_hora_desde::VARCHAR, ''), ','
        ), '#',
        string_agg(
            COALESCE(ocurrencias.ocu_hora_hasta::VARCHAR, ''), ','
        ), '#',
        string_agg(
            CASE 
                WHEN ocurrencias.ocu_tipo <> 2 AND ocurrencias.ocu_tipo <> 1 THEN 
                    COALESCE(
                        CONCAT(
                            '<a href=''ocurrencias_view.php?editid1=', ocurrencias.ocu_cod, ''' target=''_blank'' > ', 
                            ocurrencias.ocu_descripcion, 
                            '</a>'
                        ), 
                        ''
                    ) 
                WHEN ocurrencias.ocu_tipo = 1 THEN 
                    COALESCE(
                        CONCAT(
                            '<a href=''vacaciones_view.php?editid1=', 
                            (
                                SELECT vac_cod FROM vacaciones WHERE vac_cod = ocurrencias.ocu_cod_referencia
                            ), 
                            ''' target=''_blank'' > ', 
                            ocurrencias.ocu_descripcion, 
                            '</a>'
                        ), 
                        ''
                    ) 
                WHEN ocurrencias.ocu_tipo = 2 THEN 
                    COALESCE(
                        CONCAT(
                            '<a href=''feriados_view.php?editid1=', 
                            ocurrencias.ocu_cod_referencia, 
                            ''' target=''_blank'' > ', 
                            ocurrencias.ocu_descripcion, 
                            '</a>'
                        ), 
                        ''
                    ) 
                ELSE 
                    COALESCE(
                        ocurrencias.ocu_descripcion, 
                        ''
                    ) 
            END, 
            ','
        ), '#'
    ) INTO resultado
    FROM (
        SELECT 
            ocu_fecha_desde,
            ocu_fecha_hasta,
            ocu_tipo_grupo,
            ocu_cod_persona,
            ocu_tipo,
            ocu_hora_desde,
            ocu_hora_hasta,
            ocu_cod_referencia, 
            (
                SELECT tip_dias 
                FROM tipos_ocurrencias 
                WHERE ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod
            ) AS ocu_tipo_dia,
            ocu_funcionarios_afectados,
            ocu_tipo_grupo_sede,
            ocu_cod,
            ocu_dias,
            ocu_descripcion
        FROM ocurrencias
        WHERE fecha_parametro BETWEEN ocu_fecha_desde AND ocu_fecha_hasta AND (
            ocurrencias.ocu_cod_persona = funcionario_parametro OR 
            (
                ocu_tipo_grupo = 'G'  AND 
                (
                    FIND_IN_SET(funcionario_parametro, ocu_funcionarios_afectados) OR 
                    ocu_tipo = 2 OR 
                    ocu_tipo_grupo_sede = 100
                )
            )
        )
    ) AS ocurrencias
    WHERE (
        (
            NOT (
                ocurrencias.ocu_tipo = 14 AND 
                ocurrencias.ocu_cod_referencia IS NOT NULL
            ) 
            AND ocurrencias.ocu_tipo <> 15
        ) AND (
            ocurrencias.ocu_cod_persona = funcionario_parametro OR 
            (
                ocu_tipo_grupo = 'G'  AND 
                (
                    FIND_IN_SET(funcionario_parametro, ocu_funcionarios_afectados) OR 
                    ocu_tipo = 2 OR 
                    ocu_tipo_grupo_sede = 100
                )
            )
        ) AND (
            ocurrencias.ocu_fecha_desde <= fecha_parametro
        ) AND (
            ocurrencias.ocu_fecha_hasta >= fecha_parametro
        ) AND (
            (
                DAYOFWEEK(fecha_parametro) <> 7 AND 
                DAYOFWEEK(fecha_parametro) <> 1 AND 
                (
                    (
                        SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro
                    ) < 1 
                )
            ) OR 
            ocu_tipo_dia <> 2 OR 
            ocurrencias.ocu_tipo = 2
        )
    );

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_datos_desde(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_datos_desde(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    datos VARCHAR(500);
BEGIN
    SELECT min(ocu_hora_desde) INTO datos
    FROM (
        SELECT 
            ocu_fecha_desde,
            ocu_fecha_hasta,
            ocu_tipo_grupo,
            ocu_cod_persona,
            ocu_tipo,
            ocu_cod_referencia,
            ocu_hora_desde,
            ocu_hora_hasta,
            ocu_dias,
            (
                SELECT tip_dias 
                FROM tipos_ocurrencias 
                WHERE ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod
            ) AS ocu_tipo_dia,
            ocu_funcionarios_afectados,
            ocu_tipo_grupo_sede
        FROM ocurrencias
        WHERE (
            ocu_cod_persona = funcionario_parametro OR 
            (
                ocu_tipo_grupo_digito = 1 AND 
                (
                    FIND_IN_SET(funcionario_parametro, ocu_funcionarios_afectados) OR 
                    ocu_tipo = 2 OR 
                    ocu_tipo_grupo_sede = 100
                )
            )
        ) AND (
            ocu_fecha_desde <= fecha_parametro
        ) AND (
            ocu_fecha_hasta >= fecha_parametro
        ) AND (
            (
                DAYOFWEEK(fecha_parametro) <> 7 AND 
                DAYOFWEEK(fecha_parametro) <> 1 AND 
                (
                    (
                        SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro
                    ) < 1 
                )
            ) OR 
            ocu_tipo_dia <> 2 OR 
            ocurrencias.ocu_tipo = 2
        )
    ) AS ocurrencias;

    RETURN datos;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_datos_desde_hasta(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_datos_desde_hasta(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    hora_desde VARCHAR(8);
    hora_hasta VARCHAR(8);
    resultado VARCHAR(500);
BEGIN
    SELECT 
        MAX(ocu_hora_hasta) INTO hora_hasta
    FROM (
        SELECT 
            ocu_hora_hasta
        FROM ocurrencias
        WHERE (
            ocu_cod_persona = funcionario_parametro OR 
            (
                ocu_tipo_grupo_digito = 1 AND 
                (
                    FIND_IN_SET(funcionario_parametro, ocu_funcionarios_afectados) OR 
                    ocu_tipo = 2 OR 
                    ocu_tipo_grupo_sede = 100
                )
            )
        ) AND (
            ocu_fecha_desde <= fecha_parametro
        ) AND (
            ocu_fecha_hasta >= fecha_parametro
        ) AND (
            (
                DAYOFWEEK(fecha_parametro) <> 7 AND 
                DAYOFWEEK(fecha_parametro) <> 1 AND 
                (
                    (
                        SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro
                    ) < 1 
                )
            ) OR 
            ocu_tipo_dia <> 2 OR 
            ocurrencias.ocu_tipo = 2
        )
    ) AS ocurrencias;

    SELECT 
        MIN(ocu_hora_desde) INTO hora_desde
    FROM ocurrencias
    WHERE (
        ocu_cod_persona = funcionario_parametro OR 
        (
            ocu_tipo_grupo_digito = 1 AND 
            (
                FIND_IN_SET(funcionario_parametro, ocu_funcionarios_afectados) OR 
                ocu_tipo = 2 OR 
                ocu_tipo_grupo_sede = 100
            )
        )
    ) AND (
        ocu_fecha_desde <= fecha_parametro
    ) AND (
        ocu_fecha_hasta >= fecha_parametro
    ) AND (
        (
            DAYOFWEEK(fecha_parametro) <> 7 AND 
            DAYOFWEEK(fecha_parametro) <> 1 AND 
            (
                (
                    SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro
                ) < 1 
            )
        ) OR 
        ocu_tipo_dia <> 2 OR 
        ocurrencias.ocu_tipo = 2
    );

    resultado := hora_desde || '#' || hora_hasta;
    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_datos_enlaces(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_datos_enlaces(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    resultado VARCHAR(500);
BEGIN
    SELECT
        CONCAT(
            COALESCE(string_agg(
                CASE
                    WHEN ocu_tipo <> 1 AND ocu_tipo <> 2 THEN
                        COALESCE(
                            CONCAT(
                                '<a href=''ocurrencias_view.php?editid1=', ocurrencias.ocu_cod, ''' target=''_blank'' > ',
                                ocurrencias.ocu_descripcion,
                                '</a>'
                            ),
                            ''
                        )
                    ELSE
                        COALESCE(ocurrencias.ocu_descripcion, '')
                END,
                ','
            ), ''),
            '#',
            COALESCE(string_agg(COALESCE(ocurrencias.ocu_tipo, ''), ','), ''),
            '#',
            COALESCE(string_agg(COALESCE(ocurrencias.ocu_hora_desde, ''), ','), ''),
            '#',
            COALESCE(string_agg(COALESCE(ocurrencias.ocu_hora_hasta, ''), ','), ''),
            '#',
            COALESCE(string_agg(COALESCE(ocurrencias.ocu_tipo, ''), ','), '')
        ) INTO resultado
    FROM (
        SELECT 
            CONCAT('{', (SELECT tipos_ocurrencias.tip_codigo FROM tipos_ocurrencias WHERE tipos_ocurrencias.tip_cod = ocurrencias.ocu_tipo), '} ', ocurrencias.ocu_descripcion) AS ocu_descripcion,
            ocu_cod,
            ocu_fecha_desde,
            ocu_fecha_hasta,
            ocu_tipo_grupo,
            ocu_cod_persona,
            ocu_tipo,
            ocu_cod_referencia,
            ocu_hora_desde,
            ocu_hora_hasta,
            (SELECT tip_dias FROM tipos_ocurrencias WHERE ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod) AS ocu_tipo_dia,
            ocu_funcionarios_afectados,
            ocu_tipo_grupo_sede
        FROM ocurrencias
        WHERE (fecha_parametro BETWEEN ocu_fecha_desde AND ocu_fecha_hasta) 
        AND (
            ocu_cod_persona = funcionario_parametro
            OR (
                ocu_tipo_grupo = 'G'  
                AND (
                    FIND_IN_SET(funcionario_parametro, ocu_funcionarios_afectados) 
                    OR ocu_tipo = 2 
                    OR ocu_tipo_grupo_sede = 100
                )
            )
        )
    ) AS ocurrencias
    WHERE (
        ((NOT(ocurrencias.ocu_tipo = 14 AND ocurrencias.ocu_cod_referencia IS NOT NULL)) AND ocurrencias.ocu_tipo <> 15) 
        AND (
            ocurrencias.ocu_cod_persona = funcionario_parametro
            OR (ocurrencias.ocu_tipo_grupo = 'G' AND (FIND_IN_SET(funcionario_parametro, ocurrencias.ocu_funcionarios_afectados) OR ocurrencias.ocu_tipo = 2 OR ocurrencias.ocu_tipo_grupo_sede = 100))
        )
        AND (ocurrencias.ocu_fecha_desde <= fecha_parametro)
        AND (ocurrencias.ocu_fecha_hasta >= fecha_parametro)
        AND (
            (
                DAYOFWEEK(fecha_parametro) <> 7
                AND DAYOFWEEK(fecha_parametro) <> 1 
                AND ((SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) < 1 )
            )  
            OR (ocurrencias.ocu_tipo_dia <> 2) 
            OR (ocurrencias.ocu_tipo = 2)
        )
    );

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_datos_faltas(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_datos_faltas(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    min_ocu_hora_desde VARCHAR(50);
    max_ocu_hora_hasta VARCHAR(50);
    resultado VARCHAR(500);
BEGIN
    SELECT
        CONCAT(
            COALESCE(string_agg(COALESCE(ocurrencias.ocu_descripcion, ''), ','), ''),
            '#',
            COALESCE(string_agg(COALESCE(ocurrencias.ocu_tipo, ''), ','), ''),
            '#',
            COALESCE(min_ocu_hora_desde, ''),
            '#',
            COALESCE(max_ocu_hora_hasta, ''),
            '#',
            COALESCE(string_agg(COALESCE(ocurrencias.ocu_tipo, ''), ','), '')
        ) INTO resultado
    FROM (
        SELECT 
            CONCAT('{', (SELECT tipos_ocurrencias.tip_codigo FROM tipos_ocurrencias WHERE tipos_ocurrencias.tip_cod = ocurrencias.ocu_tipo), '} ', ocurrencias.ocu_descripcion) AS ocu_descripcion,
            ocu_fecha_desde,
            ocu_fecha_hasta,
            ocu_tipo_grupo,
            ocu_cod_persona,
            ocu_tipo,
            ocu_cod_referencia,
            ocu_hora_desde,
            ocu_hora_hasta,
            ocu_dias,
            (SELECT tip_dias FROM tipos_ocurrencias WHERE ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod) AS ocu_tipo_dia,
            ocu_funcionarios_afectados,
            ocu_tipo_grupo_sede
        FROM ocurrencias
        WHERE (
                ((NOT(ocurrencias.ocu_tipo = 14 AND ocurrencias.ocu_cod_referencia IS NOT NULL)) ) 
                AND (
                    ocurrencias.ocu_cod_persona = funcionario_parametro
                    OR (ocurrencias.ocu_tipo_grupo = 'G' AND (FIND_IN_SET(funcionario_parametro, ocurrencias.ocu_funcionarios_afectados) OR ocurrencias.ocu_tipo = 2 OR ocurrencias.ocu_tipo_grupo_sede = 100))
                )
                AND (ocurrencias.ocu_fecha_desde <= fecha_parametro)
                AND (ocurrencias.ocu_fecha_hasta >= fecha_parametro)
                AND (
                    (
                        DAYOFWEEK(fecha_parametro) <> 7
                        AND DAYOFWEEK(fecha_parametro) <> 1 
                        AND ((SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) < 1 )
                    )  
                    OR (ocu_tipo_dia <> 2) 
                    OR (ocurrencias.ocu_tipo = 2)
                )
            )
    ) AS ocurrencias;

    SELECT MIN(ocu_hora_desde) INTO min_ocu_hora_desde FROM ocurrencias WHERE ((
                ((NOT(ocurrencias.ocu_tipo = 14 AND ocurrencias.ocu_cod_referencia IS NOT NULL)) ) 
                AND (
                    ocurrencias.ocu_cod_persona = funcionario_parametro
                    OR ocurrencias.ocu_tipo_grupo = 'G'
                )
                AND (ocurrencias.ocu_fecha_desde <= fecha_parametro)
                AND (ocurrencias.ocu_fecha_hasta >= fecha_parametro)
                AND (
                    (
                        DAYOFWEEK(fecha_parametro) <> 7
                        AND DAYOFWEEK(fecha_parametro) <> 1 
                        AND ((SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) < 1 )
                    )  
                    OR (ocu_tipo_dia <> 2) 
                    OR (ocurrencias.ocu_tipo = 2)
                )
            ));

    SELECT MAX(ocu_hora_hasta) INTO max_ocu_hora_hasta FROM ocurrencias WHERE ((
                ((NOT(ocurrencias.ocu_tipo = 14 AND ocurrencias.ocu_cod_referencia IS NOT NULL)) ) 
                AND (
                    ocurrencias.ocu_cod_persona = funcionario_parametro
                    OR (ocurrencias.ocu_tipo_grupo = 'G' AND (FIND_IN_SET(funcionario_parametro, ocurrencias.ocu_funcionarios_afectados) OR ocurrencias.ocu_tipo = 2))
                )
                AND (ocurrencias.ocu_fecha_desde <= fecha_parametro)
                AND (ocurrencias.ocu_fecha_hasta >= fecha_parametro)
                AND (
                    (
                        DAYOFWEEK(fecha_parametro) <> 7
                        AND DAYOFWEEK(fecha_parametro) <> 1 
                        AND ((SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) < 1 )
                    )  
                    OR (ocu_tipo_dia <> 2) 
                    OR (ocurrencias.ocu_tipo = 2)
                )
            ));

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_datos_hasta(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_datos_hasta(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    resultado VARCHAR(500);
BEGIN
    SELECT
        MAX(ocu_hora_hasta)
    INTO resultado
    FROM (
        SELECT 
            ocu_fecha_desde,
            ocu_fecha_hasta,
            ocu_tipo_grupo,
            ocu_cod_persona,
            ocu_tipo,
            ocu_cod_referencia,
            ocu_hora_desde,
            ocu_hora_hasta,
            ocu_dias,
            (SELECT tip_dias FROM tipos_ocurrencias WHERE ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod) AS ocu_tipo_dia,
            ocu_funcionarios_afectados,
            ocu_tipo_grupo_sede
        FROM ocurrencias
        WHERE (
            (
                NOT((ocurrencias.ocu_tipo = 14 OR ocurrencias.ocu_tipo = 15) AND ocurrencias.ocu_cod_referencia IS NOT NULL) 
                AND NOT (ocurrencias.ocu_tipo = 15)
            )
            AND (
                ocurrencias.ocu_cod_persona = funcionario_parametro
                OR (ocu_tipo_grupo = 'G' AND (FIND_IN_SET(funcionario_parametro, ocu_funcionarios_afectados) OR ocu_tipo = 2 OR ocu_tipo_grupo_sede = 100))
            )
            AND (ocurrencias.ocu_fecha_desde <= fecha_parametro)
            AND (ocurrencias.ocu_fecha_hasta >= fecha_parametro)
            AND (
                (
                    EXTRACT(DOW FROM fecha_parametro) <> 0
                    AND EXTRACT(DOW FROM fecha_parametro) <> 1
                    AND (
                        SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro
                    ) < 1
                )
                OR (ocu_tipo_dia <> 2)
                OR (ocurrencias.ocu_tipo = 2)
            )
        )
    ) AS ocurrencias;

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_datos_listado_faltas(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_datos_listado_faltas(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    descripcion text;
    tipos text;
    hora_desde_min text;
    hora_hasta_max text;
BEGIN
    -- Concatena descripciones, tipos y horas
    SELECT 
        string_agg(ocu_descripcion, ','), 
        string_agg(ocu_tipo::text, ','), 
        string_agg(min_hora_desde::text, ','), 
        string_agg(max_hora_hasta::text, ',')
    INTO 
        descripcion, tipos, hora_desde_min, hora_hasta_max
    FROM (
        SELECT 
            '{' || COALESCE(tip.tip_codigo, '') || '} ' || ocu.ocu_descripcion AS ocu_descripcion,
            ocu.ocu_tipo,
            MIN(ocu.ocu_hora_desde) AS min_hora_desde,
            MAX(ocu.ocu_hora_hasta) AS max_hora_hasta
        FROM 
            ocurrencias ocu
            LEFT JOIN tipos_ocurrencias tip ON ocu.ocu_tipo = tip.tip_cod
        WHERE
            ocu.ocu_cod_persona = funcionario_parametro
            OR ocu_tipo_grupo = 'G'
            AND ocu.ocu_fecha_desde <= fecha_parametro
            AND ocu.ocu_fecha_hasta >= fecha_parametro
            AND (
                EXTRACT(DOW FROM fecha_parametro) NOT IN (0, 6)
                OR ocu.ocu_dias::text LIKE '%' || EXTRACT(DOW FROM fecha_parametro)::text || '%'
            )
            AND (
                (SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) = 0
                OR ocu_tipo_dia <> 2
                OR ocu.ocu_tipo = 2
            )
        GROUP BY ocu.ocu_descripcion, ocu.ocu_tipo
    ) as datos;

    -- Devuelve los resultados concatenados con '#'
    RETURN descripcion || '#' || tipos || '#' || hora_desde_min || '#' || hora_hasta_max;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_desde(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_desde(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    result text;
BEGIN
    SELECT string_agg(to_char(ocu_hora_desde, 'HH24:MI'), ',')
    INTO result
    FROM (
        SELECT 
            ocu_fecha_desde, ocu_fecha_hasta, ocu_tipo_grupo, ocu_cod_persona, ocu_tipo, ocu_hora_desde, ocu_hora_hasta, ocu_cod_referencia, ocu_funcionarios_afectados,
            (SELECT tip_dias FROM tipos_ocurrencias WHERE ocurrencias.ocu_tipo = tip_cod) AS ocu_tipo_dia
        FROM 
            ocurrencias
    ) AS ocurrencias
    WHERE
        (NOT (ocu_tipo = 14 AND ocu_cod_referencia IS NOT NULL) AND ocu_tipo <> 15)
        AND (ocu_cod_persona = funcionario_parametro OR (ocu_tipo_grupo = 'G' AND position(funcionario_parametro::text in ocu_funcionarios_afectados) > 0))
        AND ocu_fecha_desde <= fecha_parametro
        AND ocu_fecha_hasta >= fecha_parametro
        AND (
            (EXTRACT('dow' FROM fecha_parametro) NOT IN (0, 6) AND (SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) = 0)
            OR ocu_tipo_dia <> 2 OR ocu_tipo = 2
        );

    RETURN result;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_desde_hasta(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_desde_hasta(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    result varchar(500);
BEGIN
    SELECT
        TO_CHAR(MIN(ocu_hora_desde), 'HH24:MI') || '#' || TO_CHAR(MAX(ocu_hora_hasta), 'HH24:MI')
    INTO result
    FROM (
        SELECT 
            ocu_fecha_desde, ocu_fecha_hasta, ocu_tipo_grupo, ocu_cod_persona, ocu_tipo,
            ocu_cod_referencia, ocu_hora_desde, ocu_hora_hasta,
            (SELECT tip_dias FROM tipos_ocurrencias WHERE ocurrencias.ocu_tipo = tip_cod) AS ocu_tipo_dia,
            ocu_funcionarios_afectados, ocu_tipo_grupo_sede
        FROM 
            ocurrencias 
        WHERE 
            (ocu_cod_persona = funcionario_parametro OR (ocu_tipo_grupo = 'G' AND 
            (POSITION(funcionario_parametro::text IN ocu_funcionarios_afectados) > 0 OR ocu_tipo = 2 OR ocu_tipo_grupo_sede = 100))
            ) AND ocu_fecha_desde <= fecha_parametro AND ocu_fecha_hasta >= fecha_parametro
            AND ((EXTRACT('dow' FROM fecha_parametro) NOT IN (0, 6) AND
                 (SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) < 1) OR ocu_tipo_dia <> 2 OR ocu_tipo = 2)
    ) AS ocurrencias;

    RETURN result;
END;
$function$
;

-- DROP FUNCTION public.reg_observacion_horas(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observacion_horas(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    result varchar(500);
BEGIN
    SELECT
        COALESCE(MAX(ocu_horas_estaticas), 0)::text || '#' ||
        COALESCE(MAX(ocu_horas_extras), 0)::text || '#' ||
        COALESCE(MAX(ocu_horas_adicionales), 0)::text || '#' ||
        COALESCE(MAX(ocu_horas_adicionales_100), 0)::text
    INTO result
    FROM (
        SELECT 
            ocu_horas_estaticas, ocu_horas_extras, ocu_horas_adicionales, ocu_horas_adicionales_100,
            ocu_fecha_desde, ocu_fecha_hasta, ocu_tipo_grupo, ocu_cod_persona, ocu_tipo,
            ocu_cod_referencia, (SELECT tip_dias FROM tipos_ocurrencias WHERE ocu_tipo = tip_cod) AS ocu_tipo_dia
        FROM 
            ocurrencias 
        WHERE 
            (ocu_cod_persona = funcionario_parametro OR 
            (ocu_tipo_grupo = 'G' AND POSITION(funcionario_parametro::text IN ocu_funcionarios_afectados::text) > 0 OR ocu_tipo = 2 OR ocu_tipo = 2 OR ocu_tipo_grupo_sede = 100))
            AND ocu_fecha_desde <= fecha_parametro AND ocu_fecha_hasta >= fecha_parametro
    ) ocurrencias
    WHERE
        NOT (ocu_tipo = 14 AND ocu_cod_referencia IS NOT NULL) AND ocu_tipo <> 15
        AND (ocu_cod_persona = funcionario_parametro OR ocu_tipo_grupo = 'G')
        AND (EXTRACT('dow' FROM fecha_parametro) NOT IN (0, 6) OR ocu_tipo_dia <> 2 OR ocu_tipo = 2)
        AND (SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) < 1;

    RETURN result;
END;
$function$
;

-- DROP FUNCTION public.reg_observaciones_ocurrencias(int4, date);

CREATE OR REPLACE FUNCTION public.reg_observaciones_ocurrencias(funcionario_parametro integer, fecha_parametro date)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE
    resultado VARCHAR(500);
BEGIN
    SELECT CONCAT(
               COALESCE(string_agg(ocurrencias.ocu_horas_estaticas, ','), ''), '#',
               COALESCE(string_agg(ocurrencias.ocu_horas_extras, ','), ''), '#',
               COALESCE(string_agg(ocurrencias.ocu_horas_adicionales, ','), ''), '#',
               COALESCE(string_agg(ocurrencias.ocu_horas_adicionales_100, ','), ''), '#',
               LEAST(ocu_hora_desde)::TIME, '#',
               LEAST(ocu_hora_hasta)::TIME
           ) INTO resultado
    FROM (
        SELECT 
            ocu_fecha_desde,
            ocu_fecha_hasta,
            ocu_tipo_grupo,
            ocu_cod_persona,
            ocu_tipo,
            ocu_cod_referencia,
            ocu_hora_desde,
            ocu_hora_hasta,
            (
                SELECT tip_dias FROM tipos_ocurrencias WHERE ocurrencias.ocu_tipo = tipos_ocurrencias.tip_cod
            ) AS ocu_tipo_dia,
            ocu_funcionarios_afectados,
            ocu_horas_estaticas,
            ocu_horas_extras,
            ocu_horas_adicionales,
            ocu_horas_adicionales_100
        FROM (
            SELECT * FROM ocurrencias WHERE 
                (ocu_cod_persona = funcionario_parametro OR (ocu_tipo_grupo_digito = 1 AND (FIND_IN_SET(1, ocu_funcionarios_afectados) OR ocu_tipo = 2 OR ocu_tipo = 2 OR ocu_tipo_grupo_sede = 100)))
        ) AS ocurrencias 
        WHERE fecha_parametro BETWEEN ocu_fecha_desde AND ocu_fecha_hasta AND (
            ocurrencias.ocu_cod_persona = funcionario_parametro OR 
            (ocu_tipo_grupo = 'G' AND (FIND_IN_SET(funcionario_parametro, ocu_funcionarios_afectados) OR ocu_tipo = 2))
        )
    ) AS ocurrencias
    WHERE (
        (NOT (ocurrencias.ocu_tipo = 14 AND ocurrencias.ocu_cod_referencia IS NOT NULL)) AND 
        ocurrencias.ocu_tipo <> 15 AND 
        (
            ocurrencias.ocu_cod_persona = funcionario_parametro OR 
            ocu_tipo_grupo = 'G'
        ) AND 
        (
            ocurrencias.ocu_fecha_desde <= fecha_parametro AND 
            ocurrencias.ocu_fecha_hasta >= fecha_parametro AND 
            (
                (DAYOFWEEK(fecha_parametro) <> 7 AND DAYOFWEEK(fecha_parametro) <> 1 AND ((SELECT COUNT(*) FROM feriados WHERE fer_fecha = fecha_parametro) < 1)) OR 
                ocu_tipo_dia <> 2 OR 
                ocurrencias.ocu_tipo = 2
            )
        )
    );

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.set_anho_mes_sincronizacion();

CREATE OR REPLACE FUNCTION public.set_anho_mes_sincronizacion()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Establece año y mes del registro basándose en reg_fecha
    NEW.reg_anho := EXTRACT(YEAR FROM NEW.reg_fecha);
    NEW.reg_mes := EXTRACT(MONTH FROM NEW.reg_fecha);
    -- Establece la fecha de sincronización al momento actual
    NEW.reg_fecha_sincronizacion := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.split(text, text, int4);

CREATE OR REPLACE FUNCTION public.split(cadena text, delimitador text, ubicacion integer)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    resultado text;
    partes text[];
BEGIN
    IF ubicacion <= 0 THEN
        RETURN '';
    END IF;

    partes := string_to_array(cadena, delimitador);
    IF ubicacion > array_length(partes, 1) THEN
        RETURN '';
    ELSE
        resultado := partes[ubicacion];
    END IF;

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.split_str(text, text, int4);

CREATE OR REPLACE FUNCTION public.split_str(cadena text, delimitador text, ubicacion integer)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    partes text[];
    resultado text;
BEGIN
    IF ubicacion <= 0 THEN
        RETURN '';
    END IF;

    partes := string_to_array(cadena, delimitador);
    IF ubicacion > array_length(partes, 1) THEN
        RETURN '';
    ELSE
        resultado := partes[ubicacion];
    END IF;

    RETURN resultado;
END;
$function$
;

-- DROP FUNCTION public.sumatoria_compensacion(int4, date);

CREATE OR REPLACE FUNCTION public.sumatoria_compensacion(funcionario_parametro integer, fecha_parametro date)
 RETURNS time without time zone
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN (
        SELECT SUM(com_horas_restantes_acumuladas) 
        FROM compensaciones_actualizacion 
        WHERE com_cod_personal = funcionario_parametro 
        AND com_fecha = fecha_parametro
    );
END;
$function$
;

-- DROP FUNCTION public.turno_actualizar_insert();

CREATE OR REPLACE FUNCTION public.turno_actualizar_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Ajusta tur_entrada_horas y tur_salida_horas basado en tur_horas
    IF NEW.tur_horas = 1 THEN
        NEW.tur_entrada_horas := NEW.tur_entrada_horas;
        NEW.tur_salida_horas := NEW.tur_salida_horas;
    ELSE
        NEW.tur_entrada_horas := NEW.tur_entrada;
        NEW.tur_salida_horas := NEW.tur_salida;
    END IF;
    RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.turno_actualizar_update();

CREATE OR REPLACE FUNCTION public.turno_actualizar_update()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Ajusta tur_entrada_horas y tur_salida_horas basado en tur_horas
    IF NEW.tur_horas = 1 THEN
        NEW.tur_entrada_horas := NEW.tur_entrada_horas;
        NEW.tur_salida_horas := NEW.tur_salida_horas;
    ELSE
        NEW.tur_entrada_horas := NEW.tur_entrada;
        NEW.tur_salida_horas := NEW.tur_salida;
    END IF;
    RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.update_anho_mes();

CREATE OR REPLACE FUNCTION public.update_anho_mes()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Actualiza año y mes del registro basándose en reg_fecha
    NEW.reg_anho := EXTRACT(YEAR FROM NEW.reg_fecha);
    NEW.reg_mes := EXTRACT(MONTH FROM NEW.reg_fecha);
    RETURN NEW;
END;
$function$
;
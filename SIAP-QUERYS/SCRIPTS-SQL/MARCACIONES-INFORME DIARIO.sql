-------------------------------------------
-- REPORTE: MARCACIONES - INFORME DIARIO --
-------------------------------------------
SELECT per_cod, 
		per_nombre||' '||per_apellido||' ('||per_cod||') '||'('||per_ci||')' AS full_details
FROM personales
WHERE per_estado = 1
ORDER BY per_cod;

-- select utilizado para encabezado(Datos del Turno)
SELECT t.tur_descripcion,
        t.tur_entrada,
        t.tur_salida,
        t.tur_tipo,
        t.tur_horas_trabajo,
        tt.tip_descripcion,
        tur_fecha_desde ,
        tur_fecha_hasta,
        p.par_valor_time as tolerancia
FROM turnos t
        INNER JOIN tipos_turnos tt ON tt.tip_cod = t.tur_tipo
        INNER JOIN parametros p ON p.par_cod = t.tur_tolerancia
WHERE t.tur_cod_personal = 8
AND t.tur_fecha_desde <= make_date(2023, 6, 1)
AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= make_date(2023, 6, 1));

-- select utilizado en la grilla de datos del funcionario
SELECT * 
FROM vista_func_asistencia
WHERE reg_cod_personal = 8 
AND reg_fecha = '06/30/2023';
--AND reg_fecha = '07/04/2023';
-----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------

select * from historico_marcaciones_diarias;
select * from log_cron_historico_marcaciones;
select * from vista_func_asistencia order by reg_fecha desc; --2023-06-30
select count(*) as total from vista_func_asistencia; -- 117847
select insertar_historico_marcaciones_diarias();
select count(*) as total from historico_marcaciones_diarias; --117847

/* Paso 3: Crear el cron job que invoque a esta funcion. */
-- Asegúrate de que pg_cron está habilitado
-- Los comandos en pg_cron usan la sintaxis estándar de cron: minuto hora día_mes mes día_semana
CREATE EXTENSION IF NOT EXISTS pg_cron;
-- Crear el cron job
--Ejemplo para pruebas: cada minuto
SELECT cron.schedule(
	'cron_diario_marcaciones_prueba', -- nombre del job
	'* * * * *',                      -- cada minuto
	$$SELECT insertar_historico_marcaciones_diario();$$
);
-- Verificar los jobs existentes
SELECT * FROM cron.job;
-- Eliminar o modificar un cron job
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cron_diario_marcaciones_prueba';
-- Modificar: primero eliminas y luego lo creas de nuevo con nueva configuración.
-----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------


CREATE OR REPLACE VIEW marcacion_entrada_adsoluta AS 
	WITH earliest_entries AS (
		-- CTE 1: earliest_entries
		-- Su propósito es encontrar la primera marcación (hora más temprana)
		-- de cada empleado en un día dado, pero solo si esa marcación ocurrió antes de las 13:00 (1 PM).
		select res.reg_codigo,        -- Selecciona el código del registro
				res.reg_cod_personal, -- Selecciona el código del personal
				res.reg_fecha,        -- Selecciona la fecha del registro
				res.reg_hora,         -- Selecciona la hora del registro
				res.reg_tipo,         -- Selecciona el tipo de registro (ej. entrada/salida)
				res.reg_reloj         -- Selecciona el reloj donde se realizó la marcación
		from registros_entrada_salida res  -- Desde la tabla 'registros_entrada_salida', usando 'res' como alias
		where res.reg_hora = (             -- Primera condición: la hora del registro debe ser igual a...
		                        select min(auxiliar.reg_hora) -- ...la hora mínima (más temprana)
		                        from registros_entrada_salida auxiliar -- de la misma tabla, usando 'auxiliar' como alias
		                        where auxiliar.reg_cod_personal = res.reg_cod_personal -- para el mismo empleado
		                        and auxiliar.reg_fecha = res.reg_fecha            -- y para la misma fecha
		                     )
		and res.reg_hora < '13:00:00'::time without time zone -- Segunda condición: y la hora del registro debe ser ANTES de las 13:00:00 (1 PM)
    )
	SELECT DISTINCT ON (ee.reg_fecha, ee.reg_cod_personal) -- CLÁUSULA CLAVE 1: DISTINCT ON
			ee.reg_codigo,
			ee.reg_cod_personal,
			ee.reg_fecha,
			ee.reg_hora,
			ee.reg_tipo,
			ee.reg_reloj,
			COALESCE(te.tol_tiempo::interval, '00:00:00'::interval) AS tol_tiempo_interval -- CLÁUSULA CLAVE 2: Manejo de tolerancia
	FROM earliest_entries ee -- Usamos la CTE anterior como base
		LEFT JOIN LATERAL ( -- CLÁUSULA CLAVE 3: LEFT JOIN LATERAL para tolerancias
			-- Subconsulta LATERAL para encontrar la tolerancia especial aplicable
			SELECT te_1.tol_tiempo
			FROM tolerancias_especiales te_1
			WHERE (
					-- Condición para tolerancia INDIVIDUAL (tipo 'I')
					te_1.tol_tipo::text = 'I'::text 
					AND 
					te_1.tol_cod_personal = ee.reg_cod_personal 
					OR 
					-- Condición para tolerancia de GRUPO (tipo 'G')
					te_1.tol_tipo::text = 'G'::text 
					AND te_1.tol_sed_cod = (( SELECT personales.per_sede -- Subconsulta anidada para obtener la sede del personal
																FROM personales
																WHERE personales.per_cod = ee.reg_cod_personal
															))
				) 
			-- La tolerancia debe ser vigente para la fecha del registro
			AND ee.reg_fecha >= te_1.tol_fecha_desde 
			AND ee.reg_fecha <= te_1.tol_fecha_hasta
			ORDER BY (CASE -- Priorización de tolerancias si hay varias
						WHEN te_1.tol_tipo::text = 'I'::text THEN 1 -- Las tolerancias Individuales tienen prioridad (1 es menor)
						ELSE 2                                  -- Las tolerancias de Grupo tienen menor prioridad (2 es mayor)
						END), te_1.tol_fecha_desde DESC -- Si hay el mismo tipo, se prefiere la más reciente (fecha_desde DESC)
			LIMIT 1 -- Solo tomamos una tolerancia (la de mayor prioridad)
		) te ON true; -- La unión LATERAL siempre es verdadera para ejecutar la subconsulta por cada fila de 'earliest_entries'
------------------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.marcacion_salida_adsoluta as
-- Su propósito es identificar la última marcación de salida "absoluta" de 
-- cada personal en un día específico.
SELECT DISTINCT ON (reg_fecha, reg_cod_personal) -- CLÁUSULA CLAVE 1: DISTINCT ON
    reg_codigo, 		-- Selecciona el código del registro
    reg_cod_personal,	-- Selecciona el código del personal
    reg_fecha,			-- Selecciona la fecha del registro
    reg_hora,			-- Selecciona la hora del registro
    reg_tipo,			-- Selecciona el tipo de registro (ej. entrada/salida)
    reg_reloj			-- Selecciona el reloj donde se realizó la marcación
FROM registros_entrada_salida -- Desde la tabla de registros de entrada y salida
WHERE reg_hora = (              -- Primera condición: la hora del registro debe ser igual a...
    SELECT max(auxiliar.reg_hora) AS max -- ...la hora máxima (más tardía)
    FROM registros_entrada_salida auxiliar
    WHERE auxiliar.reg_cod_personal = registros_entrada_salida.reg_cod_personal
    AND auxiliar.reg_fecha = registros_entrada_salida.reg_fecha
)
AND reg_hora >= '10:00:00'::time without time zone -- Segunda condición: y la hora del registro debe ser DESPUÉS o IGUAL a las 10:00:00 (10 AM)
ORDER BY reg_fecha, reg_cod_personal, reg_hora DESC, reg_codigo; -- CLÁUSULA CLAVE 2: ORDER BY para DISTINCT ON
-----------------------------------------------------------------------------------------------

SELECT * FROM turnos;
SELECT * FROM parametros;
----------------------------

CREATE OR REPLACE VIEW public.marcaciones_entradas_salidas AS 
SELECT COALESCE(e.reg_fecha, s.reg_fecha) AS reg_fecha, -- Fecha consolidada (de entrada o salida si solo una existe)
		COALESCE(e.reg_cod_personal, s.reg_cod_personal) AS reg_cod_personal, -- Código de personal consolidado
		t.tur_entrada,     -- Hora de entrada programada del turno
		t.tur_salida,      -- Hora de salida programada del turno
		p.par_valor_time,  -- Valor del parámetro de tolerancia (ej. 15 minutos)
		e.reg_hora AS reg_hora_entrada, -- Hora de la marcación de entrada (desde marcacion_entrada_adsoluta)
		s.reg_hora AS reg_hora_salida,  -- Hora de la marcación de salida (desde marcacion_salida_adsoluta)

		-- CÁLCULO 1: reg_horas_trabajadas (Tiempo real de trabajo)
		CASE
			-- Si hay una marcación de entrada y esta es <= a la hora de entrada del turno (llegó a tiempo o temprano)
			WHEN e.reg_hora IS NOT NULL AND e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_entrada -- Se calcula desde la hora de entrada del turno hasta la salida
			-- En cualquier otro caso (ej. llegó tarde, o no hay entrada)
			ELSE s.reg_hora - e.reg_hora -- Se calcula desde su hora de entrada real hasta su salida real
		END AS reg_horas_trabajadas,

		-- CÁLCULO 2: reg_retraso (Tiempo de retraso)
		CASE
			-- Si hay una marcación de entrada y esta es > que la hora de entrada del turno MÁS el valor de tolerancia
			WHEN e.reg_hora IS NOT NULL AND e.reg_hora > (t.tur_entrada + p.par_valor_time) THEN e.reg_hora - (t.tur_entrada + p.par_valor_time) -- El retraso es la diferencia entre su entrada real y (entrada programada + tolerancia)
			-- En cualquier otro caso (no hay entrada, o llegó a tiempo, o llegó dentro de la tolerancia)
			ELSE '00:00:00'::interval -- No hay retraso, es 0 horas 0 minutos
		END AS reg_retraso,

		-- CÁLCULO 3: reg_horas_extras (Tiempo de horas extras)
		CASE
			WHEN e.reg_hora IS NULL THEN NULL::interval -- Si no hay marcación de entrada, no se calculan horas extras (es NULL)
			-- Si hay marcación de entrada Y esta es <= a la hora de entrada del turno MÁS el valor de tolerancia (llegó a tiempo o dentro de tolerancia)
			WHEN e.reg_hora <= (t.tur_entrada + p.par_valor_time) THEN
			CASE
				WHEN s.reg_hora IS NULL THEN '00:00:00'::interval -- Si no hay marcación de salida, no hay horas extras
				WHEN e.reg_hora <= t.tur_entrada THEN s.reg_hora - t.tur_salida -- Si llegó a tiempo o temprano, las extras son desde la salida programada hasta su salida real
				-- Si llegó un poco tarde, pero dentro de la tolerancia (porque lo cubre el WHEN e.reg_hora <= (t.tur_entrada + p.par_valor_time))
				ELSE s.reg_hora - (t.tur_salida + (e.reg_hora - t.tur_entrada)) -- Las extras se calculan ajustando la salida programada por el tiempo que llegó tarde.
                                                                                -- Por ejemplo, si entró 5 min tarde, su salida programada se "mueve" 5 min para calcular las extras.
			END
			-- Si llegó muy tarde (e.reg_hora > (t.tur_entrada + p.par_valor_time))
			ELSE '00:00:00'::interval -- No hay horas extras (se asume que si llega muy tarde, no acumula extras)
		END AS reg_horas_extras

FROM marcacion_entrada_adsoluta e -- Vista de entradas absolutas (alias 'e')
	FULL JOIN marcacion_salida_adsoluta s ON e.reg_fecha = s.reg_fecha AND e.reg_cod_personal = s.reg_cod_personal
    -- Se usa FULL JOIN para incluir:
    -- - Entradas que no tienen una salida correspondiente
    -- - Salidas que no tienen una entrada correspondiente
    -- - Y pares de entrada-salida que sí coinciden

	LEFT JOIN turnos t ON COALESCE(e.reg_cod_personal, s.reg_cod_personal) = t.tur_cod_personal -- Unir con la tabla de turnos
                           AND t.tur_fecha_desde <= COALESCE(e.reg_fecha, s.reg_fecha) -- Donde el turno es vigente desde
                           AND (t.tur_fecha_hasta IS NULL OR t.tur_fecha_hasta >= COALESCE(e.reg_fecha, s.reg_fecha)) -- Y el turno es vigente hasta (o no tiene fecha fin)
    -- Se usa LEFT JOIN porque una marcación podría no tener un turno asignado.

	LEFT JOIN parametros p ON p.par_cod = t.tur_tolerancia -- Unir con la tabla de parámetros para obtener el valor de la tolerancia
    -- Se usa LEFT JOIN porque un turno podría no tener un parámetro de tolerancia asociado.

ORDER BY (COALESCE(e.reg_fecha, s.reg_fecha)), (COALESCE(e.reg_cod_personal, s.reg_cod_personal)) DESC;
-- Ordena los resultados por fecha y luego por código de personal (descendente).
------------------------------------------------------------------------------------------

SELECT * FROM personales;
SELECT * FROM turnos;
-------------------------------

CREATE OR REPLACE VIEW public.vista_func_asistencia AS 
SELECT DISTINCT ON (m.reg_fecha, m.reg_cod_personal) m.reg_cod_personal,
		btrim(
			CASE
				WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '1'::text THEN 'DOMINGO'::text
				WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '2'::text THEN 'LUNES'::text
				WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '3'::text THEN 'MARTES'::text
				WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '4'::text THEN 'MIÉRCOLES'::text
				WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '5'::text THEN 'JUEVES'::text
				WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '6'::text THEN 'VIERNES'::text
				WHEN to_char(m.reg_fecha::timestamp with time zone, 'd'::text) = '7'::text THEN 'SÁBADO'::text
				ELSE NULL::text
			END
		) AS dia_semana,
		m.reg_fecha,
		p.per_nombre AS nombre,
		p.per_apellido AS apellido,
		t.tur_entrada AS hora_entrada_programada,
		t.tur_salida AS hora_salida_programada,
		m.reg_hora_entrada AS entrada,
		m.reg_hora_salida AS salida,
		m.reg_retraso AS retraso,
		m.reg_horas_trabajadas AS horas_trabajadas,
		m.reg_horas_extras AS horas_extras
FROM marcaciones_entradas_salidas m
		LEFT JOIN personales p ON m.reg_cod_personal = p.per_cod
		LEFT JOIN turnos t ON p.per_cod = t.tur_cod_personal
ORDER BY m.reg_fecha, m.reg_cod_personal;



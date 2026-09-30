-- public.actualizacion_generados definition

-- Drop table

-- DROP TABLE public.actualizacion_generados;

CREATE TABLE public.actualizacion_generados (
	act_cod serial4 NOT NULL,
	act_tipo varchar(255) NULL,
	act_anho int4 NULL,
	act_mes int4 NULL,
	act_estado int4 NULL,
	CONSTRAINT actualizacion_generados_pkey PRIMARY KEY (act_cod)
);


-- public.anhos definition

-- Drop table

-- DROP TABLE public.anhos;

CREATE TABLE public.anhos (
	cod int4 NOT NULL,
	numero int4 NULL,
	numero_meses int4 NULL,
	CONSTRAINT anhos_pkey PRIMARY KEY (cod)
);


-- public.auditoria_reloj definition

-- Drop table

-- DROP TABLE public.auditoria_reloj;

CREATE TABLE public.auditoria_reloj (
	aud_cod serial4 NOT NULL,
	aud_ip varchar(20) NULL,
	aud_error varchar(2000) NULL,
	aud_fecha date DEFAULT CURRENT_DATE NULL,
	CONSTRAINT auditoria_reloj_pkey PRIMARY KEY (aud_cod)
);


-- public.auxiliar definition

-- Drop table

-- DROP TABLE public.auxiliar;

CREATE TABLE public.auxiliar (
	cod_detalle int4 NOT NULL,
	valor_1 int4 NULL,
	valor_2 int4 NULL,
	valor_3 int4 NULL,
	CONSTRAINT auxiliar_pkey PRIMARY KEY (cod_detalle)
);


-- public.calculo_parametros definition

-- Drop table

-- DROP TABLE public.calculo_parametros;

CREATE TABLE public.calculo_parametros (
	id serial4 NOT NULL,
	periodo_year int4 NOT NULL,
	estado varchar(10) NULL,
	max_re_diario interval DEFAULT '02:00:00'::interval NULL,
	max_re_semanal interval DEFAULT '08:00:00'::interval NULL,
	max_re_mensual interval DEFAULT '32:00:00'::interval NULL,
	limite_ra_normal interval DEFAULT '10:00:00'::interval NULL,
	hora_tope_ra_80 time DEFAULT '19:59:59'::time without time zone NULL,
	dias_laborables jsonb DEFAULT '[1, 2, 3, 4, 5]'::jsonb NULL,
	feriados_incluidos bool DEFAULT true NULL,
	compensatorio_usado bool DEFAULT true NULL,
	re_calculado bool DEFAULT true NULL,
	usu_cod int4 NULL,
	fecha_insert timestamp NULL,
	CONSTRAINT calculo_parametros_estado_check CHECK (((estado)::text = ANY (ARRAY[('activo'::character varying)::text, ('inactivo'::character varying)::text]))),
	CONSTRAINT calculo_parametros_periodo_year_key UNIQUE (periodo_year),
	CONSTRAINT calculo_parametros_pkey PRIMARY KEY (id)
);


-- public.cantidad_actual definition

-- Drop table

-- DROP TABLE public.cantidad_actual;

CREATE TABLE public.cantidad_actual (
	count int8 NULL
);


-- public.cantidad_vacaciones_por_anho definition

-- Drop table

-- DROP TABLE public.cantidad_vacaciones_por_anho;

CREATE TABLE public.cantidad_vacaciones_por_anho (
	can_cod int4 NOT NULL,
	can_anhos_desde int4 NULL,
	can_anhos_hasta int4 NULL,
	can_cantidad int4 NULL,
	CONSTRAINT cantidad_vacaciones_por_anho_pkey PRIMARY KEY (can_cod)
);


-- public.cargos definition

-- Drop table

-- DROP TABLE public.cargos;

CREATE TABLE public.cargos (
	car_cod serial4 NOT NULL,
	car_descri varchar(50) NULL,
	car_cod_tipo_cargo int4 NULL,
	CONSTRAINT cargos_pkey PRIMARY KEY (car_cod)
);


-- public.cedula definition

-- Drop table

-- DROP TABLE public.cedula;

CREATE TABLE public.cedula (
	cedula int4 NOT NULL,
	apellido varchar(255) NULL,
	nombre varchar(255) NULL,
	fecha_nacim varchar(255) NULL,
	sexo varchar(255) NULL,
	estado_civil varchar(255) NULL,
	CONSTRAINT cedula_pkey PRIMARY KEY (cedula)
);


-- public.configuracion definition

-- Drop table

-- DROP TABLE public.configuracion;

CREATE TABLE public.configuracion (
	con_cod serial4 NOT NULL,
	con_fecha_desde date NULL,
	con_fecha_hasta date NULL,
	con_valor varchar(255) DEFAULT '0'::character varying NULL,
	con_horas int2 NULL,
	con_grupo int4 DEFAULT 0 NULL,
	CONSTRAINT configuracion_pkey PRIMARY KEY (con_cod)
);
CREATE INDEX idx_codigo_configuracion ON public.configuracion USING btree (con_cod);
CREATE INDEX idx_fechas ON public.configuracion USING btree (con_fecha_desde, con_fecha_hasta);


-- public.configuracion_llegada_tardia definition

-- Drop table

-- DROP TABLE public.configuracion_llegada_tardia;

CREATE TABLE public.configuracion_llegada_tardia (
	con_cod serial4 NOT NULL,
	con_fecha_desde date NULL,
	con_fecha_hasta date NULL,
	con_valor varchar(255) NULL,
	con_grupo int4 NULL,
	CONSTRAINT configuracion_llegada_tardia_pkey PRIMARY KEY (con_cod)
);


-- public.dependencias definition

-- Drop table

-- DROP TABLE public.dependencias;

CREATE TABLE public.dependencias (
	dep_cod serial4 NOT NULL,
	dep_descripcion_corta varchar(50) NULL,
	dep_descripcion varchar(255) NULL,
	dep_padre int4 NULL,
	dep_estado int4 NULL,
	CONSTRAINT dependencias_pkey PRIMARY KEY (dep_cod)
);


-- public.dias definition

-- Drop table

-- DROP TABLE public.dias;

CREATE TABLE public.dias (
	dia_cod int4 NULL,
	dia_sumar int4 NULL
);
CREATE INDEX idx_dia ON public.dias USING btree (dia_cod);
CREATE INDEX idx_dia_sumar ON public.dias USING btree (dia_sumar);


-- public.estados definition

-- Drop table

-- DROP TABLE public.estados;

CREATE TABLE public.estados (
	es_cod serial4 NOT NULL,
	es_valor varchar(255) NULL,
	es_descripcion varchar(255) NULL,
	es_grupo int4 NULL,
	CONSTRAINT estados_pkey PRIMARY KEY (es_cod)
);


-- public.estados_tablas_generadas definition

-- Drop table

-- DROP TABLE public.estados_tablas_generadas;

CREATE TABLE public.estados_tablas_generadas (
	est_cod int4 NOT NULL,
	est_descripcion varchar(255) NULL,
	CONSTRAINT estados_tablas_generadas_pkey PRIMARY KEY (est_cod)
);


-- public.fechas definition

-- Drop table

-- DROP TABLE public.fechas;

CREATE TABLE public.fechas (
	fecha date NOT NULL,
	CONSTRAINT fechas_pkey PRIMARY KEY (fecha)
);


-- public.fechas_a_numeros definition

-- Drop table

-- DROP TABLE public.fechas_a_numeros;

CREATE TABLE public.fechas_a_numeros (
	numero int4 NOT NULL,
	CONSTRAINT fechas_a_numeros_pkey PRIMARY KEY (numero)
);
CREATE INDEX idx_id_2 ON public.fechas_a_numeros USING btree (numero);


-- public.fechas_ocurrencias definition

-- Drop table

-- DROP TABLE public.fechas_ocurrencias;

CREATE TABLE public.fechas_ocurrencias (
	fecha date NOT NULL,
	anho int4 NULL,
	mes int2 NULL,
	CONSTRAINT fechas_ocurrencias_pkey PRIMARY KEY (fecha)
);
CREATE INDEX idx_fecha_anho ON public.fechas_ocurrencias USING btree (anho);
CREATE INDEX idx_fecha_mes ON public.fechas_ocurrencias USING btree (mes);


-- public.historial_marcaciones definition

-- Drop table

-- DROP TABLE public.historial_marcaciones;

CREATE TABLE public.historial_marcaciones (
	id bigserial NOT NULL,
	periodo_year int4 NOT NULL,
	periodo_month int4 NOT NULL,
	fecha_insercion timestamp DEFAULT now() NULL,
	reg_fecha date NULL,
	reg_cod_personal int4 NULL,
	tur_entrada time NULL,
	tur_salida time NULL,
	par_valor_time interval NULL,
	reg_hora_entrada time NULL,
	reg_hora_salida time NULL,
	reg_horas_trabajadas interval NULL,
	reg_retraso interval NULL,
	reg_horas_extras interval NULL,
	re interval NULL,
	horas_a_compensar interval NULL,
	horas_compensadas interval NULL,
	horas_restantes interval NULL,
	estado_compensacion varchar NULL,
	re_semanal_suma interval NULL,
	re_mensual_suma interval NULL,
	re_acumulada_semanal interval NULL,
	re_acumulada_mensual interval NULL,
	ra interval NULL,
	ra_semanal_suma interval NULL,
	ra_mensual_suma interval NULL,
	ra_80 interval NULL,
	ra_100 interval NULL,
	ra_80_semanal interval NULL,
	ra_100_semanal interval NULL,
	ra_80_mensual interval NULL,
	ra_100_mensual interval NULL,
	dia_semana text NULL,
	ocurrencia_descripcion text NULL,
	ocurrencia_tipo text NULL,
	ocu_tipo int4 NULL,
	tip_codigo varchar NULL,
	feriado_descripcion text NULL,
	tolerancia_especial text NULL,
	CONSTRAINT historial_marcaciones_pkey PRIMARY KEY (id)
);


-- public.instituciones_origen definition

-- Drop table

-- DROP TABLE public.instituciones_origen;

CREATE TABLE public.instituciones_origen (
	ins_cod serial4 NOT NULL,
	ins_nombre varchar(255) NULL,
	CONSTRAINT instituciones_origen_pkey PRIMARY KEY (ins_cod)
);


-- public.mensajes definition

-- Drop table

-- DROP TABLE public.mensajes;

CREATE TABLE public.mensajes (
	men_cod serial4 NOT NULL,
	men_texto varchar(500) NULL,
	CONSTRAINT mensajes_pkey PRIMARY KEY (men_cod)
);


-- public.meses definition

-- Drop table

-- DROP TABLE public.meses;

CREATE TABLE public.meses (
	mes_cod serial4 NOT NULL,
	mes_letras varchar(255) NULL,
	CONSTRAINT meses_pkey PRIMARY KEY (mes_cod)
);


-- public.notificaciones definition

-- Drop table

-- DROP TABLE public.notificaciones;

CREATE TABLE public.notificaciones (
	not_cod serial4 NOT NULL,
	not_descripcion varchar(1000) NULL,
	not_fecha date NULL,
	not_archivo varchar(1000) NULL,
	CONSTRAINT notificaciones_pkey PRIMARY KEY (not_cod)
);


-- public.numeros definition

-- Drop table

-- DROP TABLE public.numeros;

CREATE TABLE public.numeros (
	num_cod serial4 NOT NULL,
	num_numero int4 NULL,
	num_sumar int4 NULL,
	num_letras varchar(255) NULL,
	CONSTRAINT numeros_pkey PRIMARY KEY (num_cod)
);


-- public.observaciones definition

-- Drop table

-- DROP TABLE public.observaciones;

CREATE TABLE public.observaciones (
	obs_cod serial4 NOT NULL,
	obs_cod_personal int4 NULL,
	obs_anho int4 NULL,
	obs_mes int4 NULL,
	obs_texto varchar(500) NULL,
	CONSTRAINT observaciones_pkey PRIMARY KEY (obs_cod)
);


-- public.observaciones_comisionamiento definition

-- Drop table

-- DROP TABLE public.observaciones_comisionamiento;

CREATE TABLE public.observaciones_comisionamiento (
	obs_cod serial4 NOT NULL,
	obs_descripcion varchar(1000) NULL,
	obs_funcionario int4 NULL,
	obs_fecha_desde date NULL,
	obs_fecha_hasta date NULL,
	CONSTRAINT observaciones_comisionamiento_pkey PRIMARY KEY (obs_cod)
);


-- public.ocurrencias definition

-- Drop table

-- DROP TABLE public.ocurrencias;

CREATE TABLE public.ocurrencias (
	ocu_cod serial4 NOT NULL,
	ocu_cod_persona int2 NULL,
	ocu_fecha_desde date NULL,
	ocu_fecha_hasta date NULL,
	ocu_hora_desde time NULL,
	ocu_hora_hasta time NULL,
	ocu_dias varchar(255) NULL,
	ocu_descripcion varchar(100) NULL,
	ocu_tipo int4 NULL,
	ocu_cantidad_periodo int4 NULL,
	ocu_periodo varchar(5) NULL,
	ocu_tipo_grupo varchar(2) NULL,
	ocu_tipo_grupo_sede varchar(255) NULL,
	ocu_funcionarios_afectados varchar(5000) NULL,
	ocu_tipo_grupo_digito int4 NULL,
	ocu_cod_referencia int4 NULL,
	ocu_sin_horas_extras int2 NULL,
	ocu_asueto int2 NULL,
	ocu_asueto_sin_horas int2 NULL,
	ocu_asueto_dia_completo int2 NULL,
	ocu_dias_gastados int4 NULL,
	ocu_compensar int2 NULL,
	ocu_horas_compensacion time NULL,
	ocu_compensa int2 NULL,
	ocu_horas_estaticas int2 NULL,
	ocu_horas_extras time NULL,
	ocu_horas_adicionales time NULL,
	ocu_horas_adicionales_100 time NULL,
	ocu_dia_completo int2 NULL,
	ocu_usuario varchar(50) NULL,
	ocu_archivo text NULL,
	CONSTRAINT ocurrencias_pkey PRIMARY KEY (ocu_cod)
);
CREATE INDEX idx_ocu_asueto ON public.ocurrencias USING btree (ocu_asueto);
CREATE INDEX idx_ocu_asueto_dia_completo ON public.ocurrencias USING btree (ocu_asueto_dia_completo);
CREATE INDEX idx_ocu_cod ON public.ocurrencias USING btree (ocu_cod);
CREATE INDEX idx_ocu_cod_persona ON public.ocurrencias USING btree (ocu_cod_persona);
CREATE INDEX idx_ocu_fecha_desde ON public.ocurrencias USING btree (ocu_fecha_desde, ocu_fecha_hasta);
CREATE INDEX idx_ocu_funcionarios_afectados ON public.ocurrencias USING btree (ocu_funcionarios_afectados);
CREATE INDEX idx_ocu_tipo_grupo ON public.ocurrencias USING btree (ocu_tipo_grupo);
CREATE INDEX idx_ocu_tipo_grupo_digito ON public.ocurrencias USING btree (ocu_tipo_grupo_digito);

-- Table Triggers

create trigger
insert
    before
insert
    on
    public.ocurrencias for each row execute function asignar_ocu_tipo_grupo_digito();
create trigger trg_regenerar_compensacion after
update
    of ocu_horas_compensacion on
    public.ocurrencias for each row
    when ((old.ocu_horas_compensacion is distinct
from
    new.ocu_horas_compensacion)) execute function fn_regenerar_compensacion();
create trigger
update
    before
update
    on
    public.ocurrencias for each row execute function actualizar_ocu_tipo_grupo_digito();


-- public.ocurrencias_solicitud definition

-- Drop table

-- DROP TABLE public.ocurrencias_solicitud;

CREATE TABLE public.ocurrencias_solicitud (
	ocu_cod serial4 NOT NULL,
	ocu_cod_persona int4 NULL,
	ocu_fecha_desde date NULL,
	ocu_fecha_hasta date NULL,
	ocu_hora_desde time NULL,
	ocu_hora_hasta time NULL,
	ocu_descripcion varchar(100) NULL,
	ocu_tipo int4 NULL,
	ocu_cantidad_periodo int4 NULL,
	ocu_periodo varchar(5) NULL,
	ocu_tipo_grupo varchar(2) NULL,
	ocu_tipo_grupo_sede varchar(255) NULL,
	ocu_funcionarios_afectados varchar(1000) NULL,
	ocu_tipo_grupo_digito int4 NULL,
	ocu_cod_referencia int4 NULL,
	ocu_sin_horas_extras int2 NULL,
	ocu_asueto int2 NULL,
	ocu_dias_gastados int4 NULL,
	ocu_compensar int2 NULL,
	ocu_horas_compensacion time NULL,
	ocu_compensa int2 NULL,
	CONSTRAINT ocurrencias_solicitud_pkey PRIMARY KEY (ocu_cod)
);

-- Table Triggers

create trigger insert_copy1 before
insert
    on
    public.ocurrencias_solicitud for each row execute function insertar_ocu_tipo_grupo_digito();
create trigger update_copy1 before
update
    on
    public.ocurrencias_solicitud for each row execute function actualizar_ocu_tipo_grupo_digito();


-- public.paises definition

-- Drop table

-- DROP TABLE public.paises;

CREATE TABLE public.paises (
	pai_cod serial4 NOT NULL,
	pai_descri varchar(40) NULL,
	CONSTRAINT paises_pkey PRIMARY KEY (pai_cod)
);


-- public.parametro_vacaciones definition

-- Drop table

-- DROP TABLE public.parametro_vacaciones;

CREATE TABLE public.parametro_vacaciones (
	par_cod serial4 NOT NULL,
	par_desde int4 NULL,
	par_hasta int4 NULL,
	par_dias int4 NULL,
	CONSTRAINT parametro_vacaciones_pkey PRIMARY KEY (par_cod)
);


-- public.parametros definition

-- Drop table

-- DROP TABLE public.parametros;

CREATE TABLE public.parametros (
	par_cod serial4 NOT NULL,
	par_descripcion varchar(255) NULL,
	par_valor varchar(255) NULL,
	par_valor_time interval NULL,
	par_estado int4 NULL,
	par_anho int4 NOT NULL,
	par_usuario varchar(255) NULL,
	CONSTRAINT parametros_pkey PRIMARY KEY (par_cod)
);
CREATE INDEX idx_parametro_anho ON public.parametros USING btree (par_anho);
CREATE INDEX idx_parametro_cod ON public.parametros USING btree (par_cod);


-- public.personas definition

-- Drop table

-- DROP TABLE public.personas;

CREATE TABLE public.personas (
	codigo serial4 NOT NULL,
	cedula int4 NULL,
	nombre varchar(255) NULL,
	CONSTRAINT personas_pkey PRIMARY KEY (codigo)
);


-- public.profesiones definition

-- Drop table

-- DROP TABLE public.profesiones;

CREATE TABLE public.profesiones (
	pro_cod serial4 NOT NULL,
	pro_descri varchar(40) NULL,
	CONSTRAINT profesiones_pkey PRIMARY KEY (pro_cod)
);


-- public.referenciales definition

-- Drop table

-- DROP TABLE public.referenciales;

CREATE TABLE public.referenciales (
	ref_cod serial4 NOT NULL,
	ref_descripcion varchar(255) NULL,
	ref_valor varchar(3) NULL,
	ref_referencia int2 DEFAULT 0 NULL,
	CONSTRAINT referenciales_pkey PRIMARY KEY (ref_cod)
);


-- public.registros_entrada_salida definition

-- Drop table

-- DROP TABLE public.registros_entrada_salida;

CREATE TABLE public.registros_entrada_salida (
	reg_codigo serial4 NOT NULL,
	reg_cod_personal int4 NULL,
	reg_fecha date NULL,
	reg_hora time NULL,
	reg_tipo varchar(1) DEFAULT '1'::character varying NULL,
	reg_reloj int4 NULL,
	reg_anho int4 NULL,
	reg_mes int4 NULL,
	reg_fecha_sincronizacion date NULL,
	"timestamp" timestamp DEFAULT now() NULL,
	CONSTRAINT registros_entrada_salida_pkey PRIMARY KEY (reg_codigo)
);
CREATE INDEX idx_reg_fecha_personal ON public.registros_entrada_salida USING btree (reg_fecha, reg_cod_personal);
CREATE INDEX idx_reg_hora ON public.registros_entrada_salida USING btree (reg_hora);

-- Table Triggers

create trigger anho_mes_insert before
insert
    on
    public.registros_entrada_salida for each row execute function set_anho_mes_sincronizacion();
create trigger anho_mes_update before
update
    on
    public.registros_entrada_salida for each row execute function update_anho_mes();


-- public.relojes definition

-- Drop table

-- DROP TABLE public.relojes;

CREATE TABLE public.relojes (
	rel_cod serial4 NOT NULL,
	rel_descripcion varchar(50) NULL,
	rel_ip varchar(255) NULL,
	rel_regional varchar(11) NULL,
	rel_fecha date NULL,
	CONSTRAINT relojes_pkey PRIMARY KEY (rel_cod)
);


-- public.roles definition

-- Drop table

-- DROP TABLE public.roles;

CREATE TABLE public.roles (
	rol_id serial4 NOT NULL,
	rol_nombre varchar(100) NOT NULL,
	CONSTRAINT roles_pkey PRIMARY KEY (rol_id)
);


-- public.sedes definition

-- Drop table

-- DROP TABLE public.sedes;

CREATE TABLE public.sedes (
	sed_cod serial4 NOT NULL,
	sed_descripcion varchar(255) NULL,
	sed_numero int4 NULL,
	CONSTRAINT sedes_pkey PRIMARY KEY (sed_cod)
);


-- public.semana definition

-- Drop table

-- DROP TABLE public.semana;

CREATE TABLE public.semana (
	sem_cod serial4 NOT NULL,
	sem_numero int4 NULL,
	sem_letras varchar(255) NULL,
	CONSTRAINT semana_pkey PRIMARY KEY (sem_cod)
);


-- public.sexos definition

-- Drop table

-- DROP TABLE public.sexos;

CREATE TABLE public.sexos (
	sex_cod serial4 NOT NULL,
	sex_valor varchar(255) NULL,
	sex_descripcion varchar(255) NULL,
	CONSTRAINT sexos_pkey PRIMARY KEY (sex_cod)
);


-- public.siap_auditoria_audit definition

-- Drop table

-- DROP TABLE public.siap_auditoria_audit;

CREATE TABLE public.siap_auditoria_audit (
	id serial4 NOT NULL,
	datetime timestamp NOT NULL,
	ip varchar NOT NULL,
	"user" varchar NULL,
	"table" varchar NULL,
	"action" varchar NOT NULL,
	description text NULL,
	CONSTRAINT siap_auditoria_audit_pkey PRIMARY KEY (id)
);


-- public.sincronizacion definition

-- Drop table

-- DROP TABLE public.sincronizacion;

CREATE TABLE public.sincronizacion (
	sin_cod serial4 NOT NULL,
	sin_descripcion varchar(255) NULL,
	sin_fecha date NULL,
	sin_nombre_reloj varchar(255) NULL,
	CONSTRAINT sincronizacion_pkey PRIMARY KEY (sin_cod)
);


-- public.talentos_permisos_uggroups definition

-- Drop table

-- DROP TABLE public.talentos_permisos_uggroups;

CREATE TABLE public.talentos_permisos_uggroups (
	"GroupID" serial4 NOT NULL,
	"Label" varchar NULL,
	"Provider" varchar DEFAULT ''::character varying NULL,
	"Comment" text NULL,
	CONSTRAINT talentos_permisos_uggroups_pkey PRIMARY KEY ("GroupID")
);


-- public.talentos_permisos_ugmembers definition

-- Drop table

-- DROP TABLE public.talentos_permisos_ugmembers;

CREATE TABLE public.talentos_permisos_ugmembers (
	"UserName" varchar NOT NULL,
	"GroupID" int4 NOT NULL,
	"Provider" varchar DEFAULT ''::character varying NOT NULL,
	CONSTRAINT talentos_permisos_ugmembers_pkey PRIMARY KEY ("UserName", "GroupID", "Provider")
);


-- public.talentos_permisos_ugrights definition

-- Drop table

-- DROP TABLE public.talentos_permisos_ugrights;

CREATE TABLE public.talentos_permisos_ugrights (
	"TableName" varchar NOT NULL,
	"GroupID" int4 NOT NULL,
	"AccessMask" varchar NULL,
	"Page" text NULL,
	CONSTRAINT talentos_permisos_ugrights_pkey PRIMARY KEY ("TableName", "GroupID")
);


-- public.temporal definition

-- Drop table

-- DROP TABLE public.temporal;

CREATE TABLE public.temporal (
	valor0 varchar(255) DEFAULT NULL::character varying NULL,
	valor1 varchar(255) DEFAULT NULL::character varying NULL,
	valor2 varchar(255) DEFAULT NULL::character varying NULL
);


-- public.tipo_cargos definition

-- Drop table

-- DROP TABLE public.tipo_cargos;

CREATE TABLE public.tipo_cargos (
	tic_cod serial4 NOT NULL,
	tic_descripcion varchar(100) NULL,
	CONSTRAINT tipo_cargos_pkey PRIMARY KEY (tic_cod)
);


-- public.tipo_faltas definition

-- Drop table

-- DROP TABLE public.tipo_faltas;

CREATE TABLE public.tipo_faltas (
	tip_cod int4 NOT NULL,
	tip_descripcion varchar(255) NULL,
	tip_codigo varchar(255) NULL,
	CONSTRAINT tipo_faltas_pkey PRIMARY KEY (tip_cod)
);


-- public.tipo_feriados definition

-- Drop table

-- DROP TABLE public.tipo_feriados;

CREATE TABLE public.tipo_feriados (
	tif_cod serial4 NOT NULL,
	tif_descripcion varchar(50) NULL,
	CONSTRAINT tipo_feriados_pkey PRIMARY KEY (tif_cod)
);


-- public.tipo_funcionario definition

-- Drop table

-- DROP TABLE public.tipo_funcionario;

CREATE TABLE public.tipo_funcionario (
	tfun_cod serial4 NOT NULL,
	tfun_descri varchar(40) NULL,
	CONSTRAINT tipo_funcionario_pkey PRIMARY KEY (tfun_cod)
);


-- public.tipos_grupos definition

-- Drop table

-- DROP TABLE public.tipos_grupos;

CREATE TABLE public.tipos_grupos (
	tip_cod serial4 NOT NULL,
	tip_valor varchar(255) NULL,
	tip_descripcion varchar(255) NULL,
	CONSTRAINT tipos_grupos_pkey PRIMARY KEY (tip_cod)
);


-- public.tipos_legajos definition

-- Drop table

-- DROP TABLE public.tipos_legajos;

CREATE TABLE public.tipos_legajos (
	tip_cod serial4 NOT NULL,
	tip_descripcion varchar(50) NULL,
	tip_eliminable int2 NULL,
	tip_tiempo_eliminable int4 NULL,
	CONSTRAINT tipos_legajos_pkey PRIMARY KEY (tip_cod)
);


-- public.tipos_ocurrencias definition

-- Drop table

-- DROP TABLE public.tipos_ocurrencias;

CREATE TABLE public.tipos_ocurrencias (
	tip_cod serial4 NOT NULL,
	tip_descripcion varchar(100) NULL,
	tip_cantidad_maxima_mes int4 NULL,
	tip_cantidad_maxima_anho int4 NULL,
	tip_dias int4 NULL,
	tip_codigo varchar(255) NULL,
	tip_horas_extras int2 NULL,
	tip_sin_horas int2 NULL,
	tip_asistencia int2 NULL,
	tip_llegada_tardia int2 NULL,
	tip_salida_temprana int2 NULL,
	tip_asueto int2 NULL,
	tip_compensacion int2 NULL,
	tip_estado varchar(50) NULL,
	tip_cod_tipo_sumatoria int4 NULL,
	tip_horario_compensatorio int2 NULL,
	CONSTRAINT tipos_ocurrencias_pkey PRIMARY KEY (tip_cod)
);
CREATE INDEX idx_tip_dias ON public.tipos_ocurrencias USING btree (tip_dias);


-- public.tipos_turnos definition

-- Drop table

-- DROP TABLE public.tipos_turnos;

CREATE TABLE public.tipos_turnos (
	tip_cod serial4 NOT NULL,
	tip_descripcion varchar(255) NULL,
	tip_especial bpchar(2) DEFAULT 'NO'::bpchar NULL,
	CONSTRAINT tipos_turnos_pkey PRIMARY KEY (tip_cod)
);


-- public.tolerancias_entrada definition

-- Drop table

-- DROP TABLE public.tolerancias_entrada;

CREATE TABLE public.tolerancias_entrada (
	tol_cod serial4 NOT NULL,
	tol_valor time NULL,
	CONSTRAINT tolerancias_entrada_pkey PRIMARY KEY (tol_cod)
);


-- public.usuarios_uggroups definition

-- Drop table

-- DROP TABLE public.usuarios_uggroups;

CREATE TABLE public.usuarios_uggroups (
	"GroupID" serial4 NOT NULL,
	"Label" varchar(300) NULL,
	"Provider" varchar(10) DEFAULT ''::character varying NULL,
	"Comment" text NULL,
	CONSTRAINT usuarios_uggroups_pkey PRIMARY KEY ("GroupID")
);


-- public.usuarios_ugmembers definition

-- Drop table

-- DROP TABLE public.usuarios_ugmembers;

CREATE TABLE public.usuarios_ugmembers (
	"UserName" varchar(255) NOT NULL,
	"GroupID" int4 NOT NULL,
	"Provider" varchar(10) DEFAULT ''::character varying NOT NULL,
	CONSTRAINT usuarios_ugmembers_pkey PRIMARY KEY ("UserName", "GroupID", "Provider")
);


-- public.usuarios_ugrights definition

-- Drop table

-- DROP TABLE public.usuarios_ugrights;

CREATE TABLE public.usuarios_ugrights (
	"TableName" varchar(255) NOT NULL,
	"GroupID" int4 NOT NULL,
	"AccessMask" varchar(10) DEFAULT NULL::character varying NULL,
	"Page" text NULL,
	CONSTRAINT usuarios_ugrights_pkey PRIMARY KEY ("TableName", "GroupID")
);


-- public.volcado_oficial definition

-- Drop table

-- DROP TABLE public.volcado_oficial;

CREATE TABLE public.volcado_oficial (
	cod_usuario varchar(255) NULL,
	nombres varchar(255) NULL,
	apellidos varchar(255) NULL,
	email varchar(255) NULL,
	id_funcionario int4 NULL,
	fechaingreso date DEFAULT now() NULL
);


-- public.departamentos definition

-- Drop table

-- DROP TABLE public.departamentos;

CREATE TABLE public.departamentos (
	dep_cod serial4 NOT NULL,
	departamento varchar(50) NULL,
	dep_cod_pais int4 NULL,
	CONSTRAINT departamentos_pkey PRIMARY KEY (dep_cod),
	CONSTRAINT departamentos_dep_cod_pais_fkey FOREIGN KEY (dep_cod_pais) REFERENCES public.paises(pai_cod) ON DELETE SET NULL
);


-- public.distrito definition

-- Drop table

-- DROP TABLE public.distrito;

CREATE TABLE public.distrito (
	id_dis bigserial NOT NULL,
	nombre varchar(100) NOT NULL,
	id_dep int4 NOT NULL,
	dis_cod varchar(10) NULL,
	dis_cod_completo varchar(10) NULL,
	nombre_departamento varchar(255) NULL,
	CONSTRAINT distrito_pkey PRIMARY KEY (id_dis),
	CONSTRAINT distrito_id_dep_fkey FOREIGN KEY (id_dep) REFERENCES public.departamentos(dep_cod) ON DELETE CASCADE
);


-- public.feriados definition

-- Drop table

-- DROP TABLE public.feriados;

CREATE TABLE public.feriados (
	fer_cod serial4 NOT NULL,
	fer_cod_tipo int4 NOT NULL,
	fer_descripcion varchar(100) NULL,
	fer_fecha date NULL,
	CONSTRAINT feriados_pkey PRIMARY KEY (fer_cod, fer_cod_tipo),
	CONSTRAINT feriados_fer_cod_tipo_fkey FOREIGN KEY (fer_cod_tipo) REFERENCES public.tipo_feriados(tif_cod) ON DELETE CASCADE
);
CREATE INDEX idx_fechas_feriados ON public.feriados USING btree (fer_fecha);
CREATE INDEX idx_fer_cod ON public.feriados USING btree (fer_cod);


-- public.tolerancias definition

-- Drop table

-- DROP TABLE public.tolerancias;

CREATE TABLE public.tolerancias (
	tol_cod serial4 NOT NULL,
	tol_cod_cargo int4 NULL,
	tol_minutos int4 NULL,
	tol_cod_turno int4 NULL,
	tol_descripcion varchar(50) NULL,
	CONSTRAINT tolerancias_pkey PRIMARY KEY (tol_cod),
	CONSTRAINT tolerancias_tol_cod_cargo_fkey FOREIGN KEY (tol_cod_cargo) REFERENCES public.cargos(car_cod) ON DELETE SET NULL,
	CONSTRAINT tolerancias_tol_cod_turno_fkey FOREIGN KEY (tol_cod_turno) REFERENCES public.tipos_turnos(tip_cod) ON DELETE SET NULL
);


-- public.usuarios definition

-- Drop table

-- DROP TABLE public.usuarios;

CREATE TABLE public.usuarios (
	usu_cod serial4 NOT NULL,
	usu_usuario varchar(255) NOT NULL,
	usu_contrasenha varchar(255) NOT NULL,
	usu_nombre varchar(255) NOT NULL,
	usu_dependencia int4 NULL,
	usu_personal int4 NULL,
	usu_correo varchar(100) NULL,
	active int4 DEFAULT 1 NULL,
	rol int4 NULL,
	two_factor int4 NULL,
	totp text NULL,
	CONSTRAINT usuarios_pkey PRIMARY KEY (usu_cod),
	CONSTRAINT fk_rol FOREIGN KEY (rol) REFERENCES public.roles(rol_id)
);


-- public.ciudades definition

-- Drop table

-- DROP TABLE public.ciudades;

CREATE TABLE public.ciudades (
	ciu_cod serial4 NOT NULL,
	ciu_descri varchar(40) NULL,
	ciu_cod_departamento int4 NULL,
	CONSTRAINT ciudades_pkey PRIMARY KEY (ciu_cod),
	CONSTRAINT ciudades_ciu_cod_departamento_fkey FOREIGN KEY (ciu_cod_departamento) REFERENCES public.departamentos(dep_cod) ON DELETE SET NULL
);


-- public.personales definition

-- Drop table

-- DROP TABLE public.personales;

CREATE TABLE public.personales (
	per_cod serial4 NOT NULL,
	categoria_cat_codigo int4 NULL,
	departamentos_dep_cod int4 NULL,
	dependencias_dep_cod int4 NULL,
	paises_pai_cod int4 NULL,
	ciudades_ciu_cod int4 NULL,
	profesiones_pro_cod int4 NULL,
	per_profesional int2 NULL,
	tipo_funcionario_tfun_cod int4 NULL,
	per_institucion_origen int4 NULL,
	cargos_car_cod int4 NULL,
	per_nombre varchar(60) NULL,
	per_apellido varchar(60) NULL,
	per_ci varchar(20) NULL,
	per_sexo bpchar(1) NULL,
	per_nacimiento date NULL,
	per_est_civil varchar(10) NULL,
	per_gruposangre varchar(10) NULL,
	per_pcd int2 NULL,
	per_domicilio varchar(100) NULL,
	per_barrio varchar(30) NULL,
	per_teleparticular varchar(30) NULL,
	per_telecelular varchar(30) NULL,
	per_email_part varchar(50) NULL,
	per_email_instit varchar(50) NULL,
	per_ruc varchar(40) NULL,
	per_contacto_eme varchar(50) NULL,
	per_tele_emer varchar(20) NULL,
	per_ingreso date NULL,
	per_nombramiento date NULL,
	per_estado int2 NULL,
	per_usuario varchar(50) NULL,
	per_sede int4 NULL,
	CONSTRAINT personales_pkey PRIMARY KEY (per_cod),
	CONSTRAINT fk_personales_cargos FOREIGN KEY (cargos_car_cod) REFERENCES public.cargos(car_cod),
	CONSTRAINT fk_personales_ciudades FOREIGN KEY (ciudades_ciu_cod) REFERENCES public.ciudades(ciu_cod),
	CONSTRAINT fk_personales_departamentos FOREIGN KEY (departamentos_dep_cod) REFERENCES public.departamentos(dep_cod),
	CONSTRAINT fk_personales_dependencias FOREIGN KEY (dependencias_dep_cod) REFERENCES public.dependencias(dep_cod),
	CONSTRAINT fk_personales_instituciones_origen FOREIGN KEY (per_institucion_origen) REFERENCES public.instituciones_origen(ins_cod),
	CONSTRAINT fk_personales_paises FOREIGN KEY (paises_pai_cod) REFERENCES public.paises(pai_cod),
	CONSTRAINT fk_personales_profesiones FOREIGN KEY (profesiones_pro_cod) REFERENCES public.profesiones(pro_cod),
	CONSTRAINT fk_personales_sedes FOREIGN KEY (per_sede) REFERENCES public.sedes(sed_cod),
	CONSTRAINT fk_personales_tipo_funcionario FOREIGN KEY (tipo_funcionario_tfun_cod) REFERENCES public.tipo_funcionario(tfun_cod)
);


-- public.tabla_vacaciones definition

-- Drop table

-- DROP TABLE public.tabla_vacaciones;

CREATE TABLE public.tabla_vacaciones (
	tab_cod serial4 NOT NULL,
	tab_cod_personal int4 NULL,
	tab_anho_vacaciones int4 NULL,
	tab_cantidad_dias int4 NULL,
	tab_activo int4 NULL,
	CONSTRAINT tabla_vacaciones_pkey PRIMARY KEY (tab_cod),
	CONSTRAINT tabla_vacaciones_tab_cod_personal_fkey FOREIGN KEY (tab_cod_personal) REFERENCES public.personales(per_cod)
);


-- public.tolerancias_especiales definition

-- Drop table

-- DROP TABLE public.tolerancias_especiales;

CREATE TABLE public.tolerancias_especiales (
	tol_cod serial4 NOT NULL,
	tol_descripcion varchar(255) NULL,
	tol_tiempo time NULL,
	tol_cod_personal int4 NULL,
	tol_fecha_desde date NULL,
	tol_fecha_hasta date NULL,
	tol_tipo varchar(2) NULL,
	tol_sed_cod int4 NULL,
	CONSTRAINT tolerancias_especiales_pkey PRIMARY KEY (tol_cod),
	CONSTRAINT tolerancias_especiales_sed_cod_fkey FOREIGN KEY (tol_sed_cod) REFERENCES public.sedes(sed_cod) ON DELETE SET NULL,
	CONSTRAINT tolerancias_especiales_tol_cod_personal_fkey FOREIGN KEY (tol_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);


-- public.turnos definition

-- Drop table

-- DROP TABLE public.turnos;

CREATE TABLE public.turnos (
	tur_codigo serial4 NOT NULL,
	tur_tipo int4 DEFAULT 1 NULL,
	tur_cod_personal int4 NULL,
	tur_descripcion varchar(50) NULL,
	tur_entrada time NULL,
	tur_salida time NULL,
	tur_horas_trabajo time NULL,
	tur_estado varchar(10) NULL,
	tur_fecha_desde date NULL,
	tur_fecha_hasta date NULL,
	tur_dias varchar(255) NULL,
	tur_tolerancia int4 NULL,
	tur_entrada_horas time NULL,
	tur_salida_horas time NULL,
	tur_horas int2 NULL,
	tur_especiales int2 NULL,
	tur_horas_diferentes int2 NULL,
	tur_sin_horas_dias_habiles int2 NULL,
	tur_sin_limite_100 int2 NULL,
	tur_archivo text NULL,
	CONSTRAINT turnos_pkey PRIMARY KEY (tur_codigo),
	CONSTRAINT turnos_tur_cod_personal_fkey FOREIGN KEY (tur_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);
CREATE INDEX idx_fechas_turnos ON public.turnos USING btree (tur_fecha_desde, tur_fecha_hasta);
CREATE INDEX idx_tur_persona ON public.turnos USING btree (tur_cod_personal);

-- Table Triggers

create trigger turno_actualizar_insert before
insert
    on
    public.turnos for each row execute function turno_actualizar_insert();
create trigger turno_actualizar_update before
update
    on
    public.turnos for each row execute function turno_actualizar_update();


-- public.vacaciones definition

-- Drop table

-- DROP TABLE public.vacaciones;

CREATE TABLE public.vacaciones (
	vac_cod serial4 NOT NULL,
	vac_cod_personal int4 NULL,
	vac_fecha_desde date NULL,
	vac_fecha_hasta date NULL,
	vac_dias_pedidos int4 NULL,
	vac_dias_usados int4 NULL,
	vac_descripcion varchar(1000) NULL,
	vac_periodo int4 NULL,
	vac_dias varchar(255) NULL,
	vac_archivo text NULL,
	CONSTRAINT vacaciones_pkey PRIMARY KEY (vac_cod),
	CONSTRAINT vacaciones_vac_cod_personal_fkey FOREIGN KEY (vac_cod_personal) REFERENCES public.personales(per_cod)
);


-- public.codigos_reloj definition

-- Drop table

-- DROP TABLE public.codigos_reloj;

CREATE TABLE public.codigos_reloj (
	rel_cod serial4 NOT NULL,
	rel_codigo int4 NULL,
	rel_cod_persona int4 NULL,
	rel_estado int4 NULL,
	rel_periodo int4 NULL,
	rel_reloj int4 NULL,
	rel_fecha_desde date NULL,
	rel_fecha_hasta date NULL,
	CONSTRAINT codigos_reloj_pkey PRIMARY KEY (rel_cod),
	CONSTRAINT fk_codigos_reloj_personales FOREIGN KEY (rel_cod_persona) REFERENCES public.personales(per_cod),
	CONSTRAINT fk_reloj FOREIGN KEY (rel_reloj) REFERENCES public.relojes(rel_cod)
);
CREATE INDEX idx_reg_fecha ON public.codigos_reloj USING btree (rel_fecha_desde, rel_fecha_hasta);
CREATE INDEX idx_rel_cod_persona ON public.codigos_reloj USING btree (rel_cod_persona);
CREATE INDEX idx_rel_codigo ON public.codigos_reloj USING btree (rel_codigo);


-- public.compensaciones definition

-- Drop table

-- DROP TABLE public.compensaciones;

CREATE TABLE public.compensaciones (
	com_cod serial4 NOT NULL,
	com_cod_ocurrencia int4 NULL,
	com_cod_personal int4 NULL,
	com_fecha date NULL,
	com_cantidad_horas time NULL,
	com_fecha_inicio date NULL,
	com_fecha_fin date NULL,
	com_orden int4 NULL,
	CONSTRAINT compensaciones_pkey PRIMARY KEY (com_cod),
	CONSTRAINT compensaciones_com_cod_ocurrencia_fkey FOREIGN KEY (com_cod_ocurrencia) REFERENCES public.ocurrencias(ocu_cod) ON DELETE SET NULL,
	CONSTRAINT compensaciones_com_cod_personal_fkey FOREIGN KEY (com_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);
CREATE INDEX idx_con_fecha ON public.compensaciones USING btree (com_fecha);
CREATE INDEX idx_fecha_finalizacion ON public.compensaciones USING btree (com_fecha_fin);
CREATE INDEX idx_fecha_inicio ON public.compensaciones USING btree (com_fecha_inicio);
CREATE INDEX idx_funcionario ON public.compensaciones USING btree (com_cod_personal);


-- public.compensaciones_actualizacion definition

-- Drop table

-- DROP TABLE public.compensaciones_actualizacion;

CREATE TABLE public.compensaciones_actualizacion (
	com_cod serial4 NOT NULL,
	com_cod_ocurrencia int4 NULL,
	com_cod_personal int4 NULL,
	com_fecha date NULL,
	com_cantidad_horas time NULL,
	com_horas_restantes time NULL,
	com_horas_restantes_acumuladas time NULL,
	com_cantidad_horas_compensadas time NULL,
	com_fecha_inicio date NULL,
	CONSTRAINT compensaciones_actualizacion_pkey PRIMARY KEY (com_cod),
	CONSTRAINT compensaciones_actualizacion_com_cod_ocurrencia_fkey FOREIGN KEY (com_cod_ocurrencia) REFERENCES public.ocurrencias(ocu_cod) ON DELETE SET NULL,
	CONSTRAINT compensaciones_actualizacion_com_cod_personal_fkey FOREIGN KEY (com_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);
CREATE INDEX idx_ocurrencia ON public.compensaciones_actualizacion USING btree (com_cod_ocurrencia);


-- public.compensaciones_completas definition

-- Drop table

-- DROP TABLE public.compensaciones_completas;

CREATE TABLE public.compensaciones_completas (
	com_cod serial4 NOT NULL,
	com_cod_personal int4 NOT NULL,
	com_fecha_generacion date NOT NULL,
	com_mes int4 NOT NULL,
	com_anio int4 NOT NULL,
	com_horas_a_compensar interval NOT NULL,
	com_horas_compensadas interval DEFAULT '00:00:00'::interval NULL,
	com_estado varchar(50) DEFAULT 'pendiente'::character varying NULL,
	com_cod_ocurrencia int4 NULL,
	com_ultimo_dia_compensado date NULL,
	com_minutos_pendientes interval DEFAULT '00:00:00'::interval NULL,
	CONSTRAINT compensaciones_completas_pkey PRIMARY KEY (com_cod),
	CONSTRAINT fk_com_ocurrencia FOREIGN KEY (com_cod_ocurrencia) REFERENCES public.ocurrencias(ocu_cod) ON DELETE CASCADE,
	CONSTRAINT fk_com_personal FOREIGN KEY (com_cod_personal) REFERENCES public.personales(per_cod) ON DELETE CASCADE
);


-- public.compensaciones_detalles definition

-- Drop table

-- DROP TABLE public.compensaciones_detalles;

CREATE TABLE public.compensaciones_detalles (
	com_det_cod serial4 NOT NULL,
	com_cod int4 NOT NULL,
	com_cod_personal int4 NOT NULL,
	com_det_fecha date NOT NULL,
	com_det_horas_a_compensar interval NOT NULL,
	com_det_horas_compensadas interval NOT NULL,
	com_det_horas_restantes interval NOT NULL,
	com_cod_ocurrencia int4 NULL,
	CONSTRAINT compensaciones_detalles_pkey PRIMARY KEY (com_det_cod),
	CONSTRAINT fk_compensaciones_completas FOREIGN KEY (com_cod) REFERENCES public.compensaciones_completas(com_cod) ON DELETE CASCADE
);


-- public.contratos definition

-- Drop table

-- DROP TABLE public.contratos;

CREATE TABLE public.contratos (
	con_cod serial4 NOT NULL,
	con_cod_personal int4 NULL,
	con_fecha_desde date NULL,
	con_fecha_hasta date NULL,
	con_resolucion varchar(500) NULL,
	con_numero int4 NULL,
	con_salario int4 NULL,
	CONSTRAINT contratos_pkey PRIMARY KEY (con_cod),
	CONSTRAINT contratos_con_cod_personal_fkey FOREIGN KEY (con_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);


-- public.designaciones definition

-- Drop table

-- DROP TABLE public.designaciones;

CREATE TABLE public.designaciones (
	des_cod serial4 NOT NULL,
	des_cod_personal int4 NOT NULL,
	des_cod_cargo int4 NOT NULL,
	des_descripcion varchar(255) NOT NULL,
	des_archivo text NULL,
	des_fecha_desde date NOT NULL,
	des_fecha_hasta date NULL,
	des_estado int4 NOT NULL,
	CONSTRAINT designaciones_pkey PRIMARY KEY (des_cod),
	CONSTRAINT fk_des_cargo FOREIGN KEY (des_cod_cargo) REFERENCES public.cargos(car_cod) ON DELETE SET NULL,
	CONSTRAINT fk_des_personal FOREIGN KEY (des_cod_personal) REFERENCES public.personales(per_cod) ON DELETE CASCADE
);


-- public.detalle_ocurrencias definition

-- Drop table

-- DROP TABLE public.detalle_ocurrencias;

CREATE TABLE public.detalle_ocurrencias (
	det_cod serial4 NOT NULL,
	det_cod_ocurrencia int4 NULL,
	det_mes_gasto int4 NULL,
	det_anho_gasto int4 NULL,
	det_cod_persona int4 NULL,
	det_dias_gastados int4 NULL,
	CONSTRAINT detalle_ocurrencias_pkey PRIMARY KEY (det_cod),
	CONSTRAINT detalle_ocurrencias_det_cod_ocurrencia_fkey FOREIGN KEY (det_cod_ocurrencia) REFERENCES public.ocurrencias(ocu_cod) ON DELETE CASCADE,
	CONSTRAINT detalle_ocurrencias_det_cod_persona_fkey FOREIGN KEY (det_cod_persona) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);
CREATE INDEX idx_fk_anho ON public.detalle_ocurrencias USING btree (det_anho_gasto);
CREATE INDEX idx_fk_mes_anho ON public.detalle_ocurrencias USING btree (det_mes_gasto);
CREATE INDEX idx_fk_ocurrencias ON public.detalle_ocurrencias USING btree (det_cod_ocurrencia);


-- public.entradas_salidas definition

-- Drop table

-- DROP TABLE public.entradas_salidas;

CREATE TABLE public.entradas_salidas (
	ent_cod serial4 NOT NULL,
	ent_cod_personal int4 NULL,
	ent_fecha date NULL,
	ent_hora_entrada varchar(5) NULL,
	ent_hora_salida varchar(5) NULL,
	CONSTRAINT entradas_salidas_pkey PRIMARY KEY (ent_cod),
	CONSTRAINT entradas_salidas_ent_cod_personal_fkey FOREIGN KEY (ent_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);


-- public.faltas definition

-- Drop table

-- DROP TABLE public.faltas;

CREATE TABLE public.faltas (
	fal_cod serial4 NOT NULL,
	fal_cod_personal int4 NULL,
	fal_cod_tipo int4 NULL,
	fal_cantidad int4 NULL,
	fal_mes int4 NULL,
	fal_anho int4 NULL,
	fal_fecha_actualizacion date NULL,
	CONSTRAINT faltas_fal_cod_personal_fal_cod_tipo_fal_mes_fal_anho_key UNIQUE (fal_cod_personal, fal_cod_tipo, fal_mes, fal_anho),
	CONSTRAINT faltas_pkey PRIMARY KEY (fal_cod),
	CONSTRAINT faltas_fal_cod_personal_fkey FOREIGN KEY (fal_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);


-- public.generar_compensaciones definition

-- Drop table

-- DROP TABLE public.generar_compensaciones;

CREATE TABLE public.generar_compensaciones (
	gen_cod serial4 NOT NULL,
	gen_dias int4 NULL,
	gen_cod_ocurrencia int4 NULL,
	gen_cod_personal int4 NULL,
	CONSTRAINT generar_compensaciones_pkey PRIMARY KEY (gen_cod),
	CONSTRAINT generar_compensaciones_gen_cod_ocurrencia_fkey FOREIGN KEY (gen_cod_ocurrencia) REFERENCES public.ocurrencias(ocu_cod) ON DELETE SET NULL,
	CONSTRAINT generar_compensaciones_gen_cod_personal_fkey FOREIGN KEY (gen_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);


-- public.horas_diarias definition

-- Drop table

-- DROP TABLE public.horas_diarias;

CREATE TABLE public.horas_diarias (
	hor_cod serial4 NOT NULL,
	hor_cod_personal int4 NULL,
	hor_fecha date NULL,
	hor_horas time NULL,
	hor_horas_100 time NULL,
	hor_actualizar int2 NULL,
	CONSTRAINT horas_diarias_pkey PRIMARY KEY (hor_cod),
	CONSTRAINT horas_diarias_hor_cod_personal_fkey FOREIGN KEY (hor_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);
CREATE INDEX idx_indice ON public.horas_diarias USING btree (hor_cod_personal, hor_fecha, hor_horas);


-- public.horas_personales definition

-- Drop table

-- DROP TABLE public.horas_personales;

CREATE TABLE public.horas_personales (
	hor_cod serial4 NOT NULL,
	hor_cod_personal int4 NULL,
	hor_mes int4 NULL,
	hor_anho varchar(255) NULL,
	hor_extras time NULL,
	hor_adicional time NULL,
	hor_adicional_100 time NULL,
	hor_fecha date NULL,
	CONSTRAINT horas_personales_hor_cod_personal_hor_mes_hor_anho_key UNIQUE (hor_cod_personal, hor_mes, hor_anho),
	CONSTRAINT horas_personales_pkey PRIMARY KEY (hor_cod),
	CONSTRAINT horas_personales_hor_cod_personal_fkey FOREIGN KEY (hor_cod_personal) REFERENCES public.personales(per_cod) ON DELETE SET NULL
);


-- public.idiomas definition

-- Drop table

-- DROP TABLE public.idiomas;

CREATE TABLE public.idiomas (
	idi_codigo serial4 NOT NULL,
	personales_per_cod int4 NULL,
	idi_idioma varchar(20) NULL,
	idi_habla varchar(10) NULL,
	idi_lee varchar(10) NULL,
	idi_escribe varchar(10) NULL,
	CONSTRAINT idiomas_pkey PRIMARY KEY (idi_codigo),
	CONSTRAINT idiomas_personales_per_cod_fkey FOREIGN KEY (personales_per_cod) REFERENCES public.personales(per_cod) ON DELETE CASCADE
);


-- public.legajos definition

-- Drop table

-- DROP TABLE public.legajos;

CREATE TABLE public.legajos (
	leg_cod serial4 NOT NULL,
	leg_cod_personal int4 NULL,
	leg_fecha date NULL,
	leg_descripcion varchar(1000) NULL,
	leg_cod_tipo int4 NULL,
	leg_usuario varchar(50) NULL,
	leg_fecha_creacion date NULL,
	leg_usuario_modificacion varchar(50) NULL,
	leg_fecha_modificacion date NULL,
	leg_archivo varchar(1000) NULL,
	CONSTRAINT legajos_pkey PRIMARY KEY (leg_cod),
	CONSTRAINT legajos_leg_cod_personal_fkey FOREIGN KEY (leg_cod_personal) REFERENCES public.personales(per_cod),
	CONSTRAINT legajos_leg_cod_tipo_fkey FOREIGN KEY (leg_cod_tipo) REFERENCES public.tipos_legajos(tip_cod)
);


-- public.marcaciones_observaciones definition

-- Drop table

-- DROP TABLE public.marcaciones_observaciones;

CREATE TABLE public.marcaciones_observaciones (
	reg_cod_persona int8 NULL,
	reg_cod_reloj varchar(255) NULL,
	reg_fecha date NULL,
	reg_hora_entrada time NULL,
	reg_hora_salida time NULL,
	tur_entrada time NULL,
	reg_retraso time NULL,
	reg_horas_total time NULL,
	reg_horas_extras time NULL,
	ocu_descripcion text NULL,
	ocu_tipo text NULL,
	CONSTRAINT marcaciones_observaciones_reg_cod_persona_fkey FOREIGN KEY (reg_cod_persona) REFERENCES public.personales(per_cod)
);


-- public.observaciones_asistencia definition

-- Drop table

-- DROP TABLE public.observaciones_asistencia;

CREATE TABLE public.observaciones_asistencia (
	obs_cod serial4 NOT NULL,
	obs_cod_personal int4 NULL,
	obs_fecha_desde date NULL,
	obs_fecha_hasta date NULL,
	obs_descripcion varchar(255) NULL,
	obs_inicio varchar(255) NULL,
	obs_fin varchar(255) NULL,
	CONSTRAINT observaciones_asistencia_pkey PRIMARY KEY (obs_cod),
	CONSTRAINT observaciones_asistencia_obs_cod_personal_fkey FOREIGN KEY (obs_cod_personal) REFERENCES public.personales(per_cod)
);

-- Table Triggers

create trigger actualizar before
update
    on
    public.observaciones_asistencia for each row execute function actualizar_observaciones_asistencia();
create trigger insertar before
insert
    on
    public.observaciones_asistencia for each row execute function before_insert_observaciones_asistencia();
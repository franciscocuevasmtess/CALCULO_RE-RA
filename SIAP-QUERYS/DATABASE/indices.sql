CREATE UNIQUE INDEX distrito_pkey ON public.distrito USING btree (id_dis);

CREATE UNIQUE INDEX personas_pkey ON public.personas USING btree (codigo);

CREATE INDEX idx_ocu_asueto ON public.ocurrencias USING btree (ocu_asueto);

CREATE INDEX idx_ocu_asueto_dia_completo ON public.ocurrencias USING btree (ocu_asueto_dia_completo);

CREATE INDEX idx_ocu_cod ON public.ocurrencias USING btree (ocu_cod);

CREATE INDEX idx_ocu_cod_persona ON public.ocurrencias USING btree (ocu_cod_persona);

CREATE INDEX idx_ocu_fecha_desde ON public.ocurrencias USING btree (ocu_fecha_desde, ocu_fecha_hasta);

CREATE INDEX idx_ocu_funcionarios_afectados ON public.ocurrencias USING btree (ocu_funcionarios_afectados);

CREATE INDEX idx_ocu_tipo_grupo ON public.ocurrencias USING btree (ocu_tipo_grupo);

CREATE INDEX idx_ocu_tipo_grupo_digito ON public.ocurrencias USING btree (ocu_tipo_grupo_digito);

CREATE UNIQUE INDEX ocurrencias_pkey ON public.ocurrencias USING btree (ocu_cod);

CREATE UNIQUE INDEX tipos_legajos_pkey ON public.tipos_legajos USING btree (tip_cod);

CREATE UNIQUE INDEX vacaciones_pkey ON public.vacaciones USING btree (vac_cod);

CREATE UNIQUE INDEX sexos_pkey ON public.sexos USING btree (sex_cod);

CREATE UNIQUE INDEX contratos_pkey ON public.contratos USING btree (con_cod);

CREATE UNIQUE INDEX observaciones_asistencia_pkey ON public.observaciones_asistencia USING btree (obs_cod);

CREATE UNIQUE INDEX paises_pkey ON public.paises USING btree (pai_cod);

CREATE UNIQUE INDEX talentos_permisos_uggroups_pkey ON public.talentos_permisos_uggroups USING btree ("GroupID");

CREATE UNIQUE INDEX cargos_pkey ON public.cargos USING btree (car_cod);

CREATE UNIQUE INDEX fechas_pkey ON public.fechas USING btree (fecha);

CREATE UNIQUE INDEX configuracion_pkey ON public.configuracion USING btree (con_cod);

CREATE INDEX idx_codigo_configuracion ON public.configuracion USING btree (con_cod);

CREATE INDEX idx_fechas ON public.configuracion USING btree (con_fecha_desde, con_fecha_hasta);

CREATE INDEX idx_tip_dias ON public.tipos_ocurrencias USING btree (tip_dias);

CREATE UNIQUE INDEX tipos_ocurrencias_pkey ON public.tipos_ocurrencias USING btree (tip_cod);

CREATE UNIQUE INDEX ocurrencias_solicitud_pkey ON public.ocurrencias_solicitud USING btree (ocu_cod);

CREATE INDEX idx_vista_marcaciones_completas ON public.vista_marcaciones_completas USING btree (reg_fecha, reg_cod_personal);

CREATE UNIQUE INDEX tolerancias_especiales_pkey ON public.tolerancias_especiales USING btree (tol_cod);

CREATE UNIQUE INDEX sedes_pkey ON public.sedes USING btree (sed_cod);

CREATE UNIQUE INDEX mensajes_pkey ON public.mensajes USING btree (men_cod);

CREATE UNIQUE INDEX faltas_fal_cod_personal_fal_cod_tipo_fal_mes_fal_anho_key ON public.faltas USING btree (fal_cod_personal, fal_cod_tipo, fal_mes, fal_anho);

CREATE UNIQUE INDEX faltas_pkey ON public.faltas USING btree (fal_cod);

CREATE UNIQUE INDEX horas_personales_hor_cod_personal_hor_mes_hor_anho_key ON public.horas_personales USING btree (hor_cod_personal, hor_mes, hor_anho);

CREATE UNIQUE INDEX horas_personales_pkey ON public.horas_personales USING btree (hor_cod);

CREATE UNIQUE INDEX tipo_faltas_pkey ON public.tipo_faltas USING btree (tip_cod);

CREATE UNIQUE INDEX semana_pkey ON public.semana USING btree (sem_cod);

CREATE UNIQUE INDEX ciudades_pkey ON public.ciudades USING btree (ciu_cod);

CREATE UNIQUE INDEX numeros_pkey ON public.numeros USING btree (num_cod);

CREATE UNIQUE INDEX talentos_permisos_ugrights_pkey ON public.talentos_permisos_ugrights USING btree ("TableName", "GroupID");

CREATE UNIQUE INDEX profesiones_pkey ON public.profesiones USING btree (pro_cod);

CREATE UNIQUE INDEX auditoria_reloj_pkey ON public.auditoria_reloj USING btree (aud_cod);

CREATE UNIQUE INDEX fechas_a_numeros_pkey ON public.fechas_a_numeros USING btree (numero);

CREATE INDEX idx_id_2 ON public.fechas_a_numeros USING btree (numero);

CREATE UNIQUE INDEX codigos_reloj_pkey ON public.codigos_reloj USING btree (rel_cod);

CREATE INDEX idx_reg_fecha ON public.codigos_reloj USING btree (rel_fecha_desde, rel_fecha_hasta);

CREATE INDEX idx_rel_cod_persona ON public.codigos_reloj USING btree (rel_cod_persona);

CREATE INDEX idx_rel_codigo ON public.codigos_reloj USING btree (rel_codigo);

CREATE UNIQUE INDEX relojes_pkey ON public.relojes USING btree (rel_cod);

CREATE UNIQUE INDEX usuarios_ugmembers_pkey ON public.usuarios_ugmembers USING btree ("UserName", "GroupID", "Provider");

CREATE UNIQUE INDEX notificaciones_pkey ON public.notificaciones USING btree (not_cod);

CREATE INDEX idx_parametro_anho ON public.parametros USING btree (par_anho);

CREATE INDEX idx_parametro_cod ON public.parametros USING btree (par_cod);

CREATE UNIQUE INDEX parametros_pkey ON public.parametros USING btree (par_cod);

CREATE UNIQUE INDEX auxiliar_pkey ON public.auxiliar USING btree (cod_detalle);

CREATE UNIQUE INDEX tipo_cargos_pkey ON public.tipo_cargos USING btree (tic_cod);

CREATE INDEX idx_reg_fecha_personal ON public.registros_entrada_salida USING btree (reg_fecha, reg_cod_personal);

CREATE INDEX idx_reg_hora ON public.registros_entrada_salida USING btree (reg_hora);

CREATE UNIQUE INDEX registros_entrada_salida_pkey ON public.registros_entrada_salida USING btree (reg_codigo);

CREATE UNIQUE INDEX configuracion_llegada_tardia_pkey ON public.configuracion_llegada_tardia USING btree (con_cod);

CREATE UNIQUE INDEX designaciones_pkey ON public.designaciones USING btree (des_cod);

CREATE UNIQUE INDEX entradas_salidas_pkey ON public.entradas_salidas USING btree (ent_cod);

CREATE UNIQUE INDEX fechas_ocurrencias_pkey ON public.fechas_ocurrencias USING btree (fecha);

CREATE INDEX idx_fecha_anho ON public.fechas_ocurrencias USING btree (anho);

CREATE INDEX idx_fecha_mes ON public.fechas_ocurrencias USING btree (mes);

CREATE UNIQUE INDEX compensaciones_completas_pkey ON public.compensaciones_completas USING btree (com_cod);

CREATE UNIQUE INDEX horas_diarias_pkey ON public.horas_diarias USING btree (hor_cod);

CREATE INDEX idx_indice ON public.horas_diarias USING btree (hor_cod_personal, hor_fecha, hor_horas);

CREATE UNIQUE INDEX anhos_pkey ON public.anhos USING btree (cod);

CREATE UNIQUE INDEX personales_pkey ON public.personales USING btree (per_cod);

CREATE UNIQUE INDEX tipo_funcionario_pkey ON public.tipo_funcionario USING btree (tfun_cod);

CREATE UNIQUE INDEX usuarios_uggroups_pkey ON public.usuarios_uggroups USING btree ("GroupID");

CREATE UNIQUE INDEX tabla_vacaciones_pkey ON public.tabla_vacaciones USING btree (tab_cod);

CREATE UNIQUE INDEX dependencias_pkey ON public.dependencias USING btree (dep_cod);

CREATE UNIQUE INDEX historial_marcaciones_pkey ON public.historial_marcaciones USING btree (id);

CREATE UNIQUE INDEX detalle_ocurrencias_pkey ON public.detalle_ocurrencias USING btree (det_cod);

CREATE INDEX idx_fk_anho ON public.detalle_ocurrencias USING btree (det_anho_gasto);

CREATE INDEX idx_fk_mes_anho ON public.detalle_ocurrencias USING btree (det_mes_gasto);

CREATE INDEX idx_fk_ocurrencias ON public.detalle_ocurrencias USING btree (det_cod_ocurrencia);

CREATE UNIQUE INDEX compensaciones_pkey ON public.compensaciones USING btree (com_cod);

CREATE INDEX idx_con_fecha ON public.compensaciones USING btree (com_fecha);

CREATE INDEX idx_fecha_finalizacion ON public.compensaciones USING btree (com_fecha_fin);

CREATE INDEX idx_fecha_inicio ON public.compensaciones USING btree (com_fecha_inicio);

CREATE INDEX idx_funcionario ON public.compensaciones USING btree (com_cod_personal);

CREATE INDEX idx_fechas_turnos ON public.turnos USING btree (tur_fecha_desde, tur_fecha_hasta);

CREATE INDEX idx_tur_persona ON public.turnos USING btree (tur_cod_personal);

CREATE UNIQUE INDEX turnos_pkey ON public.turnos USING btree (tur_codigo);

CREATE UNIQUE INDEX tipo_feriados_pkey ON public.tipo_feriados USING btree (tif_cod);

CREATE UNIQUE INDEX estados_pkey ON public.estados USING btree (es_cod);

CREATE UNIQUE INDEX tolerancias_pkey ON public.tolerancias USING btree (tol_cod);

CREATE UNIQUE INDEX cedula_pkey ON public.cedula USING btree (cedula);

CREATE UNIQUE INDEX calculo_parametros_periodo_year_key ON public.calculo_parametros USING btree (periodo_year);

CREATE UNIQUE INDEX calculo_parametros_pkey ON public.calculo_parametros USING btree (id);

CREATE INDEX idx_dia ON public.dias USING btree (dia_cod);

CREATE INDEX idx_dia_sumar ON public.dias USING btree (dia_sumar);

CREATE UNIQUE INDEX feriados_pkey ON public.feriados USING btree (fer_cod, fer_cod_tipo);

CREATE INDEX idx_fechas_feriados ON public.feriados USING btree (fer_fecha);

CREATE INDEX idx_fer_cod ON public.feriados USING btree (fer_cod);

CREATE UNIQUE INDEX tipos_turnos_pkey ON public.tipos_turnos USING btree (tip_cod);

CREATE UNIQUE INDEX siap_auditoria_audit_pkey ON public.siap_auditoria_audit USING btree (id);

CREATE UNIQUE INDEX tolerancias_entrada_pkey ON public.tolerancias_entrada USING btree (tol_cod);

CREATE UNIQUE INDEX parametro_vacaciones_pkey ON public.parametro_vacaciones USING btree (par_cod);

CREATE UNIQUE INDEX observaciones_pkey ON public.observaciones USING btree (obs_cod);

CREATE UNIQUE INDEX actualizacion_generados_pkey ON public.actualizacion_generados USING btree (act_cod);

CREATE UNIQUE INDEX generar_compensaciones_pkey ON public.generar_compensaciones USING btree (gen_cod);

CREATE UNIQUE INDEX compensaciones_detalles_pkey ON public.compensaciones_detalles USING btree (com_det_cod);

CREATE UNIQUE INDEX sincronizacion_pkey ON public.sincronizacion USING btree (sin_cod);

CREATE UNIQUE INDEX meses_pkey ON public.meses USING btree (mes_cod);

CREATE UNIQUE INDEX referenciales_pkey ON public.referenciales USING btree (ref_cod);

CREATE UNIQUE INDEX talentos_permisos_ugmembers_pkey ON public.talentos_permisos_ugmembers USING btree ("UserName", "GroupID", "Provider");

CREATE UNIQUE INDEX usuarios_pkey ON public.usuarios USING btree (usu_cod);

CREATE UNIQUE INDEX cantidad_vacaciones_por_anho_pkey ON public.cantidad_vacaciones_por_anho USING btree (can_cod);

CREATE UNIQUE INDEX roles_pkey ON public.roles USING btree (rol_id);

CREATE UNIQUE INDEX compensaciones_actualizacion_pkey ON public.compensaciones_actualizacion USING btree (com_cod);

CREATE INDEX idx_ocurrencia ON public.compensaciones_actualizacion USING btree (com_cod_ocurrencia);

CREATE UNIQUE INDEX estados_tablas_generadas_pkey ON public.estados_tablas_generadas USING btree (est_cod);

CREATE UNIQUE INDEX legajos_pkey ON public.legajos USING btree (leg_cod);

CREATE UNIQUE INDEX departamentos_pkey ON public.departamentos USING btree (dep_cod);

CREATE UNIQUE INDEX tipos_grupos_pkey ON public.tipos_grupos USING btree (tip_cod);

CREATE UNIQUE INDEX idiomas_pkey ON public.idiomas USING btree (idi_codigo);

CREATE UNIQUE INDEX observaciones_comisionamiento_pkey ON public.observaciones_comisionamiento USING btree (obs_cod);

CREATE UNIQUE INDEX instituciones_origen_pkey ON public.instituciones_origen USING btree (ins_cod);

CREATE UNIQUE INDEX usuarios_ugrights_pkey ON public.usuarios_ugrights USING btree ("TableName", "GroupID");
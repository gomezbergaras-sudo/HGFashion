-- =====================================================================
-- 008 · ROW LEVEL SECURITY
-- Modelo: gerente general → toda la empresa
--         supervisor de tienda → su tienda (sin datos salariales de escritura)
--         supervisor auxiliar → su tienda, solo lectura + registro operativo
--         empleado → únicamente sus propios datos
-- =====================================================================

-- ---------------------------------------------------------------------
-- HELPERS  (security definer: leen perfiles sin disparar recursión de RLS)
-- ---------------------------------------------------------------------
create or replace function rrhh.mi_rol()
returns rol_sistema
language sql stable security definer set search_path = public, rrhh as $$
  select rol from perfiles where id = auth.uid() and activo;
$$;

create or replace function rrhh.mi_empresa()
returns uuid
language sql stable security definer set search_path = public, rrhh as $$
  select empresa_id from perfiles where id = auth.uid() and activo;
$$;

create or replace function rrhh.mi_tienda()
returns uuid
language sql stable security definer set search_path = public, rrhh as $$
  select tienda_id from perfiles where id = auth.uid() and activo;
$$;

create or replace function rrhh.mi_empleado_id()
returns uuid
language sql stable security definer set search_path = public, rrhh as $$
  select id from empleados where usuario_id = auth.uid();
$$;

create or replace function rrhh.es_gerente()
returns boolean language sql stable as $$ select rrhh.mi_rol() = 'gerente_general'; $$;

create or replace function rrhh.es_supervisor()
returns boolean language sql stable as $$
  select rrhh.mi_rol() in ('gerente_general','supervisor_tienda');
$$;

create or replace function rrhh.tiene_acceso_tienda(p_tienda uuid)
returns boolean language sql stable as $$
  select rrhh.es_gerente() or (p_tienda is not null and p_tienda = rrhh.mi_tienda());
$$;

-- Acceso a datos salariales: solo gerente general y supervisor de tienda
-- (lectura). El auxiliar y el empleado ajeno quedan fuera.
create or replace function rrhh.ve_salarios_de(p_tienda uuid)
returns boolean language sql stable as $$
  select rrhh.es_gerente()
      or (rrhh.mi_rol() = 'supervisor_tienda' and p_tienda = rrhh.mi_tienda());
$$;

grant usage on schema rrhh to authenticated;
grant execute on function rrhh.mi_rol, rrhh.mi_empresa, rrhh.mi_tienda,
  rrhh.mi_empleado_id, rrhh.es_gerente, rrhh.es_supervisor,
  rrhh.tiene_acceso_tienda, rrhh.ve_salarios_de to authenticated;

-- ---------------------------------------------------------------------
-- ACTIVACIÓN
-- ---------------------------------------------------------------------
alter table empresas               enable row level security;
alter table tiendas                enable row level security;
alter table perfiles               enable row level security;
alter table cargos                 enable row level security;
alter table empleados              enable row level security;
alter table historial_salarios     enable row level security;
alter table documentos             enable row level security;
alter table parametros_legales     enable row level security;
alter table tasas_cambio           enable row level security;
alter table feriados               enable row level security;
alter table islr_tramos            enable row level security;
alter table conceptos_nomina       enable row level security;
alter table empleado_conceptos     enable row level security;
alter table prestamos              enable row level security;
alter table horarios               enable row level security;
alter table horario_dias           enable row level security;
alter table empleado_horarios      enable row level security;
alter table marcajes               enable row level security;
alter table asistencias            enable row level security;
alter table horas_extra            enable row level security;
alter table incidencias            enable row level security;
alter table vacaciones_periodos    enable row level security;
alter table nominas                enable row level security;
alter table nomina_empleados       enable row level security;
alter table detalle_nomina         enable row level security;
alter table recibos_pago           enable row level security;
alter table prestaciones_movimientos enable row level security;
alter table prestaciones_saldo     enable row level security;
alter table utilidades             enable row level security;
alter table liquidaciones          enable row level security;

-- ---------------------------------------------------------------------
-- CONFIGURACIÓN Y CATÁLOGOS
-- ---------------------------------------------------------------------
create policy empresas_select on empresas for select to authenticated
  using (id = rrhh.mi_empresa());
create policy empresas_write on empresas for update to authenticated
  using (id = rrhh.mi_empresa() and rrhh.es_gerente())
  with check (id = rrhh.mi_empresa() and rrhh.es_gerente());

create policy tiendas_select on tiendas for select to authenticated
  using (empresa_id = rrhh.mi_empresa());
create policy tiendas_admin on tiendas for all to authenticated
  using (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente())
  with check (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente());

create policy cargos_select on cargos for select to authenticated
  using (empresa_id = rrhh.mi_empresa());
create policy cargos_admin on cargos for all to authenticated
  using (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente())
  with check (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente());

-- Parámetros legales y tasas: lectura para todos, escritura solo gerente
create policy param_select on parametros_legales for select to authenticated using (true);
create policy param_admin  on parametros_legales for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy tasas_select on tasas_cambio for select to authenticated using (true);
create policy tasas_admin  on tasas_cambio for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy feriados_select on feriados for select to authenticated using (true);
create policy feriados_admin  on feriados for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy islr_select on islr_tramos for select to authenticated using (true);
create policy islr_admin  on islr_tramos for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy conceptos_select on conceptos_nomina for select to authenticated
  using (empresa_id = rrhh.mi_empresa());
create policy conceptos_admin on conceptos_nomina for all to authenticated
  using (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente())
  with check (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente());

-- ---------------------------------------------------------------------
-- PERFILES
-- ---------------------------------------------------------------------
create policy perfiles_propio on perfiles for select to authenticated
  using (id = auth.uid());
create policy perfiles_equipo on perfiles for select to authenticated
  using (empresa_id = rrhh.mi_empresa()
         and (rrhh.es_gerente() or tienda_id = rrhh.mi_tienda()));
create policy perfiles_admin on perfiles for all to authenticated
  using (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente())
  with check (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente());

-- ---------------------------------------------------------------------
-- EMPLEADOS
-- ---------------------------------------------------------------------
create policy empleados_select on empleados for select to authenticated
  using (
    empresa_id = rrhh.mi_empresa()
    and (rrhh.es_gerente()
         or tienda_id = rrhh.mi_tienda()
         or usuario_id = auth.uid())
  );

-- Alta y baja: solo gerente general
create policy empleados_insert on empleados for insert to authenticated
  with check (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente());
create policy empleados_delete on empleados for delete to authenticated
  using (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente());

-- Actualización: gerente en toda la empresa; supervisor de tienda solo en la
-- suya y sin poder mover al empleado a otra tienda.
create policy empleados_update_gerente on empleados for update to authenticated
  using (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente())
  with check (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente());
create policy empleados_update_supervisor on empleados for update to authenticated
  using (tienda_id = rrhh.mi_tienda() and rrhh.mi_rol() = 'supervisor_tienda')
  with check (tienda_id = rrhh.mi_tienda() and rrhh.mi_rol() = 'supervisor_tienda');

-- ---------------------------------------------------------------------
-- HISTORIAL SALARIAL  (el dato más sensible del sistema)
-- ---------------------------------------------------------------------
create policy salarios_select on historial_salarios for select to authenticated
  using (
    exists (
      select 1 from empleados e
      where e.id = historial_salarios.empleado_id
        and ( rrhh.ve_salarios_de(e.tienda_id)      -- gerente o supervisor de esa tienda
              or e.usuario_id = auth.uid() )        -- el propio trabajador
    )
  );

-- Escritura: EXCLUSIVA del gerente general.
create policy salarios_admin on historial_salarios for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy empleado_conceptos_select on empleado_conceptos for select to authenticated
  using (exists (select 1 from empleados e where e.id = empleado_conceptos.empleado_id
                 and (rrhh.ve_salarios_de(e.tienda_id) or e.usuario_id = auth.uid())));
create policy empleado_conceptos_admin on empleado_conceptos for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy prestamos_select on prestamos for select to authenticated
  using (exists (select 1 from empleados e where e.id = prestamos.empleado_id
                 and (rrhh.ve_salarios_de(e.tienda_id) or e.usuario_id = auth.uid())));
create policy prestamos_admin on prestamos for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

-- ---------------------------------------------------------------------
-- DOCUMENTOS
-- ---------------------------------------------------------------------
create policy documentos_select on documentos for select to authenticated
  using (exists (select 1 from empleados e where e.id = documentos.empleado_id
                 and (rrhh.es_gerente() or e.tienda_id = rrhh.mi_tienda()
                      or e.usuario_id = auth.uid())));
create policy documentos_insert on documentos for insert to authenticated
  with check (exists (select 1 from empleados e where e.id = documentos.empleado_id
                      and (rrhh.es_gerente() or e.tienda_id = rrhh.mi_tienda())));
create policy documentos_delete on documentos for delete to authenticated
  using (rrhh.es_gerente());

-- ---------------------------------------------------------------------
-- HORARIOS
-- ---------------------------------------------------------------------
create policy horarios_select on horarios for select to authenticated
  using (empresa_id = rrhh.mi_empresa());
create policy horarios_admin on horarios for all to authenticated
  using (empresa_id = rrhh.mi_empresa() and rrhh.es_supervisor())
  with check (empresa_id = rrhh.mi_empresa() and rrhh.es_supervisor());

create policy horario_dias_all on horario_dias for all to authenticated
  using (exists (select 1 from horarios h where h.id = horario_dias.horario_id
                 and h.empresa_id = rrhh.mi_empresa()))
  with check (exists (select 1 from horarios h where h.id = horario_dias.horario_id
                 and h.empresa_id = rrhh.mi_empresa() and rrhh.es_supervisor()));

create policy empleado_horarios_all on empleado_horarios for all to authenticated
  using (exists (select 1 from empleados e where e.id = empleado_horarios.empleado_id
                 and (rrhh.es_gerente() or e.tienda_id = rrhh.mi_tienda())))
  with check (exists (select 1 from empleados e where e.id = empleado_horarios.empleado_id
                 and (rrhh.es_gerente() or e.tienda_id = rrhh.mi_tienda())));

-- ---------------------------------------------------------------------
-- ASISTENCIA  (auxiliar SÍ registra; empleado solo consulta lo propio)
-- ---------------------------------------------------------------------
create policy marcajes_select on marcajes for select to authenticated
  using (rrhh.tiene_acceso_tienda(tienda_id) or empleado_id = rrhh.mi_empleado_id());
create policy marcajes_insert on marcajes for insert to authenticated
  with check (rrhh.tiene_acceso_tienda(tienda_id) or empleado_id = rrhh.mi_empleado_id());
-- Los marcajes son inmutables: no hay policy de update ni delete.

create policy asistencias_select on asistencias for select to authenticated
  using (rrhh.tiene_acceso_tienda(tienda_id) or empleado_id = rrhh.mi_empleado_id());
create policy asistencias_write on asistencias for update to authenticated
  using (rrhh.tiene_acceso_tienda(tienda_id) and rrhh.mi_rol() <> 'empleado')
  with check (rrhh.tiene_acceso_tienda(tienda_id) and rrhh.mi_rol() <> 'empleado');

-- ---------------------------------------------------------------------
-- HORAS EXTRA: el auxiliar registra, NO aprueba
-- ---------------------------------------------------------------------
create policy he_select on horas_extra for select to authenticated
  using (rrhh.tiene_acceso_tienda(tienda_id) or empleado_id = rrhh.mi_empleado_id());
create policy he_insert on horas_extra for insert to authenticated
  with check (rrhh.tiene_acceso_tienda(tienda_id)
              and rrhh.mi_rol() <> 'empleado'
              and estado = 'pendiente');
create policy he_aprobar on horas_extra for update to authenticated
  using (rrhh.tiene_acceso_tienda(tienda_id)
         and rrhh.mi_rol() in ('gerente_general','supervisor_tienda'))
  with check (rrhh.tiene_acceso_tienda(tienda_id)
         and rrhh.mi_rol() in ('gerente_general','supervisor_tienda'));

-- ---------------------------------------------------------------------
-- INCIDENCIAS: el empleado solicita permisos; el auxiliar reporta sin aprobar
-- ---------------------------------------------------------------------
create policy inc_select on incidencias for select to authenticated
  using (rrhh.tiene_acceso_tienda(tienda_id) or empleado_id = rrhh.mi_empleado_id());
create policy inc_insert_propia on incidencias for insert to authenticated
  with check (empleado_id = rrhh.mi_empleado_id()
              and estado = 'pendiente'
              and tipo in ('permiso_con_goce','permiso_sin_goce','reposo_medico','permiso_especial'));
create policy inc_insert_supervision on incidencias for insert to authenticated
  with check (rrhh.tiene_acceso_tienda(tienda_id)
              and rrhh.mi_rol() <> 'empleado'
              and estado = 'pendiente');
create policy inc_aprobar on incidencias for update to authenticated
  using (rrhh.tiene_acceso_tienda(tienda_id)
         and rrhh.mi_rol() in ('gerente_general','supervisor_tienda'))
  with check (rrhh.tiene_acceso_tienda(tienda_id)
         and rrhh.mi_rol() in ('gerente_general','supervisor_tienda'));
-- Despidos y suspensiones: solo el gerente general
create policy inc_egresos on incidencias for insert to authenticated
  with check (rrhh.es_gerente());

create policy vac_select on vacaciones_periodos for select to authenticated
  using (exists (select 1 from empleados e where e.id = vacaciones_periodos.empleado_id
                 and (rrhh.tiene_acceso_tienda(e.tienda_id) or e.usuario_id = auth.uid())));
create policy vac_admin on vacaciones_periodos for all to authenticated
  using (rrhh.es_supervisor()) with check (rrhh.es_supervisor());

-- ---------------------------------------------------------------------
-- NÓMINA
-- ---------------------------------------------------------------------
create policy nominas_select on nominas for select to authenticated
  using (empresa_id = rrhh.mi_empresa()
         and (rrhh.es_gerente()
              or (rrhh.mi_rol() = 'supervisor_tienda' and tienda_id = rrhh.mi_tienda())));
create policy nominas_admin on nominas for all to authenticated
  using (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente())
  with check (empresa_id = rrhh.mi_empresa() and rrhh.es_gerente());

create policy ne_select on nomina_empleados for select to authenticated
  using (
    rrhh.ve_salarios_de(tienda_id)
    or empleado_id = rrhh.mi_empleado_id()
  );
create policy ne_admin on nomina_empleados for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy dn_select on detalle_nomina for select to authenticated
  using (exists (select 1 from nomina_empleados ne
                 where ne.id = detalle_nomina.nomina_empleado_id
                   and (rrhh.ve_salarios_de(ne.tienda_id)
                        or ne.empleado_id = rrhh.mi_empleado_id())));
create policy dn_admin on detalle_nomina for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy recibos_select on recibos_pago for select to authenticated
  using (exists (select 1 from nomina_empleados ne
                 where ne.id = recibos_pago.nomina_empleado_id
                   and (rrhh.ve_salarios_de(ne.tienda_id)
                        or ne.empleado_id = rrhh.mi_empleado_id())));
create policy recibos_admin on recibos_pago for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

-- ---------------------------------------------------------------------
-- PRESTACIONES, UTILIDADES Y LIQUIDACIONES
-- ---------------------------------------------------------------------
create policy presta_select on prestaciones_movimientos for select to authenticated
  using (exists (select 1 from empleados e where e.id = prestaciones_movimientos.empleado_id
                 and (rrhh.ve_salarios_de(e.tienda_id) or e.usuario_id = auth.uid())));
create policy presta_admin on prestaciones_movimientos for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy saldo_select on prestaciones_saldo for select to authenticated
  using (exists (select 1 from empleados e where e.id = prestaciones_saldo.empleado_id
                 and (rrhh.ve_salarios_de(e.tienda_id) or e.usuario_id = auth.uid())));

create policy util_select on utilidades for select to authenticated
  using (exists (select 1 from empleados e where e.id = utilidades.empleado_id
                 and (rrhh.ve_salarios_de(e.tienda_id) or e.usuario_id = auth.uid())));
create policy util_admin on utilidades for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

create policy liq_select on liquidaciones for select to authenticated
  using (exists (select 1 from empleados e where e.id = liquidaciones.empleado_id
                 and (rrhh.ve_salarios_de(e.tienda_id) or e.usuario_id = auth.uid())));
create policy liq_admin on liquidaciones for all to authenticated
  using (rrhh.es_gerente()) with check (rrhh.es_gerente());

-- =====================================================================
-- 009 · VISTAS DE REPORTE Y AUDITORÍA
-- =====================================================================

-- ---------------------------------------------------------------------
-- AUDITORÍA GENÉRICA
-- ---------------------------------------------------------------------
create table auditoria (
  id            bigserial primary key,
  tabla         text not null,
  registro_id   text,
  operacion     char(1) not null check (operacion in ('I','U','D')),
  usuario_id    uuid,
  rol           text,
  datos_antes   jsonb,
  datos_despues jsonb,
  campos_cambiados text[],
  ip            inet,
  momento       timestamptz not null default now()
);

create index on auditoria (tabla, momento desc);
create index on auditoria (usuario_id, momento desc);
create index on auditoria (registro_id);

create or replace function rrhh.audit()
returns trigger language plpgsql security definer set search_path = public, rrhh as $$
declare
  v_antes jsonb; v_despues jsonb; v_campos text[];
begin
  if tg_op = 'DELETE' then
    v_antes := to_jsonb(old);
  elsif tg_op = 'INSERT' then
    v_despues := to_jsonb(new);
  else
    v_antes := to_jsonb(old); v_despues := to_jsonb(new);
    select array_agg(key) into v_campos
    from jsonb_each(v_despues) d
    where d.value is distinct from v_antes -> d.key;
  end if;

  insert into auditoria (tabla, registro_id, operacion, usuario_id, rol,
                         datos_antes, datos_despues, campos_cambiados)
  values (tg_table_name,
          coalesce((v_despues->>'id'), (v_antes->>'id')),
          left(tg_op, 1),
          auth.uid(),
          rrhh.mi_rol()::text,
          v_antes, v_despues, v_campos);

  return coalesce(new, old);
end;
$$;

-- Tablas auditadas (las que tienen consecuencias legales o económicas)
create trigger audit_empleados after insert or update or delete on empleados
  for each row execute function rrhh.audit();
create trigger audit_salarios after insert or update or delete on historial_salarios
  for each row execute function rrhh.audit();
create trigger audit_nominas after insert or update or delete on nominas
  for each row execute function rrhh.audit();
create trigger audit_incidencias after insert or update or delete on incidencias
  for each row execute function rrhh.audit();
create trigger audit_horas_extra after insert or update or delete on horas_extra
  for each row execute function rrhh.audit();
create trigger audit_parametros after insert or update or delete on parametros_legales
  for each row execute function rrhh.audit();
create trigger audit_prestaciones after insert or update or delete on prestaciones_movimientos
  for each row execute function rrhh.audit();
create trigger audit_liquidaciones after insert or update or delete on liquidaciones
  for each row execute function rrhh.audit();

alter table auditoria enable row level security;
create policy auditoria_select on auditoria for select to authenticated
  using (rrhh.es_gerente());
-- Nadie puede modificar ni borrar la auditoría desde la API.

-- ---------------------------------------------------------------------
-- VISTA: RECIBO DE PAGO (todo lo que necesita el PDF en una consulta)
-- ---------------------------------------------------------------------
create or replace view v_recibo_pago
with (security_invoker = true) as
select
  ne.id                       as nomina_empleado_id,
  r.numero                    as numero_recibo,
  em.nombre                   as empresa_nombre,
  em.razon_social,
  em.rif                      as empresa_rif,
  em.logo_path,
  em.direccion_fiscal,
  em.telefono                 as empresa_telefono,
  em.email                    as empresa_email,
  e.nombre_completo           as empleado,
  e.nacionalidad_ci || '-' || e.cedula as cedula,
  c.nombre                    as cargo,
  t.nombre                    as tienda,
  e.fecha_ingreso,
  n.periodo_inicio,
  n.periodo_fin,
  n.fecha_pago,
  n.tasa_bcv,
  ne.dias_laborados,
  ne.salario_diario_normal,
  ne.salario_diario_integral,
  ne.total_asignaciones,
  ne.total_deducciones,
  ne.total_neto,
  ne.neto_usd,
  (select jsonb_agg(jsonb_build_object(
      'codigo', d.codigo, 'nombre', d.nombre, 'caracter', d.caracter,
      'cantidad', d.cantidad, 'monto', d.monto, 'moneda', d.moneda,
      'monto_usd', d.monto_usd) order by d.orden)
   from detalle_nomina d
   where d.nomina_empleado_id = ne.id
     and d.caracter in ('salarial','no_salarial')) as asignaciones,
  (select jsonb_agg(jsonb_build_object(
      'codigo', d.codigo, 'nombre', d.nombre,
      'monto', d.monto, 'moneda', d.moneda) order by d.orden)
   from detalle_nomina d
   where d.nomina_empleado_id = ne.id
     and d.caracter = 'deduccion') as deducciones
from nomina_empleados ne
join nominas n   on n.id = ne.nomina_id
join empleados e on e.id = ne.empleado_id
join empresas em on em.id = n.empresa_id
join tiendas  t  on t.id = ne.tienda_id
left join cargos c on c.id = e.cargo_id
left join recibos_pago r on r.nomina_empleado_id = ne.id;

-- ---------------------------------------------------------------------
-- VISTA: COSTO LABORAL POR TIENDA
-- ---------------------------------------------------------------------
create materialized view mv_costo_laboral_tienda as
select
  n.empresa_id,
  ne.tienda_id,
  t.nombre                    as tienda,
  date_trunc('month', n.fecha_pago)::date as mes,
  count(distinct ne.empleado_id)          as empleados,
  sum(ne.total_asignaciones)              as asignaciones,
  sum(ne.total_deducciones)               as deducciones,
  sum(ne.total_neto)                      as neto_pagado,
  sum(ne.total_aportes_patronales)        as aportes_patronales,
  sum(ne.total_neto + ne.total_aportes_patronales) as costo_total,
  sum(ne.neto_usd)                        as neto_usd,
  max(n.tasa_bcv)                         as tasa_bcv
from nomina_empleados ne
join nominas n on n.id = ne.nomina_id
join tiendas t on t.id = ne.tienda_id
where n.estado in ('aprobada','pagada')
group by 1,2,3,4;

create unique index on mv_costo_laboral_tienda (tienda_id, mes);

-- ---------------------------------------------------------------------
-- VISTA: AUSENTISMO POR TIENDA
-- ---------------------------------------------------------------------
create materialized view mv_ausentismo as
select
  a.tienda_id,
  t.nombre as tienda,
  date_trunc('month', a.fecha)::date as mes,
  count(*)                                                  as dias_programados,
  count(*) filter (where a.estatus = 'ausente')             as dias_ausencia,
  count(*) filter (where a.minutos_retardo > 0)             as eventos_retardo,
  sum(a.minutos_retardo)                                    as minutos_retardo,
  round(100.0 * count(*) filter (where a.estatus = 'ausente')
        / nullif(count(*),0), 2)                            as tasa_ausentismo
from asistencias a
join tiendas t on t.id = a.tienda_id
where a.estatus not in ('descanso','feriado')
group by 1,2,3;

create unique index on mv_ausentismo (tienda_id, mes);

-- ---------------------------------------------------------------------
-- VISTA: ROTACIÓN DE PERSONAL
-- ---------------------------------------------------------------------
create materialized view mv_rotacion as
with meses as (
  select generate_series(
    date_trunc('month', (select min(fecha_ingreso) from empleados)),
    date_trunc('month', current_date), interval '1 month')::date as mes
)
select
  t.id as tienda_id, t.nombre as tienda, m.mes,
  count(*) filter (where date_trunc('month', e.fecha_ingreso)::date = m.mes) as ingresos,
  count(*) filter (where date_trunc('month', e.fecha_egreso)::date  = m.mes) as egresos,
  count(*) filter (where e.fecha_ingreso <= (m.mes + interval '1 month' - interval '1 day')::date
                     and (e.fecha_egreso is null
                          or e.fecha_egreso > (m.mes + interval '1 month' - interval '1 day')::date)) as plantilla,
  round(100.0 * count(*) filter (where date_trunc('month', e.fecha_egreso)::date = m.mes)
        / nullif(count(*) filter (where e.fecha_ingreso <= (m.mes + interval '1 month' - interval '1 day')::date
                     and (e.fecha_egreso is null
                          or e.fecha_egreso > (m.mes + interval '1 month' - interval '1 day')::date)),0), 2) as tasa_rotacion
from meses m
cross join tiendas t
left join empleados e on e.tienda_id = t.id
group by 1,2,3;

create unique index on mv_rotacion (tienda_id, mes);

-- ---------------------------------------------------------------------
-- VISTA: PASIVO LABORAL (prestaciones acumuladas — cifra de balance)
-- ---------------------------------------------------------------------
create or replace view v_pasivo_laboral
with (security_invoker = true) as
select
  e.tienda_id,
  t.nombre as tienda,
  e.id as empleado_id,
  e.nombre_completo,
  e.fecha_ingreso,
  rrhh.antiguedad_anios(e.fecha_ingreso) as anios,
  s.dias_acumulados,
  s.capital_acumulado,
  s.intereses_acumulados,
  s.anticipos_otorgados,
  s.saldo_disponible,
  rrhh.a_dolares(s.saldo_disponible, current_date) as saldo_usd
from empleados e
join tiendas t on t.id = e.tienda_id
left join prestaciones_saldo s on s.empleado_id = e.id
where e.estado <> 'egresado';

-- ---------------------------------------------------------------------
-- VISTA: VACACIONES PENDIENTES
-- ---------------------------------------------------------------------
create or replace view v_vacaciones_pendientes
with (security_invoker = true) as
select
  e.tienda_id, t.nombre as tienda, e.id as empleado_id, e.nombre_completo,
  v.anio_servicio, v.fecha_inicio_periodo, v.fecha_fin_periodo,
  v.dias_vacaciones, v.dias_disfrutados,
  v.dias_vacaciones - v.dias_disfrutados as dias_pendientes,
  v.bono_pagado,
  (current_date - v.fecha_fin_periodo) > 365 as vencida
from vacaciones_periodos v
join empleados e on e.id = v.empleado_id
join tiendas t   on t.id = e.tienda_id
where v.dias_disfrutados < v.dias_vacaciones
  and e.estado <> 'egresado';

-- ---------------------------------------------------------------------
-- REFRESCO DE MATERIALIZADAS (cron de Supabase, cada noche)
-- ---------------------------------------------------------------------
create or replace function rrhh.refrescar_reportes()
returns void language plpgsql security definer set search_path = public, rrhh as $$
begin
  refresh materialized view concurrently mv_costo_laboral_tienda;
  refresh materialized view concurrently mv_ausentismo;
  refresh materialized view concurrently mv_rotacion;
end;
$$;

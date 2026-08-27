-- =====================================================================
-- 007 · TRIGGERS Y REGLAS DE NEGOCIO
-- =====================================================================

-- ---------------------------------------------------------------------
-- actualizado_en
-- ---------------------------------------------------------------------
create or replace function rrhh.touch_actualizado_en()
returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

create trigger trg_touch_empresas   before update on empresas
  for each row execute function rrhh.touch_actualizado_en();
create trigger trg_touch_empleados  before update on empleados
  for each row execute function rrhh.touch_actualizado_en();
create trigger trg_touch_perfiles   before update on perfiles
  for each row execute function rrhh.touch_actualizado_en();

-- ---------------------------------------------------------------------
-- HISTORIAL SALARIAL: cerrar automáticamente la vigencia anterior
-- ---------------------------------------------------------------------
create or replace function rrhh.cerrar_salario_anterior()
returns trigger language plpgsql as $$
begin
  update historial_salarios
     set vigente_hasta = new.vigente_desde - 1
   where empleado_id = new.empleado_id
     and vigente_hasta is null
     and vigente_desde < new.vigente_desde
     and id <> new.id;
  return new;
end;
$$;

create trigger trg_cerrar_salario_anterior
  before insert on historial_salarios
  for each row execute function rrhh.cerrar_salario_anterior();

-- ---------------------------------------------------------------------
-- PARÁMETROS LEGALES: cerrar la vigencia anterior de la misma clave
-- ---------------------------------------------------------------------
create or replace function rrhh.cerrar_parametro_anterior()
returns trigger language plpgsql as $$
begin
  update parametros_legales
     set vigente_hasta = new.vigente_desde - 1
   where clave = new.clave
     and vigente_hasta is null
     and vigente_desde < new.vigente_desde
     and id <> new.id;
  return new;
end;
$$;

create trigger trg_cerrar_parametro_anterior
  before insert on parametros_legales
  for each row execute function rrhh.cerrar_parametro_anterior();

-- ---------------------------------------------------------------------
-- HORAS EXTRA: topes legales (art. 178 LOTTT)
-- ---------------------------------------------------------------------
create or replace function rrhh.valida_topes_horas_extra()
returns trigger language plpgsql as $$
declare
  v_dia numeric; v_semana numeric; v_anio numeric;
  v_tope_dia numeric; v_tope_sem numeric; v_tope_anio numeric;
begin
  v_tope_dia  := coalesce(rrhh.param('TOPE_HE_DIARIAS',   new.fecha), 2);
  v_tope_sem  := coalesce(rrhh.param('TOPE_HE_SEMANALES', new.fecha), 10);
  v_tope_anio := coalesce(rrhh.param('TOPE_HE_ANUALES',   new.fecha), 100);

  select coalesce(sum(horas),0) into v_dia
  from horas_extra
  where empleado_id = new.empleado_id and fecha = new.fecha
    and estado <> 'rechazada' and id <> coalesce(new.id, gen_random_uuid());

  select coalesce(sum(horas),0) into v_semana
  from horas_extra
  where empleado_id = new.empleado_id
    and date_trunc('week', fecha) = date_trunc('week', new.fecha)
    and estado <> 'rechazada' and id <> coalesce(new.id, gen_random_uuid());

  select coalesce(sum(horas),0) into v_anio
  from horas_extra
  where empleado_id = new.empleado_id
    and extract(year from fecha) = extract(year from new.fecha)
    and estado <> 'rechazada' and id <> coalesce(new.id, gen_random_uuid());

  if v_dia + new.horas > v_tope_dia then
    raise exception 'Tope legal excedido: máximo % horas extra por día (art. 178 LOTTT). Acumulado: %',
      v_tope_dia, v_dia + new.horas;
  end if;
  if v_semana + new.horas > v_tope_sem then
    raise exception 'Tope legal excedido: máximo % horas extra semanales (art. 178 LOTTT). Acumulado: %',
      v_tope_sem, v_semana + new.horas;
  end if;
  if v_anio + new.horas > v_tope_anio then
    raise exception 'Tope legal excedido: máximo % horas extra anuales (art. 178 LOTTT). Acumulado: %',
      v_tope_anio, v_anio + new.horas;
  end if;

  return new;
end;
$$;

create trigger trg_valida_topes_horas_extra
  before insert or update of horas, fecha on horas_extra
  for each row execute function rrhh.valida_topes_horas_extra();

-- ---------------------------------------------------------------------
-- PRESTACIONES: mantener el saldo materializado
-- ---------------------------------------------------------------------
create or replace function rrhh.actualiza_saldo_prestaciones()
returns trigger language plpgsql as $$
declare v_emp uuid;
begin
  v_emp := coalesce(new.empleado_id, old.empleado_id);

  insert into prestaciones_saldo (empleado_id) values (v_emp)
  on conflict (empleado_id) do nothing;

  update prestaciones_saldo s set
    dias_acumulados = c.dias,
    capital_acumulado = c.capital,
    intereses_acumulados = c.intereses,
    anticipos_otorgados = c.anticipos,
    saldo_disponible = c.capital + c.intereses - c.anticipos,
    actualizado_en = now()
  from (
    select
      coalesce(sum(dias) filter (where tipo in ('garantia_trimestral','dias_adicionales')),0) as dias,
      coalesce(sum(monto) filter (where tipo in ('garantia_trimestral','dias_adicionales','ajuste')),0) as capital,
      coalesce(sum(monto) filter (where tipo = 'intereses'),0) as intereses,
      coalesce(sum(monto) filter (where tipo in ('anticipo','pago_liquidacion')),0) as anticipos
    from prestaciones_movimientos where empleado_id = v_emp
  ) c
  where s.empleado_id = v_emp;

  return null;
end;
$$;

create trigger trg_saldo_prestaciones
  after insert or update or delete on prestaciones_movimientos
  for each row execute function rrhh.actualiza_saldo_prestaciones();

-- Anticipo máximo 75% de lo acumulado (art. 144 LOTTT)
create or replace function rrhh.valida_anticipo_prestaciones()
returns trigger language plpgsql as $$
declare v_disp numeric; v_tope numeric;
begin
  if new.tipo <> 'anticipo' then return new; end if;

  select capital_acumulado + intereses_acumulados - anticipos_otorgados
    into v_disp from prestaciones_saldo where empleado_id = new.empleado_id;

  v_tope := coalesce(v_disp, 0) * coalesce(rrhh.param('TOPE_ANTICIPO_PRESTACIONES', new.fecha), 0.75);

  if abs(new.monto) > v_tope then
    raise exception 'El anticipo (%) supera el 75%% del haber acumulado (tope: %) — art. 144 LOTTT',
      abs(new.monto), round(v_tope, 2);
  end if;
  return new;
end;
$$;

create trigger trg_valida_anticipo
  before insert on prestaciones_movimientos
  for each row execute function rrhh.valida_anticipo_prestaciones();

-- ---------------------------------------------------------------------
-- RECIBOS: correlativo atómico por empresa y año
-- ---------------------------------------------------------------------
create or replace function rrhh.siguiente_correlativo(p_empresa uuid, p_anio int)
returns text language plpgsql as $$
declare v_num integer; v_prefijo text;
begin
  insert into recibos_correlativo (empresa_id, anio) values (p_empresa, p_anio)
  on conflict (empresa_id, anio) do nothing;

  update recibos_correlativo
     set ultimo = ultimo + 1
   where empresa_id = p_empresa and anio = p_anio
  returning ultimo, prefijo into v_num, v_prefijo;

  return v_prefijo || '-' || p_anio || '-' || lpad(v_num::text, 6, '0');
end;
$$;

create or replace function rrhh.asigna_numero_recibo()
returns trigger language plpgsql as $$
declare v_empresa uuid; v_anio int;
begin
  if new.numero is not null and new.numero <> '' then return new; end if;

  select n.empresa_id, extract(year from n.fecha_pago)::int
    into v_empresa, v_anio
  from nomina_empleados ne join nominas n on n.id = ne.nomina_id
  where ne.id = new.nomina_empleado_id;

  new.numero := rrhh.siguiente_correlativo(v_empresa, v_anio);
  return new;
end;
$$;

create trigger trg_numero_recibo
  before insert on recibos_pago
  for each row execute function rrhh.asigna_numero_recibo();

-- ---------------------------------------------------------------------
-- NÓMINA: inmutabilidad tras la aprobación
-- ---------------------------------------------------------------------
create or replace function rrhh.protege_nomina_aprobada()
returns trigger language plpgsql as $$
declare v_estado estado_nomina;
begin
  select estado into v_estado from nominas
  where id = coalesce(
    (select nomina_id from nomina_empleados where id =
       coalesce(new.nomina_empleado_id, old.nomina_empleado_id)),
    null);

  if v_estado in ('aprobada','pagada') then
    raise exception 'La nómina está % y no admite cambios. Genere una nómina de ajuste retroactivo.', v_estado;
  end if;
  return coalesce(new, old);
end;
$$;

create trigger trg_protege_detalle
  before insert or update or delete on detalle_nomina
  for each row execute function rrhh.protege_nomina_aprobada();

-- Transiciones de estado válidas
create or replace function rrhh.valida_estado_nomina()
returns trigger language plpgsql as $$
begin
  if old.estado = new.estado then return new; end if;

  if old.estado in ('pagada','anulada') then
    raise exception 'Una nómina % no puede cambiar de estado.', old.estado;
  end if;

  if new.estado = 'aprobada' and new.aprobada_por is null then
    raise exception 'La aprobación requiere identificar al aprobador (gerente general).';
  end if;

  if new.estado = 'aprobada' then
    new.aprobada_en := now();
  end if;

  return new;
end;
$$;

create trigger trg_estado_nomina
  before update of estado on nominas
  for each row execute function rrhh.valida_estado_nomina();

-- ---------------------------------------------------------------------
-- ASISTENCIA: consolidar marcajes en la fila diaria
-- ---------------------------------------------------------------------
create or replace function rrhh.consolida_asistencia()
returns trigger language plpgsql as $$
declare
  v_ent timestamptz; v_sal timestamptz; v_alm int := 0;
  v_horas numeric := 0; v_retardo int := 0;
  v_hora_prog time; v_tolerancia int;
  v_feriado boolean;
begin
  select min(momento) filter (where tipo = 'entrada'),
         max(momento) filter (where tipo = 'salida'),
         coalesce(extract(epoch from (
           max(momento) filter (where tipo = 'regreso_almuerzo')
         - min(momento) filter (where tipo = 'salida_almuerzo')))/60, 0)::int
    into v_ent, v_sal, v_alm
  from marcajes
  where empleado_id = new.empleado_id and fecha_laboral = new.fecha_laboral;

  if v_ent is not null and v_sal is not null then
    v_horas := round(greatest(extract(epoch from (v_sal - v_ent))/3600 - v_alm/60.0, 0)::numeric, 2);
  end if;

  -- Retardo contra el horario asignado
  select hd.hora_entrada into v_hora_prog
  from empleado_horarios eh
  join horario_dias hd on hd.horario_id = eh.horario_id
   and hd.dia_semana = extract(dow from new.fecha_laboral)::smallint
  where eh.empleado_id = new.empleado_id
    and new.fecha_laboral >= eh.vigente_desde
    and (eh.vigente_hasta is null or new.fecha_laboral <= eh.vigente_hasta)
  limit 1;

  select em.tolerancia_retardo_min into v_tolerancia
  from empleados e join empresas em on em.id = e.empresa_id where e.id = new.empleado_id;

  if v_ent is not null and v_hora_prog is not null then
    v_retardo := greatest(0,
      (extract(epoch from ((v_ent at time zone 'America/Caracas')::time - v_hora_prog))/60)::int
      - coalesce(v_tolerancia, 0));
  end if;

  select exists(select 1 from feriados f where f.fecha = new.fecha_laboral) into v_feriado;

  insert into asistencias (empleado_id, tienda_id, fecha, hora_entrada, hora_salida,
                           minutos_almuerzo, horas_trabajadas, minutos_retardo,
                           es_feriado, estatus, calculado_en)
  values (new.empleado_id, new.tienda_id, new.fecha_laboral, v_ent, v_sal,
          v_alm, v_horas, v_retardo, coalesce(v_feriado,false),
          case when v_feriado then 'feriado' else 'presente' end, now())
  on conflict (empleado_id, fecha) do update set
    hora_entrada = excluded.hora_entrada,
    hora_salida  = excluded.hora_salida,
    minutos_almuerzo = excluded.minutos_almuerzo,
    horas_trabajadas = excluded.horas_trabajadas,
    minutos_retardo  = excluded.minutos_retardo,
    es_feriado = excluded.es_feriado,
    calculado_en = now();

  return null;
end;
$$;

create trigger trg_consolida_asistencia
  after insert on marcajes
  for each row execute function rrhh.consolida_asistencia();

-- ---------------------------------------------------------------------
-- VACACIONES: generar el periodo al cumplir cada aniversario
-- ---------------------------------------------------------------------
create or replace function rrhh.generar_periodos_vacaciones(p_empleado uuid)
returns int
language plpgsql security definer set search_path = public, rrhh as $$
declare
  e record; i int; v_creados int := 0; v_ini date; v_fin date;
begin
  select em.fecha_ingreso, em.fecha_egreso, e2.dias_vacaciones_base, e2.tope_dias_vacaciones,
         e2.dias_bono_vacacional_base, e2.tope_dias_bono_vacacional
    into e
  from empleados em join empresas e2 on e2.id = em.empresa_id where em.id = p_empleado;
  if not found then return 0; end if;

  for i in 1..rrhh.antiguedad_anios(e.fecha_ingreso, coalesce(e.fecha_egreso, current_date)) loop
    v_ini := (e.fecha_ingreso + make_interval(years => i - 1))::date;
    v_fin := (e.fecha_ingreso + make_interval(years => i))::date - 1;

    insert into vacaciones_periodos
      (empleado_id, anio_servicio, fecha_inicio_periodo, fecha_fin_periodo,
       dias_vacaciones, dias_bono_vacacional)
    values
      (p_empleado, i, v_ini, v_fin,
       rrhh.dias_vacaciones(i, e.dias_vacaciones_base, e.tope_dias_vacaciones),
       rrhh.dias_bono_vacacional(i, e.dias_bono_vacacional_base, e.tope_dias_bono_vacacional))
    on conflict (empleado_id, anio_servicio) do nothing;

    v_creados := v_creados + 1;
  end loop;

  return v_creados;
end;
$$;

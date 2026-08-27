-- =====================================================================
-- 006 · FUNCIONES DE CÁLCULO LEGAL
-- Todas viven en el esquema rrhh (no expuesto por PostREST) salvo las
-- marcadas explícitamente como API.
-- =====================================================================

-- ---------------------------------------------------------------------
-- LECTURA DE PARÁMETROS
-- ---------------------------------------------------------------------
create or replace function rrhh.param(p_clave text, p_fecha date default current_date)
returns numeric
language sql stable as $$
  select valor
  from parametros_legales
  where clave = p_clave
    and p_fecha >= vigente_desde
    and (vigente_hasta is null or p_fecha <= vigente_hasta)
  limit 1;
$$;

create or replace function rrhh.param_req(p_clave text, p_fecha date default current_date)
returns numeric
language plpgsql stable as $$
declare v numeric;
begin
  v := rrhh.param(p_clave, p_fecha);
  if v is null then
    raise exception 'Parámetro legal "%" no definido para la fecha %', p_clave, p_fecha
      using hint = 'Cargue la vigencia en parametros_legales antes de calcular la nómina.';
  end if;
  return v;
end;
$$;

-- Tasa BCV: la del día; si no hay (fin de semana), la última anterior.
create or replace function rrhh.tasa_bcv(p_fecha date default current_date)
returns numeric
language plpgsql stable as $$
declare v numeric;
begin
  select tasa_usd into v from tasas_cambio
  where fecha <= p_fecha
  order by fecha desc
  limit 1;

  -- Un cálculo con tasa cero es peor que un cálculo que falla: si falta la
  -- tasa del BCV para la fecha, se detiene el proceso en lugar de emitir
  -- un recibo en cero.
  if v is null then
    raise exception 'No hay tasa BCV registrada para el % ni para ninguna fecha anterior', p_fecha
      using hint = 'Ejecute la Edge Function sync-bcv o cargue la tasa manualmente en tasas_cambio.';
  end if;
  return v;
end;
$$;

create or replace function rrhh.a_bolivares(p_monto numeric, p_moneda moneda, p_fecha date)
returns numeric
language sql stable as $$
  select case when p_moneda = 'USD'
              then round(p_monto * rrhh.tasa_bcv(p_fecha), 4)
              else round(p_monto, 4) end;
$$;

create or replace function rrhh.a_dolares(p_monto_bs numeric, p_fecha date)
returns numeric
language sql stable as $$
  select round(p_monto_bs / rrhh.tasa_bcv(p_fecha), 4);
$$;

-- ---------------------------------------------------------------------
-- ANTIGÜEDAD
-- ---------------------------------------------------------------------
create or replace function rrhh.antiguedad_anios(p_ingreso date, p_corte date default current_date)
returns integer
language sql immutable as $$
  select greatest(0, extract(year from age(p_corte, p_ingreso))::int);
$$;

create or replace function rrhh.antiguedad_meses(p_ingreso date, p_corte date default current_date)
returns integer
language sql immutable as $$
  select greatest(0,
    extract(year from age(p_corte, p_ingreso))::int * 12
    + extract(month from age(p_corte, p_ingreso))::int);
$$;

-- ---------------------------------------------------------------------
-- SALARIOS
-- ---------------------------------------------------------------------
-- Salario base mensual expresado SIEMPRE en bolívares a la fecha dada.
create or replace function rrhh.salario_base_mensual(p_empleado uuid, p_fecha date)
returns numeric
language plpgsql stable as $$
declare r record;
begin
  select salario_base, moneda_salario into r
  from historial_salarios
  where empleado_id = p_empleado
    and p_fecha >= vigente_desde
    and (vigente_hasta is null or p_fecha <= vigente_hasta)
  limit 1;

  if not found then return 0; end if;
  return rrhh.a_bolivares(r.salario_base, r.moneda_salario, p_fecha);
end;
$$;

create or replace function rrhh.salario_diario_base(p_empleado uuid, p_fecha date)
returns numeric
language sql stable as $$
  select round(rrhh.salario_base_mensual(p_empleado, p_fecha) / 30.0, 4);
$$;

-- Salario NORMAL mensual = base + percepciones salariales regulares
-- (art. 104 LOTTT). Excluye expresamente los bonos no salariales.
create or replace function rrhh.salario_normal_mensual(p_empleado uuid, p_fecha date)
returns numeric
language plpgsql stable as $$
declare v_extra numeric := 0;
begin
  select coalesce(sum(
           rrhh.a_bolivares(coalesce(ec.monto,0) * coalesce(ec.cantidad,1), c.moneda, p_fecha)
         ), 0)
  into v_extra
  from empleado_conceptos ec
  join conceptos_nomina c on c.id = ec.concepto_id
  where ec.empleado_id = p_empleado
    and c.caracter = 'salarial'
    and c.activo
    and p_fecha >= ec.vigente_desde
    and (ec.vigente_hasta is null or p_fecha <= ec.vigente_hasta);

  return rrhh.salario_base_mensual(p_empleado, p_fecha) + v_extra;
end;
$$;

create or replace function rrhh.salario_diario_normal(p_empleado uuid, p_fecha date)
returns numeric
language sql stable as $$
  select round(rrhh.salario_normal_mensual(p_empleado, p_fecha) / 30.0, 4);
$$;

-- ---------------------------------------------------------------------
-- VACACIONES Y BONO VACACIONAL (arts. 190 y 192 LOTTT)
-- 15 días + 1 día adicional por cada año de servicio, tope 30.
-- ---------------------------------------------------------------------
create or replace function rrhh.dias_vacaciones(p_anio_servicio int, p_base int default 15, p_tope int default 30)
returns int
language sql immutable as $$
  select least(p_base + greatest(p_anio_servicio - 1, 0), p_tope);
$$;

create or replace function rrhh.dias_bono_vacacional(p_anio_servicio int, p_base int default 15, p_tope int default 30)
returns int
language sql immutable as $$
  select least(p_base + greatest(p_anio_servicio - 1, 0), p_tope);
$$;

-- ---------------------------------------------------------------------
-- ALÍCUOTAS Y SALARIO INTEGRAL (art. 122 LOTTT)
-- ---------------------------------------------------------------------
create or replace function rrhh.alicuota_bono_vacacional(p_empleado uuid, p_fecha date)
returns numeric
language plpgsql stable as $$
declare
  v_emp record; v_dias int; v_sdn numeric;
begin
  select e.fecha_ingreso, em.dias_bono_vacacional_base, em.tope_dias_bono_vacacional
    into v_emp
  from empleados e join empresas em on em.id = e.empresa_id
  where e.id = p_empleado;

  if not found then return 0; end if;

  v_dias := rrhh.dias_bono_vacacional(
              greatest(rrhh.antiguedad_anios(v_emp.fecha_ingreso, p_fecha), 1),
              v_emp.dias_bono_vacacional_base, v_emp.tope_dias_bono_vacacional);
  v_sdn  := rrhh.salario_diario_normal(p_empleado, p_fecha);
  return round(v_sdn * v_dias / 360.0, 4);
end;
$$;

create or replace function rrhh.alicuota_utilidades(p_empleado uuid, p_fecha date)
returns numeric
language plpgsql stable as $$
declare v_dias int; v_sdn numeric;
begin
  select em.dias_utilidades into v_dias
  from empleados e join empresas em on em.id = e.empresa_id
  where e.id = p_empleado;

  if not found then return 0; end if;

  v_sdn := rrhh.salario_diario_normal(p_empleado, p_fecha);
  return round(v_sdn * v_dias / 360.0, 4);
end;
$$;

create or replace function rrhh.salario_diario_integral(p_empleado uuid, p_fecha date)
returns numeric
language sql stable as $$
  select round(
    rrhh.salario_diario_normal(p_empleado, p_fecha)
    + rrhh.alicuota_bono_vacacional(p_empleado, p_fecha)
    + rrhh.alicuota_utilidades(p_empleado, p_fecha), 4);
$$;

-- ---------------------------------------------------------------------
-- HORAS EXTRA (arts. 117, 118 y 120 LOTTT)
-- ---------------------------------------------------------------------
create or replace function rrhh.factor_hora_extra(p_tipo tipo_hora_extra, p_fecha date default current_date)
returns numeric
language sql stable as $$
  select case p_tipo
    -- Diurna: valor hora + 50%
    when 'diurna'   then 1 + coalesce(rrhh.param('RECARGO_HE_DIURNA', p_fecha), 0.50)
    -- Nocturna: bono nocturno 30% sobre la hora y sobre eso el recargo de 50%
    when 'nocturna' then (1 + coalesce(rrhh.param('RECARGO_NOCTURNO', p_fecha), 0.30))
                       * (1 + coalesce(rrhh.param('RECARGO_HE_DIURNA', p_fecha), 0.50))
    -- Feriado / día de descanso trabajado: recargo del 50%
    when 'feriado'  then 1 + coalesce(rrhh.param('RECARGO_FERIADO', p_fecha), 0.50)
    when 'descanso' then 1 + coalesce(rrhh.param('RECARGO_FERIADO', p_fecha), 0.50)
  end;
$$;

create or replace function rrhh.valor_hora(p_empleado uuid, p_fecha date, p_horas_jornada numeric default 8)
returns numeric
language sql stable as $$
  select round(rrhh.salario_diario_normal(p_empleado, p_fecha) / nullif(p_horas_jornada, 0), 6);
$$;

create or replace function rrhh.monto_horas_extra(
  p_empleado uuid, p_fecha date, p_tipo tipo_hora_extra,
  p_horas numeric, p_horas_jornada numeric default 8)
returns numeric
language sql stable as $$
  select round(rrhh.valor_hora(p_empleado, p_fecha, p_horas_jornada)
             * rrhh.factor_hora_extra(p_tipo, p_fecha)
             * p_horas, 4);
$$;

-- ---------------------------------------------------------------------
-- SEGURIDAD SOCIAL
-- Bases y topes se leen de parametros_legales; nada va en duro.
-- ---------------------------------------------------------------------
-- IVSS: se cotiza sobre el salario normal semanal, tope 5 salarios mínimos.
create or replace function rrhh.base_ivss(p_salario_normal_mensual numeric, p_fecha date)
returns numeric
language plpgsql stable as $$
declare v_tope numeric; v_sm numeric;
begin
  v_sm   := coalesce(rrhh.param('SALARIO_MINIMO', p_fecha), 0);
  v_tope := coalesce(rrhh.param('TOPE_SM_IVSS', p_fecha), 5) * v_sm;
  if v_tope > 0 then
    return least(p_salario_normal_mensual, v_tope);
  end if;
  return p_salario_normal_mensual;
end;
$$;

create or replace function rrhh.retencion_ivss(
  p_salario_normal_mensual numeric, p_lunes_periodo int, p_fecha date)
returns numeric
language sql stable as $$
  -- Cotización semanal: base mensual / 4.333 * % * nº de lunes del periodo
  select round(
    rrhh.base_ivss(p_salario_normal_mensual, p_fecha) / 4.3333
    * coalesce(rrhh.param('IVSS_TRABAJADOR', p_fecha), 0.04)
    * p_lunes_periodo, 4);
$$;

create or replace function rrhh.retencion_rpe(
  p_salario_normal_mensual numeric, p_lunes_periodo int, p_fecha date)
returns numeric
language sql stable as $$
  select round(
    rrhh.base_ivss(p_salario_normal_mensual, p_fecha) / 4.3333
    * coalesce(rrhh.param('RPE_TRABAJADOR', p_fecha), 0.005)
    * p_lunes_periodo, 4);
$$;

-- FAOV: 1% del salario integral mensual (Ley del Régimen Prestacional de Vivienda)
create or replace function rrhh.retencion_faov(p_salario_integral_mensual numeric, p_fecha date)
returns numeric
language sql stable as $$
  select round(p_salario_integral_mensual
             * coalesce(rrhh.param('FAOV_TRABAJADOR', p_fecha), 0.01), 4);
$$;

-- INCES trabajador: 0,5% sobre las UTILIDADES pagadas (no sobre el sueldo).
create or replace function rrhh.retencion_inces_trabajador(p_utilidades numeric, p_fecha date)
returns numeric
language sql stable as $$
  select round(p_utilidades * coalesce(rrhh.param('INCES_TRABAJADOR', p_fecha), 0.005), 4);
$$;

comment on function rrhh.retencion_inces_trabajador is
  'Ley del INCES art. 14 num. 2: el aporte del trabajador es 0,5% de las
   utilidades anuales, retenido por el patrono. NO se descuenta del sueldo
   quincenal. El 2% patronal sí se calcula sobre salarios normales pagados.';

-- Aporte patronal INCES: 2% del total de salarios normales pagados
create or replace function rrhh.aporte_inces_patronal(p_total_salarios numeric, p_fecha date)
returns numeric
language sql stable as $$
  select round(p_total_salarios * coalesce(rrhh.param('INCES_PATRONO', p_fecha), 0.02), 4);
$$;

-- ISLR: porcentaje de retención del AR-I declarado por el trabajador
create or replace function rrhh.retencion_islr(
  p_empleado uuid, p_enriquecimiento numeric, p_fecha date)
returns numeric
language plpgsql stable as $$
declare v_pct numeric; v_ut numeric; v_minimo numeric;
begin
  select porcentaje_retencion_islr into v_pct from empleados where id = p_empleado;
  if coalesce(v_pct, 0) = 0 then return 0; end if;

  -- Exención: enriquecimiento anual inferior a 1.000 U.T. no retiene
  v_ut := coalesce(rrhh.param('UNIDAD_TRIBUTARIA', p_fecha), 0);
  v_minimo := coalesce(rrhh.param('ISLR_UT_MINIMO_ANUAL', p_fecha), 1000) * v_ut;
  if p_enriquecimiento * 12 < v_minimo then return 0; end if;

  return round(p_enriquecimiento * v_pct / 100.0, 4);
end;
$$;

-- ---------------------------------------------------------------------
-- PRESTACIONES SOCIALES (art. 142 LOTTT)
-- ---------------------------------------------------------------------
-- Literal a: 15 días por trimestre a partir del 1er trimestre.
-- Literal b: 2 días adicionales por año, acumulativos, desde el 2º año, tope 30.
create or replace function rrhh.dias_adicionales_antiguedad(p_anio_servicio int)
returns int
language sql immutable as $$
  select least(greatest(p_anio_servicio - 1, 0) * 2, 30);
$$;

-- API: calcula y registra la garantía trimestral de un empleado.
create or replace function rrhh.registrar_garantia_trimestral(
  p_empleado uuid, p_anio int, p_trimestre int)
returns uuid
language plpgsql security definer set search_path = public, rrhh as $$
declare
  v_corte date;
  v_sdi numeric;
  v_dias int := 15;
  v_id uuid;
begin
  v_corte := make_date(p_anio, p_trimestre * 3, 1) + interval '1 month' - interval '1 day';
  v_sdi := rrhh.salario_diario_integral(p_empleado, v_corte);

  insert into prestaciones_movimientos
    (empleado_id, fecha, tipo, trimestre, anio, dias, salario_integral_diario, monto)
  values
    (p_empleado, v_corte, 'garantia_trimestral', p_trimestre, p_anio,
     v_dias, v_sdi, round(v_dias * v_sdi, 4))
  returning id into v_id;

  return v_id;
end;
$$;

-- API: liquidación completa. Devuelve jsonb con todos los renglones.
create or replace function rrhh.calcular_liquidacion(
  p_empleado uuid, p_fecha_egreso date, p_motivo tipo_incidencia)
returns jsonb
language plpgsql security definer set search_path = public, rrhh as $$
declare
  e            record;
  v_anios      int;
  v_meses      int;
  v_sdi        numeric;
  v_sdn        numeric;
  v_garantia   numeric;
  v_intereses  numeric;
  v_retro      numeric;
  v_presta     numeric;
  v_vac_pend   numeric := 0;
  v_bono_pend  numeric := 0;
  v_vac_frac   numeric := 0;
  v_bono_frac  numeric := 0;
  v_util_frac  numeric := 0;
  v_art92      numeric := 0;
  v_dias_vac_frac numeric;
  v_meses_ult_anio int;
  v_dias_util  int;
  v_meses_util int;
  v_total      numeric;
begin
  select em.*, e2.dias_utilidades, e2.dias_vacaciones_base, e2.tope_dias_vacaciones,
         e2.dias_bono_vacacional_base, e2.tope_dias_bono_vacacional
    into e
  from empleados em join empresas e2 on e2.id = em.empresa_id
  where em.id = p_empleado;

  if not found then raise exception 'Empleado % no existe', p_empleado; end if;

  v_anios := rrhh.antiguedad_anios(e.fecha_ingreso, p_fecha_egreso);
  v_meses := rrhh.antiguedad_meses(e.fecha_ingreso, p_fecha_egreso);
  v_sdi   := rrhh.salario_diario_integral(p_empleado, p_fecha_egreso);
  v_sdn   := rrhh.salario_diario_normal(p_empleado, p_fecha_egreso);

  -- Garantía acumulada e intereses (literales a y b)
  select coalesce(sum(monto) filter (where tipo in ('garantia_trimestral','dias_adicionales','ajuste')), 0)
       - coalesce(sum(monto) filter (where tipo = 'anticipo'), 0),
         coalesce(sum(monto) filter (where tipo = 'intereses'), 0)
    into v_garantia, v_intereses
  from prestaciones_movimientos where empleado_id = p_empleado;

  -- Literal c: 30 días por año (o fracción > 6 meses) al último salario integral
  v_retro := round(v_sdi * 30 * (v_anios + case when (v_meses - v_anios*12) > 6 then 1 else 0 end), 4);

  -- Literal d: se paga el mayor
  v_presta := greatest(coalesce(v_garantia,0), v_retro);

  -- Vacaciones vencidas no disfrutadas
  select coalesce(sum((dias_vacaciones - dias_disfrutados) * v_sdn), 0),
         coalesce(sum(case when bono_pagado then 0 else dias_bono_vacacional * v_sdn end), 0)
    into v_vac_pend, v_bono_pend
  from vacaciones_periodos
  where empleado_id = p_empleado and dias_disfrutados < dias_vacaciones;

  -- Fracción del año en curso (art. 196: 1/12 por mes completo)
  v_meses_ult_anio := v_meses - (v_anios * 12);
  v_dias_vac_frac := rrhh.dias_vacaciones(v_anios + 1, e.dias_vacaciones_base, e.tope_dias_vacaciones)
                     * v_meses_ult_anio / 12.0;
  v_vac_frac  := round(v_dias_vac_frac * v_sdn, 4);
  v_bono_frac := round(rrhh.dias_bono_vacacional(v_anios + 1, e.dias_bono_vacacional_base,
                        e.tope_dias_bono_vacacional) * v_meses_ult_anio / 12.0 * v_sdn, 4);

  -- Utilidades fraccionadas del ejercicio en curso (art. 131 LOTTT):
  -- se cuentan los meses COMPLETOS laborados dentro del año calendario del
  -- egreso, no los meses transcurridos del año.
  v_dias_util := e.dias_utilidades;
  v_meses_util := extract(month from p_fecha_egreso)::int
                  - case when extract(year from e.fecha_ingreso)::int
                              = extract(year from p_fecha_egreso)::int
                         then extract(month from e.fecha_ingreso)::int - 1
                         else 0 end;
  v_util_frac := round(v_dias_util * greatest(v_meses_util,0) / 12.0 * v_sdn, 4);

  -- Indemnización art. 92 LOTTT: monto igual a las prestaciones sociales
  if p_motivo = 'despido_injustificado' then
    v_art92 := v_presta;
  end if;

  v_total := v_presta + coalesce(v_intereses,0) + v_vac_pend + v_bono_pend
           + v_vac_frac + v_bono_frac + v_util_frac + v_art92;

  return jsonb_build_object(
    'empleado_id', p_empleado,
    'fecha_egreso', p_fecha_egreso,
    'motivo', p_motivo,
    'antiguedad_anios', v_anios,
    'antiguedad_meses', v_meses,
    'salario_diario_normal', v_sdn,
    'salario_diario_integral', v_sdi,
    'prestaciones_garantia', round(coalesce(v_garantia,0),4),
    'prestaciones_retroactivo', v_retro,
    'prestaciones_a_pagar', round(v_presta,4),
    'intereses_prestaciones', round(coalesce(v_intereses,0),4),
    'vacaciones_pendientes', v_vac_pend,
    'bono_vacacional_pendiente', v_bono_pend,
    'vacaciones_fraccionadas', v_vac_frac,
    'bono_vacacional_fraccionado', v_bono_frac,
    'utilidades_fraccionadas', v_util_frac,
    'indemnizacion_art92', v_art92,
    'total_liquidacion', round(v_total,4),
    'total_usd', rrhh.a_dolares(round(v_total,4), p_fecha_egreso),
    'tasa_bcv', rrhh.tasa_bcv(p_fecha_egreso)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- UTILIDADES FRACCIONADAS
-- ---------------------------------------------------------------------
create or replace function rrhh.calcular_utilidades(p_empleado uuid, p_anio int)
returns numeric
language plpgsql stable as $$
declare
  e record; v_meses int; v_dias numeric; v_sdn numeric; v_cierre date;
begin
  v_cierre := make_date(p_anio, 12, 31);
  select em.fecha_ingreso, em.fecha_egreso, e2.dias_utilidades into e
  from empleados em join empresas e2 on e2.id = em.empresa_id where em.id = p_empleado;
  if not found then return 0; end if;

  v_meses := least(12,
    case when extract(year from e.fecha_ingreso)::int = p_anio
         then 12 - extract(month from e.fecha_ingreso)::int + 1
         else 12 end);

  if e.fecha_egreso is not null and extract(year from e.fecha_egreso)::int = p_anio then
    v_meses := least(v_meses, extract(month from e.fecha_egreso)::int);
  end if;

  v_sdn  := rrhh.salario_diario_normal(p_empleado, least(v_cierre, coalesce(e.fecha_egreso, v_cierre)));
  v_dias := e.dias_utilidades * v_meses / 12.0;
  return round(v_dias * v_sdn, 4);
end;
$$;

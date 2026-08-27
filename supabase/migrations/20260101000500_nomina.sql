-- =====================================================================
-- 005 · NÓMINA, RECIBOS, PRESTACIONES Y UTILIDADES
-- =====================================================================

-- ---------------------------------------------------------------------
-- PERIODOS DE NÓMINA
-- ---------------------------------------------------------------------
create table nominas (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references empresas(id) on delete restrict,
  tienda_id         uuid references tiendas(id) on delete restrict,  -- null = consolidada
  tipo              tipo_nomina not null default 'quincenal',
  descripcion       text not null,
  periodo_inicio    date not null,
  periodo_fin       date not null,
  fecha_pago        date not null,
  dias_periodo      smallint not null,
  tasa_bcv          numeric(18,8) not null,      -- congelada al calcular
  estado            estado_nomina not null default 'borrador',

  total_asignaciones numeric(18,4) not null default 0,
  total_deducciones  numeric(18,4) not null default 0,
  total_neto         numeric(18,4) not null default 0,
  total_aportes_patronales numeric(18,4) not null default 0,
  costo_total_empresa numeric(18,4) not null default 0,
  cantidad_empleados smallint not null default 0,

  calculada_en      timestamptz,
  calculada_por     uuid references perfiles(id),
  revisada_por      uuid references perfiles(id),
  aprobada_por      uuid references perfiles(id),
  aprobada_en       timestamptz,
  es_retroactiva    boolean not null default false,
  nomina_origen_id  uuid references nominas(id),  -- para ajustes retroactivos
  observaciones     text,
  creado_en         timestamptz not null default now(),
  constraint chk_periodo check (periodo_fin >= periodo_inicio)
);

create index on nominas (empresa_id, periodo_inicio desc);
create index on nominas (tienda_id, estado);

-- Solo el gerente general aprueba; se refuerza en RLS y en trigger.
comment on column nominas.tasa_bcv is
  'Tasa congelada en el momento del cálculo. Recalcular una nómina aprobada
   exige crear una nómina de ajuste retroactivo, no modificar esta.';

-- ---------------------------------------------------------------------
-- CABECERA POR EMPLEADO
-- ---------------------------------------------------------------------
create table nomina_empleados (
  id                      uuid primary key default gen_random_uuid(),
  nomina_id               uuid not null references nominas(id) on delete cascade,
  empleado_id             uuid not null references empleados(id) on delete restrict,
  tienda_id               uuid not null references tiendas(id) on delete restrict,

  dias_laborados          numeric(6,2) not null default 0,
  dias_ausencia           numeric(6,2) not null default 0,

  salario_base_periodo    numeric(18,4) not null default 0,
  salario_diario_base     numeric(18,4) not null default 0,
  salario_diario_normal   numeric(18,4) not null default 0,
  salario_diario_integral numeric(18,4) not null default 0,
  alicuota_bono_vacacional numeric(18,4) not null default 0,
  alicuota_utilidades      numeric(18,4) not null default 0,

  total_asignaciones      numeric(18,4) not null default 0,
  total_salarial          numeric(18,4) not null default 0,  -- base para SSO/FAOV
  total_no_salarial       numeric(18,4) not null default 0,
  total_deducciones       numeric(18,4) not null default 0,
  total_neto              numeric(18,4) not null default 0,
  total_aportes_patronales numeric(18,4) not null default 0,

  neto_usd                numeric(18,4) not null default 0,
  unique (nomina_id, empleado_id)
);

create index on nomina_empleados (empleado_id);
create index on nomina_empleados (tienda_id);

-- ---------------------------------------------------------------------
-- DETALLE (líneas del recibo)
-- ---------------------------------------------------------------------
create table detalle_nomina (
  id                  uuid primary key default gen_random_uuid(),
  nomina_empleado_id  uuid not null references nomina_empleados(id) on delete cascade,
  concepto_id         uuid not null references conceptos_nomina(id) on delete restrict,
  codigo              text not null,       -- copia histórica
  nombre              text not null,       -- copia histórica
  caracter            caracter_concepto not null,
  cantidad            numeric(14,4) not null default 1,
  base                numeric(18,4) not null default 0,
  factor              numeric(12,6) not null default 1,
  monto               numeric(18,4) not null,
  moneda              moneda not null default 'VES',
  monto_usd           numeric(18,4),
  orden               smallint not null default 100,
  detalle_calculo     jsonb        -- trazabilidad: qué parámetros se usaron
);

create index on detalle_nomina (nomina_empleado_id, orden);
create index on detalle_nomina (concepto_id);

comment on column detalle_nomina.detalle_calculo is
  'Auditoría del cálculo: {"parametro":"IVSS_TRAB","valor":0.04,"gaceta":"...",
   "salario_base":123.45}. Permite explicar cualquier recibo años después.';

-- ---------------------------------------------------------------------
-- RECIBOS DE PAGO GENERADOS
-- ---------------------------------------------------------------------
create table recibos_pago (
  id                  uuid primary key default gen_random_uuid(),
  nomina_empleado_id  uuid not null unique references nomina_empleados(id) on delete cascade,
  numero              text not null unique,     -- 0001-2026-000123
  storage_path        text,                     -- bucket 'recibos'
  hash_documento      text,                     -- SHA-256 del PDF
  generado_en         timestamptz not null default now(),
  enviado_email       boolean not null default false,
  enviado_en          timestamptz,
  visto_por_empleado  boolean not null default false,
  visto_en            timestamptz,
  firmado             boolean not null default false,
  firma_storage_path  text
);

-- Secuencia de correlativo por empresa y año
create table recibos_correlativo (
  empresa_id  uuid not null references empresas(id) on delete cascade,
  anio        smallint not null,
  prefijo     text not null default '0001',
  ultimo      integer not null default 0,
  primary key (empresa_id, anio)
);

-- ---------------------------------------------------------------------
-- PRESTACIONES SOCIALES (art. 142 LOTTT)
-- ---------------------------------------------------------------------
create table prestaciones_movimientos (
  id                  uuid primary key default gen_random_uuid(),
  empleado_id         uuid not null references empleados(id) on delete cascade,
  fecha               date not null,
  tipo                text not null check (tipo in (
                        'garantia_trimestral',   -- 15 días por trimestre (lit. a)
                        'dias_adicionales',      -- 2 días por año a partir del 2º (lit. b)
                        'intereses',             -- art. 143
                        'anticipo',              -- hasta 75% (art. 144)
                        'ajuste',
                        'pago_liquidacion')),
  trimestre           smallint check (trimestre between 1 and 4),
  anio                smallint,
  dias                numeric(8,2) not null default 0,
  salario_integral_diario numeric(18,4) not null default 0,
  monto               numeric(18,4) not null,
  tasa_interes        numeric(8,4),        -- tasa activa BCV del periodo
  nomina_id           uuid references nominas(id) on delete set null,
  observacion         text,
  creado_en           timestamptz not null default now()
);

create index on prestaciones_movimientos (empleado_id, fecha);

-- Saldo materializado por empleado (mantenido por trigger)
create table prestaciones_saldo (
  empleado_id             uuid primary key references empleados(id) on delete cascade,
  dias_acumulados         numeric(10,2) not null default 0,
  capital_acumulado       numeric(18,4) not null default 0,
  intereses_acumulados    numeric(18,4) not null default 0,
  anticipos_otorgados     numeric(18,4) not null default 0,
  saldo_disponible        numeric(18,4) not null default 0,
  actualizado_en          timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- UTILIDADES (art. 131 LOTTT)
-- ---------------------------------------------------------------------
create table utilidades (
  id                  uuid primary key default gen_random_uuid(),
  empleado_id         uuid not null references empleados(id) on delete cascade,
  anio                smallint not null,
  meses_completos     smallint not null check (meses_completos between 0 and 12),
  dias_asignados      numeric(8,2) not null,
  salario_promedio_diario numeric(18,4) not null,
  monto               numeric(18,4) not null,
  anticipo_pagado     numeric(18,4) not null default 0,
  nomina_id           uuid references nominas(id) on delete set null,
  pagado              boolean not null default false,
  creado_en           timestamptz not null default now(),
  unique (empleado_id, anio)
);

-- ---------------------------------------------------------------------
-- LIQUIDACIONES
-- ---------------------------------------------------------------------
create table liquidaciones (
  id                      uuid primary key default gen_random_uuid(),
  empleado_id             uuid not null references empleados(id) on delete restrict,
  fecha_egreso            date not null,
  motivo                  tipo_incidencia not null,
  antiguedad_anios        numeric(6,2) not null,
  antiguedad_meses        numeric(6,2) not null,
  salario_integral_diario numeric(18,4) not null,
  salario_normal_diario   numeric(18,4) not null,

  -- Art. 142 lit. c: retroactivo 30 días por año sobre último salario integral
  prestaciones_garantia   numeric(18,4) not null default 0,
  prestaciones_retroactivo numeric(18,4) not null default 0,
  prestaciones_a_pagar    numeric(18,4) not null default 0,  -- el mayor de los dos
  intereses_prestaciones  numeric(18,4) not null default 0,
  vacaciones_pendientes   numeric(18,4) not null default 0,
  vacaciones_fraccionadas numeric(18,4) not null default 0,
  bono_vacacional_pendiente numeric(18,4) not null default 0,
  utilidades_fraccionadas numeric(18,4) not null default 0,
  indemnizacion_art92     numeric(18,4) not null default 0,  -- despido injustificado
  otros_conceptos         numeric(18,4) not null default 0,
  deducciones             numeric(18,4) not null default 0,
  total_liquidacion       numeric(18,4) not null default 0,

  tasa_bcv                numeric(18,8) not null,
  estado                  estado_nomina not null default 'borrador',
  calculado_por           uuid references perfiles(id),
  aprobado_por            uuid references perfiles(id),
  storage_path            text,
  creado_en               timestamptz not null default now()
);

create index on liquidaciones (empleado_id);

comment on column liquidaciones.prestaciones_a_pagar is
  'Art. 142 lit. d LOTTT: el trabajador recibe el MAYOR entre la garantía
   acumulada (lit. a+b) y el retroactivo de 30 días por año de servicio
   calculado al último salario integral (lit. c).';

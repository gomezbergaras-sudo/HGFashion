-- =====================================================================
-- 003 · PARÁMETROS LEGALES VERSIONADOS
-- Regla de oro: los parámetros NUNCA se actualizan en sitio.
-- Se cierra la vigencia anterior y se inserta una fila nueva, para que
-- una nómina recalculada en 2029 reproduzca exactamente el valor de 2026.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PARÁMETROS LEGALES (salario mínimo, cestaticket, UT, alícuotas)
-- ---------------------------------------------------------------------
create table parametros_legales (
  id              uuid primary key default gen_random_uuid(),
  clave           text not null,
  descripcion     text not null,
  valor           numeric(18,6) not null,
  moneda          moneda,                     -- null si es un porcentaje o factor
  unidad          text not null default 'monto', -- monto | porcentaje | dias | factor
  vigente_desde   date not null,
  vigente_hasta   date,
  gaceta_oficial  text,
  fundamento      text,
  creado_en       timestamptz not null default now(),
  constraint chk_vig_param check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  exclude using gist (
    clave with =,
    daterange(vigente_desde, coalesce(vigente_hasta, 'infinity'::date), '[]') with &&
  )
);

create index on parametros_legales (clave, vigente_desde desc);

comment on table parametros_legales is
  'Fuente única de verdad de todo valor legal. Ningún cálculo debe llevar
   números en duro: siempre rrhh.param(clave, fecha).';

-- ---------------------------------------------------------------------
-- TASAS DE CAMBIO BCV
-- ---------------------------------------------------------------------
create table tasas_cambio (
  fecha        date primary key,
  tasa_usd     numeric(18,8) not null check (tasa_usd > 0),
  tasa_eur     numeric(18,8),
  origen       origen_tasa not null default 'bcv_oficial',
  registrado_en timestamptz not null default now()
);

comment on table tasas_cambio is
  'Una fila por día. La Edge Function sync-bcv la puebla cada día hábil.
   Toda conversión histórica usa la tasa de la fecha del hecho, no la de hoy.';

-- ---------------------------------------------------------------------
-- DÍAS FERIADOS
-- ---------------------------------------------------------------------
create table feriados (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid references empresas(id) on delete cascade, -- null = nacional
  tienda_id   uuid references tiendas(id) on delete cascade,  -- null = todas
  fecha       date not null,
  nombre      text not null,
  tipo        text not null default 'nacional'
              check (tipo in ('nacional','regional','bancario','convencional')),
  unique nulls not distinct (empresa_id, tienda_id, fecha)
);

create index on feriados (fecha);

-- ---------------------------------------------------------------------
-- TABLA DE RETENCIÓN ISLR (tarifa Nº 1 personas naturales, en U.T.)
-- ---------------------------------------------------------------------
create table islr_tramos (
  id              uuid primary key default gen_random_uuid(),
  desde_ut        numeric(14,2) not null,
  hasta_ut        numeric(14,2),
  porcentaje      numeric(6,3) not null,
  sustraendo_ut   numeric(14,2) not null default 0,
  vigente_desde   date not null,
  vigente_hasta   date
);

create index on islr_tramos (vigente_desde desc, desde_ut);

-- ---------------------------------------------------------------------
-- CATÁLOGO DE CONCEPTOS DE NÓMINA
-- Estructura abierta: agregar un bono nuevo es un INSERT, no un deploy.
-- ---------------------------------------------------------------------
create table conceptos_nomina (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references empresas(id) on delete cascade,
  codigo          text not null,
  nombre          text not null,
  caracter        caracter_concepto not null,
  base            base_calculo not null default 'monto_fijo',
  factor          numeric(12,6) not null default 1,   -- multiplicador sobre la base
  moneda          moneda not null default 'VES',
  -- Incidencias
  incide_prestaciones boolean not null default false,
  incide_vacaciones   boolean not null default false,
  incide_utilidades   boolean not null default false,
  incide_islr         boolean not null default false,
  imprime_en_recibo   boolean not null default true,
  orden               smallint not null default 100,
  formula_sql         text,      -- solo para base='formula' (evaluada en Edge Function)
  fundamento_legal    text,
  activo              boolean not null default true,
  unique (empresa_id, codigo)
);

comment on column conceptos_nomina.caracter is
  'salarial → incide en salario normal/integral. no_salarial → bonificación
   sin incidencia (típico "bono de guerra"/bono de productividad). El sistema
   fuerza la coherencia: no_salarial no puede incidir en prestaciones.';

alter table conceptos_nomina add constraint chk_coherencia_caracter check (
  caracter <> 'no_salarial'
  or (incide_prestaciones = false and incide_vacaciones = false and incide_utilidades = false)
);

-- ---------------------------------------------------------------------
-- CONCEPTOS FIJOS ASIGNADOS A UN EMPLEADO (recurrentes)
-- ---------------------------------------------------------------------
create table empleado_conceptos (
  id            uuid primary key default gen_random_uuid(),
  empleado_id   uuid not null references empleados(id) on delete cascade,
  concepto_id   uuid not null references conceptos_nomina(id) on delete restrict,
  monto         numeric(18,4),
  cantidad      numeric(12,4),
  vigente_desde date not null,
  vigente_hasta date,
  observacion   text,
  creado_en     timestamptz not null default now()
);

create index on empleado_conceptos (empleado_id, vigente_desde desc);

-- ---------------------------------------------------------------------
-- PRÉSTAMOS Y ANTICIPOS
-- ---------------------------------------------------------------------
create table prestamos (
  id                uuid primary key default gen_random_uuid(),
  empleado_id       uuid not null references empleados(id) on delete cascade,
  monto_total       numeric(18,4) not null check (monto_total > 0),
  moneda            moneda not null default 'VES',
  cuotas_totales    smallint not null check (cuotas_totales > 0),
  monto_cuota       numeric(18,4) not null,
  saldo_pendiente   numeric(18,4) not null,
  fecha_otorgamiento date not null,
  tipo              text not null default 'prestamo'
                    check (tipo in ('prestamo','anticipo_prestaciones','anticipo_sueldo','caja_ahorro')),
  estado            text not null default 'activo'
                    check (estado in ('activo','pagado','suspendido','condonado')),
  autorizado_por    uuid references perfiles(id),
  creado_en         timestamptz not null default now()
);

create index on prestamos (empleado_id) where estado = 'activo';

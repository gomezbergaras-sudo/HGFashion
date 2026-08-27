-- =====================================================================
-- 002 · NÚCLEO ORGANIZACIONAL
-- empresas · tiendas · perfiles de usuario · empleados
-- =====================================================================

-- ---------------------------------------------------------------------
-- EMPRESAS (configuración del recibo y datos fiscales)
-- ---------------------------------------------------------------------
create table empresas (
  id                uuid primary key default gen_random_uuid(),
  nombre            text not null,
  razon_social      text not null,
  rif               text not null unique,
  logo_path         text,                       -- ruta en Storage: bucket 'logos'
  direccion_fiscal  text not null,
  telefono          text,
  email             text,
  -- Políticas internas configurables
  dias_utilidades           smallint not null default 30
                            check (dias_utilidades between 30 and 120),
  dias_vacaciones_base      smallint not null default 15,
  dias_bono_vacacional_base smallint not null default 15,
  tope_dias_vacaciones      smallint not null default 30,
  tope_dias_bono_vacacional smallint not null default 30,
  tolerancia_retardo_min    smallint not null default 10,
  moneda_referencia         moneda   not null default 'USD',
  creado_en         timestamptz not null default now(),
  actualizado_en    timestamptz not null default now()
);

comment on column empresas.dias_utilidades is
  'Art. 131 LOTTT: mínimo 30 días, máximo 120 días de salario.';
comment on column empresas.tope_dias_vacaciones is
  'Art. 190 LOTTT: 15 días + 1 por año hasta un máximo de 30 días hábiles.';

-- ---------------------------------------------------------------------
-- TIENDAS
-- ---------------------------------------------------------------------
create table tiendas (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references empresas(id) on delete restrict,
  codigo        text not null,
  nombre        text not null,
  estado_pais   text not null,               -- Estado (Zulia, Miranda, ...)
  ciudad        text not null,
  direccion     text,
  telefono      text,
  centro_costo  text,
  activa        boolean not null default true,
  creado_en     timestamptz not null default now(),
  unique (empresa_id, codigo)
);

create index on tiendas (empresa_id) where activa;

-- ---------------------------------------------------------------------
-- PERFILES DE USUARIO  (puente con auth.users de Supabase)
-- ---------------------------------------------------------------------
create table perfiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  empresa_id   uuid not null references empresas(id) on delete restrict,
  rol          rol_sistema not null default 'empleado',
  tienda_id    uuid references tiendas(id) on delete set null,
  nombre       text not null,
  email        text not null,
  activo       boolean not null default true,
  creado_en    timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  -- Un gerente general no está atado a una tienda; los demás sí.
  constraint chk_tienda_por_rol check (
    (rol = 'gerente_general' and tienda_id is null)
    or (rol <> 'gerente_general')
  )
);

create index on perfiles (empresa_id, rol);
create index on perfiles (tienda_id);

-- ---------------------------------------------------------------------
-- EMPLEADOS
-- ---------------------------------------------------------------------
create table cargos (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references empresas(id) on delete cascade,
  nombre      text not null,
  departamento text not null,
  es_de_direccion boolean not null default false,   -- art. 37 LOTTT (trabajador de dirección)
  unique (empresa_id, nombre)
);

create table empleados (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references empresas(id) on delete restrict,
  tienda_id         uuid not null references tiendas(id) on delete restrict,
  usuario_id        uuid unique references perfiles(id) on delete set null,
  cargo_id          uuid references cargos(id) on delete set null,

  -- Identificación
  nacionalidad_ci   char(1) not null default 'V' check (nacionalidad_ci in ('V','E')),
  cedula            text not null,
  rif               text,
  primer_nombre     text not null,
  segundo_nombre    text,
  primer_apellido   text not null,
  segundo_apellido  text,
  fecha_nacimiento  date,
  sexo              char(1) check (sexo in ('M','F')),
  estado_civil      text,

  -- Contacto
  telefono_movil    text,
  telefono_local    text,
  email_personal    text,
  direccion         text,
  contacto_emergencia_nombre   text,
  contacto_emergencia_telefono text,

  -- Datos laborales
  fecha_ingreso     date not null,
  fecha_egreso      date,
  motivo_egreso     tipo_incidencia,
  tipo_contrato     tipo_contrato not null default 'tiempo_indeterminado',
  fecha_fin_contrato date,
  tipo_jornada      tipo_jornada not null default 'diurna',
  tipo_nomina       tipo_nomina not null default 'quincenal',
  estado            estado_laboral not null default 'activo',

  -- Seguridad social
  numero_ivss       text,
  inscrito_ivss     boolean not null default true,
  aplica_faov       boolean not null default true,
  aplica_inces      boolean not null default true,
  aplica_rpe        boolean not null default true,

  -- Banco
  banco             text,
  tipo_cuenta       text check (tipo_cuenta in ('corriente','ahorro')),
  numero_cuenta     text,

  -- ISLR
  porcentaje_retencion_islr numeric(5,2) not null default 0
                            check (porcentaje_retencion_islr between 0 and 100),
  cargas_familiares smallint not null default 0,

  creado_en         timestamptz not null default now(),
  actualizado_en    timestamptz not null default now(),

  unique (empresa_id, nacionalidad_ci, cedula),
  constraint chk_egreso check (fecha_egreso is null or fecha_egreso >= fecha_ingreso)
);

create index on empleados (tienda_id) where estado <> 'egresado';
create index on empleados (empresa_id, estado);
create index on empleados (cedula);

-- Nombre completo generado para búsquedas
alter table empleados add column nombre_completo text
  generated always as (
    primer_nombre || ' ' || coalesce(segundo_nombre || ' ', '')
    || primer_apellido || coalesce(' ' || segundo_apellido, '')
  ) stored;

create index on empleados using gin (to_tsvector('spanish', nombre_completo));

-- ---------------------------------------------------------------------
-- HISTORIAL SALARIAL  (nunca se sobrescribe: se inserta una fila nueva)
-- ---------------------------------------------------------------------
create table historial_salarios (
  id              uuid primary key default gen_random_uuid(),
  empleado_id     uuid not null references empleados(id) on delete cascade,
  vigente_desde   date not null,
  vigente_hasta   date,
  salario_base    numeric(18,4) not null check (salario_base >= 0),
  moneda_salario  moneda not null default 'VES',
  -- Si el salario se pacta en USD se paga en Bs a la tasa del día de pago
  motivo          text,
  registrado_por  uuid references perfiles(id),
  creado_en       timestamptz not null default now(),
  constraint chk_vigencia_salario check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  exclude using gist (
    empleado_id with =,
    daterange(vigente_desde, coalesce(vigente_hasta, 'infinity'::date), '[]') with &&
  )
);

create index on historial_salarios (empleado_id, vigente_desde desc);

-- ---------------------------------------------------------------------
-- DOCUMENTOS DIGITALIZADOS (metadatos; el binario vive en Storage)
-- ---------------------------------------------------------------------
create table documentos (
  id            uuid primary key default gen_random_uuid(),
  empleado_id   uuid not null references empleados(id) on delete cascade,
  tipo          text not null,           -- contrato, cedula, rif, titulo, constancia...
  nombre        text not null,
  storage_path  text not null unique,    -- bucket 'documentos-empleados'
  mime_type     text,
  tamano_bytes  bigint,
  fecha_vencimiento date,
  subido_por    uuid references perfiles(id),
  creado_en     timestamptz not null default now()
);

create index on documentos (empleado_id, tipo);
create index on documentos (fecha_vencimiento) where fecha_vencimiento is not null;

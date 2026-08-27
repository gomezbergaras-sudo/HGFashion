-- =====================================================================
-- 004 · ASISTENCIA, HORAS EXTRA E INCIDENCIAS
-- =====================================================================

-- ---------------------------------------------------------------------
-- HORARIOS / TURNOS
-- ---------------------------------------------------------------------
create table horarios (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references empresas(id) on delete cascade,
  nombre          text not null,
  tipo_jornada    tipo_jornada not null default 'diurna',
  horas_diarias   numeric(4,2) not null default 8,
  horas_semanales numeric(5,2) not null default 40,
  unique (empresa_id, nombre)
);

create table horario_dias (
  id            uuid primary key default gen_random_uuid(),
  horario_id    uuid not null references horarios(id) on delete cascade,
  dia_semana    smallint not null check (dia_semana between 0 and 6), -- 0=domingo
  hora_entrada  time,
  hora_salida   time,
  inicio_almuerzo time,
  fin_almuerzo  time,
  es_descanso   boolean not null default false,
  unique (horario_id, dia_semana)
);

create table empleado_horarios (
  id            uuid primary key default gen_random_uuid(),
  empleado_id   uuid not null references empleados(id) on delete cascade,
  horario_id    uuid not null references horarios(id) on delete restrict,
  vigente_desde date not null,
  vigente_hasta date,
  exclude using gist (
    empleado_id with =,
    daterange(vigente_desde, coalesce(vigente_hasta, 'infinity'::date), '[]') with &&
  )
);

-- ---------------------------------------------------------------------
-- MARCAJES (registro crudo, inmutable)
-- ---------------------------------------------------------------------
create table marcajes (
  id            uuid primary key default gen_random_uuid(),
  empleado_id   uuid not null references empleados(id) on delete cascade,
  tienda_id     uuid not null references tiendas(id) on delete restrict,
  tipo          tipo_marcaje not null,
  momento       timestamptz not null default now(),
  fecha_laboral date not null,     -- día de la jornada (turno nocturno cruza medianoche)
  origen        text not null default 'app'
                check (origen in ('app','web','biometrico','manual','importacion')),
  latitud       numeric(10,7),
  longitud      numeric(10,7),
  registrado_por uuid references perfiles(id),
  observacion   text,
  creado_en     timestamptz not null default now()
);

create index on marcajes (empleado_id, fecha_laboral);
create index on marcajes (tienda_id, fecha_laboral);

-- ---------------------------------------------------------------------
-- ASISTENCIA CONSOLIDADA POR DÍA (derivada de marcajes, es la que se paga)
-- ---------------------------------------------------------------------
create table asistencias (
  id                  uuid primary key default gen_random_uuid(),
  empleado_id         uuid not null references empleados(id) on delete cascade,
  tienda_id           uuid not null references tiendas(id) on delete restrict,
  fecha               date not null,
  hora_entrada        timestamptz,
  hora_salida         timestamptz,
  minutos_almuerzo    smallint not null default 0,
  horas_trabajadas    numeric(6,2) not null default 0,
  minutos_retardo     smallint not null default 0,
  es_feriado          boolean not null default false,
  es_descanso         boolean not null default false,
  estatus             text not null default 'presente'
                      check (estatus in ('presente','ausente','permiso','reposo',
                                         'vacaciones','feriado','descanso','suspension')),
  incidencia_id       uuid,   -- FK poblada más abajo
  observacion         text,
  calculado_en        timestamptz not null default now(),
  unique (empleado_id, fecha)
);

create index on asistencias (tienda_id, fecha);
create index on asistencias (fecha) where estatus = 'ausente';

-- ---------------------------------------------------------------------
-- HORAS EXTRA (requieren aprobación explícita)
-- ---------------------------------------------------------------------
create table horas_extra (
  id              uuid primary key default gen_random_uuid(),
  empleado_id     uuid not null references empleados(id) on delete cascade,
  tienda_id       uuid not null references tiendas(id) on delete restrict,
  fecha           date not null,
  tipo            tipo_hora_extra not null,
  horas           numeric(5,2) not null check (horas > 0),
  motivo          text,
  estado          estado_solicitud not null default 'pendiente',
  solicitado_por  uuid references perfiles(id),
  aprobado_por    uuid references perfiles(id),
  aprobado_en     timestamptz,
  nomina_id       uuid,   -- se marca cuando ya fue pagada
  creado_en       timestamptz not null default now()
);

create index on horas_extra (empleado_id, fecha);
create index on horas_extra (tienda_id, estado);

comment on table horas_extra is
  'Art. 178 LOTTT: máximo 10 h extra semanales, 100 h al año y 2 h diarias.
   El trigger trg_valida_topes_horas_extra bloquea el exceso.';

-- ---------------------------------------------------------------------
-- INCIDENCIAS (permisos, reposos, amonestaciones, egresos)
-- ---------------------------------------------------------------------
create table incidencias (
  id                uuid primary key default gen_random_uuid(),
  empleado_id       uuid not null references empleados(id) on delete cascade,
  tienda_id         uuid not null references tiendas(id) on delete restrict,
  tipo              tipo_incidencia not null,
  fecha_inicio      date not null,
  fecha_fin         date not null,
  dias_habiles      smallint,
  descripcion       text not null,
  afecta_pago       boolean not null default false,
  estado            estado_solicitud not null default 'pendiente',
  solicitado_por    uuid references perfiles(id),
  aprobado_por      uuid references perfiles(id),
  aprobado_en       timestamptz,
  documento_id      uuid references documentos(id) on delete set null,
  -- Datos específicos de reposo médico
  certificado_ivss  text,
  creado_en         timestamptz not null default now(),
  constraint chk_rango_incidencia check (fecha_fin >= fecha_inicio)
);

create index on incidencias (empleado_id, fecha_inicio desc);
create index on incidencias (tienda_id, estado);
create index on incidencias (tipo, fecha_inicio);

alter table asistencias
  add constraint fk_asistencia_incidencia
  foreign key (incidencia_id) references incidencias(id) on delete set null;

-- ---------------------------------------------------------------------
-- VACACIONES (control de días causados, disfrutados y pendientes)
-- ---------------------------------------------------------------------
create table vacaciones_periodos (
  id                    uuid primary key default gen_random_uuid(),
  empleado_id           uuid not null references empleados(id) on delete cascade,
  anio_servicio         smallint not null,        -- 1, 2, 3...
  fecha_inicio_periodo  date not null,
  fecha_fin_periodo     date not null,
  dias_vacaciones       smallint not null,        -- 15 + 1 por año, tope 30
  dias_bono_vacacional  smallint not null,        -- 15 + 1 por año, tope 30
  dias_disfrutados      smallint not null default 0,
  dias_pagados          smallint not null default 0,
  bono_pagado           boolean not null default false,
  fecha_disfrute_inicio date,
  fecha_disfrute_fin    date,
  vencido               boolean not null default false,
  unique (empleado_id, anio_servicio)
);

create index on vacaciones_periodos (empleado_id)
  where dias_disfrutados < dias_vacaciones;

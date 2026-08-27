-- =====================================================================
-- 001 · EXTENSIONES, ESQUEMAS Y TIPOS
-- Plataforma RRHH Retail Venezuela
-- =====================================================================

create extension if not exists "pgcrypto";
create extension if not exists "uuid-ossp";
create extension if not exists "btree_gist";

-- Esquema para funciones internas que NO deben exponerse por PostgREST
create schema if not exists rrhh;
revoke all on schema rrhh from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- TIPOS ENUMERADOS
-- ---------------------------------------------------------------------

create type rol_sistema as enum (
  'gerente_general',
  'supervisor_tienda',
  'supervisor_auxiliar',
  'empleado'
);

create type estado_laboral as enum (
  'activo', 'suspendido', 'reposo', 'vacaciones', 'egresado'
);

create type tipo_contrato as enum (
  'tiempo_indeterminado', 'tiempo_determinado', 'obra_determinada', 'pasantia'
);

create type tipo_jornada as enum (
  'diurna', 'nocturna', 'mixta', 'especial_comercio'
);

create type moneda as enum ('VES', 'USD');

-- Carácter del concepto: define si incide o no en prestaciones sociales.
-- Crítico en Venezuela: los bonos "no salariales" no forman parte del
-- salario normal (art. 104 LOTTT) y por tanto no generan antigüedad.
create type caracter_concepto as enum (
  'salarial',          -- entra en salario normal e integral
  'no_salarial',       -- bonificaciones sin incidencia (art. 105 LOTTT)
  'deduccion',
  'aporte_patronal'    -- costo empresa, no afecta al recibo del trabajador
);

create type base_calculo as enum (
  'monto_fijo',
  'salario_base',
  'salario_normal',
  'salario_integral',
  'salario_diario_normal',
  'salario_diario_integral',
  'total_asignaciones_salariales',
  'formula'
);

create type tipo_nomina as enum ('semanal', 'quincenal', 'mensual', 'especial', 'utilidades', 'liquidacion');

create type estado_nomina as enum (
  'borrador', 'calculada', 'revision_supervisor', 'aprobada', 'pagada', 'anulada'
);

create type tipo_marcaje as enum (
  'entrada', 'salida', 'salida_almuerzo', 'regreso_almuerzo'
);

create type tipo_incidencia as enum (
  'permiso_con_goce', 'permiso_sin_goce', 'reposo_medico', 'vacaciones',
  'inasistencia_justificada', 'inasistencia_injustificada', 'retardo',
  'amonestacion_verbal', 'amonestacion_escrita', 'suspension',
  'accidente_laboral', 'despido_justificado', 'despido_injustificado',
  'renuncia', 'feriado_trabajado', 'permiso_especial'
);

create type estado_solicitud as enum ('pendiente', 'aprobada', 'rechazada', 'anulada');

create type tipo_hora_extra as enum ('diurna', 'nocturna', 'feriado', 'descanso');

create type origen_tasa as enum ('bcv_oficial', 'manual', 'promedio_bcv');

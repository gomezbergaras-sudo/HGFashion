# Plataforma de RRHH y Nómina — Retail Venezuela

Sistema integral de recursos humanos para cadena de 20 tiendas, construido sobre
Supabase (PostgreSQL + Auth + Storage + Realtime + Edge Functions) y React + TypeScript.

## Estado

El esquema de base de datos está completo y **verificado contra PostgreSQL 16**:
31 tablas, 24 funciones de cálculo, 14 triggers, 47 políticas RLS, 3 vistas
materializadas y seed con las 20 tiendas y los parámetros legales.

## Instalación

```bash
npm install -g supabase
supabase init
supabase start                 # entorno local
supabase db reset              # aplica migrations/ + seed.sql
```

Para un proyecto en la nube:

```bash
supabase link --project-ref <PROJECT_ID>
supabase db push
supabase functions deploy calcular-nomina
```

## Orden de las migraciones

| Archivo | Contenido |
|---|---|
| `..._100_extensiones_y_tipos.sql` | Extensiones, esquema `rrhh`, tipos enumerados |
| `..._200_core_organizacion.sql` | Empresas, tiendas, perfiles, empleados, historial salarial |
| `..._300_parametros_legales.sql` | Parámetros con vigencia, tasas BCV, ISLR, conceptos de nómina |
| `..._400_asistencia_incidencias.sql` | Horarios, marcajes, asistencia, horas extra, incidencias, vacaciones |
| `..._500_nomina.sql` | Nóminas, detalle, recibos, prestaciones, utilidades, liquidaciones |
| `..._600_funciones_calculo.sql` | 24 funciones de cálculo legal |
| `..._700_triggers.sql` | Topes legales, saldos, inmutabilidad, correlativos |
| `..._800_rls.sql` | 47 políticas de acceso por rol y por tienda |
| `..._900_vistas_auditoria.sql` | Auditoría y vistas de reporte |

## Reglas de diseño que no se deben romper

1. **Ningún valor legal en el código.** Todo va en `parametros_legales` con vigencia.
   Un decreto nuevo es un `INSERT`, nunca un `UPDATE` ni un despliegue.
2. **Los conceptos de nómina son datos.** Un bono nuevo es una fila en
   `conceptos_nomina`, no una columna ni una migración.
3. **Un concepto no salarial no puede incidir en prestaciones.** Está garantizado
   por `CHECK` a nivel de base de datos.
4. **La nómina aprobada es inmutable.** Las correcciones se hacen con una nómina de
   ajuste retroactivo enlazada a la original.
5. **Sin tasa BCV no hay cálculo.** `rrhh.tasa_bcv()` lanza excepción antes que
   devolver cero.

## Antes de producción

Verifique **cada** valor del seed contra Gaceta Oficial y con su abogado laboral.
Los montos cargados son de referencia, en particular el cestaticket y el bono de
guerra económica.

## Licencia

Propietario.

## Primer push al repositorio

```bash
git init
git add .
git commit -m "Esquema completo de base de datos y configuración del proyecto"
git branch -M main
git remote add origin https://github.com/gomezbergaras-sudo/HGFashion.git
git push -u origin main

# Rama de integración
git checkout -b develop
git push -u origin develop
```

## Secretos a configurar en GitHub

`Settings → Secrets and variables → Actions`

| Secreto | Dónde se obtiene |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | supabase.com/dashboard/account/tokens |
| `SUPABASE_PROJECT_ID` | URL del proyecto (`aiwbjnoafonhjesjllib`) |
| `SUPABASE_DB_PASSWORD` | Settings → Database del proyecto |
| `VITE_SUPABASE_URL` | Settings → API |
| `VITE_SUPABASE_ANON_KEY` | Settings → API |

La `service_role key` **no** va en GitHub Secrets: se configura como variable de
entorno del proyecto en Supabase, donde solo la leen las Edge Functions.

## Protección de ramas recomendada

`Settings → Branches → Add rule` sobre `main`:

- Require a pull request before merging
- Require status checks to pass (`base-de-datos`, `frontend`)
- Do not allow bypassing the above settings

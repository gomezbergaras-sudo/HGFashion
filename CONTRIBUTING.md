# Guía de contribución

## Ramas

| Rama | Uso |
|---|---|
| `main` | Producción. Solo recibe merges desde `develop` vía PR aprobado. |
| `develop` | Tronco de integración. |
| `feature/*` | Funcionalidad nueva. |
| `fix/*` | Corrección de errores. |
| `legal/*` | Cambios de parámetros legales. Se revisan con criterio distinto al del código. |

## Reglas que no se negocian

1. **Ningún valor legal en el código.** Si un cálculo necesita un número
   (una alícuota, un tope, un recargo), va en `parametros_legales`.
2. **Los parámetros legales no se actualizan, se versionan.** Nunca un `UPDATE`
   sobre una vigencia pasada: se inserta la nueva y el trigger cierra la anterior.
3. **Toda migración es aditiva.** No se edita una migración ya aplicada en
   producción; se crea una nueva.
4. **Cambio en un cálculo = prueba en `supabase/tests/`.** Sin excepción.
5. **Nada de `service_role` en el frontend.** Si una operación necesita saltarse
   la RLS, va en una Edge Function.

## Ramas `legal/*`

Un PR que toque `parametros_legales` debe incluir en la descripción:

- Número de Gaceta Oficial o providencia
- Fecha de entrada en vigencia
- Si aplica al sector privado (muchos anuncios no lo aclaran)
- Confirmación de que se revisó con el asesor laboral

## Antes de abrir un PR

```bash
npm run lint
npm run typecheck
npm run test
supabase db reset      # verifica que migraciones + seed corren de cero
```

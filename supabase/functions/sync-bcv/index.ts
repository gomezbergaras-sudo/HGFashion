// Edge Function: sync-bcv
// Registra la tasa oficial del BCV del día en tasas_cambio.
// Programar con pg_cron / Supabase Scheduler cada día hábil a las 9:00 (America/Caracas).
//
// Si la fuente no responde, NO inventa un valor: registra el fallo y devuelve error.
// Cualquier cálculo de nómina que necesite esa tasa fallará con un mensaje claro
// en lugar de producir recibos en cero.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const FUENTE = 'https://ve.dolarapi.com/v1/dolares/oficial'

Deno.serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  try {
    const res = await fetch(FUENTE)
    if (!res.ok) throw new Error(`La fuente respondió ${res.status}`)

    const data = await res.json()
    const tasa = Number(data.promedio ?? data.compra)
    if (!Number.isFinite(tasa) || tasa <= 0) {
      throw new Error(`Tasa inválida recibida: ${JSON.stringify(data)}`)
    }

    // Fecha en horario de Venezuela, no UTC
    const hoy = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Caracas' })

    const { error } = await supabase
      .from('tasas_cambio')
      .upsert({ fecha: hoy, tasa_usd: tasa, origen: 'bcv_oficial' }, { onConflict: 'fecha' })

    if (error) throw error

    return Response.json({ ok: true, fecha: hoy, tasa_usd: tasa })
  } catch (e) {
    const mensaje = e instanceof Error ? e.message : String(e)
    console.error('sync-bcv falló:', mensaje)
    // 502: el problema está en la fuente externa, no en esta función.
    return Response.json({ ok: false, error: mensaje }, { status: 502 })
  }
})

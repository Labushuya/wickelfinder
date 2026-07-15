// Wickelfinder — Edge Function "delete-account"
// ============================================================================
// Vollstaendige Konto-Loeschung (DSGVO Art. 17). Ablauf:
//   1. JWT des Aufrufers verifizieren -> user.id.
//   2. delete_my_data() ALS DIESER NUTZER aufrufen (loescht alle App-Daten,
//      FK-sicher) -> danach zeigt keine Foreign Key mehr auf den Nutzer.
//   3. auth.admin.deleteUser(user.id) mit SERVICE-ROLE -> Auth-Konto weg.
//
// Der service_role-Key lebt NUR hier als Function-Secret (SUPABASE_SERVICE_
// ROLE_KEY), niemals im Flutter-Client. Der Client ruft die Function mit
// seinem normalen JWT via functions.invoke('delete-account').
//
// Deploy (Kunde):
//   supabase functions deploy delete-account --project-ref wnehmpzkpmnespgptrur
//   (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY sind als Function-Secrets
//    standardmaessig verfuegbar; sonst via `supabase secrets set`.)
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), {
      status: 405, headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }

  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!jwt) {
    return new Response(JSON.stringify({ error: 'auth_required' }), {
      status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }

  // Admin-Client (service_role) — nur serverseitig.
  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 1) JWT verifizieren -> echte user.id (nicht dem Client vertrauen).
  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ error: 'invalid_token' }), {
      status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }
  const userId = userData.user.id;

  // 2) delete_my_data() ALS DIESER NUTZER (JWT durchreichen -> auth.uid() passt).
  const asUser = createClient(url, serviceKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error: delDataErr } = await asUser.rpc('delete_my_data');
  if (delDataErr) {
    return new Response(JSON.stringify({ error: 'data_delete_failed', detail: delDataErr.message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }

  // 3) Auth-Konto selbst loeschen (nur mit service_role moeglich).
  const { error: delUserErr } = await admin.auth.admin.deleteUser(userId);
  if (delUserErr) {
    return new Response(JSON.stringify({ error: 'account_delete_failed', detail: delUserErr.message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
  });
});

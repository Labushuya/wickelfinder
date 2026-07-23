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

  // Defense-in-depth: Admin-Konten sind von der Loeschung ausgenommen.
  // (Die DB-Funktion delete_my_data wirft ohnehin 'admin_cannot_selfdelete',
  //  aber wir brechen hier frueh + eindeutig ab.)
  const { data: isAdmin } = await admin.rpc('is_admin', { uid: userId });
  if (isAdmin === true) {
    return new Response(JSON.stringify({ error: 'admin_cannot_selfdelete' }), {
      status: 403, headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }

  // delete_my_data() ALS DIESER NUTZER (JWT durchreichen -> auth.uid() passt).
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

  // 2b) Foto-Objekte im Storage entfernen (SQL kann das nicht -> DSGVO Art. 17).
  // Alle Objekte des Nutzers liegen unter dem Prefix "<uid>/" im Bucket
  // 'place-photos' (Pfad <uid>/<place_slug>/<uuid>.jpg). Rekursiv einsammeln
  // und loeschen. Fehler hier sind nicht fatal fuer die Kontoloeschung, werden
  // aber protokolliert (Rest-Objekte faengt spaeter ein Sweep ab).
  try {
    const bucket = admin.storage.from('place-photos');
    const toRemove: string[] = [];
    // list() ist nicht rekursiv -> pro Unterordner nachladen.
    const { data: subdirs } = await bucket.list(userId, { limit: 1000 });
    for (const entry of subdirs ?? []) {
      // Ein Eintrag ohne id ist ein "Ordner" (place_slug) -> dessen Dateien holen.
      const { data: files } = await bucket.list(`${userId}/${entry.name}`, { limit: 1000 });
      for (const f of files ?? []) {
        if (f.name) toRemove.push(`${userId}/${entry.name}/${f.name}`);
      }
      // Falls direkt Dateien unter <uid>/ liegen (Fallback).
      if (entry.id) toRemove.push(`${userId}/${entry.name}`);
    }
    if (toRemove.length > 0) {
      await bucket.remove(toRemove);
    }
  } catch (e) {
    console.error('storage sweep failed (non-fatal):', e);
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

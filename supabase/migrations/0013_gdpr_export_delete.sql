-- ============================================================================
-- Wickelfinder — Migration 13: DSGVO Datenexport + vollstaendige Loeschung
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-12 voraus.
--
-- Betroffenenrechte (Art. 15/17/20 DSGVO):
--  * export_my_data() -> jsonb: vollstaendige, selbsterklaerende Kopie ALLER
--    Daten des aufrufenden Nutzers (auth.uid()). Maschinen- + menschenlesbar.
--  * delete_my_data() -> jsonb: loescht ALLE Daten des Nutzers. FK-sicher
--    (eigene Plaetze + Beitraege zuerst), sodass danach das Auth-Konto selbst
--    per Edge Function (service_role) geloescht werden kann.
--
-- Loest die nie gebaute "Ownership-Transfer in Migration 7"-Zusage aus 0001
-- offiziell auf: Loeschung laeuft ueber delete_my_data, nicht ueber Transfer.
-- Beide Funktionen arbeiten AUSSCHLIESSLICH auf auth.uid() -> nie Fremddaten.
-- SECURITY DEFINER, weil content_reports keine Self-Read-Policy hat.
-- ============================================================================

-- --- Auskunft (Art. 15/20): vollstaendiger Datenexport als jsonb -------------
create or replace function export_my_data()
returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare
  uid uuid := auth.uid();
  v_email text;
  v_anon boolean;
begin
  if uid is null then raise exception 'auth_required'; end if;

  select email, coalesce(is_anonymous, false) into v_email, v_anon
    from auth.users where id = uid;

  return jsonb_build_object(
    'export_metadata', jsonb_build_object(
      'format_version', '1.0',
      'generated_at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'subject_id', uid,
      'subject_id_note', 'Pseudonyme Kennung (UUID). Kein Klarname. Wird beim ersten Beitrag automatisch erzeugt.',
      'is_anonymous', v_anon,
      'email', v_email,
      'controller', 'Wickelfinder (siehe PRIVACY.md)',
      'gdpr_basis', 'Art. 15 DSGVO (Auskunft) / Art. 20 DSGVO (Datenuebertragbarkeit)',
      'coverage_note', 'Enthaelt alle personenbezogenen Daten, die unter dieser Kennung serverseitig gespeichert sind.'
    ),
    'sections', jsonb_build_object(
      'ratings', jsonb_build_object(
        'description', 'Von dir abgegebene Bewertungen zu Wickelplaetzen (eine pro Platz).',
        'field_descriptions', jsonb_build_object(
          'place_ref', 'Referenz auf den Platz (community/<uuid> oder OSM-Referenz)',
          'stars', 'Sternebewertung 1-5',
          'tags', 'Eigenschafts-Tags (z.B. clean, large_surface, free_of_charge, ...)',
          'created_at', 'Erstmalige Abgabe (UTC)',
          'updated_at', 'Letzte Aenderung (UTC)'),
        'records', coalesce((
          select jsonb_agg(jsonb_build_object(
            'place_ref', r.place_ref, 'stars', r.stars, 'tags', r.tags,
            'created_at', r.created_at, 'updated_at', r.updated_at))
          from ratings r where r.user_id = uid), '[]'::jsonb)
      ),
      'flags', jsonb_build_object(
        'description', 'Von dir gemeldete Probleme (Platz nicht vorhanden/geschlossen/falsche Lage/sonstiges).',
        'field_descriptions', jsonb_build_object(
          'place_ref', 'Referenz auf den Platz',
          'reason', 'not_present | closed | wrong_location | other',
          'created_at', 'Zeitpunkt (UTC)'),
        'records', coalesce((
          select jsonb_agg(jsonb_build_object(
            'place_ref', f.place_ref, 'reason', f.reason, 'created_at', f.created_at))
          from flags f where f.user_id = uid), '[]'::jsonb)
      ),
      'confirmations', jsonb_build_object(
        'description', 'Von dir bestaetigte "existiert noch"-Angaben.',
        'field_descriptions', jsonb_build_object(
          'place_ref', 'Referenz auf den Platz', 'created_at', 'Zeitpunkt (UTC)'),
        'records', coalesce((
          select jsonb_agg(jsonb_build_object(
            'place_ref', c.place_ref, 'created_at', c.created_at))
          from confirmations c where c.user_id = uid), '[]'::jsonb)
      ),
      'community_places', jsonb_build_object(
        'description', 'Von dir angelegte Wickelplaetze (Inhalte inkl. exakter Koordinaten; oeffentlich sichtbar).',
        'field_descriptions', jsonb_build_object(
          'id', 'interne Platz-ID',
          'name', 'Name des Platzes',
          'location_hint', 'Hinweis zur Lage',
          'latitude', 'Breitengrad (aus geom)',
          'longitude', 'Laengengrad (aus geom)',
          'wheelchair', 'barrierefrei (true/false/null)',
          'fee', 'kostenpflichtig (true/false/null)',
          'fee_mode', 'free | conditional | paid',
          'moderation_state', 'Server-Status (visible/hidden/orphaned)',
          'hidden', 'serverseitig ausgeblendet',
          'created_at', 'Anlage (UTC)', 'updated_at', 'Letzte Aenderung (UTC)'),
        'records', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', cp.id, 'name', cp.name, 'location_hint', cp.location_hint,
            'latitude', public.ST_Y(cp.geom::public.geometry),
            'longitude', public.ST_X(cp.geom::public.geometry),
            'wheelchair', cp.wheelchair, 'fee', cp.fee, 'fee_mode', cp.fee_mode,
            'moderation_state', cp.moderation_state, 'hidden', cp.hidden,
            'created_at', cp.created_at, 'updated_at', cp.updated_at))
          from community_places cp where cp.created_by = uid), '[]'::jsonb)
      ),
      'content_reports', jsonb_build_object(
        'description', 'Von dir gemeldete Inhalte anderer (personenbezogene Daten/Missbrauch/Spam).',
        'field_descriptions', jsonb_build_object(
          'place_ref', 'Referenz auf den gemeldeten Platz',
          'kind', 'pii | abuse | spam | other', 'created_at', 'Zeitpunkt (UTC)'),
        'records', coalesce((
          select jsonb_agg(jsonb_build_object(
            'place_ref', cr.place_ref, 'kind', cr.kind, 'created_at', cr.created_at))
          from content_reports cr where cr.user_id = uid), '[]'::jsonb)
      )
    )
  );
end $$;

revoke all on function export_my_data() from public;
grant execute on function export_my_data() to anon, authenticated;

-- --- Loeschung (Art. 17): alle Daten des Nutzers, FK-sicher ------------------
create or replace function delete_my_data()
returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  uid uuid := auth.uid();
  n_places int := 0; n_ratings int := 0; n_flags int := 0;
  n_confirms int := 0; n_reports int := 0;
begin
  if uid is null then raise exception 'auth_required'; end if;

  -- 1) Beitraege (auch fremde) zu MEINEN Plaetzen entfernen, dann die Plaetze.
  delete from ratings       where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from flags         where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from confirmations where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from content_reports where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from community_places where created_by = uid;   -- feuert Tombstone-Trigger
  get diagnostics n_places = row_count;

  -- 2) MEINE Beitraege zu FREMDEN Plaetzen entfernen.
  delete from ratings where user_id = uid;            get diagnostics n_ratings = row_count;
  delete from flags where user_id = uid;              get diagnostics n_flags = row_count;
  delete from confirmations where user_id = uid;      get diagnostics n_confirms = row_count;
  delete from content_reports where user_id = uid;    get diagnostics n_reports = row_count;

  -- 3) Admin-Eintrag (falls vorhanden) entfernen.
  delete from admins where user_id = uid;

  -- Danach zeigt keine FK mehr auf uid -> Auth-Konto-Loeschung (Edge Function) frei.
  return jsonb_build_object('deleted', jsonb_build_object(
    'community_places', n_places, 'ratings', n_ratings, 'flags', n_flags,
    'confirmations', n_confirms, 'content_reports', n_reports));
end $$;

revoke all on function delete_my_data() from public;
grant execute on function delete_my_data() to anon, authenticated;

-- ============================================================================
-- Migration 13 fertig. Auth-Konto-Loeschung erfolgt via Edge Function
-- 'delete-account' (ruft delete_my_data + auth.admin.deleteUser).
-- ============================================================================

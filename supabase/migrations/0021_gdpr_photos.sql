-- ============================================================================
-- Wickelfinder — Migration 21: DSGVO fuer Fotos (Export + Loeschung)
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-20 voraus.
--
-- place_photos in export_my_data (Art. 15/20) und delete_my_data (Art. 17)
-- aufnehmen. WICHTIG: die eigentlichen Bild-DATEIEN liegen im Storage, nicht in
-- der DB — SQL kann sie nicht loeschen. Die Edge Function delete-account
-- entfernt die Objekte per service_role (siehe functions/delete-account).
-- Diese Migration entfernt nur die DB-Zeilen + nimmt sie in den Export auf.
-- ============================================================================

-- --- export_my_data: + Sektion place_photos ---------------------------------
-- Wir haengen die neue Sektion an, indem wir das bestehende jsonb um einen
-- Schluessel ergaenzen. Einfachste robuste Variante: Funktion neu bauen mit
-- allen bisherigen Sektionen + place_photos. (Return-Typ unveraendert: jsonb.)
create or replace function export_my_data()
returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
declare base jsonb;
begin
  if uid is null then raise exception 'auth_required'; end if;

  -- Bisherige Sektionen unveraendert uebernehmen ...
  base := jsonb_build_object(
    'export_metadata', jsonb_build_object(
      'generated_at', now(),
      'note', 'Persoenliche Daten aus Wickelfinder (DSGVO Art. 15/20).',
      'user_id', uid),
    'sections', jsonb_build_object(
      'ratings', jsonb_build_object(
        'description', 'Von dir abgegebene Bewertungen (Sterne + Eigenschaften).',
        'field_descriptions', jsonb_build_object(
          'place_ref', 'Referenz auf den Platz', 'stars', '1-5 Sterne',
          'tags', 'gewaehlte Eigenschaften', 'created_at', 'Zeitpunkt (UTC)',
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
          'id', 'interne Platz-ID', 'name', 'Name des Platzes',
          'location_hint', 'Hinweis zur Lage',
          'latitude', 'Breitengrad (aus geom)', 'longitude', 'Laengengrad (aus geom)',
          'wheelchair', 'barrierefrei (true/false/null)',
          'fee', 'kostenpflichtig (true/false/null)', 'fee_mode', 'free | conditional | paid',
          'moderation_state', 'Server-Status', 'hidden', 'serverseitig ausgeblendet',
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
      ),
      -- NEU: Fotos.
      'place_photos', jsonb_build_object(
        'description', 'Von dir hochgeladene Fotos. Die Bilddateien selbst sind separate Objekte im Speicher und werden bei der Kontoloeschung mit entfernt.',
        'field_descriptions', jsonb_build_object(
          'place_ref', 'Referenz auf den Platz',
          'storage_path', 'Pfad der Bilddatei im Speicher',
          'moderation_state', 'pending | approved | rejected',
          'created_at', 'Upload-Zeitpunkt (UTC)'),
        'records', coalesce((
          select jsonb_agg(jsonb_build_object(
            'place_ref', pp.place_ref, 'storage_path', pp.storage_path,
            'moderation_state', pp.moderation_state, 'created_at', pp.created_at))
          from place_photos pp where pp.created_by = uid), '[]'::jsonb)
      )
    )
  );
  return base;
end $$;

revoke all on function export_my_data() from public;
grant execute on function export_my_data() to authenticated;

-- --- delete_my_data: + place_photos + zugehoerige Meldungen -------------------
-- Admin-Guard + bisherige Loeschungen unveraendert; place_photos ergaenzt.
-- HINWEIS: Storage-Objekte werden hier NICHT geloescht (SQL kann das nicht) —
-- das erledigt die Edge Function delete-account per service_role.
create or replace function delete_my_data()
returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  uid uuid := auth.uid();
  n_places int := 0; n_ratings int := 0; n_flags int := 0;
  n_confirms int := 0; n_reports int := 0; n_photos int := 0;
begin
  if uid is null then raise exception 'auth_required'; end if;
  if public.is_admin(uid) then raise exception 'admin_cannot_selfdelete'; end if;

  -- 1) Beitraege (auch fremde) zu MEINEN Plaetzen entfernen, dann die Plaetze.
  delete from ratings        where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from flags          where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from confirmations  where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from content_reports where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from place_photos   where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from community_places where created_by = uid;
  get diagnostics n_places = row_count;

  -- 2) MEINE Beitraege zu FREMDEN Plaetzen entfernen.
  delete from ratings where user_id = uid;            get diagnostics n_ratings = row_count;
  delete from flags where user_id = uid;              get diagnostics n_flags = row_count;
  delete from confirmations where user_id = uid;      get diagnostics n_confirms = row_count;
  -- Meldungen zu MEINEN Fotos + meine eigenen Fotos.
  delete from content_reports where photo_id in (select id from place_photos where created_by = uid);
  delete from content_reports where user_id = uid;    get diagnostics n_reports = row_count;
  delete from place_photos where created_by = uid;    get diagnostics n_photos = row_count;

  -- 3) Admin-Eintrag (hier no-op, da Admins oben abgewiesen werden).
  delete from admins where user_id = uid;

  return jsonb_build_object('deleted', jsonb_build_object(
    'community_places', n_places, 'ratings', n_ratings, 'flags', n_flags,
    'confirmations', n_confirms, 'content_reports', n_reports,
    'place_photos', n_photos));
end $$;

revoke all on function delete_my_data() from public;
grant execute on function delete_my_data() to anon, authenticated;

-- ============================================================================
-- Migration 21 fertig. Fotos sind in Export + Loeschung enthalten.
-- Storage-Objekt-Loeschung erledigt die Edge Function delete-account.
-- ============================================================================

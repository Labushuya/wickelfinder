-- ============================================================================
-- Wickelfinder — Migration 14: Admin-Konten vor Selbstloeschung schuetzen
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-13 voraus.
--
-- Anforderung: Admin-Konten werden NIE geloescht. delete_my_data() (aus 0013)
-- wuerde einem eingeloggten Admin aber erlauben, ueber die "Meine Daten
-- loeschen"-UI (bzw. die Edge Function delete-account) sein Admin-Konto zu
-- entfernen. Guard: is_admin(uid) -> Abbruch mit 'admin_cannot_selfdelete'.
--
-- Rest der Funktion identisch zu 0013. Return-Typ unveraendert -> create or
-- replace genuegt. Defense-in-depth: die Edge Function prueft zusaetzlich.
-- ============================================================================

create or replace function delete_my_data()
returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  uid uuid := auth.uid();
  n_places int := 0; n_ratings int := 0; n_flags int := 0;
  n_confirms int := 0; n_reports int := 0;
begin
  if uid is null then raise exception 'auth_required'; end if;
  -- Admin-Konten sind von der Selbstloeschung ausgenommen.
  if public.is_admin(uid) then raise exception 'admin_cannot_selfdelete'; end if;

  -- 1) Beitraege (auch fremde) zu MEINEN Plaetzen entfernen, dann die Plaetze.
  delete from ratings       where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from flags         where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from confirmations where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from content_reports where place_ref in (select 'community/' || id::text from community_places where created_by = uid);
  delete from community_places where created_by = uid;
  get diagnostics n_places = row_count;

  -- 2) MEINE Beitraege zu FREMDEN Plaetzen entfernen.
  delete from ratings where user_id = uid;            get diagnostics n_ratings = row_count;
  delete from flags where user_id = uid;              get diagnostics n_flags = row_count;
  delete from confirmations where user_id = uid;      get diagnostics n_confirms = row_count;
  delete from content_reports where user_id = uid;    get diagnostics n_reports = row_count;

  -- 3) Admin-Eintrag (nur relevant, falls jemals Nicht-Admin -> hier no-op).
  delete from admins where user_id = uid;

  return jsonb_build_object('deleted', jsonb_build_object(
    'community_places', n_places, 'ratings', n_ratings, 'flags', n_flags,
    'confirmations', n_confirms, 'content_reports', n_reports));
end $$;

revoke all on function delete_my_data() from public;
grant execute on function delete_my_data() to anon, authenticated;

-- ============================================================================
-- Migration 14 fertig. Admins koennen sich nicht mehr selbst loeschen.
-- ============================================================================

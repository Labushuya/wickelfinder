-- ============================================================================
-- Wickelfinder — Migration 23: Admin-Moderations-Aktionen (Foto/Meldung)
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-22 voraus.
--
-- Bisher konnte ein Admin ein WARTENDES Foto nur freigeben/ablehnen
-- (admin_review_photo), aber kein fremdes Foto LOESCHEN und keine Meldung
-- (content_reports) schliessen. Damit liess sich der Melde-Loop nicht
-- abschliessen (open_reports blieb stehen). Diese Migration ergaenzt zwei
-- admin-only RPCs (Muster: admin_review_photo).
--
-- HINWEIS Storage: das eigentliche Bild-Objekt loescht der Client nach dem RPC
-- (Admin-JWT; storage.objects-DELETE-Policy erlaubt owner ODER is_admin, s. 0019).
-- ============================================================================

-- --- Admin: beliebiges Foto loeschen (inkl. zugehoeriger Meldungen) ----------
create or replace function admin_delete_photo(p_photo_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'admin_required'; end if;
  -- Zugehoerige Meldungen zuerst entfernen (verhindert verwaiste content_reports).
  delete from public.content_reports where photo_id = p_photo_id;
  delete from public.place_photos where id = p_photo_id;
  if not found then raise exception 'photo_missing'; end if;
end $$;

revoke all on function admin_delete_photo(uuid) from public, anon;
grant execute on function admin_delete_photo(uuid) to authenticated;

-- --- Admin: Meldung verwerfen/schliessen (Foto bleibt) -----------------------
create or replace function admin_dismiss_report(p_report_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'admin_required'; end if;
  delete from public.content_reports where id = p_report_id;
  if not found then raise exception 'report_missing'; end if;
end $$;

revoke all on function admin_dismiss_report(uuid) from public, anon;
grant execute on function admin_dismiss_report(uuid) to authenticated;

-- ============================================================================
-- Migration 23 fertig. Admin kann gemeldete Fotos loeschen und Meldungen
-- schliessen -> der Moderations-Loop ist vollstaendig.
-- ============================================================================

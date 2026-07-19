-- ============================================================================
-- Wickelfinder — Migration 16: Admin-Meldungsuebersicht pro Platz
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-15 voraus.
--
-- place_stats/stats_for liefert bewusst nur gereifte (>=48h) Aggregate. Fuer die
-- Moderation braucht der Admin die ROHE Aufschluesselung pro Grund (auch frische
-- Accounts <48h), sichtbar nur im Pin-Detail. Dafuer eine admin-only RPC nach
-- dem Muster von admin_list_places (Migration 12).
-- ============================================================================

create or replace function admin_place_feedback(p_ref text)
returns table (
  not_present_count   int,
  closed_count        int,
  wrong_location_count int,
  other_count         int,
  confirm_count       int,
  rating_count        int
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'admin_required';
  end if;
  return query
    select
      coalesce((select count(*) filter (where reason = 'not_present')
                from public.flags where place_ref = p_ref), 0)::int,
      coalesce((select count(*) filter (where reason = 'closed')
                from public.flags where place_ref = p_ref), 0)::int,
      coalesce((select count(*) filter (where reason = 'wrong_location')
                from public.flags where place_ref = p_ref), 0)::int,
      coalesce((select count(*) filter (where reason = 'other')
                from public.flags where place_ref = p_ref), 0)::int,
      coalesce((select count(*) from public.confirmations
                where place_ref = p_ref), 0)::int,
      coalesce((select count(*) from public.ratings
                where place_ref = p_ref), 0)::int;
end $$;

revoke all on function admin_place_feedback(text) from public, anon;
grant execute on function admin_place_feedback(text) to authenticated;

-- ============================================================================
-- Migration 16 fertig. admin_place_feedback(p_ref) liefert dem Admin die rohen
-- Melde-/Bestaetigungs-/Bewertungszaehler eines Platzes (sonst admin_required).
-- ============================================================================

-- ============================================================================
-- Wickelfinder — Migration 12: admin_list_places ohne Geo-Filter
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-11 voraus.
--
-- Bug: Die Admin-Ansicht "Alle Pins" ruft admin_list_places mit einer
-- WELT-Bounding-Box (-180,-90,180,90) auf. Als geography gecastet degeneriert
-- dieser Envelope an den Polen -> der `geom && envelope`-Filter liefert
-- praktisch KEINE Zeilen. Ergebnis: leere Liste trotz vorhandener Pins.
--
-- Fix: Fuer "alle Pins" ist ein Geo-Filter fachlich ueberfluessig. Wir
-- entfernen ihn; der is_admin()-Guard bleibt die Absicherung. Return-Typ
-- unveraendert -> create or replace genuegt. Die BBox-Parameter der Signatur
-- bleiben (Client unveraendert), werden aber ignoriert.
-- ============================================================================

create or replace function admin_list_places(
  p_south float8, p_west float8, p_north float8, p_east float8
) returns table (
  id uuid, name text, location_hint text, wheelchair boolean, fee boolean,
  fee_mode text, lat float8, lon float8, moderation_state text, hidden boolean
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'admin_required'; end if;
  return query
    select cp.id, cp.name, cp.location_hint, cp.wheelchair, cp.fee, cp.fee_mode,
           public.ST_Y(cp.geom::public.geometry), public.ST_X(cp.geom::public.geometry),
           cp.moderation_state, cp.hidden
    from public.community_places cp;
end $$;
revoke all on function admin_list_places(float8, float8, float8, float8) from public, anon;
grant execute on function admin_list_places(float8, float8, float8, float8) to authenticated;

-- ============================================================================
-- Migration 12 fertig. admin_list_places liefert jetzt ALLE Community-Pins.
-- ============================================================================

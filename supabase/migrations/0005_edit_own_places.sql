-- ============================================================================
-- Wickelfinder — Migration 5: eigene Community-Plaetze bearbeiten & loeschen
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run.
-- Setzt Migration 1-4 voraus. Idempotent (create or replace).
--
-- update_community_place + delete_community_place als SECURITY DEFINER RPCs.
-- Beide pruefen die Eigentuemerschaft SERVERSEITIG (created_by = auth.uid()),
-- damit niemand fremde Pins aendern/loeschen kann. Kein Client-UPDATE/DELETE.
-- PostGIS liegt im Schema public -> geography/ST_* voll qualifizieren.
-- ============================================================================

-- View fuer die EIGENEN Plaetze mit sauberen lat/lon. security_invoker=on ->
-- laeuft mit den Rechten des Aufrufers, sodass die RLS-Policy cp_select_own
-- (created_by = auth.uid()) greift und nur eigene Zeilen sichtbar sind.
create or replace view my_community_places
with (security_invoker = on) as
select
  cp.id, cp.name, cp.location_hint, cp.wheelchair, cp.fee,
  ST_Y(cp.geom::geometry) as lat,
  ST_X(cp.geom::geometry) as lon,
  cp.moderation_state,
  cp.created_at
from community_places cp;

grant select on my_community_places to authenticated;

create or replace function update_community_place(
  p_id         uuid,
  p_lat        float8,
  p_lon        float8,
  p_name       text default null,
  p_hint       text default null,
  p_wheelchair boolean default null,
  p_fee        boolean default null
)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  g   public.geography;
begin
  if uid is null then raise exception 'auth_required'; end if;
  if p_lat is null or p_lon is null
     or p_lat not between -90 and 90
     or p_lon not between -180 and 180 then
    raise exception 'bad_coords';
  end if;
  if p_name is not null and char_length(p_name) > 80 then raise exception 'name_too_long'; end if;
  if p_hint is not null and char_length(p_hint) > 200 then raise exception 'hint_too_long'; end if;

  g := public.ST_SetSRID(public.ST_MakePoint(p_lon, p_lat), 4326)::public.geography;

  update public.community_places
     set name = p_name,
         location_hint = p_hint,
         geom = g,
         wheelchair = p_wheelchair,
         fee = p_fee
   where id = p_id
     and created_by = uid;   -- Eigentuemerschaft: nur eigene Zeile

  if not found then raise exception 'not_owner_or_missing'; end if;
end $$;

create or replace function delete_community_place(p_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'auth_required'; end if;
  -- Ratings/Flags/Confirmations haengen an place_ref ('community/<id>'):
  delete from public.ratings       where place_ref = 'community/' || p_id::text;
  delete from public.flags         where place_ref = 'community/' || p_id::text;
  delete from public.confirmations where place_ref = 'community/' || p_id::text;
  delete from public.community_places where id = p_id and created_by = uid;
  if not found then raise exception 'not_owner_or_missing'; end if;
end $$;

revoke all on function update_community_place(uuid, float8, float8, text, text, boolean, boolean)
  from public, anon;
revoke all on function delete_community_place(uuid) from public, anon;
grant execute on function update_community_place(uuid, float8, float8, text, text, boolean, boolean)
  to authenticated;
grant execute on function delete_community_place(uuid) to authenticated;

-- ============================================================================
-- Migration 5 fertig.
-- ============================================================================

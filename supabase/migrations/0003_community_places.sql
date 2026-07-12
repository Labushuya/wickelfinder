-- ============================================================================
-- Wickelfinder — Migration 3: Community-Plaetze hinzufuegen + oeffentliche View
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> New query -> Run.
-- Setzt Migration 1 + 2 voraus. Idempotent.
--
-- Fuehrt add_community_place (SECURITY DEFINER RPC) + die oeffentliche
-- Lese-View community_places_public ein. Neue Plaetze sind SOFORT sichtbar
-- (moderation_state='visible'); die "unbestaetigt"-Kennzeichnung leitet die
-- App aus fehlenden Bestaetigungen/Bewertungen ab. Flood-Schutz: Geo-Rate-
-- Limit pro Nutzer + globaler Cluster-Cap.
-- ============================================================================

-- --- Oeffentliche View: Community-Plaetze + Aggregate, OHNE created_by-Leak --
-- Nur sichtbare, nicht versteckte Plaetze. Koordinaten als lat/lon (die App
-- braucht keine PostGIS-Geometrie). Kein created_by, kein exaktes created_at.
create or replace view community_places_public
with (security_invoker = off) as
select
  cp.id,
  cp.name,
  cp.location_hint,
  cp.wheelchair,
  cp.fee,
  ST_Y(cp.geom::geometry) as lat,
  ST_X(cp.geom::geometry) as lon,
  ('community/' || cp.id)  as place_ref
from community_places cp
where cp.moderation_state = 'visible'
  and cp.hidden = false;

grant select on community_places_public to anon, authenticated;

-- --- RPC: add_community_place -----------------------------------------------
-- created_by STRIKT aus auth.uid(). Rate-Limits gegen Flooding:
--   * max 5 neue Plaetze/Stunde pro Nutzer
--   * max 1 neuer Platz / 150 m / Tag pro Nutzer (kein Nachbarzellen-Jitter)
--   * globaler Cluster-Cap: max 10 Plaetze aller Nutzer / 150 m
-- Gibt die neue place_ref ('community/<uuid>') zurueck.
create or replace function add_community_place(
  p_lat        float8,
  p_lon        float8,
  p_name       text default null,
  p_hint       text default null,
  p_wheelchair boolean default null,
  p_fee        boolean default null
)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  g   extensions.geography;
  new_id uuid;
begin
  if uid is null then raise exception 'auth_required'; end if;
  if p_lat is null or p_lon is null
     or p_lat not between -90 and 90
     or p_lon not between -180 and 180 then
    raise exception 'bad_coords';
  end if;
  if p_name is not null and char_length(p_name) > 80 then raise exception 'name_too_long'; end if;
  if p_hint is not null and char_length(p_hint) > 200 then raise exception 'hint_too_long'; end if;

  g := extensions.ST_SetSRID(extensions.ST_MakePoint(p_lon, p_lat), 4326)::extensions.geography;

  -- Rate-Limit: max 5 Plaetze/Stunde pro Nutzer.
  if (select count(*) from public.community_places
      where created_by = uid and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'rate_limit';
  end if;

  -- Geo-Rate-Limit: derselbe Nutzer nicht 2x im 150m-Radius pro Tag.
  if exists (select 1 from public.community_places
             where created_by = uid
               and created_at > now() - interval '1 day'
               and extensions.ST_DWithin(geom, g, 150)) then
    raise exception 'geo_rate_limit';
  end if;

  -- Globaler Cluster-Cap: max 10 Plaetze aller Nutzer im 150m-Radius.
  if (select count(*) from public.community_places
      where extensions.ST_DWithin(geom, g, 150)) >= 10 then
    raise exception 'geo_cluster_cap';
  end if;

  insert into public.community_places
    (created_by, name, location_hint, geom, wheelchair, fee, moderation_state)
  values
    (uid, p_name, p_hint, g, p_wheelchair, p_fee, 'visible')
  returning id into new_id;

  return 'community/' || new_id;
end $$;

revoke all on function add_community_place(float8, float8, text, text, boolean, boolean)
  from public, anon;
grant execute on function add_community_place(float8, float8, text, text, boolean, boolean)
  to authenticated;

-- ============================================================================
-- Migration 3 fertig. Nutzer koennen via RPC eigene Plaetze hinzufuegen; die
-- App liest sie ueber community_places_public und merged sie mit OSM.
-- ============================================================================

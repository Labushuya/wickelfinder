-- ============================================================================
-- Wickelfinder — Migration 11: dreiwertige Kosten (fee_mode) + Zugangs-Tags
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-10 voraus.
--
-- Ziel:
--  (1) Kosten nicht mehr nur kostenlos/kostenpflichtig, sondern dreiwertig:
--      free | conditional (kostenlos wenn Gast/Kunde) | paid.
--      Neue Spalte community_places.fee_mode (text, nullable). fee (boolean)
--      bleibt fuer Abwaertskompatibilitaet und wird aus fee_mode abgeleitet
--      (paid -> true, free -> false, conditional/null -> null).
--  (2) Neue Zugangs-Tags im place_tag-Enum: guests_only, entry_fee,
--      free_access, ask_staff. Tag-Limit auf 14 erhoeht.
--
-- Nicht-destruktiv: bestehende Daten bleiben, fee_mode wird aus fee backfilled.
-- ============================================================================

-- --- (2) Neue Zugangs-Tags (Enum-Werte; ADD VALUE ist idempotent ab PG12) ---
alter type place_tag add value if not exists 'guests_only';
alter type place_tag add value if not exists 'entry_fee';
alter type place_tag add value if not exists 'free_access';
alter type place_tag add value if not exists 'ask_staff';

-- Tag-Limit auf 14 erhoehen (10 bestehende + 4 neue).
alter table public.ratings drop constraint if exists tags_max;
alter table public.ratings add constraint tags_max
  check (array_length(tags, 1) is null or array_length(tags, 1) <= 14);

-- --- (1) fee_mode-Spalte + Backfill -----------------------------------------
alter table public.community_places
  add column if not exists fee_mode text
    check (fee_mode is null or fee_mode in ('free','conditional','paid'));

-- Backfill aus bestehendem fee (nur wo fee_mode noch leer ist).
update public.community_places
  set fee_mode = case when fee is true then 'paid'
                      when fee is false then 'free'
                      else null end
  where fee_mode is null and fee is not null;

-- --- add_community_place: + p_fee_mode; leitet fee daraus ab ----------------
-- Signatur aendert sich -> alte Version droppen, neu anlegen.
drop function if exists add_community_place(float8, float8, text, text, boolean, boolean);

create function add_community_place(
  p_lat        float8,
  p_lon        float8,
  p_name       text default null,
  p_hint       text default null,
  p_wheelchair boolean default null,
  p_fee        boolean default null,
  p_fee_mode   text default null
)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  g   public.geography;
  new_id uuid;
  eff_mode text;
  eff_fee  boolean;
begin
  if uid is null then raise exception 'auth_required'; end if;
  if p_lat is null or p_lon is null
     or p_lat not between -90 and 90
     or p_lon not between -180 and 180 then
    raise exception 'bad_coords';
  end if;
  if p_name is not null and char_length(p_name) > 80 then raise exception 'name_too_long'; end if;
  if p_hint is not null and char_length(p_hint) > 200 then raise exception 'hint_too_long'; end if;
  if p_fee_mode is not null and p_fee_mode not in ('free','conditional','paid') then
    raise exception 'bad_fee_mode';
  end if;

  -- fee_mode ist fuehrend; fee wird abgeleitet. Faellt fee_mode weg, aus fee ableiten.
  eff_mode := coalesce(p_fee_mode,
    case when p_fee is true then 'paid' when p_fee is false then 'free' else null end);
  eff_fee  := case when eff_mode = 'paid' then true
                   when eff_mode = 'free' then false
                   else null end;

  g := public.ST_SetSRID(public.ST_MakePoint(p_lon, p_lat), 4326)::public.geography;

  if (select count(*) from public.community_places
      where created_by = uid and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'rate_limit';
  end if;
  if exists (select 1 from public.community_places
             where created_by = uid
               and created_at > now() - interval '1 day'
               and public.ST_DWithin(geom, g, 150)) then
    raise exception 'geo_rate_limit';
  end if;
  if (select count(*) from public.community_places
      where public.ST_DWithin(geom, g, 150)) >= 10 then
    raise exception 'geo_cluster_cap';
  end if;

  insert into public.community_places
    (created_by, name, location_hint, geom, wheelchair, fee, fee_mode, moderation_state)
  values
    (uid, p_name, p_hint, g, p_wheelchair, eff_fee, eff_mode, 'visible')
  returning id into new_id;

  return 'community/' || new_id;
end $$;

revoke all on function add_community_place(float8, float8, text, text, boolean, boolean, text)
  from public, anon;
grant execute on function add_community_place(float8, float8, text, text, boolean, boolean, text)
  to authenticated;

-- --- update_community_place: + p_fee_mode (Admin-Pfad bleibt) ---------------
drop function if exists update_community_place(uuid, float8, float8, text, text, boolean, boolean);

create function update_community_place(
  p_id uuid, p_lat float8, p_lon float8,
  p_name text default null, p_hint text default null,
  p_wheelchair boolean default null, p_fee boolean default null,
  p_fee_mode text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); g public.geography; adm boolean;
  eff_mode text; eff_fee boolean;
begin
  if uid is null then raise exception 'auth_required'; end if;
  adm := public.is_admin(uid);
  if p_lat is null or p_lon is null
     or p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'bad_coords'; end if;
  if p_name is not null and char_length(p_name) > 80 then raise exception 'name_too_long'; end if;
  if p_hint is not null and char_length(p_hint) > 200 then raise exception 'hint_too_long'; end if;
  if p_fee_mode is not null and p_fee_mode not in ('free','conditional','paid') then
    raise exception 'bad_fee_mode'; end if;

  eff_mode := coalesce(p_fee_mode,
    case when p_fee is true then 'paid' when p_fee is false then 'free' else null end);
  eff_fee  := case when eff_mode = 'paid' then true
                   when eff_mode = 'free' then false
                   else null end;

  g := public.ST_SetSRID(public.ST_MakePoint(p_lon, p_lat), 4326)::public.geography;
  update public.community_places
     set name=p_name, location_hint=p_hint, geom=g, wheelchair=p_wheelchair,
         fee=eff_fee, fee_mode=eff_mode
   where id = p_id and (created_by = uid or adm);
  if not found then raise exception 'not_owner_or_missing'; end if;
end $$;

revoke all on function update_community_place(uuid, float8, float8, text, text, boolean, boolean, text)
  from public, anon;
grant execute on function update_community_place(uuid, float8, float8, text, text, boolean, boolean, text)
  to authenticated;

-- --- Views + Delta + Admin-Liste: fee_mode mit ausgeben ----------------------
create or replace view community_places_public
with (security_invoker = off) as
select
  cp.id, cp.name, cp.location_hint, cp.wheelchair, cp.fee, cp.fee_mode,
  ST_Y(cp.geom::geometry) as lat,
  ST_X(cp.geom::geometry) as lon,
  ('community/' || cp.id) as place_ref
from community_places cp
where cp.moderation_state = 'visible' and cp.hidden = false;
grant select on community_places_public to anon, authenticated;

create or replace view my_community_places
with (security_invoker = on) as
select
  cp.id, cp.name, cp.location_hint, cp.wheelchair, cp.fee, cp.fee_mode,
  ST_Y(cp.geom::geometry) as lat,
  ST_X(cp.geom::geometry) as lon,
  cp.moderation_state, cp.created_at
from community_places cp;
grant select on my_community_places to authenticated;

-- community_places_delta: + fee_mode (Return-Typ aendert sich -> droppen).
drop function if exists community_places_delta(timestamptz);
create function community_places_delta(p_since timestamptz default null)
returns table (
  id uuid, name text, location_hint text, wheelchair boolean, fee boolean,
  fee_mode text, lat float8, lon float8, updated_at timestamptz, deleted boolean
)
language plpgsql stable security definer set search_path = '' as $$
begin
  return query
    select v.id, v.name, v.location_hint, v.wheelchair, v.fee, v.fee_mode,
           v.lat, v.lon, cp.updated_at, false
    from public.community_places_public v
    join public.community_places cp on cp.id = v.id
    where p_since is null or cp.updated_at >= p_since
    union all
    select t.id, null, null, null::boolean, null::boolean, null::text,
           null::float8, null::float8, t.deleted_at, true
    from public.community_place_tombstones t
    where p_since is not null and t.deleted_at >= p_since;
end $$;
grant execute on function community_places_delta(timestamptz) to anon, authenticated;

-- admin_list_places: + fee_mode (Return-Typ aendert sich -> droppen).
drop function if exists admin_list_places(float8, float8, float8, float8);
create function admin_list_places(
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
           public.ST_Y(cp.geom::geometry), public.ST_X(cp.geom::geometry),
           cp.moderation_state, cp.hidden
    from public.community_places cp
    where cp.geom && public.ST_MakeEnvelope(p_west, p_south, p_east, p_north, 4326)::public.geography;
end $$;
revoke all on function admin_list_places(float8, float8, float8, float8) from public, anon;
grant execute on function admin_list_places(float8, float8, float8, float8) to authenticated;

-- ============================================================================
-- Migration 11 fertig. Kosten sind dreiwertig (fee_mode), 4 neue Zugangs-Tags.
-- ============================================================================

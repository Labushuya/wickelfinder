-- ============================================================================
-- Wickelfinder — Migration 6: Admin-Rechte (Owner darf alle Pins verwalten)
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run.
-- Setzt Migration 1-5 voraus. Idempotent.
--
-- VORAUSSETZUNG (im Dashboard VOR dieser Migration erledigen):
--   1. Auth -> Users -> "Add user": Owner-Account mit echter E-Mail + Passwort
--      anlegen und E-Mail als bestaetigt markieren (Auto-Confirm).
--   NACH dieser Migration:
--   2. SQL: insert into public.admins(user_id)
--           select id from auth.users where email = '<deine-email>';
--
-- Admin-Sein wird NIE im Client entschieden. Die admins-Tabelle ist fuer
-- Clients komplett unsichtbar (RLS an, keine Policy); nur is_admin() (SECURITY
-- DEFINER) liest sie. Self-Promotion ist damit strukturell ausgeschlossen.
-- ============================================================================

create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;

-- Einzige Lesestelle fuer "ist Admin". SECURITY DEFINER umgeht die RLS-Sperre.
create or replace function public.is_admin(uid uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = '' as $$
  select uid is not null
     and exists (select 1 from public.admins a where a.user_id = uid);
$$;
revoke all on function public.is_admin(uuid) from public, anon;
grant execute on function public.is_admin(uuid) to authenticated;

-- update: created_by = uid ODER Admin (zweiter erlaubter Pfad).
create or replace function public.update_community_place(
  p_id uuid, p_lat float8, p_lon float8,
  p_name text default null, p_hint text default null,
  p_wheelchair boolean default null, p_fee boolean default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); g public.geography; adm boolean;
begin
  if uid is null then raise exception 'auth_required'; end if;
  adm := public.is_admin(uid);
  if p_lat is null or p_lon is null
     or p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'bad_coords'; end if;
  if p_name is not null and char_length(p_name) > 80 then raise exception 'name_too_long'; end if;
  if p_hint is not null and char_length(p_hint) > 200 then raise exception 'hint_too_long'; end if;
  g := public.ST_SetSRID(public.ST_MakePoint(p_lon, p_lat), 4326)::public.geography;
  update public.community_places
     set name=p_name, location_hint=p_hint, geom=g, wheelchair=p_wheelchair, fee=p_fee
   where id = p_id and (created_by = uid or adm);
  if not found then raise exception 'not_owner_or_missing'; end if;
end $$;

create or replace function public.delete_community_place(p_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); adm boolean;
begin
  if uid is null then raise exception 'auth_required'; end if;
  adm := public.is_admin(uid);
  delete from public.ratings       where place_ref = 'community/' || p_id::text;
  delete from public.flags         where place_ref = 'community/' || p_id::text;
  delete from public.confirmations where place_ref = 'community/' || p_id::text;
  delete from public.community_places where id = p_id and (created_by = uid or adm);
  if not found then raise exception 'not_owner_or_missing'; end if;
end $$;

-- Admin-Sicht auf ALLE Plaetze in einer BBox (die public-View zeigt nur
-- moderation_state='visible'; Admin will auch versteckte/fremde sehen).
create or replace function public.admin_list_places(
  p_south float8, p_west float8, p_north float8, p_east float8
) returns table (
  id uuid, name text, location_hint text, wheelchair boolean, fee boolean,
  lat float8, lon float8, moderation_state text, hidden boolean
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'admin_required'; end if;
  return query
    select cp.id, cp.name, cp.location_hint, cp.wheelchair, cp.fee,
           public.ST_Y(cp.geom::geometry), public.ST_X(cp.geom::geometry),
           cp.moderation_state, cp.hidden
    from public.community_places cp
    where cp.geom && public.ST_MakeEnvelope(p_west, p_south, p_east, p_north, 4326)::public.geography;
end $$;
revoke all on function public.admin_list_places(float8, float8, float8, float8) from public, anon;
grant execute on function public.admin_list_places(float8, float8, float8, float8) to authenticated;

-- ============================================================================
-- Migration 6 fertig. Danach Owner in admins eintragen (siehe Kopf).
-- Verifikation: select public.is_admin('<owner-uuid>'); -> true
-- ============================================================================

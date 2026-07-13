-- ============================================================================
-- Wickelfinder — Migration 7: Delta-Sync-Fundament (updated_at + Tombstones)
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run.
-- Setzt Migration 1-6 voraus. Idempotent.
--
-- Ermoeglicht den persistenten lokalen Cache + Delta-Laden der App:
--   * updated_at auf community_places (+ Trigger) -> Aenderungen erkennbar
--   * Tombstone-Tabelle + Trigger -> geloeschte/ausgeblendete Pins erkennbar
--   * community_places_delta(p_since) -> liefert nur Aenderungen seit p_since
-- ============================================================================

alter table public.community_places
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.tg_touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists community_places_touch on public.community_places;
create trigger community_places_touch before update on public.community_places
  for each row execute function public.tg_touch_updated_at();

-- Tombstones: nur id + Zeitpunkt (kein PII).
create table if not exists public.community_place_tombstones (
  id         uuid primary key,
  deleted_at timestamptz not null default now()
);
create index if not exists cp_tombstones_deleted_at_ix
  on public.community_place_tombstones (deleted_at);
revoke all on public.community_place_tombstones from anon, authenticated;

-- Jeder DELETE schreibt einen Tombstone.
create or replace function public.tg_tombstone_on_delete()
returns trigger language plpgsql set search_path = '' as $$
begin
  insert into public.community_place_tombstones(id) values (old.id)
    on conflict (id) do update set deleted_at = now();
  return old;
end $$;

drop trigger if exists community_places_tombstone on public.community_places;
create trigger community_places_tombstone before delete on public.community_places
  for each row execute function public.tg_tombstone_on_delete();

-- Sichtbarkeitsverlust (visible -> hidden/orphaned) = logische Loeschung.
create or replace function public.tg_visibility_tombstone()
returns trigger language plpgsql set search_path = '' as $$
declare now_visible boolean;
begin
  now_visible := (new.moderation_state = 'visible' and new.hidden = false);
  if not now_visible then
    insert into public.community_place_tombstones(id) values (new.id)
      on conflict (id) do update set deleted_at = now();
  else
    delete from public.community_place_tombstones where id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists community_places_visibility on public.community_places;
create trigger community_places_visibility
  after update of moderation_state, hidden on public.community_places
  for each row execute function public.tg_visibility_tombstone();

-- Delta-RPC: Aenderungen (>= p_since) + Loeschungen. p_since=null -> Vollimport.
create or replace function public.community_places_delta(p_since timestamptz default null)
returns table (
  id uuid, name text, location_hint text, wheelchair boolean, fee boolean,
  lat float8, lon float8, updated_at timestamptz, deleted boolean
)
language plpgsql stable security definer set search_path = '' as $$
begin
  return query
    select v.id, v.name, v.location_hint, v.wheelchair, v.fee, v.lat, v.lon,
           cp.updated_at, false
    from public.community_places_public v
    join public.community_places cp on cp.id = v.id
    where p_since is null or cp.updated_at >= p_since
    union all
    select t.id, null, null, null::boolean, null::boolean,
           null::float8, null::float8, t.deleted_at, true
    from public.community_place_tombstones t
    where p_since is not null and t.deleted_at >= p_since;
end $$;
grant execute on function public.community_places_delta(timestamptz) to anon, authenticated;

-- ============================================================================
-- Migration 7 fertig.
-- ============================================================================

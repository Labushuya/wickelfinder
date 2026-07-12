-- ============================================================================
-- Wickelfinder — Migration 1: Rohtabellen + RLS-Sperre + Validierung
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> New query -> einfuegen -> Run.
-- Idempotent: kann bei Bedarf erneut ausgefuehrt werden (drop/create guards).
--
-- Dieser Schritt legt NUR die Struktur an. Es gibt bewusst NOCH KEINE
-- Schreibmoeglichkeit fuer Clients und KEINE oeffentlichen Views — alles ist
-- gesperrt. Schreibpfade (RPCs) und Lese-Views kommen in Migration 2 & 3.
-- ============================================================================

-- --- Extensions -------------------------------------------------------------
-- PostGIS fuer geography-Typ + Geo-Index (Distanz in Metern out-of-the-box).
create extension if not exists postgis;

-- --- Enums ------------------------------------------------------------------
-- Geschlossene Wertebereiche -> kein Free-Text-Flooding.
do $$ begin
  create type place_tag as enum ('clean','large_surface','padding','free_of_charge');
exception when duplicate_object then null; end $$;

do $$ begin
  create type flag_reason as enum ('not_present','closed','wrong_location','other');
exception when duplicate_object then null; end $$;

-- --- Referenz-Validierung ---------------------------------------------------
-- place_ref ist der ueberall verwendete Anker:
--   OSM       -> 'node/123' | 'way/45' | 'relation/9'
--   Community -> 'community/<uuid>'
-- Hart validiert, damit ein Client keine beliebigen Strings streut.
-- ID-Obergrenze bremst Zufalls-ID-Flooding gegen OSM-Refs.
create or replace function is_valid_place_ref(ref text)
returns boolean language sql immutable as $$
  select
    (ref ~ '^(node|way|relation)/[0-9]{1,13}$'
       and split_part(ref, '/', 2)::bigint < 20000000000)
    or ref ~ '^community/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
$$;

-- --- Tabelle: community_places (eigene Plaetze der Community) ----------------
create table if not exists community_places (
  id            uuid primary key default gen_random_uuid(),
  -- KEIN cascade/set-null: beim Account-Loeschen erfolgt Ownership-Transfer
  -- auf einen System-Account (Migration 7), sonst NOT-NULL-Verletzung.
  created_by    uuid not null references auth.users(id),
  name          text check (name is null or char_length(name) <= 80),
  location_hint text check (location_hint is null or char_length(location_hint) <= 200),
  geom          geography(Point, 4326) not null,
  -- Geohash7 (~150 m Zelle) fuers Dedup gegen OSM. Generiert -> Client kann nicht luegen.
  geohash7      text generated always as (ST_GeoHash(geom::geometry, 7)) stored,
  wheelchair    boolean,
  fee           boolean,
  -- Abgeleitete Felder: NUR via RPC (Migration 3+) beschreibbar, nie durch Client.
  questionable_score int     not null default 0,
  hidden             boolean not null default false,
  -- 'pending' = frisch angelegt (mit "unbestaetigt"-Badge sofort sichtbar),
  -- 'visible' = bestaetigt, 'orphaned' = Ersteller-Account geloescht.
  moderation_state   text    not null default 'visible'
                              check (moderation_state in ('pending','visible','orphaned')),
  created_at    timestamptz not null default now()
);
create index if not exists community_places_geom_gix on community_places using gist (geom);
create index if not exists community_places_geohash_ix on community_places (geohash7);
create index if not exists community_places_created_by_ix on community_places (created_by);

-- --- Tabelle: ratings (1-5 Sterne + Attribut-Tags) --------------------------
create table if not exists ratings (
  id          uuid primary key default gen_random_uuid(),
  place_ref   text     not null check (is_valid_place_ref(place_ref)),
  user_id     uuid     not null references auth.users(id) on delete cascade,
  stars       smallint not null check (stars between 1 and 5),
  tags        place_tag[] not null default '{}'
                          check (array_length(tags, 1) is null or array_length(tags, 1) <= 4),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- KERN: 1 Stimme pro User pro Platz.
  constraint ratings_one_per_user unique (place_ref, user_id)
);
create index if not exists ratings_place_ref_ix on ratings (place_ref);

-- --- Tabelle: flags ("nicht vorhanden" / fraglich) --------------------------
create table if not exists flags (
  id          uuid primary key default gen_random_uuid(),
  place_ref   text     not null check (is_valid_place_ref(place_ref)),
  user_id     uuid     not null references auth.users(id) on delete cascade,
  reason      flag_reason not null default 'not_present',
  created_at  timestamptz not null default now(),
  constraint flags_one_per_user unique (place_ref, user_id)
);
create index if not exists flags_place_ref_ix on flags (place_ref);

-- --- Tabelle: confirmations ("doch vorhanden" — macht Soft-Hide reversibel) --
create table if not exists confirmations (
  place_ref  text not null check (is_valid_place_ref(place_ref)),
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (place_ref, user_id)
);

-- --- Tabelle: content_reports (Missbrauch/PII-Takedown durch Dritte) --------
create table if not exists content_reports (
  id         uuid primary key default gen_random_uuid(),
  place_ref  text not null check (is_valid_place_ref(place_ref)),
  kind       text not null check (kind in ('pii','abuse','spam','other')),
  user_id    uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- Row-Level-Security: ALLES ZU.
-- Clients duerfen (noch) NICHTS schreiben und nur die eigene Zeile lesen.
-- Oeffentliche Aggregat-Views + Schreib-RPCs folgen in Migration 2 & 3.
-- ============================================================================
alter table community_places enable row level security;
alter table ratings          enable row level security;
alter table flags            enable row level security;
alter table confirmations    enable row level security;
alter table content_reports  enable row level security;

-- Nur eigene Zeilen lesbar ("habe ich schon bewertet/gemeldet?") — sonst nichts.
drop policy if exists ratings_select_own on ratings;
create policy ratings_select_own on ratings
  for select using (user_id = auth.uid());

drop policy if exists flags_select_own on flags;
create policy flags_select_own on flags
  for select using (user_id = auth.uid());

drop policy if exists conf_select_own on confirmations;
create policy conf_select_own on confirmations
  for select using (user_id = auth.uid());

-- community_places: eigene Zeilen lesbar (spaeter ergaenzt die oeffentliche
-- View in Migration 3 den sichtbaren Rest OHNE created_by-Leak).
drop policy if exists cp_select_own on community_places;
create policy cp_select_own on community_places
  for select using (created_by = auth.uid());

-- KEINE insert/update/delete-Policies -> RLS verweigert jeden Client-Schreibzugriff.
-- Zusaetzlich explizit Tabellen-Grants zuruecknehmen (Guertel + Hosentraeger):
revoke insert, update, delete on community_places, ratings, flags, confirmations, content_reports
  from anon, authenticated;

-- ============================================================================
-- Migration 1 fertig. Erwartetes Ergebnis: Tabellen existieren, RLS aktiv,
-- kein Client kann schreiben, keine fremden Zeilen lesbar.
-- ============================================================================

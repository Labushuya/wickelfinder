-- ============================================================================
-- Wickelfinder — Migration 17: Koordinaten an Bewertungen (Rueckfinden)
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-16 voraus.
--
-- Ziel: "Meine Bewertungen"-Liste soll auch spaeter zum Wickelplatz
-- zurueckfuehren — auch bei OSM-Plaetzen ohne Namen und ohne dass sie gerade
-- geladen sind. Dafuer speichern wir beim Bewerten die Koordinaten mit
-- (unabhaengig davon, ob der Platz spaeter noch im Cache liegt).
--
-- lat/lon sind optional (alte Clients senden sie nicht -> bleiben null; dann
-- ist nur kein Karten-Sprung moeglich, die Bewertung selbst funktioniert).
-- ============================================================================

alter table public.ratings add column if not exists lat double precision;
alter table public.ratings add column if not exists lon double precision;

-- submit_rating um optionale Koordinaten erweitern. Signatur aendert sich
-- (neue Default-Parameter) -> alte 3-Parameter-Aufrufe funktionieren weiter,
-- aber wir legen die neue 5-Parameter-Variante an. Die alte 3-Parameter-
-- Version bleibt aus Migration 9 bestehen (Ueberladung) und schreibt lat/lon
-- einfach nicht — daher hier explizit droppen und NUR die neue behalten,
-- damit es keine mehrdeutige Ueberladung gibt.
drop function if exists submit_rating(text, smallint, place_tag[]);

create or replace function submit_rating(
  p_ref text,
  p_stars smallint,
  p_tags place_tag[] default '{}',
  p_lat double precision default null,
  p_lon double precision default null
)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'auth_required'; end if;
  if not public.is_valid_place_ref(p_ref) then raise exception 'bad_ref'; end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then raise exception 'bad_stars'; end if;
  if array_length(p_tags, 1) > 10 then raise exception 'too_many_tags'; end if;

  -- Rate-Limit pro Identitaet (bremst Einzel-Account; Sybil faengt Aggregat).
  if (select count(*) from public.ratings
      where user_id = uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'rate_limit';
  end if;

  -- Keine Selbstbewertung eigener Community-Plaetze.
  if p_ref like 'community/%' and exists (
      select 1 from public.community_places
      where id = substr(p_ref, 11)::uuid and created_by = uid) then
    raise exception 'self_rating';
  end if;

  insert into public.ratings (place_ref, user_id, stars, tags, lat, lon)
  values (p_ref, uid, p_stars, coalesce(p_tags, '{}'), p_lat, p_lon)
  on conflict (place_ref, user_id)
    do update set stars = excluded.stars, tags = excluded.tags,
                  -- Koordinaten nur ueberschreiben, wenn neue mitgesendet
                  -- wurden (sonst bestehende behalten).
                  lat = coalesce(excluded.lat, public.ratings.lat),
                  lon = coalesce(excluded.lon, public.ratings.lon),
                  updated_at = now();
end $$;

revoke all on function submit_rating(text, smallint, place_tag[], double precision, double precision) from public, anon;
grant execute on function submit_rating(text, smallint, place_tag[], double precision, double precision) to authenticated;

-- ============================================================================
-- Migration 17 fertig. Bewertungen speichern jetzt optional lat/lon, sodass
-- "Meine Bewertungen" auch spaeter zum Platz zurueckfuehren kann.
-- ============================================================================

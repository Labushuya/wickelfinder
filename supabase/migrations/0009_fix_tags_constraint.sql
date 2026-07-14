-- ============================================================================
-- Wickelfinder — Migration 9: Tag-Limit-Constraint reparieren (max 10 Tags)
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
--
-- Bug: Migration 4 wollte das Tag-Limit von 4 auf 10 heben, hat aber den
-- falschen Constraint-Namen gedroppt: `drop constraint if exists tags_max`.
-- Der urspruengliche Constraint aus Migration 1 war INLINE/anonym angelegt und
-- heisst automatisch `ratings_tags_check` (<= 4) — er wurde NIE entfernt und
-- blieb aktiv. Beide Constraints muessen erfuellt sein -> der strengere (<= 4)
-- gewinnt. Folge: jede Bewertung mit 5+ Tags wird serverseitig abgelehnt
-- (check_violation) -> die App sieht 'unknown' -> stiller Totalverlust der
-- Bewertung. Die zusaetzlich gewaehlten Tags wirken "nicht gespeichert".
--
-- Fix: ALLE Check-Constraints auf ratings, die array_length(tags ...) pruefen,
-- entfernen (ausser dem gewollten tags_max <= 10) und tags_max sicherstellen.
-- Versionssicher per pg_constraint-Scan, da der Autoname variieren kann.
-- ============================================================================

do $$
declare c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.ratings'::regclass
      and contype = 'c'
      and conname <> 'tags_max'
      and pg_get_constraintdef(oid) ilike '%array_length(tags%'
  loop
    execute format('alter table public.ratings drop constraint %I', c.conname);
  end loop;
end $$;

-- tags_max (<= 10) idempotent sicherstellen (es gibt genau 10 Tags).
alter table public.ratings drop constraint if exists tags_max;
alter table public.ratings add constraint tags_max
  check (array_length(tags, 1) is null or array_length(tags, 1) <= 10);

-- Defense-in-depth: submit_rating lehnt >10 Tags mit klarem Code ab (statt
-- stillem Constraint-Violation, das die App als 'unknown' verschluckt).
create or replace function submit_rating(
  p_ref text,
  p_stars smallint,
  p_tags place_tag[] default '{}'
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

  insert into public.ratings (place_ref, user_id, stars, tags)
  values (p_ref, uid, p_stars, coalesce(p_tags, '{}'))
  on conflict (place_ref, user_id)
    do update set stars = excluded.stars, tags = excluded.tags, updated_at = now();
end $$;

-- ============================================================================
-- Migration 9 fertig. Bewertungen mit bis zu 10 Tags werden jetzt gespeichert.
-- ============================================================================

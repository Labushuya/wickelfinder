-- ============================================================================
-- Wickelfinder — Migration 2: Bewertungen (submit_rating) + Aggregat-View
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> New query -> Run.
-- Setzt Migration 1 voraus. Idempotent (create or replace / drop if exists).
--
-- Fuehrt den ERSTEN kontrollierten Schreibpfad ein: submit_rating als
-- SECURITY DEFINER RPC. Clients schreiben NIE direkt in Tabellen (Migration 1
-- sperrt das); nur diese Funktion darf, und sie setzt user_id autoritativ aus
-- auth.uid(). Lesen der Aggregate NUR ueber stats_for(refs) (DoS-sicher:
-- Pflicht-Filter, Obergrenze) — nicht ueber eine offene View.
-- ============================================================================

-- --- Aggregat-View: Bayesian-Mean + Zeitgewicht -----------------------------
-- Laeuft als Owner (security_invoker=off), damit sie die (fuer Clients
-- gesperrten) Rohtabellen aggregieren darf — gibt aber NUR Aggregate heraus,
-- nie user_id/created_at/Rohgeometrie.
--
-- Zeitgewicht: Votes frischer Accounts (<48h) zaehlen ~0 und wachsen linear auf
-- volles Gewicht -> Sybil-Wellen aus eben erstellten Anon-Accounts verpuffen.
-- Bayesian-Mean: (m*C + sum) / (m + n) mit Prior m=5, C=3.0 -> ein einzelnes
-- 5*-Vote hebt den Schnitt nicht sofort auf 5.0 (Manipulations-Daempfung).
create or replace view place_stats
with (security_invoker = off) as
with weighted as (
  select
    r.place_ref,
    r.stars,
    least(1.0, greatest(0.0,
      extract(epoch from (now() - u.created_at)) / 86400.0 / 2.0))::numeric as w
  from ratings r
  join auth.users u on u.id = r.user_id
),
agg as (
  select
    place_ref,
    sum(w)             as wn,
    sum(stars * w)     as wsum,
    count(*)::int      as raw_count
  from weighted
  group by place_ref
),
flg as (
  select
    f.place_ref,
    sum(case when extract(epoch from (now() - u.created_at)) >= 172800 then 1 else 0 end)::int
      as aged_flags
  from flags f
  join auth.users u on u.id = f.user_id
  where f.reason in ('not_present','closed')
  group by f.place_ref
),
cnf as (
  select place_ref, count(*)::int as confirm_count
  from confirmations
  group by place_ref
)
select
  coalesce(a.place_ref, flg.place_ref, cnf.place_ref)                as place_ref,
  coalesce(a.raw_count, 0)                                           as rating_count,
  case when coalesce(a.wn, 0) > 0
       then round(((5 * 3.0) + a.wsum) / (5 + a.wn), 2) end          as avg_stars,
  coalesce(flg.aged_flags, 0)                                        as flag_count,
  coalesce(cnf.confirm_count, 0)                                     as confirm_count,
  -- Soft-Hide: >=5 gealterte, unabhaengige "nicht da"-Melder UND mehr Flags
  -- als positive Signale (Ratings + Bestaetigungen). Reversibel via confirm.
  (coalesce(flg.aged_flags, 0) >= 5
     and coalesce(flg.aged_flags, 0) > coalesce(a.raw_count, 0) + coalesce(cnf.confirm_count, 0))
                                                                      as is_questionable
from agg a
  full join flg on flg.place_ref = a.place_ref
  full join cnf on cnf.place_ref = coalesce(a.place_ref, flg.place_ref);

-- View NICHT offen exponieren (DoS: filterloser Full-Scan). Zugriff nur via RPC.
revoke all on place_stats from anon, authenticated;

-- --- RPC: stats_for(refs) — einziges Lese-Interface fuer Aggregate ----------
-- Pflicht-Parameter refs, Obergrenze 200 -> kein filterloser Scan moeglich.
create or replace function stats_for(refs text[])
returns table (
  place_ref       text,
  rating_count    int,
  avg_stars       numeric,
  flag_count      int,
  confirm_count   int,
  is_questionable boolean
)
language sql stable security definer set search_path = '' as $$
  select s.place_ref, s.rating_count, s.avg_stars, s.flag_count,
         s.confirm_count, s.is_questionable
  from public.place_stats s
  where s.place_ref = any(refs)
    and array_length(refs, 1) <= 200;
$$;

-- --- RPC: submit_rating — kontrollierter Schreibpfad ------------------------
-- user_id STRIKT aus auth.uid() (nie Parameter). Rate-Limit 20/h. Selbst-
-- bewertung eigener Community-Plaetze verboten. Upsert -> 1 Stimme pro User.
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

-- --- Rechte: Clients duerfen NUR diese Funktionen ausfuehren ----------------
revoke all on function stats_for(text[])                     from public, anon;
revoke all on function submit_rating(text, smallint, place_tag[]) from public, anon;
grant execute on function stats_for(text[])                       to authenticated, anon;
grant execute on function submit_rating(text, smallint, place_tag[]) to authenticated;

-- ============================================================================
-- Migration 2 fertig. Clients koennen jetzt via RPC bewerten (submit_rating)
-- und Aggregate lesen (stats_for) — aber weiterhin NICHT direkt in Tabellen
-- schreiben. Naechste Migration: Community-Plaetze + Flags/Soft-Hide.
-- ============================================================================

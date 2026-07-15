-- ============================================================================
-- Wickelfinder — Migration 10: Tag-Aggregat (Community-Konsens)
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-9 voraus.
--
-- Ziel: Community-Feedback soll die Stammdaten (place.fee etc.) sichtbar
-- validieren/relativieren ("Google-artig, wahrheitsgemaess"). Dafuer muss das
-- Aggregat wissen, WIE OFT jeder Tag vergeben wurde.
--
-- place_stats bekommt eine neue Spalte tag_counts (jsonb-Objekt {wire: count}),
-- z. B. {"free_of_charge": 7, "paid": 2}. stats_for gibt sie mit zurueck.
-- Die App berechnet daraus den Konsens (Mehrheit) und markiert Widersprueche.
--
-- Rest der View unveraendert (Bayesian-Mean m=1 aus Migration 8, Soft-Hide).
-- ============================================================================

create or replace view place_stats
with (security_invoker = off) as
with weighted as (
  select
    r.place_ref,
    r.stars,
    least(1.0, greatest(0.05,
      extract(epoch from (now() - u.created_at)) / 3600.0))::numeric as w
  from ratings r
  join auth.users u on u.id = r.user_id
),
agg as (
  select place_ref, sum(w) as wn, sum(stars * w) as wsum, count(*)::int as raw_count
  from weighted group by place_ref
),
-- NEU: Tag-Verteilung pro place_ref als {wire: count}.
tagcnt as (
  select place_ref, jsonb_object_agg(tag, n) as tag_counts
  from (
    select r.place_ref, t::text as tag, count(*)::int as n
    from ratings r, unnest(r.tags) as t
    group by r.place_ref, t
  ) s
  group by place_ref
),
flg as (
  select f.place_ref,
    sum(case when extract(epoch from (now() - u.created_at)) >= 172800 then 1 else 0 end)::int as aged_flags
  from flags f join auth.users u on u.id = f.user_id
  where f.reason in ('not_present','closed') group by f.place_ref
),
cnf as (
  select place_ref, count(*)::int as confirm_count from confirmations group by place_ref
)
select
  coalesce(a.place_ref, flg.place_ref, cnf.place_ref, tagcnt.place_ref) as place_ref,
  coalesce(a.raw_count, 0) as rating_count,
  case when coalesce(a.wn, 0) > 0
       then round(((1 * 3.0) + a.wsum) / (1 + a.wn), 2) end as avg_stars,
  coalesce(flg.aged_flags, 0) as flag_count,
  coalesce(cnf.confirm_count, 0) as confirm_count,
  (coalesce(flg.aged_flags, 0) >= 5
     and coalesce(flg.aged_flags, 0) > coalesce(a.raw_count, 0) + coalesce(cnf.confirm_count, 0)) as is_questionable,
  coalesce(tagcnt.tag_counts, '{}'::jsonb) as tag_counts
from agg a
  full join flg    on flg.place_ref = a.place_ref
  full join cnf    on cnf.place_ref = coalesce(a.place_ref, flg.place_ref)
  full join tagcnt on tagcnt.place_ref = coalesce(a.place_ref, flg.place_ref, cnf.place_ref);

revoke all on place_stats from anon, authenticated;

-- stats_for: Rueckgabetyp aendert sich (neue Spalte tag_counts) -> erst droppen,
-- dann neu anlegen (create or replace erlaubt keine Signatur-/Return-Aenderung).
drop function if exists stats_for(text[]);

create function stats_for(refs text[])
returns table (
  place_ref       text,
  rating_count    int,
  avg_stars       numeric,
  flag_count      int,
  confirm_count   int,
  is_questionable boolean,
  tag_counts      jsonb
)
language sql stable security definer set search_path = '' as $$
  select s.place_ref, s.rating_count, s.avg_stars, s.flag_count,
         s.confirm_count, s.is_questionable, s.tag_counts
  from public.place_stats s
  where s.place_ref = any(refs)
    and array_length(refs, 1) <= 200;
$$;

revoke all on function stats_for(text[]) from public, anon;
grant execute on function stats_for(text[]) to authenticated, anon;

-- ============================================================================
-- Migration 10 fertig. stats_for liefert jetzt tag_counts (jsonb {wire:count}).
-- ============================================================================

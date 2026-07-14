-- ============================================================================
-- Wickelfinder — Migration 8: Bewertungs-Daempfung fuer Startphase lockern
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
--
-- Problem: die urspruengliche place_stats-View daempft Einzelbewertungen so
-- stark (Bayesian-Prior m=5, Zeitgewicht ueber 48h), dass eine 5-Sterne-
-- Bewertung eines frischen Accounts nur ~3.0 zeigt -> wirkt "nicht gespeichert".
-- In der Startphase mit wenigen echten Nutzern ist das unpassend.
--
-- Lockerung: Prior-Gewicht m=1 (statt 5), Zeitgewicht ueber 1h auf voll (statt
-- 48h). Einzelbewertungen wirken jetzt realistisch; Schutz gegen Massen-
-- Manipulation bleibt durch den (kleineren) Prior + Zeitgewicht erhalten.
-- Soft-Hide-Schwelle unveraendert.
-- ============================================================================

create or replace view place_stats
with (security_invoker = off) as
with weighted as (
  select
    r.place_ref,
    r.stars,
    -- Zeitgewicht: ueber 1 Stunde auf 1.0 (statt 48h) -> schnell "voll".
    least(1.0, greatest(0.05,
      extract(epoch from (now() - u.created_at)) / 3600.0))::numeric as w
  from ratings r
  join auth.users u on u.id = r.user_id
),
agg as (
  select place_ref, sum(w) as wn, sum(stars * w) as wsum, count(*)::int as raw_count
  from weighted group by place_ref
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
  coalesce(a.place_ref, flg.place_ref, cnf.place_ref) as place_ref,
  coalesce(a.raw_count, 0) as rating_count,
  -- Bayesian mit kleinem Prior m=1, C=3.0 -> Einzelvotes zaehlen fast voll.
  case when coalesce(a.wn, 0) > 0
       then round(((1 * 3.0) + a.wsum) / (1 + a.wn), 2) end as avg_stars,
  coalesce(flg.aged_flags, 0) as flag_count,
  coalesce(cnf.confirm_count, 0) as confirm_count,
  (coalesce(flg.aged_flags, 0) >= 5
     and coalesce(flg.aged_flags, 0) > coalesce(a.raw_count, 0) + coalesce(cnf.confirm_count, 0)) as is_questionable
from agg a
  full join flg on flg.place_ref = a.place_ref
  full join cnf on cnf.place_ref = coalesce(a.place_ref, flg.place_ref);

revoke all on place_stats from anon, authenticated;

-- ============================================================================
-- Migration 8 fertig.
-- ============================================================================

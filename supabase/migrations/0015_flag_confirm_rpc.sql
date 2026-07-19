-- ============================================================================
-- Wickelfinder — Migration 15: Existenz-Feedback (flag / confirm) Schreibpfad
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-14 voraus.
--
-- Die Tabellen flags/confirmations existieren seit Migration 1, aber es gab
-- KEINE Schreib-RPCs -> Clients konnten weder "nicht vorhanden" melden noch
-- "doch vorhanden" bestaetigen (RLS blockiert Direktschreiben). Diese Migration
-- ergaenzt die fehlenden SECURITY-DEFINER-RPCs (Muster: submit_rating).
--
-- Getrennte Behandlung der Melde-Gruende (Kundenwunsch):
--   - not_present + closed -> Soft-Hide ("Existenz fraglich"), bestehende Logik.
--   - wrong_location       -> EIGENER Zaehler + location_disputed-Flag, KEIN
--                             Ausblenden (Platz bleibt sichtbar/nutzbar).
--   - other                -> ungenutzt (im Client gar nicht angeboten).
-- ============================================================================

-- --- RPC: nicht-vorhanden / geschlossen / falscher-Ort melden ---------------
create or replace function submit_flag(
  p_ref text,
  p_reason flag_reason default 'not_present'
)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'auth_required'; end if;
  if not public.is_valid_place_ref(p_ref) then raise exception 'bad_ref'; end if;

  -- Rate-Limit pro Identitaet (bremst Einzel-Account; Sybil faengt Aggregat).
  if (select count(*) from public.flags
      where user_id = uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'rate_limit';
  end if;

  -- Keine Meldung gegen den eigenen Community-Platz.
  if p_ref like 'community/%' and exists (
      select 1 from public.community_places
      where id = substr(p_ref, 11)::uuid and created_by = uid) then
    raise exception 'self_flag';
  end if;

  insert into public.flags (place_ref, user_id, reason)
  values (p_ref, uid, p_reason)
  on conflict (place_ref, user_id)
    do update set reason = excluded.reason, created_at = now();
end $$;

revoke all on function submit_flag(text, flag_reason) from public, anon;
grant execute on function submit_flag(text, flag_reason) to authenticated;

-- --- RPC: "doch vorhanden" bestaetigen (macht Soft-Hide reversibel) ----------
create or replace function confirm_present(p_ref text)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'auth_required'; end if;
  if not public.is_valid_place_ref(p_ref) then raise exception 'bad_ref'; end if;

  if (select count(*) from public.confirmations
      where user_id = uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'rate_limit';
  end if;

  insert into public.confirmations (place_ref, user_id)
  values (p_ref, uid)
  on conflict (place_ref, user_id)
    do update set created_at = now();
end $$;

revoke all on function confirm_present(text) from public, anon;
grant execute on function confirm_present(text) to authenticated;

-- --- place_stats neu: + wrong_loc_count + location_disputed ------------------
-- Bestehende Logik (Bayesian-Mean, tag_counts, is_questionable aus not_present+
-- closed) UNVERAENDERT; nur der wrong_location-Kanal kommt getrennt hinzu.
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
-- NEU: gereifte "falscher Ort"-Meldungen, getrennt vom Soft-Hide.
wloc as (
  select f.place_ref,
    sum(case when extract(epoch from (now() - u.created_at)) >= 172800 then 1 else 0 end)::int as aged_wrong_loc
  from flags f join auth.users u on u.id = f.user_id
  where f.reason = 'wrong_location' group by f.place_ref
),
cnf as (
  select place_ref, count(*)::int as confirm_count from confirmations group by place_ref
)
select
  coalesce(a.place_ref, flg.place_ref, cnf.place_ref, tagcnt.place_ref, wloc.place_ref) as place_ref,
  coalesce(a.raw_count, 0) as rating_count,
  case when coalesce(a.wn, 0) > 0
       then round(((1 * 3.0) + a.wsum) / (1 + a.wn), 2) end as avg_stars,
  coalesce(flg.aged_flags, 0) as flag_count,
  coalesce(cnf.confirm_count, 0) as confirm_count,
  (coalesce(flg.aged_flags, 0) >= 5
     and coalesce(flg.aged_flags, 0) > coalesce(a.raw_count, 0) + coalesce(cnf.confirm_count, 0)) as is_questionable,
  coalesce(tagcnt.tag_counts, '{}'::jsonb) as tag_counts,
  coalesce(wloc.aged_wrong_loc, 0) as wrong_loc_count,
  (coalesce(wloc.aged_wrong_loc, 0) >= 3) as location_disputed
from agg a
  full join flg    on flg.place_ref = a.place_ref
  full join cnf    on cnf.place_ref = coalesce(a.place_ref, flg.place_ref)
  full join tagcnt on tagcnt.place_ref = coalesce(a.place_ref, flg.place_ref, cnf.place_ref)
  full join wloc   on wloc.place_ref = coalesce(a.place_ref, flg.place_ref, cnf.place_ref, tagcnt.place_ref);

revoke all on place_stats from anon, authenticated;

-- stats_for: Rueckgabetyp aendert sich (2 neue Spalten) -> droppen + neu.
drop function if exists stats_for(text[]);

create function stats_for(refs text[])
returns table (
  place_ref         text,
  rating_count      int,
  avg_stars         numeric,
  flag_count        int,
  confirm_count     int,
  is_questionable   boolean,
  tag_counts        jsonb,
  wrong_loc_count   int,
  location_disputed boolean
)
language sql stable security definer set search_path = '' as $$
  select s.place_ref, s.rating_count, s.avg_stars, s.flag_count,
         s.confirm_count, s.is_questionable, s.tag_counts,
         s.wrong_loc_count, s.location_disputed
  from public.place_stats s
  where s.place_ref = any(refs)
    and array_length(refs, 1) <= 200;
$$;

revoke all on function stats_for(text[]) from public, anon;
grant execute on function stats_for(text[]) to authenticated, anon;

-- ============================================================================
-- Migration 15 fertig. submit_flag/confirm_present schreibbar (RPC-only);
-- stats_for liefert zusaetzlich wrong_loc_count + location_disputed.
-- ============================================================================

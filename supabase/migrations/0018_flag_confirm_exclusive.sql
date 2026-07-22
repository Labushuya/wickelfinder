-- ============================================================================
-- Wickelfinder — Migration 18: flag/confirm gegenseitig ausschliessend
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-17 voraus.
--
-- Problem: flags ("nicht vorhanden") und confirmations ("vorhanden") sind
-- getrennte Tabellen mit je eigener Unique-Constraint. Ein Nutzer konnte
-- gleichzeitig BEIDES halten (widerspruechlich) — er zaehlte auf beiden Seiten
-- des Aggregats. Fix: beim Melden die eigene Bestaetigung loeschen und
-- umgekehrt. Nur die jeweils NEUE Aussage des Nutzers bleibt bestehen.
--
-- Nur die Insert-Logik der beiden RPCs erweitert; alles andere unveraendert.
-- ============================================================================

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

  if (select count(*) from public.flags
      where user_id = uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'rate_limit';
  end if;

  if p_ref like 'community/%' and exists (
      select 1 from public.community_places
      where id = substr(p_ref, 11)::uuid and created_by = uid) then
    raise exception 'self_flag';
  end if;

  -- Gegenseitiger Ausschluss: eine "vorhanden"-Bestaetigung desselben Nutzers
  -- fuer diesen Platz entfernen (er sagt jetzt das Gegenteil).
  delete from public.confirmations where place_ref = p_ref and user_id = uid;

  insert into public.flags (place_ref, user_id, reason)
  values (p_ref, uid, p_reason)
  on conflict (place_ref, user_id)
    do update set reason = excluded.reason, created_at = now();
end $$;

revoke all on function submit_flag(text, flag_reason) from public, anon;
grant execute on function submit_flag(text, flag_reason) to authenticated;

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

  -- Gegenseitiger Ausschluss: eine "nicht vorhanden"-Meldung desselben Nutzers
  -- fuer diesen Platz entfernen.
  delete from public.flags where place_ref = p_ref and user_id = uid;

  insert into public.confirmations (place_ref, user_id)
  values (p_ref, uid)
  on conflict (place_ref, user_id)
    do update set created_at = now();
end $$;

revoke all on function confirm_present(text) from public, anon;
grant execute on function confirm_present(text) to authenticated;

-- ============================================================================
-- Migration 18 fertig. Melden und Bestaetigen schliessen sich pro Nutzer nun
-- gegenseitig aus (kein widerspruechlicher Doppel-Zustand mehr).
-- ============================================================================

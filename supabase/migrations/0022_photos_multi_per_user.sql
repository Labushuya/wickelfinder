-- ============================================================================
-- Wickelfinder — Migration 22: Fotos — bis zu 3 pro Nutzer je Platz
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-21 voraus.
--
-- Bisher: 1 Foto pro Nutzer je Platz (unique-Constraint). Neu: bis zu 3.
-- Jedes NEUE Foto (auch weitere) startet 'pending' und braucht Admin-Freigabe
-- (der Default 'pending' aus Migration 19 gilt unveraendert fuer jeden Insert).
--
-- Die Ober-Grenze (3) wird jetzt in register_photo per COUNT geprueft (wie das
-- Rate-Limit), da eine Unique-Constraint nur genau 1 erlauben wuerde.
-- ============================================================================

-- 1) Die 1-pro-Nutzer-Sperre entfernen.
alter table place_photos drop constraint if exists place_photos_one_per_user;

-- 2) register_photo: statt unique-Verletzung nun Cap von 3 pro Nutzer je Platz.
create or replace function register_photo(p_ref text, p_path text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
declare new_id uuid;
begin
  if uid is null then raise exception 'auth_required'; end if;
  if not public.is_valid_place_ref(p_ref) then raise exception 'bad_ref'; end if;
  -- Pfad muss im eigenen <uid>/-Ordner liegen (Defense-in-depth).
  if p_path is null or p_path not like uid::text || '/%' then
    raise exception 'bad_path';
  end if;
  -- Rate-Limit pro Identitaet (gesamt, gegen Flut).
  if (select count(*) from public.place_photos
      where created_by = uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'photo_rate_limit';
  end if;
  -- Ober-Grenze: max 3 Fotos pro Nutzer je Platz.
  if (select count(*) from public.place_photos
      where created_by = uid and place_ref = p_ref) >= 3 then
    raise exception 'photo_limit';
  end if;

  insert into public.place_photos (place_ref, created_by, storage_path)
  values (p_ref, uid, p_path)
  returning id into new_id;
  return new_id;
end $$;

revoke all on function register_photo(text, text) from public, anon;
grant execute on function register_photo(text, text) to authenticated;

-- ============================================================================
-- Migration 22 fertig. Nutzer koennen bis zu 3 Fotos je Platz hochladen;
-- jedes neue wartet auf Admin-Freigabe.
-- ============================================================================

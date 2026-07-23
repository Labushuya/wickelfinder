-- ============================================================================
-- Wickelfinder — Migration 20: Foto-RPCs (Upload/Lesen/Melden/Admin)
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-19 voraus.
--
-- Alle Schreibpfade laufen ueber SECURITY-DEFINER-RPCs (wie im ganzen Projekt).
-- Der Client laedt das Objekt zuerst in den Bucket (storage.objects-INSERT-
-- Policy prueft <uid>/-Praefix) und registriert es DANN per register_photo.
-- ============================================================================

-- --- Foto registrieren (nach Storage-Upload) --------------------------------
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
  -- Rate-Limit pro Identitaet.
  if (select count(*) from public.place_photos
      where created_by = uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'photo_rate_limit';
  end if;

  begin
    insert into public.place_photos (place_ref, created_by, storage_path)
    values (p_ref, uid, p_path)
    returning id into new_id;
  exception when unique_violation then
    raise exception 'photo_exists';
  end;
  return new_id;
end $$;

revoke all on function register_photo(text, text) from public, anon;
grant execute on function register_photo(text, text) to authenticated;

-- --- Fotos zu Plaetzen lesen ------------------------------------------------
-- Liefert freigegebene Fotos + die EIGENEN (auch pending). Nie created_by/
-- review_note an Fremde. is_mine steuert die Client-UI.
create or replace function photos_for(refs text[])
returns table (
  place_ref        text,
  photo_id         uuid,
  storage_path     text,
  moderation_state text,
  is_mine          boolean
)
language sql stable security definer set search_path = '' as $$
  select p.place_ref, p.id, p.storage_path, p.moderation_state,
         (p.created_by = auth.uid()) as is_mine
  from public.place_photos p
  where p.place_ref = any(refs)
    and array_length(refs, 1) <= 200
    and (p.moderation_state = 'approved' or p.created_by = auth.uid());
$$;

revoke all on function photos_for(text[]) from public, anon;
grant execute on function photos_for(text[]) to authenticated, anon;

-- --- Eigenes Foto loeschen (Client entfernt vorher das Storage-Objekt) ------
create or replace function delete_my_photo(p_photo_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'auth_required'; end if;
  delete from public.place_photos where id = p_photo_id and created_by = uid;
  if not found then raise exception 'photo_missing'; end if;
end $$;

revoke all on function delete_my_photo(uuid) from public, anon;
grant execute on function delete_my_photo(uuid) to authenticated;

-- --- Inhalt melden (Foto oder Platz) ----------------------------------------
-- Schreibt in content_reports (die Tabelle hatte bisher KEINEN Schreibpfad).
create or replace function report_content(
  p_ref text,
  p_kind text,
  p_photo_id uuid default null
)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'auth_required'; end if;
  if not public.is_valid_place_ref(p_ref) then raise exception 'bad_ref'; end if;
  if p_kind not in ('pii','abuse','spam','other') then raise exception 'bad_kind'; end if;
  if (select count(*) from public.content_reports
      where user_id = uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'report_rate_limit';
  end if;

  insert into public.content_reports (place_ref, kind, user_id, photo_id)
  values (p_ref, p_kind, uid, p_photo_id);
end $$;

revoke all on function report_content(text, text, uuid) from public, anon;
grant execute on function report_content(text, text, uuid) to authenticated;

-- --- Admin: wartende Fotos --------------------------------------------------
create or replace function admin_pending_photos()
returns table (
  photo_id     uuid,
  place_ref    text,
  storage_path text,
  created_at   timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'admin_required'; end if;
  return query
    select p.id, p.place_ref, p.storage_path, p.created_at
    from public.place_photos p
    where p.moderation_state = 'pending'
    order by p.created_at;
end $$;

revoke all on function admin_pending_photos() from public, anon;
grant execute on function admin_pending_photos() to authenticated;

-- --- Admin: Foto freigeben / ablehnen ---------------------------------------
create or replace function admin_review_photo(
  p_photo_id uuid,
  p_approve boolean,
  p_note text default null
)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'admin_required'; end if;
  update public.place_photos
    set moderation_state = case when p_approve then 'approved' else 'rejected' end,
        review_note = p_note,
        reviewed_at = now()
    where id = p_photo_id;
  if not found then raise exception 'photo_missing'; end if;
end $$;

revoke all on function admin_review_photo(uuid, boolean, text) from public, anon;
grant execute on function admin_review_photo(uuid, boolean, text) to authenticated;

-- --- Admin: pruefungsbeduerftige Zaehler je Platz (fuer Highlight, R2) -------
create or replace function admin_moderation_counts()
returns table (
  place_ref      text,
  pending_photos int,
  open_reports   int
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'admin_required'; end if;
  return query
    with pend as (
      select p.place_ref, count(*)::int as n
      from public.place_photos p where p.moderation_state = 'pending'
      group by p.place_ref
    ),
    rep as (
      select cr.place_ref, count(*)::int as n
      from public.content_reports cr group by cr.place_ref
    )
    select coalesce(pend.place_ref, rep.place_ref) as place_ref,
           coalesce(pend.n, 0) as pending_photos,
           coalesce(rep.n, 0) as open_reports
    from pend full join rep on rep.place_ref = pend.place_ref;
end $$;

revoke all on function admin_moderation_counts() from public, anon;
grant execute on function admin_moderation_counts() to authenticated;

-- --- Admin: offene Meldungen (fuer Meldungs-Review, R2) ----------------------
create or replace function admin_open_reports()
returns table (
  report_id    uuid,
  place_ref    text,
  kind         text,
  photo_id     uuid,
  storage_path text,
  created_at   timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'admin_required'; end if;
  return query
    select cr.id, cr.place_ref, cr.kind, cr.photo_id, p.storage_path, cr.created_at
    from public.content_reports cr
    left join public.place_photos p on p.id = cr.photo_id
    order by cr.created_at desc;
end $$;

revoke all on function admin_open_reports() from public, anon;
grant execute on function admin_open_reports() to authenticated;

-- ============================================================================
-- Migration 20 fertig. Foto-Upload/-Lesen/-Melden + Admin-Freigabe schreibbar.
-- ============================================================================

-- ============================================================================
-- Wickelfinder — Migration 19: Fotos zu Plaetzen (Tabelle + Storage + Policies)
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run. Idempotent.
-- Setzt Migration 1-18 voraus.
--
-- Fotos zu Wickelplaetzen. Lebenszyklus: nach Upload PRIVAT (nur Uploader
-- sichtbar) -> Admin-Freigabe -> oeffentlich. Jederzeit meldbar. 1 Foto pro
-- Platz pro Nutzer, stark komprimiert (Client). Upload nur mit echtem Konto.
--
-- Design: PRIVATER Storage-Bucket + signierte URLs. Privatsphaere wird ueber
-- die storage.objects-RLS erzwungen (an place_photos.moderation_state gebunden),
-- NICHT ueber URL-Unrätselbarkeit. Fotos haengen an place_ref (OSM + community).
--
-- HINWEIS BUCKET: Der insert in storage.buckets unten ist idempotent. Falls die
-- Projekt-Rolle das im SQL-Editor verweigert, den Bucket stattdessen manuell im
-- Dashboard anlegen: Storage -> New bucket -> Name "place-photos", NICHT public,
-- File size limit 256 KB, Allowed MIME image/jpeg,image/webp.
-- ============================================================================

-- --- Storage-Bucket (privat) ------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('place-photos', 'place-photos', false, 262144, '{image/jpeg,image/webp}')
on conflict (id) do update
  set public = false,
      file_size_limit = 262144,
      allowed_mime_types = '{image/jpeg,image/webp}';

-- --- Tabelle: place_photos --------------------------------------------------
create table if not exists place_photos (
  id               uuid primary key default gen_random_uuid(),
  place_ref        text not null check (is_valid_place_ref(place_ref)),
  created_by       uuid not null references auth.users(id) on delete cascade,
  storage_path     text not null,
  moderation_state text not null default 'pending'
                     check (moderation_state in ('pending','approved','rejected')),
  review_note      text,
  created_at       timestamptz not null default now(),
  reviewed_at      timestamptz,
  -- 1 Foto pro Platz pro Nutzer.
  constraint place_photos_one_per_user unique (place_ref, created_by)
);
create index if not exists place_photos_place_ref_ix on place_photos (place_ref);
create index if not exists place_photos_pending_ix on place_photos (place_ref)
  where moderation_state = 'pending';

alter table place_photos enable row level security;

-- Nur eigene Zeile direkt lesbar; alles andere ueber RPCs (photos_for etc.).
drop policy if exists photos_select_own on place_photos;
create policy photos_select_own on place_photos
  for select using (created_by = auth.uid());

-- Kein Client-Schreibzugriff -> nur ueber SECURITY-DEFINER-RPCs.
revoke insert, update, delete on place_photos from anon, authenticated;

-- --- content_reports: Spalte photo_id (fuer Foto-Meldungen) ------------------
-- Nullable -> platz-bezogene Meldungen (ohne Foto) bleiben moeglich.
alter table content_reports
  add column if not exists photo_id uuid references place_photos(id) on delete cascade;

-- --- storage.objects RLS fuer Bucket 'place-photos' -------------------------
-- Privatsphaere-Herzstueck: Lesen nur eigene Objekte ODER freigegebene (an
-- place_photos.moderation_state gebunden) ODER als Admin. Schreiben nur in den
-- eigenen <uid>/-Ordner. Loeschen nur eigene Objekte.

drop policy if exists place_photos_insert on storage.objects;
create policy place_photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'place-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists place_photos_select on storage.objects;
create policy place_photos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'place-photos'
    and (
      owner = auth.uid()
      or exists (
        select 1 from public.place_photos p
        where p.storage_path = storage.objects.name
          and p.moderation_state = 'approved'
      )
      or public.is_admin(auth.uid())
    )
  );

drop policy if exists place_photos_delete on storage.objects;
create policy place_photos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'place-photos'
    and (owner = auth.uid() or public.is_admin(auth.uid()))
  );

-- ============================================================================
-- Migration 19 fertig. place_photos + privater Bucket + Objekt-Policies stehen.
-- Schreib-/Lese-/Admin-RPCs folgen in Migration 20.
-- ============================================================================

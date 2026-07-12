Ich liefere den finalen Architektur-Plan direkt als Antwort. Kein Tool-Aufruf nötig — die Aufgabe ist reine Synthese der Designs mit den adversarisch gefundenen Schwachstellen.

# Wickelfinder Iteration 2 — Finaler Architektur-Plan (Community-Layer auf Supabase)

## Leitentscheidung (kippt drei Design-Grundannahmen)

Die drei Original-Designs teilen alle **eine falsche Kernannahme**: „ein User = eine Identität". Anonymous Auth macht Identitäten gratis und unbegrenzt (Sybil per `curl`, kein Gerät nötig). Daher gilt für den finalen Plan:

1. **Kein direkter Table-INSERT/UPDATE für Clients.** Aller Schreibverkehr läuft über `SECURITY DEFINER` RPCs. Clients bekommen nur `SELECT` auf Aggregat-Views + `EXECUTE` auf RPCs. Das schließt: kaputte Rate-Limit-Policies, `new.`-Syntaxfehler, permissive-OR-Umgehung, Spalten-Level-Manipulation (`hidden`/`score`), gefälschte `created_by`.
2. **Missbrauchsschutz wandert von der Identität aufs Aggregat.** Roh-`avg` wird durch Bayesian-Mean + Zeitgewichtung ersetzt; Soft-Hide braucht Konsens gealterter Identitäten, nicht 3 rohe Flags.
3. **Rohzeilen (`user_id`, `lat/lon`, `created_at`) sind NIE client-lesbar** (DSGVO: Bewegungsprofil einer Eltern-Kohorte). Nur entkoppelte Aggregate raus.

---

## 1. FINALES Supabase-Schema (SQL)

### 1.1 Extensions, Enums, Helpers

```sql
create extension if not exists postgis;   -- geography + ST_DWithin + ST_GeoHash

create type place_source as enum ('osm', 'community');
create type place_tag    as enum ('clean','large_surface','padding','free_of_charge');
create type flag_reason  as enum ('not_present','closed','wrong_location','other');

-- Format-Validierung + OSM-ID-Plausibilitätsobergrenze (bremst Zufalls-ID-Flooding)
create or replace function is_valid_place_ref(ref text)
returns boolean language sql immutable as $$
  select
    (ref ~ '^(node|way|relation)/[0-9]{1,13}$'
       and split_part(ref,'/',2)::bigint < 20000000000)   -- > aktuelle max OSM-id 2026, tunebar
    or ref ~ '^community/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
$$;
```

### 1.2 Tabellen (Rohdaten — für Clients GESPERRT)

```sql
-- Community-eigene Plätze
create table community_places (
  id            uuid primary key default gen_random_uuid(),
  created_by    uuid not null references auth.users(id),   -- KEIN Cascade/SetNull, s. Ownership-Transfer
  name          text check (name is null or char_length(name) <= 80),
  location_hint text check (location_hint is null or char_length(location_hint) <= 200),
  geom          geography(Point,4326) not null,
  geohash7      text generated always as (ST_GeoHash(geom::geometry, 7)) stored,
  wheelchair    boolean,
  fee           boolean,
  -- abgeleitete Felder — NUR via RPC beschreibbar:
  questionable_score int     not null default 0,
  hidden             boolean not null default false,
  moderation_state   text    not null default 'pending'    -- 'pending'|'visible'|'orphaned'
                              check (moderation_state in ('pending','visible','orphaned')),
  created_at    timestamptz not null default now()
);
create index community_places_geom_gix on community_places using gist (geom);
create index community_places_geohash_ix on community_places (geohash7);

-- Bewertungen (1-5 + Tags)
create table ratings (
  id          uuid primary key default gen_random_uuid(),
  place_ref   text     not null check (is_valid_place_ref(place_ref)),
  user_id     uuid     not null references auth.users(id) on delete cascade,
  stars       smallint not null check (stars between 1 and 5),
  tags        place_tag[] not null default '{}'
                          check (array_length(tags,1) is null or array_length(tags,1) <= 4),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint ratings_one_per_user unique (place_ref, user_id)
);
create index ratings_place_ref_ix on ratings (place_ref);

-- Flags ("nicht vorhanden"/fraglich)
create table flags (
  id          uuid     primary key default gen_random_uuid(),
  place_ref   text     not null check (is_valid_place_ref(place_ref)),
  user_id     uuid     not null references auth.users(id) on delete cascade,
  reason      flag_reason not null default 'not_present',
  created_at  timestamptz not null default now(),
  constraint flags_one_per_user unique (place_ref, user_id)
);
create index flags_place_ref_ix on flags (place_ref);

-- "doch vorhanden"-Gegensignal (macht Soft-Hide reversibel)
create table confirmations (
  place_ref  text not null check (is_valid_place_ref(place_ref)),
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (place_ref, user_id)
);

-- Missbrauchs-/Dritt-Betroffenen-Meldungen (PII/Abuse-Takedown)
create table content_reports (
  id         uuid primary key default gen_random_uuid(),
  place_ref  text not null check (is_valid_place_ref(place_ref)),
  kind       text not null check (kind in ('pii','abuse','spam','other')),
  user_id    uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
```

**Ownership-Transfer statt SET-NULL-Widerspruch** (behebt NOT-NULL/SET-NULL-Bug): Beim Account-Löschen werden Plätze auf einen technischen System-Account übertragen und auf `moderation_state='orphaned'` gesetzt (siehe `delete_my_data`), statt in eine NOT-NULL-Verletzung zu laufen.

### 1.3 RLS: alles zu, Clients dürfen nur lesen was Views freigeben

```sql
alter table community_places enable row level security;
alter table ratings          enable row level security;
alter table flags            enable row level security;
alter table confirmations    enable row level security;
alter table content_reports  enable row level security;

-- KEINE SELECT-Policy mit using(true) auf Rohtabellen. Kein INSERT/UPDATE/DELETE für Clients.
-- Nur eigene Zeile lesbar (für "habe ich schon bewertet?"), sonst nichts:
create policy ratings_select_own  on ratings       for select using (user_id = auth.uid());
create policy flags_select_own    on flags         for select using (user_id = auth.uid());
create policy conf_select_own     on confirmations for select using (user_id = auth.uid());
-- community_places: nur sichtbare/eigene Zeilen direkt (Aggregat-View liefert den Rest ohne created_by)
create policy cp_select_visible   on community_places for select
  using (moderation_state = 'visible' or created_by = auth.uid());

-- Rechte-Vergabe: Clients kein direkter Schreibzugriff
revoke insert, update, delete on community_places, ratings, flags, confirmations, content_reports from anon, authenticated;
```

### 1.4 Aggregat-Views (das EINZIGE öffentliche Lese-Interface)

```sql
-- Bayesian-Mean + Zeitgewicht gegen Sybil-Wellen; keine user_id/kein Zeitstempel raus.
-- age_weight: Votes von frischen Anon-Accounts zählen ~0, erst gealterte voll.
create or replace view place_stats
with (security_invoker = off) as   -- läuft als Owner: darf Rohdaten aggregieren, gibt nur Aggregate raus
with weighted as (
  select r.place_ref, r.stars,
         least(1.0, greatest(0.0,
           extract(epoch from (now() - u.created_at)) / 86400.0 / 2.0))::numeric as w  -- 0..1 über 48h
  from ratings r join auth.users u on u.id = r.user_id
),
agg as (
  select place_ref,
         sum(w)                         as wn,
         sum(stars * w)                 as wsum,
         count(*)::int                  as raw_count
  from weighted group by place_ref
),
flg as (
  select f.place_ref,
         sum(case when extract(epoch from (now()-u.created_at))>=172800 then 1 else 0 end)::int as aged_flags
  from flags f join auth.users u on u.id=f.user_id
  where f.reason in ('not_present','closed') group by f.place_ref
),
cnf as (select place_ref, count(*)::int c from confirmations group by place_ref)
select
  coalesce(a.place_ref, flg.place_ref, cnf.place_ref)              as place_ref,
  coalesce(a.raw_count,0)                                          as rating_count,
  -- Bayesian: (m*C + wsum) / (m + wn), m=5 Prior-Gewicht, C=3.0 Prior-Mittel
  case when coalesce(a.wn,0) > 0
       then round(((5*3.0) + a.wsum) / (5 + a.wn), 2) end          as avg_stars,
  coalesce(flg.aged_flags,0)                                       as flag_count,
  coalesce(cnf.c,0)                                                as confirm_count,
  -- Soft-Hide: Konsens gealterter, unabhängiger Melder, relativ zu Bestätigungen
  (coalesce(flg.aged_flags,0) >= 5
     and coalesce(flg.aged_flags,0) > coalesce(a.raw_count,0) + coalesce(cnf.c,0)) as is_questionable
from agg a
  full join flg on flg.place_ref = a.place_ref
  full join cnf on cnf.place_ref = coalesce(a.place_ref, flg.place_ref);

-- Community-Plätze mit Stats, OHNE created_by/exakte Rohgeometrie-Leaks
create or replace view community_places_public
with (security_invoker = off) as
select cp.id, cp.name, cp.location_hint, cp.wheelchair, cp.fee,
       ST_Y(cp.geom::geometry) as lat, ST_X(cp.geom::geometry) as lon,
       ('community/'||cp.id)     as place_ref,
       s.rating_count, s.avg_stars, s.flag_count,
       coalesce(s.is_questionable,false) as is_questionable
from community_places cp
left join place_stats s on s.place_ref = 'community/'||cp.id
where cp.moderation_state = 'visible' and cp.hidden = false;

grant select on place_stats, community_places_public to anon, authenticated;
```

> **DoS-Schutz gegen filterlose View-Scans:** `place_stats` NICHT direkt exponieren, sondern über RPC `stats_for(refs)` (Pflicht-Parameter, max 200 refs) — plus `ALTER ROLE anon SET statement_timeout='2s'` und PostgREST `db-max-rows`. Die `grant` auf `place_stats` oben nur setzen, wenn `stats_for` als alleiniges Interface zu aufwändig ist. [ENTSCHEIDUNG: `place_stats` direkt (einfacher) vs. nur RPC `stats_for` (DoS-sicherer) — Empfehlung: RPC.]

### 1.5 SECURITY DEFINER RPCs (aller Schreibverkehr + Rate-Limits)

**Regeln für JEDEN RPC:** `created_by`/`user_id` strikt aus `auth.uid()` im Body — NIE als Parameter. `set search_path = ''`. Abbruch bei `auth.uid() is null`. `grant execute` nur an `authenticated`.

```sql
create or replace function submit_rating(p_ref text, p_stars smallint, p_tags place_tag[] default '{}')
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'auth_required'; end if;
  if not public.is_valid_place_ref(p_ref) then raise exception 'bad_ref'; end if;
  -- Rate-Limit pro UID (bremst Einzel-Account; Sybil fängt Aggregat + Signup-Limit)
  if (select count(*) from public.ratings
      where user_id=uid and created_at > now()-interval '1 hour') >= 20 then
    raise exception 'rate_limit'; end if;
  -- Selbstbewertung eigener Community-Plätze verbieten
  if p_ref like 'community/%' and exists (
      select 1 from public.community_places
      where id = substr(p_ref,11)::uuid and created_by = uid) then
    raise exception 'self_rating'; end if;
  insert into public.ratings(place_ref,user_id,stars,tags) values (p_ref,uid,p_stars,p_tags)
  on conflict (place_ref,user_id) do update set stars=excluded.stars, tags=excluded.tags, updated_at=now();
end $$;

create or replace function submit_flag(p_ref text, p_reason flag_reason default 'not_present')
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); acct_age interval;
begin
  if uid is null then raise exception 'auth_required'; end if;
  if not public.is_valid_place_ref(p_ref) then raise exception 'bad_ref'; end if;
  -- Flag zählt nur von gealterten Accounts (>48h) — verteuert Soft-Hide-Vandalismus
  select now()-created_at into acct_age from auth.users where id=uid;
  if acct_age < interval '48 hours' then raise exception 'account_too_new'; end if;
  insert into public.flags(place_ref,user_id,reason) values (p_ref,uid,p_reason)
  on conflict (place_ref,user_id) do update set reason=excluded.reason;
end $$;

create or replace function confirm_present(p_ref text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'auth_required'; end if;
  insert into public.confirmations(place_ref,user_id) values (p_ref,uid)
  on conflict do nothing;         -- macht Soft-Hide reversibel
end $$;

create or replace function add_community_place(
  p_lat float8, p_lon float8, p_name text default null,
  p_hint text default null, p_wheelchair boolean default null, p_fee boolean default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); g geography;
begin
  if uid is null then raise exception 'auth_required'; end if;
  if p_lat not between -90 and 90 or p_lon not between -180 and 180 then raise exception 'bad_coords'; end if;
  g := ST_SetSRID(ST_MakePoint(p_lon,p_lat),4326)::geography;
  -- Rate-Limit: max 5 Plätze/h pro UID
  if (select count(*) from public.community_places
      where created_by=uid and created_at>now()-interval '1 hour') >= 5 then
    raise exception 'rate_limit'; end if;
  -- Geo-Flood: max 1 neuer Platz / 150m-Radius / Tag pro UID (Nachbarzellen-sicher via ST_DWithin)
  if exists (select 1 from public.community_places
             where created_by=uid and created_at>now()-interval '1 day'
               and ST_DWithin(geom, g, 150)) then
    raise exception 'geo_rate_limit'; end if;
  -- Globaler Cluster-Cap (Sybil-übergreifend): max 10 Plätze aller UIDs / 150m
  if (select count(*) from public.community_places where ST_DWithin(geom, g, 150)) >= 10 then
    raise exception 'geo_cluster_cap'; end if;
  insert into public.community_places(created_by,name,location_hint,geom,wheelchair,fee,moderation_state)
  values (uid,p_name,p_hint,g,p_wheelchair,p_fee,'pending')   -- pending: erst nach Alterung sichtbar
  returning id into g;  -- reuse var not ideal; use separate uuid var in impl
  return g;
end $$;

-- DSGVO Art.17: eigene Daten löschen, Plätze auf System-Account transferieren
create or replace function delete_my_data()
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); sys uuid := '00000000-0000-0000-0000-000000000000';
begin
  if uid is null then raise exception 'auth_required'; end if;
  delete from public.ratings where user_id=uid;
  delete from public.flags   where user_id=uid;
  delete from public.confirmations where user_id=uid;
  update public.community_places set created_by=sys, moderation_state='orphaned' where created_by=uid;
  -- auth.users-Löschung: NICHT hier (kein service_role) -> Edge Function delete-account (s.u.)
end $$;

revoke all on function submit_rating, submit_flag, confirm_present, add_community_place, delete_my_data from public, anon;
grant execute on function submit_rating, submit_flag, confirm_present, add_community_place, delete_my_data to authenticated;
```

> **Anti-Sybil Aggregat-Reife-Job (statt „pending" ewig):** Ein leichter Job promotet `community_places` von `pending`→`visible`, sobald der Ersteller-Account > 48h alt ist. [ENTSCHEIDUNG: `pg_cron` (Verfügbarkeit im Free-Tier verifizieren!) vs. GitHub-Actions-Cron gegen eine RPC `promote_pending_places()`. Empfehlung: GH-Actions-Cron — planunabhängig, 0€, `last_run`-Alert einfach.]

### 1.6 Was welche Schwachstelle abwehrt (Kurz-Matrix)

| Angriff | Gegenmaßnahme im Schema |
|---|---|
| Sybil Vote-Stuffing | Bayesian-Mean + Zeitgewicht (frische Accounts ~0), Signup-Rate-Limit (Dashboard), Anomalie-Alert |
| Soft-Hide-Vandalismus | Flags nur von >48h-Accounts, Schwelle ≥5 gealterte UND > Bestätigungen, reversibel via `confirm_present` |
| place_ref-Flooding | Format + ID-Obergrenze, Rate-Limit im RPC, Cleanup-Job |
| DSGVO Rohdaten-Leak | KEINE `using(true)`-SELECT; nur Aggregat-Views ohne `user_id`/`created_at` |
| Free-Tier-DoS (View) | `stats_for(refs)`-RPC mit Pflichtfilter, `statement_timeout=2s`, `db-max-rows` |
| Rate-Limit umgehbar / `new.`-Bug / permissive OR | Kein Client-INSERT; alles im DEFINER-RPC autoritativ |
| Spalten-Manipulation (`hidden`/`score`) | Client hat kein UPDATE-Recht; Felder nur via RPC |
| gefälschtes `created_by` / Fremd-Delete | `uid` aus `auth.uid()` im Body, nie Parameter |
| NOT-NULL/SET-NULL-Widerspruch | Ownership-Transfer auf System-Account statt SET NULL |
| Selbstbewertung Fake-POI | `self_rating`-Check im `submit_rating` |
| Geo-Flood + Nachbarzellen-Jitter | `ST_DWithin`-Radius statt Geohash-Gleichheit, globaler Cluster-Cap |

---

## 2. OSM↔Community Merge/Dedup (Dart, pur, testbar)

**Anker = `place_ref`:** `osm` → `"node/123"`, community → `"community/<uuid>"`. OSM-Plätze werden NIE in Supabase geschrieben (ODbL). Feedback hängt an `place_ref`.

```dart
// lib/features/community/domain/place_merge.dart
const double kDedupRadiusMeters = 75;      // Bucket-Vorfilter Geohash7 + Nachbarn, dann Haversine-Confirm
const _dist = Distance();

List<ChangingPlace> mergePlaces({
  required List<ChangingPlace> osm,          // aus Overpass (Iter.1)
  required List<ChangingPlace> community,     // community_places_public
  required Map<String, PlaceStats> statsByRef // stats_for(sichtbare refs)
}) {
  final osmBuckets = _bucketizeGeohash7(osm);   // Geohash7 + 8 Nachbarn als Kandidaten
  final out = <ChangingPlace>[...osm];

  for (final c in community) {
    final near = _candidatesNear(c.location, osmBuckets)
        .where((o) => _dist(o.location, c.location) <= kDedupRadiusMeters);
    // Dedup NICHT rein geometrisch: Zusatzsignal (Name-Ähnlichkeit ODER null-Name) nötig,
    // sonst wird ein echter Community-Platz nahe irrelevantem OSM-Node still verschluckt.
    final dup = near.where((o) => _semanticMatch(o, c));
    if (dup.isEmpty) out.add(c);            // kein Match -> eigener Pin
    // Match: OSM gewinnt Anzeige-Identität; Community-Feedback bleibt an SEINER place_ref
    //        (kein Umhängen fremder lat/lon -> Feedback-Hijack unmöglich).
  }
  // Stats/Flags per EXAKTEM place_ref anhängen. KEIN Geohash-Feedback-Fallback als Default.
  return out.map((p) => p.withStats(statsByRef[p.placeRef])).toList(growable: false);
}

bool _semanticMatch(ChangingPlace osm, ChangingPlace c) =>
    c.name == null || osm.name == null ||
    _normalizedSimilar(osm.name!, c.name!);   // trigram/lowercase-Vergleich
```

**Bewusste Abweichungen von den Original-Designs:**
- **Kein `lat/lon` im Feedback, kein Geohash-Feedback-Fallback als Default.** Design 2 hängte Feedback per Client-`lat/lon`+Geohash an → Feedback-Hijack (Fake `node/999` mit Koordinate eines Nachbarplatzes). Stattdessen: Feedback strikt an exakte `place_ref`. OSM-ID-Churn ist selten und akzeptierter Datenverlust (Rating verwaist, verschwindet aus der Anzeige).
- **Semantik-Confirm im Dedup** (Name/Kategorie), nicht rein geometrisch → kein stilles Verschlucken.
- **Freshness getrennt anzeigen** (`check_date:changing_table` → `fresh`/`aging`/`stale` Badge), NICHT in Sterne mischen.

```dart
// ChangingPlace erweitert (nicht-brechend, Overpass-Pfad bleibt):
Freshness get freshness { /* <12M fresh, 12-36M aging, sonst stale/null */ }
Set<String> get factBadges => { if (wheelchair==true)'accessible', if (fee==false)'free', if (locationHint!=null)'location' };
// avgStars, ratingCount, isQuestionable, freshness aus withStats gemerged.
```

---

## 3. Missbrauchsschutz + DSGVO (0€, wenig Pflege)

**Missbrauchsschutz-Stack (priorisiert):**
1. **Supabase Auth Rate-Limit für anonyme Sign-ins pro IP** (Dashboard → Auth → Rate Limits). Einzige Bremse VOR MAU-Zählung. **Muss explizit gesetzt werden.**
2. **Schreiben nur via DEFINER-RPC** + Rate-Limits im Body (s.o.).
3. **Aggregat-Robustheit:** Bayesian-Mean + Zeitgewicht; Soft-Hide-Konsens ≥5 gealterte Melder.
4. **Anomalie-Alert:** GH-Actions-Job pollt `count(new UIDs/h)` und `Votes/geohash7` gegen Read-only-RPC → Alert bei Schwelle. Kill-Switch: Anon-Signup temporär im Dashboard sperren.
5. **Content-Takedown für Dritt-Betroffene** (`content_reports` + `report_content`-RPC): bei `kind='pii'` Freitext sofort maskieren (Feld-Soft-Hide), da Opfer ≠ Urheber keinen Löschbutton hat. Regex-Trigger gegen Telefonnummern/„PLZ+Straße" flaggt beim Insert.

[ENTSCHEIDUNG: Turnstile am Signup-Endpoint (unsichtbar, 0€, kein Klarname, aber Cloudflare-Endpunkt = leichter DSGVO-/„keine-Tracker"-Konflikt) vs. nur IP-Rate-Limit. Empfehlung: erst IP-Rate-Limit + Alert; Turnstile als dokumentierte Eskalation, falls Missbrauch messbar.]

**DSGVO-Konzept (verbindlich VOR Go-Live):**
- **Sprache korrigieren:** UID ist ein **Pseudonym = personenbezogenes Datum** (Art. 4 Nr. 5), NICHT „anonym/kein Personenbezug". PRIVACY.md Zeile 26-30 ersetzen.
- **Rechtsgrundlage Art. 6 (1) a** (Einwilligung, freiwilliger Beitrag, widerrufbar) — nicht 1f.
- **Datenminimierung:** keine `user_id`/`created_at`/exakte `lat-lon` je an Client. Nur Aggregate.
- **AVV mit Supabase + EU-Region (Frankfurt)** = harte Vorbedingung, nicht Risiko.
- **Betroffenenrechte:** In-App `delete_my_data()` (Art. 17) + `export_my_data()` (Art. 15/20). **Ehrlicher Hinweis:** nach Löschen der lokalen App-Daten kein Zugriff mehr (Pseudonymität) — muss im Text stehen (sonst formaler Art-15-Verstoß).
- **Account-Löschung vollständig:** `auth.users`-Delete braucht `service_role` → **Edge Function `delete-account`** (service_role serverseitig, nie im Client), ruft `delete_my_data()` + `auth.admin.deleteUser()`.
- **Retention:** GH-Actions-Cron löscht beitragslose Anon-Users > 30 Tage. Verdächtige Cluster (viele UIDs/IP-Range/geohash7) → Bulk-Delete inkl. Beiträge.
- **Freitext-Warnung** im Eingabefeld („keine persönlichen Daten Dritter").

---

## 4. Flutter-Umsetzung (Feature-First)

```
lib/features/community/
  data/
    community_repository.dart      // NUR RPC-Calls + View-SELECTs, injizierbarer SupabaseClient
    anon_session.dart              // LAZY signInAnonymously beim 1. Schreibversuch, flutter_secure_storage
  domain/
    rating.dart, flag.dart, community_place.dart, place_stats.dart
    place_merge.dart               // PUR -> Golden-Unit-Test (kein Netz/DB)
  presentation/
    community_providers.dart       // Riverpod: mergedPlacesProvider(BBox)
    place_detail_sheet.dart        // Sterne + Badges + Freshness + "fraglich" + Buttons
    rate_place_dialog.dart, add_place_screen.dart
lib/core/supabase/supabase_init.dart
```

```dart
// Repository: kein Table-Insert, nur RPC
Future<void> rate(String ref,int stars,List<String> tags) =>
  _db.rpc('submit_rating', params:{'p_ref':ref,'p_stars':stars,'p_tags':tags});
Future<void> flagNotPresent(String ref) => _db.rpc('submit_flag', params:{'p_ref':ref});
Future<List<PlaceStats>> statsFor(List<String> refs) =>
  _db.rpc('stats_for', params:{'refs':refs}).then(_parse);   // max 200

// anon_session: LAZY (DSGVO: reine Kartennutzung erzeugt KEINE Identität)
Future<String> ensureAnonId(SupabaseClient c) async =>
  c.auth.currentUser?.id ?? (await c.auth.signInAnonymously()).user!.id;

// main.dart: Init aus --dart-define
await Supabase.initialize(
  url: const String.fromEnvironment('SUPABASE_URL'),
  anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'));
```

```yaml
# .github/workflows/release.yml (Kern)
- run: flutter build apk --release
    --dart-define=SUPABASE_URL=${{ secrets.SUPABASE_URL }}
    --dart-define=SUPABASE_ANON_KEY=${{ secrets.SUPABASE_ANON_KEY }}
```
`mergedPlacesProvider = FutureProvider.family<List<ChangingPlace>, BBox>`: lädt OSM (Iter.1) + `community_places_public` + `stats_for` per `Future.wait`, ruft `mergePlaces`. Presentation: `is_questionable` ans Ende + ausgegraut, sonst nach Distanz, Rating als Tiebreaker.

---

## 5. Test-Strategie

**pgTAP (DB — der kritische Layer):**
- Direkt-INSERT via anon-key auf `ratings`/`flags`/`community_places` **schlägt fehl** (nur RPC erlaubt).
- `submit_rating` mit gefälschtem `user_id`-Versuch → schreibt eigene `auth.uid()`, nie fremde.
- 2. Rating desselben `place_ref` → Upsert (kein Fehler), 21. in 1h → `rate_limit`.
- `submit_flag` von <48h-Account → `account_too_new`.
- `is_questionable` erst ab ≥5 gealterten Flags UND > confirms; `confirm_present` kippt zurück.
- Ersteller kann `hidden`/`questionable_score` seines Platzes NICHT patchen (kein UPDATE-Recht).
- `place_stats`/`community_places_public` liefern **kein** `user_id`/`created_at`.
- Self-Rating eigener Community-Platz → `self_rating`.
- `add_community_place`: Geo-Rate-Limit + Cluster-Cap greifen.
- `delete_my_data` löscht nur eigene, transferiert Plätze auf System-Account.

**Dart-Unit (pur):** `place_merge` Golden-Tests — Dedup Zellgrenze, Semantik-Confirm (kein Verschlucken), kein Feedback-Hijack (Fake-`node`-ref bekommt kein fremdes Feedback), Freshness-Ableitung, Sortierung.

**Integration:** Repository gegen lokale Supabase-Instanz (`supabase start`) — RPC-Roundtrips, RLS-Fehlerpfade.

**Widget:** `place_detail_sheet` rendert Sterne/Badges/„fraglich"; Buttons lösen RPC aus.

---

## 6. Umsetzungs-Reihenfolge (kleine, einzeln releasebare Schritte)

1. **Supabase-Projekt + CI-Wiring.** EU-Region Frankfurt, AVV, Repo-Secrets, `--dart-define`, `Supabase.initialize`, lazy `signInAnonymously`. Release: App startet, keine Community-UI. *Test:* Session persistiert.
2. **Migration 1 — Rohtabellen + RLS-Sperre + `is_valid_place_ref`.** Keine RPCs. *pgTAP:* kein Client-Schreibzugriff, keine Rohdaten lesbar.
3. **Migration 2 — DEFINER-RPCs `submit_rating`/`stats_for` + `place_stats`-View.** Repository + `rate_place_dialog`. Release: OSM-Plätze bewertbar, Schnitt sichtbar. *pgTAP + Golden.*
4. **Migration 3 — `community_places` + `add_community_place` + `community_places_public` + Dedup.** `place_merge` + `add_place_screen`. Release: eigene Plätze, dedupliziert. *Golden Dedup.*
5. **Migration 4 — Flags + Confirmations + Soft-Hide-Logik.** `place_detail_sheet` „fraglich"/„doch vorhanden". Release: reversibler Soft-Hide. *pgTAP Schwellen.*
6. **Freshness + Fact-Badges** (`check_date:changing_table` aus Overpass). Release: Aktualitätssignal.
7. **DSGVO-Vollausbau:** `delete_my_data`/`export_my_data`, Edge Function `delete-account` (service_role), PRIVACY.md-Update, Freitext-Warnung, `content_reports` + `report_content` + PII-Regex-Trigger. **Blocker für Go-Live.**
8. **Betrieb/Härtung:** Signup-IP-Rate-Limit (Dashboard), GH-Actions-Cron (Retention + Anomalie-Alert + `promote_pending_places`), MAU-Budget-Alert, Runbook (Kill-Switch, Notfall-SQL, Cluster-Bulk-Delete).

**Reihenfolge-Logik:** Sicherheitsfundament (2) vor jedem Schreibpfad; jeder Schritt ist eine lauffähige App; DSGVO (7) hart vor Go-Live; Härtung (8) darf nach erstem internen Release folgen, MUSS aber vor öffentlicher Verteilung stehen.

---

## Offene Entscheidungen (Auftraggeber)

- [ENTSCHEIDUNG: `place_stats` direkt exponieren vs. nur `stats_for`-RPC. Empfehlung: RPC (DoS-sicher).]
- [ENTSCHEIDUNG: `pg_cron` (Free-Tier-Verfügbarkeit verifizieren) vs. GH-Actions-Cron für Retention/Reife/Anomalie. Empfehlung: GH-Actions.]
- [ENTSCHEIDUNG: Turnstile am Signup vs. nur IP-Rate-Limit. Empfehlung: erst IP-Limit, Turnstile als Eskalation.]
- [ENTSCHEIDUNG: Bayesian-Prior (m=5, C=3.0) und Soft-Hide-Schwelle (≥5 gealterte Flags, >48h) — Startwerte, nach realen Daten tunen. Als GUC/Konstante halten.]
- [ENTSCHEIDUNG: `pending`→`visible`-Reifezeit für Community-Plätze (48h vorgeschlagen) vs. sofort sichtbar mit „unbestätigt"-Badge. Empfehlung: „unbestätigt"-Badge (bessere UX) + globaler Cluster-Cap als Flood-Schutz.]
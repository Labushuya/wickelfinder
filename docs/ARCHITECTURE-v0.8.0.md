Ich erstelle den umsetzungsreifen v0.8.0-Plan. Kein Geschwafel, direkt der Plan.

---

# Wickelfinder v0.8.0 — Umsetzungsplan

## Leitentscheidung vorab (aus den Funden abgeleitet)

Drei Funde sind **kritisch und blockierend** für Cache+Delta+Akkumulation:
1. `community_places` hat **kein `updated_at`** → Delta unmöglich.
2. `delete_community_place` ist **Hard-Delete ohne Tombstone** → gelöschte Pins bleiben in jedem Cache ewig.
3. Sichtbarkeitsverlust (`hidden`/`orphaned`/`questionable`) erzeugt **kein Delta-Signal** → Zombie-Pins.

Konsequenz: **Ein einziger DELETE-Trigger + updated_at-Trigger auf `community_places` lösen alle drei zentral** — nicht in einzelnen RPCs verstreut (Fund KRITISCH #1). Das ist das Fundament; Admin und Akkumulation bauen darauf auf.

---

## 1. Admin-Auth

### Entscheidung Tabelle vs. E-Mail-Allowlist

Design 1 schlägt `admins`-Tabelle vor, Design 2 hardcodet die E-Mail in `is_admin()`. **Ich nehme die Tabelle** — die E-Mail im Schema-Klartext ist Recon-Info (Fund MITTEL, Risiko 9) und ein Redeploy für Admin-Wechsel ist unnötig starr. Tabelle mit RLS-Deny-All ist strukturell dicht (Fund „verifiziert dicht").

### Finales SQL — `0006_admin.sql`

```sql
-- === admins: nur via is_admin() lesbar. RLS an, KEINE Policy => Clients sehen nichts. ===
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;

-- === is_admin(uid): einzige Lesestelle. SECURITY DEFINER umgeht RLS. ===
create or replace function public.is_admin(uid uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = '' as $$
  select uid is not null
     and exists (select 1 from public.admins a where a.user_id = uid);
$$;
revoke all on function public.is_admin(uuid) from public, anon;
grant execute on function public.is_admin(uuid) to authenticated;

-- === Regressions-Selbsttest: kippt eine spätere create-or-replace die Sperre, schlägt Migration fehl. ===
do $$
begin
  if not exists (
    select 1 from pg_proc p
    where p.proname = 'is_admin' and p.prosecdef = true
      and p.proconfig @> array['search_path=']
  ) then
    raise exception 'is_admin muss SECURITY DEFINER mit search_path='''' sein';
  end if;
end $$;
```

### RPC-Erweiterung — bestehende RPCs, zweiter erlaubter Pfad

Ich weiche die **bestehenden** RPCs auf (Design 1), statt getrennte `admin_*`-RPCs (Design 2) — Signaturen bleiben identisch (`create or replace`), **keine Client-Repo-Änderung** an bestehenden Aufrufen. **Aber**: Der Admin-Edit-Nullt-Felder-Fund (MITTEL) zwingt zu COALESCE-Semantik für den Admin-Pfad.

```sql
-- update: COALESCE-Semantik (nur nicht-NULL überschreiben). Schützt Admin UND Owner vor
-- versehentlichem Nullen fremder/eigener Felder. VERHALTENSÄNDERUNG ggü. 0005 (dort NULL=löschen).
create or replace function public.update_community_place(
  p_id uuid, p_lat float8, p_lon float8,
  p_name text default null, p_hint text default null,
  p_wheelchair boolean default null, p_fee boolean default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); g public.geography; adm boolean;
begin
  if uid is null then raise exception 'auth_required'; end if;
  adm := public.is_admin(uid);
  if p_lat is null or p_lon is null
     or p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'bad_coords'; end if;
  if p_name is not null and char_length(p_name) > 80 then raise exception 'name_too_long'; end if;
  if p_hint is not null and char_length(p_hint) > 200 then raise exception 'hint_too_long'; end if;
  g := public.ST_SetSRID(public.ST_MakePoint(p_lon, p_lat), 4326)::public.geography;
  update public.community_places
     set name          = coalesce(p_name, name),
         location_hint  = coalesce(p_hint, location_hint),
         geom           = g,
         wheelchair     = coalesce(p_wheelchair, wheelchair),
         fee            = coalesce(p_fee, fee)
   where id = p_id
     and (created_by = uid or adm);   -- zweiter erlaubter Pfad
  if not found then raise exception 'not_owner_or_missing'; end if;
end $$;
```

> [ENTSCHEIDUNG: COALESCE-Semantik heißt: „Feld leeren" ist per RPC nicht mehr möglich. Für Wickelplätze (Name/Hinweis sind quasi immer gesetzt) akzeptabel. Falls explizites Leeren gebraucht wird → separater `p_clear_name boolean`-Flag-RPC, nicht in v0.8.0.]

```sql
-- delete: gleiche OR-Erweiterung. Tombstone NICHT hier — der Trigger unten macht das zentral.
create or replace function public.delete_community_place(p_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); adm boolean;
begin
  if uid is null then raise exception 'auth_required'; end if;
  adm := public.is_admin(uid);
  delete from public.ratings       where place_ref = 'community/' || p_id::text;
  delete from public.flags         where place_ref = 'community/' || p_id::text;
  delete from public.confirmations where place_ref = 'community/' || p_id::text;
  delete from public.community_places where id = p_id and (created_by = uid or adm);
  if not found then raise exception 'not_owner_or_missing'; end if;
end $$;
```

### Admin-Sicht auf fremde/verwaiste Pins — `admin_list_places`

Die public-View zeigt dem Admin fremde Pins nicht (RLS + `moderation_state='visible'`-Filter). Fund MITTEL fordert: is_admin-Gate als **erste Anweisung**, bbox **Pflicht** mit Cap, kein anon-Grant.

```sql
create or replace function public.admin_list_places(
  p_min_lat float8, p_min_lon float8, p_max_lat float8, p_max_lon float8
) returns table (
  id uuid, name text, location_hint text, lat float8, lon float8,
  created_by uuid, moderation_state text, hidden boolean, updated_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'admin_required'; end if;
  if p_min_lat is null or p_max_lat is null or p_min_lon is null or p_max_lon is null then
    raise exception 'bbox_required'; end if;
  if (p_max_lat - p_min_lat) * (p_max_lon - p_min_lon) > 4.0 then
    raise exception 'bbox_too_large'; end if;  -- ~ Flächen-Cap gegen Full-Scan
  return query
    select cp.id, cp.name, cp.location_hint,
           public.ST_Y(cp.geom::geometry), public.ST_X(cp.geom::geometry),
           cp.created_by, cp.moderation_state::text, cp.hidden, cp.updated_at
    from public.community_places cp
    where public.ST_Y(cp.geom::geometry) between p_min_lat and p_max_lat
      and public.ST_X(cp.geom::geometry) between p_min_lon and p_max_lon
    limit 500;
end $$;
revoke all on function public.admin_list_places(float8,float8,float8,float8) from public, anon;
grant execute on function public.admin_list_places(float8,float8,float8,float8) to authenticated;
```

### Herrenlose Pins — Definition + Transfer

Fund HOCH (FK-Henne-Ei) + Fund MITTEL (orphaned wird unsichtbar) zwingen zu:
- System-User **vor** jedem Delete anlegen, feste UUID.
- Transfer setzt `created_by = SYSTEM_UUID`, **belässt `moderation_state='visible'`** (Fund: sonst verschwinden valide Pins von der Karte). „Herrenlos" = `created_by = SYSTEM_UUID`.
- Kein `is_admin(auth.uid())`-Guard im Dashboard-Pfad (Service-Role hat keine `auth.uid()`). → `before delete`-Trigger.

```sql
-- Feste System-UUID. VORAUSSETZUNG: system-Auth-User mit exakt dieser id im Dashboard angelegt.
-- Auto-Transfer bei Account-Löschung: created_by wandert auf System-User, Pin bleibt sichtbar.
create or replace function public.tg_orphan_places()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.community_places
     set created_by = '00000000-0000-0000-0000-0000000000AD'  -- SYSTEM_UUID (Konstante)
   where created_by = old.id;
  return old;
end $$;

drop trigger if exists auth_user_orphan on auth.users;
create trigger auth_user_orphan before delete on auth.users
  for each row execute function public.tg_orphan_places();
```

> [ENTSCHEIDUNG: SYSTEM_UUID = `00000000-0000-0000-0000-0000000000AD`. Auftraggeber muss den system-Auth-User mit **genau dieser** id im Dashboard anlegen, bevor je ein Account gelöscht wird. Auftraggeber bestätigen/anpassen.]

### Login-Flow Dart

```dart
// auth_repository.dart
class AuthRepository {
  AuthRepository(this._c);
  final SupabaseClient _c;
  User? get user => _c.auth.currentUser;
  bool get isAnon => _c.auth.currentUser?.isAnonymous ?? true;
  Future<void> signInAdmin(String email, String pw) =>
      _c.auth.signInWithPassword(email: email, password: pw);
  Future<void> signOut() => _c.auth.signOut();
  Future<bool> checkIsAdmin() async {
    final u = _c.auth.currentUser;
    if (u == null || (u.isAnonymous)) return false; // kein RPC-Wait bei anon
    try { return (await _c.rpc<bool>('is_admin')) == true; } catch (_) { return false; }
  }
}

final authStateProvider =
    StreamProvider((ref) => SupabaseInit.client.auth.onAuthStateChange);

final isAdminProvider = FutureProvider<bool>((ref) async {
  ref.watch(authStateProvider);                 // bei jedem Login/Logout neu
  return ref.watch(authRepositoryProvider).checkIsAdmin();
});
```

### Session-Handling anon ↔ admin (die Fallen)

- **`signInWithPassword` ersetzt die anon-Session.** `ensureSignedIn()` prüft `currentUser != null` → bei eingeloggtem Admin wird **kein** anon-Login ausgelöst, alle Schreib-RPCs laufen als Admin. Gewünscht.
- **Fund MITTEL (Anon-Historie-Verlust):** Loggt der Owner sich auf seinem Alltagsgerät als Admin ein, sind seine früheren anon-Pins in „Meine Pins" weg (andere `created_by`). **linkIdentity bewusst NICHT nutzen** (würde anon-Beiträge an den Admin-Account heften). → **[ENTSCHEIDUNG: Admin nutzt dediziertes Gerät/Profil ODER erstellt eigene Pins ausschließlich als Admin. Als Design-Constraint dokumentiert. UX: beim Admin-Logout warnen „Du bist wieder anonym unterwegs".]**
- **Fund NIEDRIG (Stale isAdminProvider Race):** Beim `authStateChange`-Emit `isAdminProvider` hart invalidieren; bei anon/`null` sofort `false` ohne RPC-Wait (oben umgesetzt). Server-RPC fängt den Race ohnehin (`not_owner_or_missing`).
- **Erreichbarkeit:** Versteckter Login (Long-Press auf Logo im About-Screen). Security-by-obscurity nur für Sichtbarkeit — echte Sperre ist serverseitig.

### Fehlercode-Mapping (Fund NIEDRIG)

`community_repository.dart _extractCode`-Allowlist erweitern um `admin_required`, `bbox_required`, `bbox_too_large`. `signInWithPassword`-`AuthException` separat auf `email_not_confirmed`/`invalid_credentials` mappen. **`unknown` im UI IMMER als Fehler behandeln, nie als Erfolg.**

---

## 2. Cache + Delta

### Package: `drift`, nicht Hive

Design 3 nennt Hive, Design 2 begründet **drift** überzeugend: wir brauchen bbox-Range-Queries, ORDER BY updated_at, DELETE-by-key — ein Query-Problem, kein Key-Value-Problem. Hive lädt alles in Memory. **drift gewinnt.**

```yaml
# pubspec deps
drift: ^2.28.0
sqlite3_flutter_libs: ^0.5.0
# dev_deps
drift_dev: ^2.28.0
build_runner: ^2.4.0
```
Android minSdk ≥ 21 (via geolocator bereits erfüllt).

### Server-Schema — `0007_delta_sync.sql`

Der Kern. **Ein DELETE-Trigger + ein updated_at-Trigger lösen alle drei kritischen Funde zentral.**

```sql
-- updated_at + Trigger: JEDE Änderung (auch Moderation/hide) bumpt den Wert.
alter table public.community_places
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.tg_touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists community_places_touch on public.community_places;
create trigger community_places_touch before update on public.community_places
  for each row execute function public.tg_touch_updated_at();

-- Tombstones: nur id + Zeitpunkt, kein PII.
create table if not exists public.community_place_tombstones (
  id         uuid primary key,
  deleted_at timestamptz not null default now()
);
create index if not exists cp_tombstones_deleted_at_ix
  on public.community_place_tombstones (deleted_at);

-- ZENTRAL: jeder DELETE-Pfad (alter RPC, Admin, CASCADE, manuelles SQL) schreibt Tombstone.
create or replace function public.tg_tombstone_on_delete()
returns trigger language plpgsql set search_path = '' as $$
begin
  insert into public.community_place_tombstones(id) values (old.id)
    on conflict (id) do update set deleted_at = now();
  return old;
end $$;

drop trigger if exists community_places_tombstone on public.community_places;
create trigger community_places_tombstone before delete on public.community_places
  for each row execute function public.tg_tombstone_on_delete();

-- ZENTRAL: Sichtbarkeitsverlust = logische Löschung fürs Delta (Zombie-Pin-Fix).
-- visible->hidden/orphaned/questionable => Tombstone. Zurück zu visible => Tombstone weg + updated_at bump.
create or replace function public.tg_visibility_tombstone()
returns trigger language plpgsql set search_path = '' as $$
declare now_visible boolean;
begin
  now_visible := (new.moderation_state = 'visible' and new.hidden = false);
  if not now_visible then
    insert into public.community_place_tombstones(id) values (new.id)
      on conflict (id) do update set deleted_at = now();
  else
    delete from public.community_place_tombstones where id = new.id;  -- Re-Add
  end if;
  return new;
end $$;

drop trigger if exists community_places_visibility on public.community_places;
create trigger community_places_visibility after update of moderation_state, hidden
  on public.community_places
  for each row execute function public.tg_visibility_tombstone();

-- Delta-RPC: aus community_places_public gebaut (Filter-Drift zur View ausgeschlossen).
-- >= p_since + Client-Upsert per id => Skip-Lücke bei gleichen Timestamps geschlossen (Fund MITTEL Clock).
-- Retention-Fallback als eigene Spalte resync_required, NICHT als leeres Delta.
create or replace function public.community_places_delta(p_since timestamptz default null)
returns table (
  id uuid, name text, location_hint text, wheelchair boolean, fee boolean,
  lat float8, lon float8, updated_at timestamptz, deleted boolean,
  resync_required boolean, retention_days int
)
language plpgsql stable security definer set search_path = '' as $$
declare v_retention int := 90; v_resync boolean;
begin
  v_resync := p_since is not null and p_since < now() - (v_retention || ' days')::interval;
  if v_resync then
    -- Signal-Zeile: Client MUSS Cache droppen + since=NULL Vollimport fahren.
    return query select null::uuid, null, null, null::boolean, null::boolean,
                        null::float8, null::float8, null::timestamptz, null::boolean,
                        true, v_retention;
    return;
  end if;
  return query
    -- Änderungen/Neue (spiegelt die View 1:1)
    select v.id, v.name, v.location_hint, v.wheelchair, v.fee, v.lat, v.lon,
           cp.updated_at, false, false, v_retention
    from public.community_places_public v
    join public.community_places cp on cp.id = v.id
    where p_since is null or cp.updated_at >= p_since
    union all
    -- Löschungen (inkl. Sichtbarkeitsverlust)
    select t.id, null, null, null::boolean, null::boolean, null::float8, null::float8,
           t.deleted_at, true, false, v_retention
    from public.community_place_tombstones t
    where p_since is not null and t.deleted_at >= p_since;
end $$;
grant execute on function public.community_places_delta(timestamptz) to anon, authenticated;
```

> [ENTSCHEIDUNG: `updated_at` wird über die Delta-RPC exponiert (Fund MITTEL Aktivitäts-Seitenkanal). `created_by`/exaktes `created_at` bleiben verborgen. Falls der Seitenkanal stört → `date_trunc('hour', updated_at)` im Delta. Default: volle Auflösung, weil kein PII.]

### drift-Schema (App)

```dart
// Tabellen: CommunityPlaces(id PK, name, hint, wheelchair, fee, lat, lon, updatedAt, syncedAt)
//           SyncState(key PK, value)              -- hält last_watermark
//           OsmPlaces(nodeId PK, lat, lon, ..., tileKey)
//           OsmTiles(tileKey PK, fetchedAt)
// schemaVersion; onUpgrade droppt Cache-Tabellen -> Vollsync (Cache ist verwerfbar).
```

### Sync-Strategie

- **Community = globaler Delta-Sync, bbox-entkoppelt.** Datenmenge klein (paar tausend Zeilen bundesweit). Fund HOCH (Doppel-Sync-Race): `sync()` **global serialisiert** (ein `CommunitySyncService` mit Mutex, **kein** per-bbox-Trigger). Watermark-Read → RPC → Upsert nicht-deleted + `deleteIds(deleted)` + Watermark-Write **in EINER drift-Transaktion**. Neues Watermark = `max(updated_at/deleted_at)` **nur aus der verarbeiteten Antwort** (nie Client-Uhr — Fund MITTEL Clock-Drift).
- **Watermark `>=` + idempotenter Upsert** statt `>` → schließt Skip-Lücke bei gleichen Timestamps (Fund MITTEL). Doppel-Lieferung ist harmlos.
- **resync_required:** eigene Spalte, nie mit leerem Delta verwechselbar. Client droppt Cache + `since=NULL`. Retention (90d) kommt **aus der RPC** (`retention_days`) — eine Quelle für Server-Cleanup-Job und Client-Fallback.
- **OSM = per-Kachel TTL-Cache**, getrennte Tabelle, anderes Sync-Modell. 0.05°-Kacheln, TTL 7–14 Tage. **delete+insert pro Kachel in EINER Transaktion, `fetched_at` erst NACH erfolgreicher, nicht-leerer Antwort** (Fund MITTEL: sonst löscht ein 429 den Kachelinhalt und ersetzt ihn durch nichts). Bei Fehler: alter Inhalt + altes `fetched_at` bleiben (stale-but-present). Mehrere stale Kacheln zu EINER bbox-Query bündeln, harte Obergrenze paralleler Requests + Backoff bei 429.
- **Optimistisches Schreiben (Fund NIEDRIG):** Lokaler Write **erst nach RPC-Erfolg** committen. Bei RPC-Fehler optimistischen Eintrag zurücknehmen + gezielten Einzel-Reload des `id` aus der View (nicht nur auf Watermark verlassen).

### Ehrliche Grenzen

- **>90 Tage offline → Vollimport.** Wer die App selten nutzt (bei Wickelplatz-App realistisch), lädt einmal alles neu. Bewusst akzeptiert.
- **`is_questionable` ist berechnet** (aus `place_stats`, nicht in der Tabelle) → ein reines Row-`updated_at` erfasst es nur, wenn Soft-Hide **materialisiert** wird (Flag-Schwelle setzt `hidden`-Spalte, dann greift der Trigger). **[ENTSCHEIDUNG: In v0.8.0 `is_questionable` NICHT ausblenden, sondern nur visuell abwerten (siehe Teil 3). Materialisierung von Soft-Hide (Trigger setzt `hidden` bei ≥5 aged flags) ist ein separater Task v0.8.1 — sonst wird der Moderations-Missbrauchsschutz durch den Cache neutralisiert. Für v0.8.0: Admin-Hide ist der Moderationspfad, questionable ist nur Badge.]**
- **Aktivitäts-Seitenkanal** über `updated_at` (s. o.) — akzeptiert, kein PII.
- **place_merge-Determinismus:** OSM gewinnt immer beim Dedup (stabil, ladeunabhängig) — siehe Teil 3.

---

## 3. Pin-Akkumulation

### Riverpod-Architektur

Kernprinzip (Design 3, korrigiert durch Funde): **UI liest nur aus dem Akkumulator; Akkumulation ist eine MENGE mit Reconciliation, kein append-only Monoid.**

```dart
class AccumulatedPlaces {
  const AccumulatedPlaces(this.byRef);
  final Map<String, ChangingPlace> byRef;   // keyed per placeRef — dedupliziert, ersetzt, entfernt
  List<ChangingPlace> get all => byRef.values.toList(growable: false);
}

class AccumulatedPlacesNotifier extends Notifier<AccumulatedPlaces> {
  // Reference-Counting: welche Tiles liefern welchen Ref? (Fund HOCH: LRU-Eviction darf
  // geteilte OSM-Nodes nicht global killen, solange ein lebendes Nachbar-Tile ihn braucht.)
  final Map<String, Set<GeoTile>> _refTiles = {};

  @override
  AccumulatedPlaces build() => const AccumulatedPlaces({}); // (Cache-Preload siehe Naht unten)

  /// Community global: SCOPE-RECONCILIATION statt nur mergen.
  /// Nach jedem Community-Fetch alle community/*-Refs ersetzen; nicht mehr gelieferte entfernen.
  void reconcileCommunity(List<ChangingPlace> community) {
    final next = Map<String, ChangingPlace>.of(state.byRef)
      ..removeWhere((k, _) => k.startsWith('community/'));
    for (final p in community) { next[p.placeRef] = p; }
    state = AccumulatedPlaces(next);
  }

  void mergeOsmTile(GeoTile tile, List<ChangingPlace> incoming) {
    final next = Map<String, ChangingPlace>.of(state.byRef);
    for (final p in incoming) {
      next[p.placeRef] = p;
      (_refTiles[p.placeRef] ??= {}).add(tile);
    }
    state = AccumulatedPlaces(next);
  }

  void evictTile(GeoTile tile) {           // LRU ruft das
    final next = Map<String, ChangingPlace>.of(state.byRef);
    _refTiles.forEach((ref, tiles) {
      tiles.remove(tile);
      if (tiles.isEmpty && ref.startsWith('node/')) next.remove(ref); // nur wenn KEIN Tile mehr hält
    });
    _refTiles.removeWhere((_, t) => t.isEmpty);
    state = AccumulatedPlaces(next);
  }

  void removeRef(String placeRef) {        // gezieltes Remove nach Admin-/Eigen-Delta
    if (!state.byRef.containsKey(placeRef)) return;
    final next = Map<String, ChangingPlace>.of(state.byRef)..remove(placeRef);
    _refTiles.remove(placeRef);
    state = AccumulatedPlaces(next);
  }
}
```

### Wichtige Korrekturen aus den Funden

- **Scope-Reconciliation (Fund KRITISCH):** Community wird global geladen → nach jedem Fetch die gesamte `community/*`-Teilmenge **ersetzen**, nicht nur mergen. So verschwinden gehidete/gelöschte Pins auch ohne Neustart. Mit Delta (Teil 2) liefern Tombstones die `deleted=true`-Refs → `removeRef`.
- **Reference-Counting statt Ownership (Fund HOCH):** z=12-Tiles überlappen an OSM-Nodes garantiert. Ein Ref wird erst entfernt, wenn **alle** liefernden Tiles evakuiert sind. Community-Pins (kein Tile) von der Tile-LRU ausgenommen.
- **Fetch-Lifecycle (Fund MITTEL State-nach-Dispose):** Fetches **nicht** fire-and-forget `.then`. Stattdessen über `ref.listen` an den Provider-Lifecycle binden; vor `state=` auf Disposal prüfen. Retry mit exponentiellem Backoff + Cap (kein Retry-Sturm bei Overpass-429). `_loadedTiles`-Zustand aus dem Provider-Cache ableiten, nicht als transientes Feld (übersteht Rebuild).
- **Dedup deterministisch (Fund MITTEL):** OSM gewinnt **immer**, ladeunabhängig. Der angezeigte kanonische Ref ist stabil → Rating/Detail-Sheet hängen konsistent am selben Ref. `place_merge_test.dart` + `map_screen_test.dart` mitziehen.
- **questionable-Badge:** `is_questionable` beim Füllen für sichtbare Refs via `stats_for` (Cap ≤200) batchen und Marker visuell abwerten (nicht ausblenden). Rendering-Entscheidung in `_visibleSubset`.

### Memory-Obergrenze

Zwei Mechanismen kombiniert:
- **A) Viewport-Culling + Clustering beim Rendern.** `_buildMarkers`/`_visibleSubset` gibt nur Pins im aktuellen Viewport (+ kleiner Rand) an den `MarkerLayer`. „Nie verschwinden beim Zoom" = **innerhalb des Viewports stabil**, nicht „alle je gesehenen gleichzeitig gerendert" (Fund MITTEL OOM).
- **B) LRU-Deckel:** z. B. **max 400 Tiles / ~50k Pins**. Ältestes nicht-sichtbares Tile evakuieren (`evictTile`). Für typische Nutzung (eine Stadt) nie erreicht.

### Clustering-Package — Blocker (Fund MITTEL Package-Inkompatibilität)

`flutter_map: 6.1.0` ist gepinnt. `flutter_map_marker_cluster`/`supercluster` verlangen flutter_map 7.x/8.x. → **[ENTSCHEIDUNG: Zwei Optionen. (A) flutter_map auf die vom Cluster-Paket geforderte Major-Version anheben — eigener getesteter Schritt VOR der Akkumulator-Arbeit, bricht `camera.visibleBounds`/`onPositionChanged`-APIs im map_screen. (B) Eigenes Grid-Aggregations-Clustering im `_visibleSubset` ohne Zusatzpaket, bei flutter_map 6.1.0 bleiben. Empfehlung: (B) für v0.8.0 — kleinerer Blast-Radius; flutter_map-Upgrade als eigenes v0.8.1-Ticket. Auftraggeber entscheidet.]**

---

## 4. Umsetzungsreihenfolge (kleine releasebare Schritte)

Jeder Schritt ist einzeln testbar und releasebar.

**R1 — Server-Fundament (Migration 0007, ohne App-Änderung).**
`updated_at` + Trigger, Tombstone-Tabelle + DELETE-Trigger + Visibility-Trigger, `community_places_delta`-RPC. Bestehende App läuft unverändert weiter (RPC wird noch nicht aufgerufen). *Release: Backend-only.*

**R2 — Admin-Server (Migration 0006).**
`admins`-Tabelle, `is_admin()`, RPC-Erweiterung (COALESCE + OR-Pfad), `admin_list_places`, `tg_orphan_places`-Trigger. System-User + Owner-Admin im Dashboard anlegen. Noch keine App-UI. *Release: Backend-only, Admin per SQL testbar.*

**R3 — Admin-App-UI.**
`AuthRepository`, `isAdminProvider`, versteckter Login-Screen, Edit/Delete-Buttons auf fremden Pins nur bei `isAdmin`, Fehlercode-Mapping erweitern. *Release: v0.8.0-alpha, Admin funktioniert, Cache noch nicht.*

**R4 — drift einführen + Community-Cache.**
Packages, `AppDatabase`, `CommunityPlaceCache`-DAO, `CommunitySyncService` (global, serialisiert). `mergedPlacesProvider` → Stream aus Cache + Background-`sync()`. Preload aus Cache beim Start. *Release: Offline-Start + Delta funktioniert.*

**R5 — Akkumulator + Reference-Counting.**
`AccumulatedPlacesNotifier`, Scope-Reconciliation Community, Tile-Merge OSM mit Ref-Counting, `removeRef` bei Delta-Deletes. map_screen liest nur Akkumulator. *Release: Pins verschwinden nicht mehr bei Bewegung.*

**R6 — OSM-Kachel-Cache + TTL.**
`OverpassCache`-DAO, `OsmSyncService.ensureTiles`, atomare delete+insert pro Kachel, 429-Backoff. *Release: Offline-Karte für besuchte Gegenden.*

**R7 — Clustering + Memory-Deckel.**
Viewport-Culling, Clustering (Option A oder B aus Entscheidung), LRU-Eviction, questionable-Badge. *Release: v0.8.0 final.*

---

## 5. Was der Auftraggeber in Supabase ausführen muss

**Reihenfolge strikt einhalten** (FK-Henne-Ei):

1. **Dashboard → Auth:** System-Auth-User mit **exakt** UUID `00000000-0000-0000-0000-0000000000AD` anlegen (kein nutzbares Passwort, loggt sich nie ein, ist kein Admin — nur FK-Anker). *[ENTSCHEIDUNG UUID bestätigen.]*
2. **Dashboard → Auth:** Owner-Admin-Account (Labushuya) mit echter E-Mail + Passwort anlegen, **E-Mail-Confirm im Dashboard manuell bestätigen** (kein E-Mail-Provider-Setup nötig).
3. **Migration `0006_admin.sql`** ausführen (Admin-Tabelle, is_admin, RPC-Erweiterung, admin_list_places, orphan-Trigger, Selbsttest-Assert).
4. **Dashboard → SQL:** Owner in Admins eintragen:
   ```sql
   insert into public.admins (user_id, note)
   select id, 'owner' from auth.users where email = '<owner-email>';
   ```
5. **Migration `0007_delta_sync.sql`** ausführen (updated_at, Trigger, Tombstones, Delta-RPC).
6. **Optional — Cleanup-Job:** Tombstones > 90 Tage löschen (pg_cron oder Edge Function). Muss dieselbe Retention (90) kennen wie die RPC (`retention_days`). Ohne Job wächst die Tombstone-Tabelle langsam — bei dieser Datenmenge unkritisch, aber sauberer mit Job.

**Verifikation nach Migration:**
- `select public.is_admin('<owner-uuid>');` → `true`; anon-JWT gegen `admin_list_places` → `admin_required`.
- Owner-Pin per RPC editieren, `select updated_at from community_places where id=...` → frisch.
- Pin löschen → Zeile in `community_place_tombstones` vorhanden.
- Pin `hidden=true` setzen → Tombstone erscheint; `hidden=false` → Tombstone weg.

---

## Offene Entscheidungen (gesammelt)

- **[ENTSCHEIDUNG]** COALESCE-Semantik im update-RPC: Feld-Leeren nicht mehr möglich (akzeptabel für Wickelplätze).
- **[ENTSCHEIDUNG]** SYSTEM_UUID = `00000000-0000-0000-0000-0000000000AD` — Auftraggeber bestätigt/legt an.
- **[ENTSCHEIDUNG]** Admin nutzt dediziertes Gerät/Profil (anon-Historie-Verlust beim Session-Wechsel als Constraint akzeptiert; kein linkIdentity).
- **[ENTSCHEIDUNG]** `is_questionable` in v0.8.0 nur Badge, kein Ausblenden; Soft-Hide-Materialisierung → v0.8.1.
- **[ENTSCHEIDUNG]** `updated_at` volle Auflösung im Delta (kein PII); `date_trunc` nur falls Aktivitäts-Seitenkanal stört.
- **[ENTSCHEIDUNG]** Clustering: eigenes Grid-Clustering bei flutter_map 6.1.0 (Empfehlung) vs. flutter_map-Major-Upgrade (v0.8.1-Ticket).

Kritischer Pfad: **R1 (Server-Fundament) blockiert alles bei Cache/Akkumulation** — ohne `updated_at` + Tombstones ist Delta prinzipiell inkohärent. Zuerst R1+R2 (Backend), dann App-Schritte.
# Wickelfinder — Handover-Dokument (Oktober 2026)

Dieses Dokument ermöglicht einer neuen Claude-Session (Opus 5.5), nahtlos
weiterzumachen. Es dokumentiert **verifizierten Ist-Zustand** — nicht Absichten.

---

## 1. Projekt-Übersicht

**App:** Wickelfinder — findet Baby-Wickelplätze in der Nähe.  
**Repo:** `github.com/Labushuya/wickelfinder` (public)  
**Package-ID:** `de.wickelfinder.wickelfinder`  
**Stack:** Flutter (Android-First) + Supabase (Postgres, RLS, Edge Functions) + OpenStreetMap  
**Auftraggeber:** nicht-technisch, testet per In-App-Updater auf Honor VER_N49 (Serial `A2VQ024108002982`)  
**Arbeitsweise:** vollständig autark (Planung → Code → Release); Auftraggeber bestätigt am Gerät

---

## 2. Aktueller Release-Stand (verifiziert)

| Version | Status | Inhalt |
|---------|--------|--------|
| **v0.24.6** | ✅ **Final, aktuell** | Favoriten-Race-Fix, myRatings-Fehler sichtbar, Regressions-Tests |
| v0.24.5 | Final | Robustheit: null-Koordinaten, PH-Zeiten, Foto-cacheKey, DSGVO-Logs |
| v0.24.4 | Final | Filter-Button lesbar (Badge-Ansatz) |
| v0.24.3 | Final | Filter-Zähler korrekt (alle Kategorien) |
| v0.24.2 | Final | Filter: Draft-then-Apply (Übernehmen erzwingend) |
| v0.24.0 | Final | „Jetzt geöffnet"-Status + Filter |
| v0.23.0 | Final | Karten-Filter (Ortstyp/Ausstattung/Kosten/Quelle) |
| v0.22.0 | Final | Favoriten (lokal, kein Login) |
| v0.21.x | Final | UX-Entschlackung + OSM-Label-Fixes |
| v0.20.0 | Final | Öffnungszeiten-Anzeige |
| v0.19.0 | Final | Admin-Dashboard |

**`pubspec.yaml` version:** `0.24.6+56`  
**Build-Nummer:** 56  
**Flutter-Pin:** `>=3.35.0`; Dart SDK-Floor: `>=3.9.0`

---

## 3. Architektur & Tech-Stack

### Flutter-Seite
- **State:** Riverpod (Notifier/FutureProvider/family)
- **Karte:** flutter_map 6.1.0 + OSM-Tiles, AccumulatedPlacesNotifier (in-memory, LRU-Cap 4000)
- **Feature-First:** `lib/features/{account,admin,community,favorites,map,privacy,search,updater}/`
- **Kern-Patterns:**
  - `SECURITY DEFINER`-RPCs für alle Schreibpfade (kein direkter Client-DB-Zugriff)
  - `CommunityException` mit `_extractCode` (Server-Fehlercode → deutsches `userMessage`)
  - `accumulatedPlacesProvider` — einzige Quelle für Kartenpins (nie im Akkumulator filtern!)
  - `mapFilterProvider` — Sitzungs-Zustand, nur `apply()` schreibt in die Karte
  - `favoritesProvider` — lokal via SharedPreferences, `_loaded`-Future verhindert Race

### Supabase-Seite
- **Projekt-ID:** `wnehmpzkpmnespgptrur`, Region EU/Frankfurt
- **Supabase-URL:** `https://wnehmpzkpmnespgptrur.supabase.co`
- **Bucket:** `place-photos` (privat, 256KB-Limit, jpeg/webp)
- **PostGIS-Schema:** `public` (nicht `extensions`!) → in search_path=''-Funktionen `public.ST_*` verwenden
- **Migrationen alle ausgeführt:** 0001–0023

### CI/CD
- **GitHub Actions:** `.github/workflows/ci.yml` (Format → Analyze → Tests → Brand) + `release.yml` (bei Tag `v*`)
- **Release-Signierung:** Keystore aus Secret `ANDROID_KEYSTORE_BASE64`, `key.properties` wird in CI injiziert
- **Kein lokales Flutter/Analyzer** — nur `dart format` lokal via `/c/tools/dart-3.9.2/dart-sdk/bin/dart.exe`

---

## 4. Bekannte Analyzer-Fallen (CI-fatal, kein lokales Flutter)

Diese Regeln kosten sonst CI-Runden:

| Regel | Konkret |
|-------|---------|
| `strict_raw_type` | Bare `Map`/`Set`/`List` ohne Typargumente → `<String, dynamic>{}` etc. |
| `use_build_context_synchronously` | Nach jedem `await` in ConsumerWidget-Methoden: `if (!context.mounted) return;` |
| `prefer_const_constructors` | Alle const-fähigen Konstruktoren mit `const` |
| `curly_braces_in_flow_control_structures` | Jedes `if` braucht `{}` |
| `unused_import` | Imports die nur via Typ-Inferenz „genutzt" werden, zählen nicht |

---

## 5. Migrations-Übersicht (alle ausgeführt)

```
0001 Schema + RLS + PostGIS
0002 Ratings-RPC (submit_rating, stats_for, Bayesian-Mean)
0003 Community-Places (add_community_place, public View)
0004 Tags erweitert (Enum-Werte)
0005 Edit/Delete eigene Plätze (update/delete_community_place)
0006 Admin (admins-Tabelle, is_admin(), admin_list_places)
0007 Delta-Sync (community_places_delta, updated_at, Tombstones)
0008 Bayesian-Dämpfung gelockert (m=1, 1h Zeitgewicht)
0009 Tags-Constraint-Fix
0010 Tag-Aggregat in place_stats (tag_counts jsonb)
0011 Fee-Mode + Zugangs-Tags + community_places.fee_mode
0012 admin_list_places ohne Geo-Filter (Bug-Fix)
0013 DSGVO export_my_data + delete_my_data
0014 Admin-Selbstlösch-Schutz
0015 submit_flag + confirm_present RPCs
0016 admin_place_feedback RPC
0017 Rating-Koordinaten (lat/lon in ratings)
0018 Flag/Confirm gegenseitiger Ausschluss
0019 place_photos + Storage-Bucket + Policies
0020 Foto-RPCs (register_photo, photos_for, admin_pending_photos etc.)
0021 DSGVO-Fotos (export + delete_my_data)
0022 Multi-Foto (bis 3/Nutzer/Platz, Constraint gedroppt)
0023 admin_delete_photo + admin_dismiss_report
```

**Wichtig:** Migration 0024+ (falls zukünftig nötig) muss der Auftraggeber im Supabase SQL-Editor ausführen.

---

## 6. Edge Function

**`supabase/functions/delete-account/index.ts`**  
DSGVO Art. 17 — vollständige Konto-Löschung inkl. Storage-Sweep (paginiert, 100er-Chunks).

**⚠️ NOCH NICHT DEPLOYED** — der verbesserte Storage-Sweep (v0.24.5, Pagination) liegt nur lokal im Repo. Der Auftraggeber muss deployen:

```bash
# Option A: Supabase CLI (falls installiert)
supabase functions deploy delete-account --project-ref wnehmpzkpmnespgptrur

# Option B: Supabase Dashboard
# → Edge Functions → delete-account → Code aus
# supabase/functions/delete-account/index.ts einfügen → Deploy
```

---

## 7. Lokale Dateien die gesichert werden müssen

### 🔑 Release-Keystore (KRITISCH)
```
C:\Users\user\wickelfinder-release.jks
```
- Alias: `wickelfinder`
- SHA-256: `979a801956ee36936bbb9d1fdff9dab7076545aaf37fedef62b9e5b3dc80cb5c`
- **Verlust = keine signierten Updates mehr möglich für de.wickelfinder.wickelfinder**
- Empfehlung: auf mindestens zwei externen Speichermedien (USB-Stick + Cloud-Vault)

Das Passwort steht **nicht** in diesem Dokument — es liegt in den GitHub-Secrets:
- `ANDROID_KEYSTORE_BASE64` (Base64-kodierter Keystore)
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS` = `wickelfinder`
- `ANDROID_KEY_PASSWORD`

**So Keystore-Backup erstellen:**
```bash
# Base64 exportieren (für GitHub Secrets)
base64 -w 0 "C:/Users/user/wickelfinder-release.jks" > wickelfinder-keystore.b64
# → Inhalt von wickelfinder-keystore.b64 = Wert für ANDROID_KEYSTORE_BASE64
```

### Lokales Dart SDK (für dart format)
```
/c/tools/dart-3.9.2/dart-sdk/bin/dart.exe
```
- Nur für `dart format lib test` — CI-identische Formatierung
- Kein Flutter/Analyzer lokal

### GitHub Secrets (vollständige Liste)
Im Repo unter Settings → Secrets → Actions:
```
SUPABASE_URL             = https://wnehmpzkpmnespgptrur.supabase.co
SUPABASE_ANON_KEY        = (anon/public key)
ANDROID_KEYSTORE_BASE64  = (Base64 des .jks)
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS        = wickelfinder
ANDROID_KEY_PASSWORD
```

---

## 8. Nicht-Verhandelbare Constraints

- **€0 Normalbetrieb** — kein bezahlter Dienst, Free-Tier Supabase
- **Kein Scraping** — nur OSM/ODbL mit Attribution; nie fremde Apps scrapen
- **DSGVO** — EXIF/GPS bei Foto-Upload entfernt (`keepExif:false`), anonyme Auth, kein Tracking
- **Analyzer-Gates** — `flutter analyze --fatal-infos` in CI, alle Infos brechen den Build
- **Keine Secrets im Code** — alles via GitHub Secrets / Supabase Function Secrets
- **Plan vor Code** — bei Entscheidungen erst Optionen+Empfehlung vorlegen, dann handeln
- **Ehrlichkeit** — nie behaupten etwas ist fertig/funktional, wenn nicht auf Gerät bestätigt

---

## 9. Offene Backlog-Punkte (nach Priorität)

### Aktiv offen (ausstehende Kunden-Aktion)
1. **Edge Function deployen** (DSGVO-Pflicht, s. Abschnitt 6)
2. **Mail-Test** — Ende-zu-Ende-Registrierungsmail noch nicht vollständig getestet

### Nächste Features (vom Kunden priorisiert)
Diese waren die ursprünglich geplante Reihenfolge, kann sich geändert haben:

| # | Feature | Aufwand | Hinweis |
|---|---------|---------|---------|
| - | Filter & Ausstattung (v0.23) | ✅ fertig | |
| - | Öffnungszeiten / Jetzt geöffnet | ✅ fertig | Feiertage bewusst ignoriert |
| - | Favoriten | ✅ fertig | lokal, kein Sync |
| TBD | „Nur mit Foto"-Filter | mittel | Braucht Server-Aggregat (photo_count in stats_for); derzeit kein Bulk-Signal |
| TBD | „Nur bestätigte"-Filter | klein | Bulk-Stats-Provider auf vorhandenem stats_for aufbauen |
| TBD | Favoriten-Sync | mittel | Server-Tabelle + RLS + RPC, Login nötig |
| TBD | EXIF-Verify/Fallback | groß | Riskant, nicht priorisiert |
| TBD | AccumulatedPlaces-Tests | klein | Regr.-Tests fehlen noch für Dedup-Genauigkeit im Edge-Case |

### Aus Audit zurückgestellt (niedrig-prior)
- Viewport-Culling (Perf, nur bei sehr vielen Pins relevant)
- Cache-Reserialize-Optimierung (Perf, vernachlässigbar)
- Übernacht-Zeitfenster in openStateAt (z.B. `22:00-02:00` → unknown, akzeptiert)

---

## 10. Test-Infrastruktur

**22 Test-Dateien** in `test/unit/` + `test/widget/`:

Neue Tests seit v0.19 (alle grün in CI):
- `accumulated_places_test.dart` — Dedup/Cap/Reconcile/No-Op-Guard
- `changing_place_location_hint_test.dart` — Enum-Übersetzung + Multi-Value
- `favorite_place_test.dart` — toJson/fromJson round-trip
- `favorites_controller_test.dart` — Toggle/Ordering/Race/Corrupt-Recovery
- `map_filter_test.dart` — matches() je Kriterium, activeCount, onlyOpenNow
- `open_report_test.dart` — OpenReport.fromRow
- `opening_hours_format_test.dart` — Formatter gängige Muster + Rohtext-Fallback
- `opening_hours_status_test.dart` — openStateAt inkl. PH/SH-Toleranz
- `pending_photo_test.dart` — PendingPhoto.fromRow
- `update_repository_test.dart` — SemVer-Komparator (17k Paare)

**Widget-Test:** `test/widget/map_screen_test.dart` (öffnet Sheet, klappt „Mehr Details" auf)

---

## 11. Wie neue Features gebaut werden

### Workflow
1. **Vorab:** Ziel/Nutzen + Feasibility + Optionen mit Empfehlung → Kunden-Freigabe abwarten
2. **Backend:** SQL-Migration in `supabase/migrations/000X_*.sql`; Kunden muss im SQL-Editor ausführen
3. **Client:** Domain → Repository → Provider → UI; RPC-only (kein direkter Table-Zugriff)
4. **Format:** `dart.exe format lib test` (lokales Dart 3.9.2)
5. **Commit** → Push → CI grün abwarten (Analyzer + Tests)
6. **Release:** Tag `vX.Y.Z-beta.1` → Release-Build → Kunden-Test → Tag `vX.Y.Z` final

### Häufige Fehler (die CI-Runden kosteten)
- `strict_raw_type` nicht beachtet → Map/Set/List ohne Typargumente
- `context.mounted` vergessen nach `await` in Widget-Methoden
- `late final Future _loaded` vergessen bei async-init in Notifier
- OSM signing/unsigned Typen: `(row['lat'] as num?)?.toDouble()` (nullable!)
- `_communityRowToPlace()` bei null-Koordinaten → Zeile überspringen, nicht Exception

---

## 12. Admin-Zugang

- Admin = normales E-Mail-Konto + Eintrag in `admins`-Tabelle
- Aktuell eingetragene Admins: d3v@c0demon.de (Hauptentwickler/Auftraggeber) + dessen Ehefrau
- Neuen Admin eintragen:
  ```sql
  insert into public.admins (user_id, note)
  select id, 'Beschreibung'
  from auth.users
  where email = 'neue-email@example.com';
  ```
- Admin-Konto kann sich **nicht selbst löschen** (Server-Guard in Migration 0014 + Edge Function)

---

## 13. SMTP / Mail-Setup

- **Resend** als SMTP-Provider in Supabase
- Sender-E-Mail: `no-reply@no-reply.c0demon.de` (verifizierte Subdomain, NICHT `d3v@c0demon.de`)
- DNS auf Cloudflare (nicht Strato — Strato erzwingt A-Record für MX-Ziele)
- Mail-Templates nutzen `{{ .Token }}` (Code), NICHT `{{ .ConfirmationURL }}` (würde auf localhost zeigen)
- OTP-Länge in diesem Projekt: 8-stellig

---

## 14. Gerät & ADB

- **Gerät:** Honor VER_N49, Android 16, Serial `A2VQ024108002982`
- **ADB:** `/c/Users/user/Android/Sdk/platform-tools/adb.exe`
- USB-Debugging muss aktiv sein
- `screencap` liefert auf diesem Gerät schwarze Bilder (DRM/HW-Overlay) → visuelle Prüfung per Kunden-Feedback
- Git-Bash-Pfad-Konvertierung: `MSYS_NO_PATHCONV=1` vor adb-Befehlen mit Gerätepfaden

---

*Generiert: 2026-10-14 | Repo: github.com/Labushuya/wickelfinder | Version beim Handover: v0.24.6*

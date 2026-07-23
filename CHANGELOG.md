# Changelog

Alle nennenswerten Änderungen an Wickelfinder. Format lose angelehnt an
[Keep a Changelog](https://keepachangelog.com/de/), Versionierung nach SemVer.

## [0.17.1] — 2026-07-23

### Changed
- **Konto ist jetzt vollständig ins 3-Punkt-Menü gewandert:** oben erscheint
  „Anmelden / Registrieren" (abgemeldet) bzw. deine E-Mail → Abmelden
  (angemeldet). Der Konto-Bereich wurde dafür aus den Einstellungen entfernt
  (kein Doppel mehr).

## [0.17.0] — 2026-07-23

### Added
- **Fotos zu Wickelplätzen:** Angemeldete Nutzer können ein Foto je Platz
  hinzufügen (Kamera oder Galerie). Das Foto ist zunächst **nur für dich
  sichtbar** („wartet auf Freigabe") und wird erst **nach Admin-Freigabe** für
  alle öffentlich. Fotos lassen sich in der Vollbildansicht **melden**.
  Metadaten (GPS/Gerät/Zeit) werden vor dem Upload **entfernt** (Datenschutz),
  Bilder werden stark komprimiert.
- **Admin: „Fotos prüfen"** — wartende Fotos mit Vorschau freigeben oder ablehnen.
- **Konto/Anmelden** jetzt direkt im Menü erreichbar.

## [0.16.0] — 2026-07-23

### Changed
- **„Nicht vorhanden" / „Doch vorhanden" zeigen jetzt deinen eigenen Zustand:**
  Die Buttons markieren sichtbar „Gemeldet ✓" bzw. „Bestätigt ✓", wenn du bereits
  abgestimmt hast; die Bestätigungsmeldung ist zustandsabhängig (neu / geändert /
  bereits bestätigt). Es zählt weiterhin genau eine Stimme pro Person.

### Fixed
- **Melden und Bestätigen schließen sich pro Person gegenseitig aus:** Wer „nicht
  vorhanden" meldet, dessen frühere „vorhanden"-Bestätigung wird entfernt (und
  umgekehrt) — kein widersprüchlicher Doppel-Zustand mehr.

## [0.15.1] — 2026-07-22

### Fixed
- **Alle Konto-Fehlermeldungen jetzt auf Deutsch** (Login, Registrierung,
  Passwort-Reset, Admin-Login): z.B. „E-Mail oder Passwort ist falsch",
  „Das neue Passwort muss sich vom alten unterscheiden" statt englischer
  Roh-Texte.
- **„Meine Bewertungen" bleibt nicht mehr leer:** Die Liste funktioniert jetzt
  auch, wenn die Koordinaten-Spalten fehlen (Fallback ohne Karten-Sprung), und
  frisch abgegebene Bewertungen erscheinen sofort. Neue Bewertungen speichern
  ihre Koordinaten mit, damit der Rücksprung zum Platz funktioniert.

## [0.15.0] — 2026-07-20

### Added
- **„Meine Bewertungen"** im Menü: alle selbst bewerteten Wickelplätze auf einen
  Blick, Bewertung direkt aus der Liste ändern, per Karten-Symbol zum Platz
  zurückspringen. Bewertungen speichern dafür jetzt die Koordinaten mit, sodass
  auch namenlose OpenStreetMap-Plätze wiederauffindbar bleiben (i-Hinweis bei
  Einträgen ohne Namen).

### Fixed
- **Passwort-Reset:** Der Code bleibt nach einem fehlgeschlagenen Versuch (z.B.
  neues = altes Passwort) gültig — kein „Token abgelaufen" mehr; nur das Passwort
  muss erneut eingegeben werden.
- **Nach Registrierung/Bestätigung** landet man nicht mehr fälschlich wieder auf
  der Anmelde-Maske, sondern direkt eingeloggt zurück im Ausgangs-Screen.

## [0.14.1] — 2026-07-19

### Added
- **„Pins in der Nähe" — Ort/PLZ-Suche:** Über der Liste kann jetzt ein Ort,
  eine PLZ oder Adresse gesucht werden (OpenStreetMap-Nominatim). Der gewählte
  Ort wird zum Bezugspunkt — die Liste sortiert dann nach Entfernung dorthin.
  „Mein Standort" schaltet zurück auf die GPS-Position.

## [0.14.0] — 2026-07-19

### Added
- **„Pins in der Nähe"** im Menü: alle Wickelplätze (Community + OpenStreetMap)
  nach Entfernung zum aktuellen Standort sortiert, mit Distanz je Eintrag; Tippen
  fliegt zur Stelle. Ohne Standortfreigabe unsortierte Liste.
- **Admin-Meldungsübersicht** im Pin-Detail: rohe Zähler pro Grund (nicht
  vorhanden / geschlossen / falscher Ort) plus Bestätigungen und Bewertungen —
  nur für angemeldete Admins sichtbar.

### Fixed
- **Bewerten-Button** zeigt nach der ersten Bewertung korrekt „Bewertung ändern"
  (statt weiter „Bewerten") und öffnet den Dialog vorbefüllt. Pro Person zählt
  weiterhin **genau eine** Bewertung — das war serverseitig immer schon so
  erzwungen; nur die Beschriftung wirkte irreführend.

## [0.13.0] — 2026-07-19

### Added
- **Existenz-Feedback:** Ein Platz kann als „nicht vorhanden", „dauerhaft
  geschlossen" oder „falscher Ort" gemeldet und umgekehrt als „doch vorhanden"
  bestätigt werden — anonym, ohne Konto (wie Bewerten).
- **Getrennte Behandlung:** „nicht vorhanden"/„geschlossen" führen ab genügend
  unabhängigen, gereiften Meldungen zu „Existenz fraglich" (Soft-Hide). „Falscher
  Ort" zeigt stattdessen den Hinweis „Standort möglicherweise ungenau" — der Platz
  bleibt sichtbar, wird nicht ausgeblendet.
- Detail-Sheet zeigt dezente Zähler (Meldungen / Bestätigungen).

## [0.12.3] — 2026-07-19

### Fixed
- **„Code erneut senden" jetzt überall im Bestätigungs-Schritt** — nicht nur im
  Nachtrag-Weg. Kommt der Code bei der frischen Registrierung nicht an, lässt er
  sich direkt neu anfordern (wählt intern den passenden Typ: Neu-Registrierung
  bzw. E-Mail-Wechsel beim Identity-Linking).

## [0.12.2] — 2026-07-19

### Fixed
- **In-App-Updater erkennt Beta-Updates wieder:** Der Versionsvergleich las
  `-beta.N`-Suffixe falsch (z.B. `0.12.1-beta.1` wurde als `0.12.0` interpretiert),
  sodass Updates innerhalb derselben MINOR-Version fälschlich als „bereits aktuell"
  gemeldet wurden. Jetzt vollständiger SemVer-Precedence-Vergleich (Prerelease-
  Reihenfolge, numerische Beta-Zähler `beta.2 < beta.10`, Build-Metadaten ignoriert).
  Abgesichert durch Unit-Tests über die reale Release-Historie.

## [0.12.1] — 2026-07-19

### Fixed
- **Bestätigungscode nach Abbruch nachtragbar:** Wird der Registrierungs-Flow
  unterbrochen (z.B. versehentliches Zurück), lässt sich der bereits versendete
  Code jetzt über „Bestätigungscode aus E-Mail eingeben" auf dem Anmelden-Screen
  nachtragen — ohne komplett neu zu registrieren. Inklusive „Code erneut senden".
- **Texte an tatsächliche Code-Länge angepasst** („Code" statt „6-stellig"),
  passt damit unabhängig von der in Supabase eingestellten OTP-Länge.

### Hinweis
- Konten, die während der Umstellung der Mailvorlage (Link → Code) angelegt
  wurden, konnten sich einmalig abweichend verhalten (nachträgliche Aktivierung).
  Bei reiner Code-Bestätigung tritt das nicht mehr auf.

## [0.12.0] — 2026-07-16

### Added
- **Optionales Nutzerkonto** (E-Mail + Passwort): Registrierung mit
  Bestätigungscode, Login, Logout, Passwort-Reset, Konto-Löschung.
- **Identity-Linking:** Wer zuerst anonym bewertet/meldet und sich dann
  registriert, behält seine Beiträge (gleiche Kennung).
- Konto-Bereich in den Einstellungen (Anmelden/Registrieren bzw. „Angemeldet
  als …" + Abmelden).

### Changed
- **Pins hinzufügen/verwalten und „Meine Pins" erfordern jetzt ein Konto.**
  Karte, Suche, Standort sowie **Bewerten/Melden/Bestätigen bleiben ohne Konto**
  möglich (anonyme Kennung als Fallback).

### Security
- **Admin-Konten sind vor Selbstlöschung geschützt** (DB-Guard + Edge-Function-
  Check): `delete_my_data` bricht für Admins mit `admin_cannot_selfdelete` ab.

## [0.11.0] — 2026-07-15

### Added
- **DSGVO:** Datenexport (vollständiges JSON, Art. 15/20), vollständige
  Löschung inkl. Konto (Art. 17, via Edge Function), Datenschutzerklärung
  (in-App + `PRIVACY.md`).

## [0.10.1] — 2026-07-15

### Fixed
- **Fester Release-Signaturschlüssel** (GitHub-Secrets): Updates installieren
  ab jetzt „drüber", ohne Deinstallieren/Datenverlust.

## [0.10.0] — 2026-07-15

### Added
- Dreiwertige Kosten (kostenlos / bedingt / kostenpflichtig) + Zugangs-Tags.
- Community-Konsens mit Vertrauens-Badge und Autor-Hinweis.
- „Alle Pins [Admin]" + lokale Suche in Pin-Listen.

### Changed
- Dark-Karte als farberhaltender Filter; Pins bleiben bei Rotation aufrecht.

## Frühere Versionen

0.1.0–0.9.0: Kartengrundlage (OpenStreetMap), Community-Bewertungen,
eigene Pins, Offline-Cache, Theme (hell/dunkel), In-App-Updater, Admin-Rechte.
Siehe GitHub-Releases für Details.

# Changelog

Alle nennenswerten Änderungen an Wickelfinder. Format lose angelehnt an
[Keep a Changelog](https://keepachangelog.com/de/), Versionierung nach SemVer.

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

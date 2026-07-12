<p align="center">
  <img src="brand/render/preview.png" alt="Wickelfinder Logo" width="160" height="160">
</p>

# 🍼 Wickelfinder

**Finde schnell Wickelplätze in deiner Nähe – community-gepflegt, werbefrei, Open Source.**

[![CI](https://github.com/Labushuya/wickelfinder/actions/workflows/ci.yml/badge.svg)](https://github.com/Labushuya/wickelfinder/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Made with Flutter](https://img.shields.io/badge/Made%20with-Flutter-02569B?logo=flutter)](https://flutter.dev)

Wickelfinder hilft Eltern kleiner Kinder, unterwegs schnell einen Wickelplatz
zu finden. Die App zeigt Wickeltische auf einer Karte, Nutzer können neue
Plätze melden, bewerten und gegenseitig verifizieren.

---

## ✨ Features

- 🗺️ **Karte** mit Wickelplätzen in der Umgebung (OpenStreetMap)
- 📍 **Standortbasierte Suche** – finde den nächsten Wickeltisch
- ♿ **Details** zu Barrierefreiheit, Kosten und Lage
- ➕ **Community** *(geplant)*: Plätze hinzufügen, bewerten, verifizieren
- 🔒 **Datensparsam**: keine Tracker, anonyme Nutzung, Standort bleibt on-device

## 📥 Installation

Die neueste APK gibt es unter **[Releases](https://github.com/Labushuya/wickelfinder/releases)**.
APK herunterladen, auf dem Android-Gerät öffnen und installieren (Installation
aus unbekannten Quellen ggf. in den Einstellungen erlauben).

## 🏗️ Architektur

| Ebene | Technologie | Zweck |
|---|---|---|
| Frontend | Flutter (Dart) | Android-First, iOS/Web-Option offen |
| Karte | flutter_map + OSM-Tiles | Kartendarstellung ohne API-Key |
| Basisdaten | OpenStreetMap via Overpass API | `changing_table=yes`, read-only |
| Community *(geplant)* | Supabase (Postgres + Auth) | Ratings, Verifikation, Auto-Removal |
| CI/CD | GitHub Actions | Build, Test, APK-Release (SemVer) |

Feature-First Clean Architecture:

```
lib/
├── core/            # Theme, geteilte Infrastruktur
└── features/
    └── map/
        ├── domain/       # Modelle (ChangingPlace)
        ├── data/         # Overpass-Repository
        └── presentation/ # Riverpod-State, Screens, Widgets
```

## 🧪 Entwicklung

Voraussetzung: [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.22.

```bash
flutter pub get          # Abhängigkeiten
flutter analyze          # Statische Analyse
flutter test             # Unit- & Widget-Tests
flutter run              # App im Emulator/Gerät starten
```

Builds und Releases laufen automatisiert in der Cloud (GitHub Actions) –
eine lokale Android-Toolchain ist zum Mitentwickeln nicht zwingend nötig.

## 🚀 Release-Prozess (SemVer)

Ein neues Release entsteht durch einen Git-Tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Die `release.yml`-Pipeline testet, baut die APK und veröffentlicht sie
automatisch unter Releases.

## 📄 Datenschutz

Siehe [PRIVACY.md](PRIVACY.md). Kurz: keine Tracker, keine Werbung, anonyme
Nutzung, Standortdaten verlassen das Gerät nicht.

## 🤝 Mitmachen

Beiträge willkommen – siehe [CONTRIBUTING.md](CONTRIBUTING.md).

## ⚖️ Lizenz & Attribution

Code steht unter der [MIT-Lizenz](LICENSE).

Kartendaten © **OpenStreetMap-Mitwirkende**, lizenziert unter der
[Open Database License (ODbL)](https://www.openstreetmap.org/copyright).

# Beitragen zu Wickelfinder

Danke für dein Interesse! Beiträge jeder Art sind willkommen – Code, Bug-Reports,
Ideen oder Verbesserungen an der Dokumentation.

## Entwicklungsumgebung

1. [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.22 installieren
2. Repo forken und klonen
3. Abhängigkeiten: `flutter pub get`

## Vor jedem Pull Request

Diese drei Gates müssen grün sein (sie laufen auch in der CI):

```bash
dart format .                            # Formatierung
flutter analyze --fatal-infos            # Statische Analyse
flutter test                             # Tests
```

## Commit-Konventionen

Wir nutzen [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` neue Funktion
- `fix:` Bugfix
- `docs:` Dokumentation
- `test:` Tests
- `refactor:` Umbau ohne Verhaltensänderung
- `ci:` Pipeline/Tooling

## Branch- & PR-Workflow

- Branch von `main` abzweigen (`feat/kurzbeschreibung`)
- Kleine, fokussierte PRs bevorzugt
- PR-Beschreibung: was, warum, wie getestet

## Architektur-Prinzipien

- **Feature-First**: neue Features unter `lib/features/<name>/` mit
  `domain/`, `data/`, `presentation/`
- **Testbarkeit**: Logik von UI trennen; pure Funktionen bevorzugen
- **Keine Secrets im Code**: Keys über CI-Secrets / Umgebungsvariablen

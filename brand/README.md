# Wickelfinder — Brand-Assets

Logo, App-Icon und Farbsystem der App. **Quelle der Wahrheit** für das visuelle Design
ist [`DESIGN-BRIEF.md`](DESIGN-BRIEF.md).

## Dateien

| Datei | Zweck |
|---|---|
| `logo.svg` | **Master-Bildmarke** (freigestellt) — Standort-Pin mit sitzendem Baby, weiße Windel |
| `app-icon-foreground.svg` | Adaptive-Icon **Vordergrund**, Motiv in zentraler 66 %-Safe-Zone, transparente Ränder |
| `app-icon-background.svg` | Adaptive-Icon **Hintergrund**, full-bleed (surface → accent-soft) |
| `app-icon-monochrome.svg` | **Einfarbige** Silhouette für Android-13-Themed-Icons & Wasserzeichen |
| `render/*.png` | Gerenderte 1024²-PNGs — **versioniert**, dienen als Input für `flutter_launcher_icons` |
| `render/preview.png` | App-Icon-Vorschau (Vordergrund über Hintergrund) |
| `render.mjs` | Renderskript (SVG → PNG via `sharp`) |

## Motiv & Lizenz

Die Bildmarke ist **vollständig eigenständig gezeichnet** (eigene SVG-Pfade): ein Standort-Pin
(Tropfenkontur) mit einem sitzenden Baby im Kopf. Der **Windelbereich** (Becken/Schritt) ist in
**Weiß** hervorgehoben und hebt sich minimal vom soft-Rosé des Babys ab.

> Keine Fremd-Icons, **keine Font-Awesome-/CC-BY-Bindung** — die Grafik unterliegt der
> Projektlizenz (siehe `../LICENSE`). Frei nutz- und veränderbar ohne Attributionspflicht Dritter.

## Farbpalette „Sanft & modern"

| Token | Hex | Verwendung |
|---|---|---|
| primary | `#5B5BD6` | Pin-Körper, Primäraktionen |
| primary-deep | `#4340B8` | Verläufe, Tiefe |
| accent | `#E8A0BF` | Baby-Symbol, Akzente |
| accent-soft | `#F6D9E4` | Flächen, Hintergründe |
| ink | `#2A2A40` | Text auf hell |
| surface | `#FBFAFF` | Hintergrund hell |

## PNGs neu rendern

Nach Änderungen an den SVGs die PNGs neu erzeugen und **mitcommitten**
(CI validiert nur, rendert nicht):

```bash
cd brand
npm install --no-save sharp     # einmalig, lokal (node_modules ist gitignored)
node render.mjs                 # -> render/foreground.png, background.png, monochrome.png, preview.png
```

Es wird **kein** rsvg/Inkscape/ImageMagick benötigt — `sharp` (libvips) rendert SVG nativ.

## Wie das App-Icon gebaut wird

Der Android-`android/`-Ordner ist bewusst **nicht** im Repo (siehe `.gitignore`) — er wird in
CI bei jedem `v*`-Tag via `flutter create` neu erzeugt. Deshalb werden die Icon-Ressourcen
**zur Build-Zeit** injiziert:

1. `.github/workflows/release.yml` ruft nach `flutter create` den Step
   **„App-Icons generieren"** auf: `dart run flutter_launcher_icons`.
2. Konfiguration: [`../flutter_launcher_icons.yaml`](../flutter_launcher_icons.yaml)
   (dev-dependency `flutter_launcher_icons` in `pubspec.yaml`).
3. Erzeugt Adaptive Icons (`mipmap-anydpi-v26`) **und** Legacy-mipmaps als Fallback
   für Geräte < API 26.

> Ändern sich Logo/Icon: SVG anpassen → `node render.mjs` → PNGs committen.
> Das nächste Release baut das neue Icon automatisch.

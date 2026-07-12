# Wickelfinder — Logo & Brand Design Brief

> Dieses Brief gibst du 1:1 an ein KI-Bildtool (Ideogram, Midjourney, DALL·E) oder
> an einen Designer (Fiverr, 99designs, Upwork). Alle Werte sind final abgestimmt.

---

## 1. Die Marke

- **Name:** Wickelfinder
- **Was die App macht:** Eltern kleiner Kinder finden schnell öffentliche **Wickelplätze / Wickeltische** in ihrer Nähe. Nutzer können Plätze hinzufügen, bewerten und gegenseitig verifizieren.
- **Zielgruppe:** Mütter und Väter von Babys/Kleinkindern, unterwegs, oft im Stress, brauchen schnelle Orientierung.
- **Markengefühl:** vertrauenswürdig, ruhig, freundlich, hilfreich, modern — **nicht** kindisch-verspielt, **nicht** verspielt-cartoonhaft, **nicht** medizinisch-kalt.

## 2. Motiv

**Kernidee:** Ein **Kartennadel-Pin** (Standort-Symbol) verschmilzt mit einem eindeutigen **Wickel-/Baby-Symbol**.

Erlaubte Symbol-Optionen im Pin (Designer/Tool wählt die stärkste Umsetzung):
- Eine stilisierte, **gefaltete Windel** (klar als Windel erkennbar)
- ODER ein **Baby-Kopf** in Baby-Proportion (großer runder Kopf, evtl. eine Locke)
- ODER ein **Wickeltisch-Piktogramm** (das offizielle „baby changing"-Symbol: Erwachsener beugt sich über liegendes Baby)

**Wichtig:** Das Symbol muss auf 48×48 px (App-Icon-Kleingröße) noch eindeutig erkennbar sein. Keine feinen Details, keine dünnen Linien.

## 3. Stil

- **Flat / Material Design 3**, moderne App-Ästhetik
- Klare geometrische Formen, großzügige Negativräume
- Optional: sehr dezenter Verlauf im Pin (kein knalliger 3D-Look)
- Vektor-sauber, skalierbar, funktioniert in einfarbig (Monochrom-Variante mitliefern)

## 4. Farben (exakt, nicht abweichen)

| Rolle | Hex |
|---|---|
| Primär (Indigo, Pin-Körper) | `#5B5BD6` |
| Primär tief (Verlauf/Tiefe) | `#4340B8` |
| Akzent (soft Rose, Symbol) | `#E8A0BF` |
| Akzent hell (Flächen) | `#F6D9E4` |
| Ink (Text) | `#2A2A40` |
| Surface (heller Hintergrund) | `#FBFAFF` |

Palette-Charakter: „sanft & modern" — gedecktes Indigo/Lavendel + soft Rose.

## 5. Benötigte Deliverables

1. **App-Icon** — 1024×1024, quadratisch, für Android Adaptive Icon (Motiv in zentraler 66%-Safe-Zone)
2. **Logo** — Bildmarke freigestellt, transparenter Hintergrund, SVG + PNG
3. **Wortmarke** — „Wickelfinder" als Schriftzug + optional Claim „Wickelplätze finden · bewerten · teilen"
4. **Banner** — 1280×640 (GitHub/Social), Bildmarke links + Wortmarke rechts
5. **Monochrom-Variante** des Logos (eine Farbe, für Wasserzeichen/Print)
6. **Formate:** bevorzugt **SVG** (Vektor) + PNG-Exporte

## 6. Do's & Don'ts

- ✅ Sofort als „Standort + Baby/Wickeln" lesbar
- ✅ Zeitlos, seriös, elternfreundlich
- ✅ Funktioniert in Light- und Dark-Mode-Umgebung
- ❌ Keine Comic-/Cartoon-Babys, keine Kulleraugen-Niedlichkeit
- ❌ Keine Stockfoto-Optik, keine Farbverläufe außerhalb der Palette
- ❌ Kein Text im App-Icon (nur Symbol)

---

## Fertige Prompts pro Tool

### Ideogram (empfohlen — kann Logos & Text sauber)
```
Minimalist flat vector app logo for "Wickelfinder", a baby changing-table
finder app. A rounded map location pin in indigo (#5B5BD6 to #4340B8 gradient),
containing a clearly recognizable folded baby diaper symbol in soft rose
(#E8A0BF). Material Design 3 style, clean geometric shapes, generous negative
space, flat, no 3D, professional, on white background. Simple enough to read
at 48px.
```

### Midjourney
```
flat vector app icon, map location pin merged with a baby diaper symbol,
indigo #5B5BD6 and soft rose #E8A0BF, Material Design 3, minimalist,
clean geometric, professional logo, white background, no text
--style raw --v 6
```

### DALL·E / ChatGPT
```
Design a professional, minimalist flat vector app icon for a baby
changing-table finder app called "Wickelfinder". A rounded map pin in an
indigo gradient (#5B5BD6 → #4340B8) with a clearly recognizable folded
diaper symbol inside, in soft rose (#E8A0BF). Material Design 3 aesthetic,
flat, clean, readable at small sizes, transparent/white background, no text.
```

### Fiverr / 99designs Briefing-Satz
> „Flat, modern Material-Design-3 app logo: a map location pin containing a
> baby-diaper symbol. Colors: indigo #5B5BD6/#4340B8 + soft rose #E8A0BF.
> Deliver SVG + PNG, app icon 1024px, banner 1280×640, monochrome variant.
> Style: trustworthy, calm, parent-friendly — not cartoonish."

---

*Sobald du das fertige Logo hast (SVG/PNG), lege es unter `apps/wickelfinder/brand/`
ab — ich verdrahte es dann in App-Icon-Generator, README und Banner.*

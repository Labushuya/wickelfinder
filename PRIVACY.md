# Datenschutzerklärung — Wickelfinder

_Stand: Juli 2026_

Wickelfinder hilft Eltern, Wickelplätze in der Nähe zu finden, zu bewerten und
zu ergänzen. Diese Erklärung beschreibt, welche Daten dabei verarbeitet werden.

> **Hinweis:** Die Angabe des Verantwortlichen unten muss vor einer öffentlichen
> Veröffentlichung durch den Betreiber vervollständigt werden. Diese Erklärung
> ist eine technisch/organisatorisch vollständige Vorlage, ersetzt aber **keine
> Rechtsberatung**.

## 1. Verantwortlicher

Verantwortlich für die Datenverarbeitung im Sinne der DSGVO:

```
[Name / Betreiber]
[Anschrift]
E-Mail: [Kontakt-E-Mail]
```

## 2. Grundprinzip: Datensparsamkeit

- **Reine Kartennutzung erzeugt keine personenbezogenen Daten.** Wer die App nur
  öffnet und die Karte ansieht, hinterlässt serverseitig nichts.
- Eine (pseudonyme) Kennung entsteht **erst**, wenn du aktiv beiträgst
  (bewerten, einen Platz melden/hinzufügen, etwas als „nicht vorhanden" melden).
- **Keine Tracker, kein Analytics, keine Werbe-SDKs.** Wir zählen dich nicht,
  wir verfolgen dich nicht.

## 3. Pseudonyme Kennung — keine echte Anonymität

Beim ersten Beitrag wird automatisch eine anonyme Kennung (eine zufällige UUID)
erzeugt und auf deinem Gerät gespeichert. Sie enthält **keinen Klarnamen** und
keine E-Mail. Wichtig und ehrlich gesagt: Diese Kennung ist ein **Pseudonym**,
kein Zustand vollständiger Anonymität — deine Beiträge sind über diese Kennung
**untereinander verknüpfbar** (z. B. „eine Bewertung pro Platz"), und die
Kennung bleibt über App-Neustarts stabil.

Betreiber der App (Admins) melden sich zusätzlich mit einer echten E-Mail an;
diese E-Mail wird dann bei der Auth-Kennung gespeichert.

## 4. Standortdaten

- Die Ermittlung deines Standorts erfolgt **auf dem Gerät** und dient nur dazu,
  die Karte auf deine Umgebung zu zentrieren. Dein Standort wird **nicht** an den
  Server übertragen.
- **Ausnahme:** Wenn du selbst einen Wickelplatz anlegst, werden die von dir
  gewählten Koordinaten dieses Platzes als Inhalt gespeichert. Von dir angelegte
  Plätze sind **öffentlich sichtbar** (das ist der Zweck eines Verzeichnisses).

## 5. Kartendaten (OpenStreetMap)

Das Kartenmaterial stammt von **OpenStreetMap** und steht unter der Open
Database License (**ODbL**). Es gilt die Attributionspflicht: „© OpenStreetMap-
Mitwirkende". Adresssuche und Basisdaten (vorhandene Wickeltisch-Orte) werden
über OpenStreetMap-Dienste bezogen; dabei wird — wie bei jedem Internetdienst —
technisch deine IP-Adresse an diese Server übermittelt. Es gelten die
[Datenschutzbestimmungen von OpenStreetMap](https://wiki.osmfoundation.org/wiki/Privacy_Policy).

## 6. Auftragsverarbeiter

- **Supabase** (Hosting der Datenbank, Authentifizierung, Serverfunktionen).
  Verarbeitungsregion: **EU (Frankfurt)**. Mit Supabase besteht ein
  Auftragsverarbeitungsvertrag (DPA).

## 7. Welche Daten wir speichern und warum

| Datenkategorie | Inhalt | Zweck |
|---|---|---|
| Bewertungen | Platz-Referenz, 1–5 Sterne, Eigenschafts-Tags, Zeitstempel | Community-Bewertung von Wickelplätzen |
| Meldungen („nicht vorhanden" o. Ä.) | Platz-Referenz, Grund, Zeitstempel | Aktualität/Qualität des Verzeichnisses |
| Bestätigungen | Platz-Referenz, Zeitstempel | „existiert noch"-Signal |
| Angelegte Plätze | Name, Lage-Hinweis, Koordinaten, Eigenschaften, Zeitstempel | Verzeichnis der Wickelplätze |
| Inhaltsmeldungen | Platz-Referenz, Art (z. B. Spam), Zeitstempel | Moderation |
| Auth-Kennung | UUID, ggf. E-Mail (nur Admin), Zeitstempel | Zuordnung deiner Beiträge, Missbrauchsschutz |

**Rechtsgrundlage:** Erfüllung der App-Funktion sowie unser berechtigtes
Interesse an einem funktionierenden, missbrauchsgeschützten Community-Verzeichnis
(Art. 6 Abs. 1 lit. b und f DSGVO).

## 8. Speicherdauer

Deine Daten bleiben gespeichert, bis du sie löschst (siehe unten) bzw. bis der
betreffende Platz gelöscht wird. Inhaltsmeldungen können zu Moderationszwecken
aufbewahrt werden.

## 9. Deine Rechte

- **Auskunft & Datenübertragbarkeit (Art. 15/20):** In der App unter
  _Einstellungen → Meine Daten → Meine Daten exportieren_ erhältst du eine
  vollständige, maschinenlesbare Kopie (JSON) aller unter deiner Kennung
  gespeicherten Daten.
- **Löschung (Art. 17):** Unter _Einstellungen → Meine Daten → Meine Daten &
  Konto löschen_ werden **alle** deine Daten und dein Auth-Konto unwiderruflich
  gelöscht. Mit einem von dir angelegten Platz werden auch die Bewertungen und
  Meldungen anderer zu diesem Platz entfernt.
- **Berichtigung:** Von dir angelegte Plätze kannst du jederzeit bearbeiten.
- **Widerspruch** sowie **Beschwerderecht** bei einer Datenschutz-Aufsichts-
  behörde stehen dir zu.

## 10. Wichtiger technischer Hinweis (anonyme Kennung)

Deine anonyme Kennung lebt in der App auf deinem Gerät. Wenn du die App
**deinstallierst** oder ihren Speicher löschst, **ohne vorher** die
Konto-Löschung durchzuführen, ist die alte Kennung von deinem Gerät aus **nicht
mehr erreichbar**. Deine früheren Beiträge bleiben dann serverseitig verwaist
bestehen, und du kannst Export/Löschung dafür nicht mehr auslösen. **Empfehlung:**
Führe Export bzw. Löschung durch, solange die App installiert ist.

## 11. Kontakt & Änderungen

Fragen zum Datenschutz: über die oben genannte Kontaktadresse bzw. ein
[GitHub Issue](https://github.com/Labushuya/wickelfinder/issues). Wir können diese
Erklärung anpassen; die aktuelle Fassung ist in der App
(_Einstellungen → Datenschutz_) und im Projekt-Repository einsehbar.

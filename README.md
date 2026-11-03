# Epochen der Wege

Ein friedliches 3D-Aufbau- und Logistikspiel für macOS (Swift, SwiftUI, RealityKit).
Du führst ein Volk von der Antike in die Moderne – Wachstum entsteht nur,
wenn Waren und Menschen physisch transportiert werden.

Inspiriert vom Genre-Mix aus Aufbauspielen, Strategiespielen und Transport-Simulationen.
Die Spielregeln stehen im [Game Design Document](docs/GameDesign.md).

## Starten

Voraussetzungen: macOS 14 oder neuer, Xcode 16 oder neuer.

1. `EpochenDerWege.xcodeproj` in Xcode öffnen.
2. Oben links das Schema **EpochenDerWege** und als Ziel **My Mac** wählen.
3. **⌘R** drücken.

Falls Xcode beim ersten Start nach einer Signierung fragt: Unter
*Signing & Capabilities* „Sign to Run Locally“ wählen oder dein eigenes Team eintragen.

Tests der Simulation:

- in Xcode: Schema **Simulation** wählen und **⌘U** drücken, oder
- im Terminal: `cd Packages/Simulation && swift test`

## Steuerung

| Eingabe | Wirkung |
| --- | --- |
| Linksklick | Gebäude bauen (wenn ein Bauwerkzeug gewählt ist) oder auswählen |
| Linke Maustaste ziehen | Karte verschieben |
| Rechte Maustaste ziehen | Kamera drehen und neigen |
| Scrollen / Pinch | Zoomen |
| W A S D / Pfeiltasten | Kamera bewegen |
| Q / E | Kamera drehen |
| Rechtsklick / Esc | Bauwerkzeug ablegen bzw. Auswahl aufheben |
| Leertaste | Pause |

Farbige Kugeln über Gebäuden zeigen den Zustand: grün = arbeitet,
gelb = wartet oder Lager voll, rot = keine Arbeiter, keine Rohstoffe oder Hunger.
Kleine Kugeln, die über die Karte laufen, sind Träger – ihre Farbe zeigt die Ware.

## Projektstruktur

```
EpochenDerWege.xcodeproj      Xcode-Projekt (Ordner werden automatisch synchronisiert)
EpochenDerWege/               macOS-App
  EpochenDerWegeApp.swift     Einstiegspunkt
  ContentView.swift           Fenster: 3D-Ansicht plus Oberfläche
  GameController.swift        Verbindet Simulation, Eingaben und Anzeige
  Rendering/                  RealityKit: Kamera, Gelände, Gebäude, Träger
  UI/                         SwiftUI: obere Leiste, Baumenü, Gebäudeinfo
Packages/Simulation/          Spielregeln als eigenes Swift-Paket, ohne Grafik
  Sources/Simulation/
    Resources/antike.json     Alle Spielwerte (Gebäude, Waren, Regeln)
    Simulation.swift          Tick-Schleife: Produktion, Träger, Bewohner, Finanzen
    Terrain.swift             Prozedurale Karte aus einem Seed
  Tests/SimulationTests/      Unit-Tests
docs/GameDesign.md            Game Design Document
```

**Grundsatz:** Die Simulation kennt keine Grafik. Die App liest nur ihren Zustand
und schickt Befehle (bauen, abreißen). So bleibt die Spiellogik testbar, und
die Grafik-Technik könnte später ausgetauscht werden.

**Balancing:** Kosten, Produktionszeiten, Arbeiter, Lagergrößen und Regeln stehen in
`Packages/Simulation/Sources/Simulation/Resources/antike.json` und lassen sich ohne
Code-Änderung anpassen.

## Stand: Meilenstein 1 (Prototyp Antike)

Fertig:

- [x] Prozedurale 3D-Karte (Low-Poly) mit Wasser, Sand, Grasland, Wald, Fels und Schnee
- [x] Orbit-Kamera mit Maus, Trackpad und Tastatur
- [x] Startsiedlung mit Lager und fünf Häusern (20 Bauern)
- [x] Bauen mit Vorschau (grün/rot) und Regeln: Gelände, Steigung, Geld, Rohstoffe in Reichweite
- [x] Produktionsketten: Getreide → Mehl → Brot, Fisch, Holz, Stein
- [x] Träger bringen Waren sichtbar von Betrieb zu Betrieb, zu Häusern und ins Lager
- [x] Arbeiter, Versorgung, Wachstum und Hunger der Häuser
- [x] Steuern und Unterhalt pro Jahr
- [x] Pause und Zeitraffer (1×, 2×, 4×)

Bewusste Vereinfachungen für den Prototyp:

- Träger laufen in gerader Linie; Straßen, Wegfindung und Ochsenkarren kommen als Nächstes
- Bauern und Bürger werden noch nicht unterschieden
- Gebäude kosten nur Geld, noch kein Baumaterial
- Häuser setzt der Spieler selbst (später entstehen sie in Wohnzonen)
- Kein Speichern und Laden

Nächste Schritte:

1. Straßen bauen, Wegfindung (A*) und Ochsenkarren auf Linien
2. Baumaterial muss zur Baustelle transportiert werden
3. Bürger als zweiter Stand mit Kleidung und Wein
4. Speichern und Laden

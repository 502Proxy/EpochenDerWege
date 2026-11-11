# Epochen der Wege

[![CI](https://github.com/502Proxy/EpochenDerWege/actions/workflows/ci.yml/badge.svg)](https://github.com/502Proxy/EpochenDerWege/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2026-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)

A peaceful 3D city-building and logistics game for macOS, written in Swift with
SwiftUI and RealityKit.

You lead a people from antiquity to the modern age. Growth only happens when goods
and people are physically moved from A to B: every sack of grain and every commuter
is an object on a path. The genre mix combines settlement building, a civilisation
spanning several eras, and transport simulation.

The full rules are in the [game design document](docs/GameDesign.md).

## Getting started

Requirements: macOS 26 and Xcode 26.

```bash
git clone https://github.com/502Proxy/EpochenDerWege.git
open EpochenDerWege/EpochenDerWege.xcodeproj
```

Select the **EpochenDerWege** scheme and **My Mac**, then press **⌘R**.
Press **⌘U** to run all tests, or from the terminal:

```bash
swift test --package-path Packages/Core
```

If Xcode asks for signing, choose *Sign to Run Locally* or your own team under
*Signing & Capabilities*.

## Controls

| Input | Action |
| --- | --- |
| 1 – 4 | Open a category of the build bar (transport, zones, production, storage) |
| Click | Build (with a building selected) or select a building |
| Drag | Move the map; with the road or zone tool, draw a road or zone an area |
| Right-drag | Rotate and tilt the camera |
| Scroll / pinch | Zoom |
| W A S D / arrow keys | Move the camera |
| Q / E | Rotate the camera |
| Right-click / Esc | Drop the build tool, clear the selection, then close the top window |
| O | Map overlay: supply, carrier range, off |
| F | Finance window |
| G | Goods overview |
| B | Building list |
| L | Transport lines |
| K | Save and load, new game |
| ⌘S | Quick save |
| Click on the mini map | Move the camera there |
| Space | Pause |

Coloured spheres above buildings show their state: green working, yellow waiting or
full, red without workers, resources or food. Small spheres walking across the map
are carriers; their colour shows the good they carry.

## Project structure

```
EpochenDerWege.xcodeproj        Xcode project; source folders are synchronised automatically
EpochenDerWege/                 macOS app
  App/                          Entry point and composition root (GameSession)
  Features/Game/                View model, text formatting, SwiftUI views
  Rendering/                    RealityKit scene: layers, camera, input
  Resources/                    String catalog (English, German)
Packages/Core/                  Game logic, no UI frameworks
  Sources/GameDomain/           Entities and value types
  Sources/GameData/             Game data loading and validation
    Resources/antiquity.json    All balancing values for the antiquity era
  Sources/GameSimulation/       World state, systems, commands, engine, world generation
  Sources/GamePersistence/      Save games (file format, repository)
  Tests/                        Swift Testing suites per module
docs/
  GameDesign.md                 Game design document
  Architecture.md               Layers, data flow, patterns, decisions
```

See [docs/Architecture.md](docs/Architecture.md) for how the pieces fit together.

## Status

The project is in milestone **0.1 Foundation**. See the
[milestones](https://github.com/502Proxy/EpochenDerWege/milestones) for the roadmap
and the [issues](https://github.com/502Proxy/EpochenDerWege/issues) for planned work.

Playable today:

- Procedural 3D map with smooth, finely resolved hills and a painted ground texture: grass patches, beaches, cliffs on steep slopes, snow on peaks; forests, bushes and boulders
- Starting settlement with a storehouse and five houses (20 farmers)
- Build toolbar with categories; gravel roads drawn by dragging (steep hills are crossed by tunnels), demolish tool
- Residential, commercial and industrial zones: towns build houses, markets and workshops next to roads on their own
- Demand bars for every zone kind show what the town needs and warn when there is no free zoned space next to a road; click a bar to pick that zone tool
- Settlement levels from hamlet to city by population; levels unlock buildings, locked tools show the level they need
- House tiers: hut (4 farmers) → house (6 citizens, needs clothing, from village) → townhouse (8, also needs wine, from small town); houses move up when full, fed and stocked, and fall back when goods run out; higher tiers pay more taxes
- New chains: sheep farm → wool → weaver → clothing, vineyard → grapes → wine press → wine
- Markets buy food and workshops buy raw materials; every delivery earns its base price as sales income
- Processing businesses (mill, bakery) may only be built in commercial or industrial zones; raw material producers sit at their resources
- Building with live preview and rules for terrain, slope, money and nearby resources
- Production chains: grain → flour → bread, fish, wood, stone, wool → clothing, grapes → wine
- A region instead of a lone village: stone deposits and vine slopes lie beyond carrier range, and two or three neighbouring towns (fishing village, mining town, wine village, farming village) trade at their own stop: they sell their goods at base price and pay 1.5 × for what they want. Their names show on the mini map
- Carriers visibly transport goods within 150 m; for longer distances the player builds stops, creates lines and buys ox carts that drive on the road network (A* pathfinding)
- Workers, food supply, growth and hunger
- Map overlays (key O): supply of houses and efficiency of businesses, carrier range of storehouses and stops
- Per-building settings in the inspector: pause a business and set its delivery priority
- Goods overview (key G): production, consumption, stock and sales per good; building list (key B) with status and efficiency, click to jump there
- Finance window (key F or click the money): income and expenses per month and year, sales per good, costs per building and vehicle type, balance chart
- Pause and 1× / 2× / 4× speed
- Game interface in its own dark style: bottom bar with build categories, key figures, date and speed; windows that float above the map and can be dragged; mini map with roads, buildings and camera; notifications with icons

- Save and load: named saves and a quick save (⌘S) in `~/Library/Application Support/EpochenDerWege/Saves`; a new game starts on a new map

Known simplifications of the prototype: carriers walk in straight lines within their short range and buildings cost only money.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow: issues, branches,
Conventional Commits and pull requests.

## Language

Code, comments and documentation are written in English. The game is available in
English and German.

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
| 1 – 4 | Open a category of the build toolbar (transport, zones, production, storage) |
| Click | Build (with a building selected) or select a building |
| Drag | Move the map; with the road or zone tool, draw a road or zone an area |
| Right-drag | Rotate and tilt the camera |
| Scroll / pinch | Zoom |
| W A S D / arrow keys | Move the camera |
| Q / E | Rotate the camera |
| Right-click / Esc | Drop the build tool or clear the selection |
| O | Map overlay: supply, carrier range, off |
| F | Finance window |
| G | Goods overview |
| B | Building list |
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

- Procedural low-poly 3D map with water, sand, grassland, forest, rock and snow
- Starting settlement with a storehouse and five houses (20 farmers)
- Build toolbar with categories; gravel roads drawn by dragging (steep hills are crossed by tunnels), demolish tool
- Residential, commercial and industrial zones: towns build houses, markets and workshops next to roads on their own
- Markets buy food and workshops buy raw materials; every delivery earns its base price as sales income
- Processing businesses (mill, bakery) may only be built in commercial or industrial zones; raw material producers sit at their resources
- Building with live preview and rules for terrain, slope, money and nearby resources
- Production chains: grain → flour → bread, fish, wood, stone
- Carriers visibly transport goods within 150 m; for longer distances the player builds stops, creates lines and buys ox carts that drive on the road network (A* pathfinding)
- Workers, food supply, growth and hunger
- Map overlays (key O): supply of houses and efficiency of businesses, carrier range of storehouses and stops
- Per-building settings in the inspector: pause a business and set its delivery priority
- Goods overview (key G): production, consumption, stock and sales per good; building list (key B) with status and efficiency, click to jump there
- Finance window (key F or click the money): income and expenses per month and year, sales per good, costs per building and vehicle type, balance chart
- Pause and 1× / 2× / 4× speed

Known simplifications of the prototype: carriers walk in straight lines within their short range, farmers and citizens are not yet distinguished, buildings cost only money, and there is no save game yet.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow: issues, branches,
Conventional Commits and pull requests.

## Language

Code, comments and documentation are written in English. The game is available in
English and German.

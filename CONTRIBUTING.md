# Contributing

Thanks for helping build *Epochen der Wege*. This guide describes how work flows
from an idea to `main`.

## Language

Code, comments, commit messages, issues, pull requests and documentation are
written in **English**. Player-facing text is written in English in code and
translated through the String Catalog.

## Planning

- Work is planned in [milestones](../../milestones). Each milestone is a playable
  or shippable step towards the game described in [docs/GameDesign.md](docs/GameDesign.md).
- Every change starts with an [issue](../../issues) that states the goal and
  acceptance criteria. Use the issue templates.
- Labels describe the kind of work (`gameplay`, `refactor`, `performance`, `bug`, …)
  and the affected area (`area: simulation`, `area: rendering`, `area: ui`,
  `area: infrastructure`).

## Branches

Branch from `main` and name the branch after the kind of change:

| Prefix | Use for |
| --- | --- |
| `feature/` | New gameplay or UI, e.g. `feature/road-building` |
| `fix/` | Bug fixes |
| `refactor/` | Restructuring without behaviour change |
| `perf/` | Performance work |
| `docs/` | Documentation only |
| `chore/` | Tooling, CI, dependencies |

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(simulation): add A* pathfinding on the road graph
fix(rendering): keep carriers above the water surface
docs: describe the snapshot data flow
```

Keep commits focused. A reviewer should be able to read the history of a pull
request and understand each step.

## Pull requests

1. Open a pull request against `main` and fill in the template.
2. Link the issue with `Closes #<number>`.
3. CI must be green: the app builds and all tests pass.
4. Squash-merge once approved. The squash commit follows the commit convention.

Keep pull requests small enough to review in one sitting. Split large features
into several issues and pull requests.

## Code guidelines

- Follow the layering in [docs/Architecture.md](docs/Architecture.md). The
  Simulation package never imports SwiftUI, AppKit or RealityKit.
- Game rules belong in the Simulation package and are covered by unit tests.
- Balancing values belong in the game data JSON, not in code.
- Public types and functions have documentation comments (`///`).
- Prefer value types and immutable snapshots; mutable state lives in one owner.
- No force unwraps outside tests, no warnings in a clean build.

## Running locally

```bash
# Simulation tests
swift test --package-path Packages/Simulation

# Build the app (or open EpochenDerWege.xcodeproj and press ⌘R)
xcodebuild build -project EpochenDerWege.xcodeproj -scheme EpochenDerWege -destination 'platform=macOS'
```

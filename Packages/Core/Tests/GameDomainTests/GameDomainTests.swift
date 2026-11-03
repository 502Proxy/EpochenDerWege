import GameDomain
import Testing

@Suite("Inventory")
struct InventoryTests {
    @Test func addRespectsCapacity() {
        var inventory = Inventory(capacityPerGood: 5)
        #expect(inventory.add("bread", amount: 3) == 3)
        #expect(inventory.add("bread", amount: 3) == 2)
        #expect(inventory.count(of: "bread") == 5)
        #expect(inventory.space(for: "bread") == 0)
    }

    @Test func removeNeverGoesNegative() {
        var inventory = Inventory(capacityPerGood: 5)
        inventory.add("fish", amount: 2)
        #expect(inventory.remove("fish", amount: 5) == 2)
        #expect(inventory.isEmpty)
    }

    @Test func sortedItemsAreDeterministic() {
        var inventory = Inventory(capacityPerGood: 10)
        inventory.add("wood", amount: 1)
        inventory.add("bread", amount: 2)
        inventory.add("grain", amount: 3)
        #expect(inventory.sortedItems.map(\.good) == ["bread", "grain", "wood"])
    }
}

@Suite("Terrain")
struct TerrainTests {
    @Test func flatTerrainHasConstantHeight() {
        let terrain = Terrain.flat(size: 8, height: 12)
        #expect(abs(terrain.height(at: WorldPoint(x: 13.7, z: 40.2)) - 12) < 0.0001)
        #expect(terrain.slopePercent(at: GridPoint(x: 3, z: 3)) == 0)
    }

    @Test func cellLookupMatchesCenter() {
        let terrain = Terrain.flat(size: 16)
        let cell = GridPoint(x: 5, z: 9)
        #expect(terrain.cell(containing: terrain.center(of: cell)) == cell)
        #expect(terrain.cell(containing: WorldPoint(x: -1, z: 4)) == nil)
    }

    @Test func outsideCellsCountAsWater() {
        let terrain = Terrain.flat(size: 4)
        #expect(terrain.biome(at: GridPoint(x: -1, z: 0)) == .water)
        #expect(!terrain.isLand(GridPoint(x: 4, z: 4)))
    }

    @Test func replacingBiomeLeavesOriginalUntouched() {
        let original = Terrain.flat(size: 4)
        let changed = original.replacingBiome(at: GridPoint(x: 1, z: 1), with: .water)
        #expect(original.biome(at: GridPoint(x: 1, z: 1)) == .grass)
        #expect(changed.biome(at: GridPoint(x: 1, z: 1)) == .water)
    }
}

@Suite("Game clock")
struct GameClockTests {
    @Test func derivesDaysAndYears() {
        var clock = GameClock(ticksPerDay: 2, daysPerYear: 3)
        for _ in 0..<13 {
            clock.advance()
        }
        #expect(clock.day == 6)
        #expect(clock.year == 2)
        #expect(clock.dayOfYear == 0)
    }

    @Test func periodStartsAreNotTriggeredAtTickZero() {
        var clock = GameClock(ticksPerDay: 2, daysPerYear: 3)
        #expect(!clock.isStartOfPeriod(days: 1))
        clock.advance()
        clock.advance()
        #expect(clock.isStartOfPeriod(days: 1))
    }
}

@Suite("Carrier")
struct CarrierTests {
    private func makeCarrier() -> Carrier {
        Carrier(
            id: CarrierID(1),
            cargo: GoodAmount(good: "bread", amount: 1),
            sourceID: BuildingID(1),
            targetID: BuildingID(2),
            origin: WorldPoint(x: 0, z: 0),
            destination: WorldPoint(x: 10, z: 0)
        )
    }

    @Test func positionFollowsPhase() {
        var carrier = makeCarrier()
        carrier.walked = 4
        #expect(carrier.position == WorldPoint(x: 4, z: 0))
        carrier.phase = .returning
        #expect(carrier.position == WorldPoint(x: 6, z: 0))
    }

    @Test func turningBackKeepsPosition() {
        var carrier = makeCarrier()
        carrier.walked = 3
        let before = carrier.position
        carrier.turnBack()
        #expect(carrier.phase == .returning)
        #expect(carrier.position == before)
    }
}

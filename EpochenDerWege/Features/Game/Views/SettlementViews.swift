import GameDomain
import GameSimulation
import SwiftUI

/// Demand bars for residential, commercial and industrial zones.
///
/// A bar at or above the marked line means the town builds in that zone; a warning
/// sign means it wants to but finds no free zoned cell next to a road.
struct ZoneDemandView: View {
    let demand: [ZoneKind: ZoneDemand]
    let onSelectZone: (ZoneKind) -> Void

    private static let barHeight: CGFloat = 34

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(ZoneKind.allCases, id: \.self) { kind in
                let value = demand[kind] ?? ZoneDemand(value: 0, reason: .none)
                Button {
                    onSelectZone(kind)
                } label: {
                    bar(for: kind, demand: value)
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: "\(GameText.name(of: kind)): \(GameText.percent(value.value))\n\(GameText.explanation(of: value, zone: kind))"))
                .accessibilityLabel(Text(GameText.name(of: kind)))
                .accessibilityValue(Text(GameText.percent(value.value)))
            }
        }
        .padding(.horizontal, 6)
    }

    private func bar(for kind: ZoneKind, demand: ZoneDemand) -> some View {
        let color = Color(ZoneLayer.color(of: kind))
        return VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.35))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.gradient)
                    .frame(height: Self.barHeight * demand.value)
                    .opacity(demand.isGrowing ? 1 : 0.55)
                // Growth threshold.
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(height: 1)
                    .offset(y: -Self.barHeight * ZoneDemand.growthThreshold)
            }
            .frame(width: 12, height: Self.barHeight)
            .overlay(alignment: .top) {
                if demand.lacksSpace {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(GameTheme.warning)
                        .offset(y: -12)
                }
            }
            Text(GameText.zoneInitial(kind))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .animation(.easeOut(duration: 0.4), value: demand.value)
    }
}

/// Name of the settlement's level, residents and progress to the next level.
struct SettlementCard: View {
    let settlement: SettlementProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(GameTheme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: settlement.name)
                        .font(GameTheme.title)
                    Text("\(settlement.population) residents")
                        .font(GameTheme.caption.monospacedDigit())
                        .foregroundStyle(GameTheme.secondaryText)
                }
            }
            if let nextName = settlement.nextName {
                ProgressView(value: settlement.progress)
                    .tint(GameTheme.accent)
                Text("Next: \(nextName) at \(settlement.nextPopulation) residents")
                    .font(GameTheme.caption)
                    .foregroundStyle(GameTheme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 220, alignment: .leading)
        .gamePanel()
    }
}

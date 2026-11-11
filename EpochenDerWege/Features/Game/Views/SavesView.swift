import GamePersistence
import SwiftUI

/// Save the current game under a name, load or delete saves, start a new game.
struct SavesView: View {
    let app: GameApp

    @State private var name = ""
    @State private var pendingLoad: SaveGameEntry?
    @State private var pendingDelete: SaveGameEntry?
    @State private var confirmsNewGame = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Name of the save", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(app.isBusy)
            }

            if let message = app.message {
                Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(GameTheme.caption)
                    .foregroundStyle(message.isError ? GameTheme.negative : GameTheme.positive)
            }

            Divider()

            if app.saves.isEmpty {
                Text("No saves yet.")
                    .font(GameTheme.body)
                    .foregroundStyle(GameTheme.secondaryText)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(app.saves) { entry in
                            SaveRow(entry: entry, isBusy: app.isBusy) {
                                pendingLoad = entry
                            } onDelete: {
                                pendingDelete = entry
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            Divider()

            Button {
                confirmsNewGame = true
            } label: {
                Label("New game on a new map", systemImage: "map")
            }
            .disabled(app.isBusy)
        }
        .frame(width: 400)
        .confirmationDialog("Load this save? Unsaved progress is lost.", isPresented: isPresented($pendingLoad), presenting: pendingLoad) { entry in
            Button("Load") { Task { await app.load(entry.id) } }
        }
        .confirmationDialog("Delete this save?", isPresented: isPresented($pendingDelete), presenting: pendingDelete) { entry in
            Button("Delete", role: .destructive) { app.delete(entry.id) }
        }
        .confirmationDialog("Start a new game? Unsaved progress is lost.", isPresented: $confirmsNewGame) {
            Button("New game", role: .destructive) { app.newGame() }
        }
    }

    private func save() {
        let chosen = name
        Task { await app.save(named: chosen) }
    }

    private func isPresented(_ item: Binding<SaveGameEntry?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

private struct SaveRow: View {
    let entry: SaveGameEntry
    let isBusy: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let summary = entry.summary
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summary.name)
                    .font(GameTheme.body.weight(.semibold))
                Text("Year \(summary.year + 1) · \(summary.population) residents · \(summary.treasury) thalers")
                    .font(GameTheme.caption.monospacedDigit())
                    .foregroundStyle(GameTheme.secondaryText)
                Text(summary.savedAt, format: .dateTime.day().month().hour().minute())
                    .font(GameTheme.caption)
                    .foregroundStyle(GameTheme.secondaryText)
            }
            Spacer()
            Button("Load", action: onLoad)
                .disabled(isBusy)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(Text("Delete"))
        }
        .padding(8)
        .background(GameTheme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: GameTheme.smallCornerRadius))
    }
}

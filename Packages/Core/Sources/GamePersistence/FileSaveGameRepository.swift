import Foundation
import GameSimulation

/// Keeps saves as files in one directory.
///
/// File layout, so a save list never has to read whole worlds:
///
/// | Bytes | Content |
/// | --- | --- |
/// | 8 | Magic `EDWSAVE` + format version |
/// | 4 | Length of the summary, big endian |
/// | n | Summary as JSON |
/// | rest | World as binary property list, LZFSE-compressed |
public struct FileSaveGameRepository: SaveGameRepository {
    public let directory: URL

    /// Version of the file layout and of the encoded world. Raise it on incompatible changes.
    public static let formatVersion: UInt8 = 1
    public static let fileExtension = "edwsave"
    private static let magic = Array("EDWSAVE".utf8)

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/EpochenDerWege/Saves`.
    public static func defaultDirectory() -> URL {
        URL.applicationSupportDirectory
            .appending(path: "EpochenDerWege", directoryHint: .isDirectory)
            .appending(path: "Saves", directoryHint: .isDirectory)
    }

    // MARK: - SaveGameRepository

    public func list() throws -> [SaveGameEntry] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == Self.fileExtension }
        // Unreadable files are skipped rather than breaking the whole list.
        let entries = files.compactMap { url -> SaveGameEntry? in
            guard let summary = try? readSummary(of: url) else { return nil }
            return SaveGameEntry(id: url.lastPathComponent, summary: summary)
        }
        return entries.sorted { $0.summary.savedAt > $1.summary.savedAt }
    }

    @discardableResult
    public func save(_ world: WorldState, named name: String) throws -> SaveGameEntry {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let summary = SaveGameSummary(name: name, savedAt: .now, world: world)
        let data = try Self.encode(world, summary: summary)
        let id = Self.fileName(for: name)
        try data.write(to: directory.appending(path: id), options: .atomic)
        return SaveGameEntry(id: id, summary: summary)
    }

    public func load(_ id: SaveGameEntry.ID) throws -> WorldState {
        let url = directory.appending(path: id)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw SaveGameError.notFound(id) }
        return try Self.decode(try Data(contentsOf: url)).world
    }

    public func delete(_ id: SaveGameEntry.ID) throws {
        let url = directory.appending(path: id)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw SaveGameError.notFound(id) }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Format

    static func encode(_ world: WorldState, summary: SaveGameSummary) throws -> Data {
        let summaryData = try JSONEncoder.saveGame.encode(summary)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let body = try (encoder.encode(world) as NSData).compressed(using: .lzfse) as Data

        var data = Data(Self.magic)
        data.append(Self.formatVersion)
        var length = UInt32(summaryData.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(summaryData)
        data.append(body)
        return data
    }

    static func decode(_ data: Data) throws -> (summary: SaveGameSummary, world: WorldState) {
        let (summary, bodyStart) = try decodeHeader(data)
        do {
            let body = try (data.subdata(in: bodyStart..<data.endIndex) as NSData).decompressed(using: .lzfse) as Data
            let world = try PropertyListDecoder().decode(WorldState.self, from: body)
            return (summary, world)
        } catch {
            throw SaveGameError.corrupted(String(describing: error))
        }
    }

    /// Reads only as much of the file as the summary needs.
    private func readSummary(of url: URL) throws -> SaveGameSummary {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fixed = try handle.read(upToCount: Self.magic.count + 1 + 4) ?? Data()
        guard fixed.count == Self.magic.count + 5 else { throw SaveGameError.notASaveGame }
        let length = Self.summaryLength(in: fixed)
        let summary = try handle.read(upToCount: length) ?? Data()
        return try Self.decodeHeader(fixed + summary).summary
    }

    private static func decodeHeader(_ data: Data) throws -> (SaveGameSummary, Data.Index) {
        let fixedLength = magic.count + 1 + 4
        guard data.count >= fixedLength, Array(data.prefix(magic.count)) == magic else { throw SaveGameError.notASaveGame }
        let version = data[data.startIndex + magic.count]
        guard version <= formatVersion else { throw SaveGameError.newerFormat(Int(version)) }
        let length = summaryLength(in: data)
        let start = data.startIndex + fixedLength
        guard data.count >= fixedLength + length else { throw SaveGameError.corrupted("summary is cut off") }
        do {
            let summary = try JSONDecoder.saveGame.decode(SaveGameSummary.self, from: data.subdata(in: start..<start + length))
            return (summary, start + length)
        } catch {
            throw SaveGameError.corrupted(String(describing: error))
        }
    }

    private static func summaryLength(in data: Data) -> Int {
        let offset = data.startIndex + magic.count + 1
        return data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
    }

    /// A file name from the save's name: letters, digits, dashes and underscores only.
    static func fileName(for name: String) -> String {
        let allowed = name.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? Character(scalar) : "-"
        }
        let base = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return (base.isEmpty ? "Save" : base) + "." + fileExtension
    }
}

private extension JSONEncoder {
    static var saveGame: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

private extension JSONDecoder {
    static var saveGame: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

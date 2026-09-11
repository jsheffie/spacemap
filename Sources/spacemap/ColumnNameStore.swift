import Foundation

// Column names edited in the HUD (#52).
//
// These live outside ~/.config/spacemap/config on purpose. Writing them back to
// the config would mean rewriting a file the user maintains by hand: it carries
// comments and commented-out alternates, and ConfigReader's parser is lossy --
// it keeps no comments, no ordering and no blank lines -- so regenerating the
// file from a GridConfig would destroy all of that. Instead the config stays
// read-only and HUD edits go somewhere spacemap owns outright.
//
// Directory choice mirrors DesktopColorizer.colorsDirectory, and for the same
// reason: `make dev1` wipes /Applications/spacemap.app, so anything that must
// outlive a reinstall cannot live in the bundle or in .build/.
enum ColumnNameStore {
    static var fileURL: URL {
        URL(fileURLWithPath: NSString(string: "~/Library/Application Support/spacemap/column-names")
            .expandingTildeInPath)
    }

    // Written in the same KEY=VALUE shape as the config file rather than JSON,
    // so the file stays greppable and hand-fixable with an editor, and so the
    // parsing can reuse ConfigReader's list parser instead of gaining a second
    // format to keep in sync.
    private static let key = "COLUMN_NAMES"

    // nil means "no state file" -- distinct from an empty list, which is a real
    // saved value meaning every column was cleared. Callers must not collapse
    // the two: nil falls back to the config, [] overrides it.
    static func load() -> [String]? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            return ConfigReader.parseNameList(parts[1])
        }
        return nil
    }

    @discardableResult
    static func save(_ names: [String]) -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("spacemap: could not create \(dir.path): \(error.localizedDescription)")
            return false
        }

        let body = """
        # Column names edited in the spacemap HUD. This file takes precedence over
        # COLUMN_NAMES in ~/.config/spacemap/config. Delete it (or use "Reset column
        # names" in the menubar) to go back to the config's names.
        \(key)=\(names.joined(separator: ","))

        """
        guard let data = body.data(using: .utf8) else { return false }
        do {
            // Atomic because this is the user's own text: a truncated write would
            // silently lose names they typed. The colorizer writes its PNGs bare,
            // but those are regenerable from the palette and these are not.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("spacemap: could not write \(fileURL.path): \(error.localizedDescription)")
            return false
        }
        return true
    }

    // Deleting the file rather than writing an empty list is what makes the
    // config's COLUMN_NAMES visible again -- load() returns nil, not [].
    @discardableResult
    static func reset() -> Bool {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            print("spacemap: could not remove \(fileURL.path): \(error.localizedDescription)")
            return false
        }
        return true
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}

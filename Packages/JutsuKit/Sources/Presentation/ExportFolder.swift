import Foundation

/// The folder a delivery set or Export for Editing writes to. Neither writes over a file already there.
public enum ExportFolder {
    /// The names already in `folder`, lowercased, as the usual case-insensitive volumes compare them; none for a
    /// folder that isn't there yet.
    public static func existingNames(in folder: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return Set(names.map { $0.lowercased() })
    }
}

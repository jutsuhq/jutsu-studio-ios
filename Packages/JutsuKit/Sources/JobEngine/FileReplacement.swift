import Foundation

/// Puts a finished file where the app named it, replacing a file already there.
public enum FileReplacement {
    /// Across volumes, stage a complete copy on the target volume before atomically renaming it over the old file.
    /// The copy is staged in a folder beside the target; a failed copy leaves both originals intact.
    public static func move(_ finished: URL, to target: URL) throws {
        guard rename(finished.path, target.path) != 0 else { return }
        let failure = errno
        guard failure == EXDEV else { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
        let manager = FileManager.default
        let folder = target.deletingLastPathComponent().appendingPathComponent(".replacement-\(UUID())")
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: folder) }
        let staged = folder.appendingPathComponent("result")
        try manager.copyItem(at: finished, to: staged)
        guard rename(staged.path, target.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try? manager.removeItem(at: finished)
    }
}

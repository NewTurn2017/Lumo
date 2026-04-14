import Foundation

/// Pure path helpers for the MLX server install + model cache layout.
/// No filesystem side effects. `home` defaults to the current user's home,
/// but is overridable for tests.
enum MLXPaths {
    static func venvRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("Lumo", isDirectory: true)
            .appendingPathComponent("mlx-venv", isDirectory: true)
    }

    static func serverExecutable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        venvRoot(home: home)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("mlx_lm.server")
    }

    static func pipExecutable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        venvRoot(home: home)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("pip")
    }

    static func hfHubRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
    }

    /// HF cache encodes `org/name` as `models--org--name`. Multiple slashes
    /// become additional `--` separators.
    static func hfFolderName(modelID: String) -> String {
        "models--" + modelID.split(separator: "/").joined(separator: "--")
    }

    /// Returns the absolute path of the HF cache directory for `modelID`
    /// if it exists on disk, otherwise nil.
    static func detectModel(
        modelID: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL? {
        let folder = hfHubRoot(home: home)
            .appendingPathComponent(hfFolderName(modelID: modelID), isDirectory: true)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            return nil
        }
        return folder
    }
}

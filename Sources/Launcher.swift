import CoreServices
import Foundation

/// Spotlight doesn't index Homebrew's folders, so an app installed by a formula can't be found with ⌘Space.
/// When Mic Mini runs from Homebrew, it keeps a tiny launcher app in ~/Applications that opens it.
/// The launcher points at Homebrew's stable `opt` path, so it keeps working across upgrades.
enum SpotlightLauncher {
    private static let identifier = "com.philippesoubrie.micmini.launcher"
    private static let executable = "mic-mini-launcher"

    static func install() {
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard let cellar = app.path.range(of: "/Cellar/mic-mini/") else { return }
        let target = app.path[..<cellar.lowerBound] + "/opt/mic-mini/" + app.lastPathComponent
        guard !target.contains("'") else { return }

        let fileManager = FileManager.default
        let launcher = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Mic Mini.app", isDirectory: true)
        let contents = launcher.appendingPathComponent("Contents", isDirectory: true)
        let scriptURL = contents.appendingPathComponent("MacOS/\(executable)")
        let plistURL = contents.appendingPathComponent("Info.plist")
        let script = "#!/bin/sh\nexec /usr/bin/open '\(target)'\n"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let iconURL = contents.appendingPathComponent("Resources/AppIcon.icns")

        if fileManager.fileExists(atPath: launcher.path) {
            // Leave alone anything that isn't our launcher, such as a copy of the app put there by hand.
            guard let existing = NSDictionary(contentsOf: plistURL),
                  existing["CFBundleIdentifier"] as? String == identifier
            else { return }
            // Rewrite it when Mic Mini is upgraded, so it picks up a new icon or name.
            if existing["CFBundleShortVersionString"] as? String == version,
               (try? String(contentsOf: scriptURL, encoding: .utf8)) == script { return }
        }

        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": executable,
            "CFBundleIconFile": "AppIcon",
            "CFBundleShortVersionString": version,
            "CFBundleIdentifier": identifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "Mic Mini",
            "CFBundlePackageType": "APPL",
            "LSUIElement": true,
        ]
        do {
            try fileManager.createDirectory(
                at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
                try fileManager.createDirectory(
                    at: iconURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? fileManager.removeItem(at: iconURL)
                try fileManager.copyItem(at: icon, to: iconURL)
            }
            // Tell Launch Services and Spotlight about the new icon right away.
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: launcher.path)
            LSRegisterURL(launcher as CFURL, true)
        } catch {
            // Not worth bothering anyone about: Mic Mini still runs, it just can't be found in Spotlight.
        }
    }
}

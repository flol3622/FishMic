import AppKit
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class Preferences {
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let directoryKey = "RecordingDirectory"
    private static let bitRateKey = "RecordingBitRate"
    private static let opensAtLoginKey = "OpensAtLogin"

    var directory: URL {
        didSet { defaults.set(directory.path, forKey: Self.directoryKey) }
    }

    var bitRate: Int {
        didSet { defaults.set(bitRate, forKey: Self.bitRateKey) }
    }

    /// Whether Mic Mini starts when you log in. On by default, so it's back in the notch after a restart.
    private(set) var opensAtLogin: Bool
    /// macOS can require the user to allow the login item in System Settings.
    private(set) var loginItemNeedsApproval = false

    init() {
        if let path = defaults.string(forKey: Self.directoryKey), !path.isEmpty {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
            directory = music.appendingPathComponent("Mic Mini", isDirectory: true)
        }
        bitRate = defaults.integer(forKey: Self.bitRateKey) == 48_000 ? 48_000 : 32_000
        opensAtLogin = defaults.object(forKey: Self.opensAtLoginKey) as? Bool ?? true
    }

    /// Registers or removes the login item to match the setting. Returns an error message on failure.
    /// Called at every launch too, so the login item follows the app when Homebrew moves it.
    @discardableResult
    func setOpensAtLogin(_ enabled: Bool) -> String? {
        opensAtLogin = enabled
        defaults.set(enabled, forKey: Self.opensAtLoginKey)
        let service = SMAppService.mainApp
        defer { loginItemNeedsApproval = service.status == .requiresApproval }
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            return nil
        } catch {
            return "Couldn’t change the login item. \(error.localizedDescription)"
        }
    }

    /// Opens the recordings folder in Finder, creating it if needed. Returns an error message on failure.
    func openDirectory() -> String? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return NSWorkspace.shared.open(directory) ? nil : "Finder couldn’t open the recordings folder."
        } catch {
            return error.localizedDescription
        }
    }
}

@MainActor
final class SettingsWindow: NSWindowController {
    init(preferences: Preferences, onError: @escaping (String) -> Void) {
        let host = NSHostingController(rootView: SettingsView(preferences: preferences, onError: onError))
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = "Mic Mini Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { nil }
}

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let onError: (String) -> Void

    private var abbreviatedPath: String {
        (preferences.directory.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Choose…", action: chooseDirectory)
                } label: {
                    Text("Save recordings to")
                    Text(abbreviatedPath)
                        .truncationMode(.middle)
                        .help(preferences.directory.path)
                }

                Picker("Audio quality", selection: $preferences.bitRate) {
                    Text("Compact · 32 kbps · ~15 MB/hour").tag(32_000)
                    Text("Higher quality · 48 kbps · ~22 MB/hour").tag(48_000)
                }
            } footer: {
                Text("Mono M4A from the current macOS microphone.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { preferences.opensAtLogin },
                    set: { enabled in
                        if let message = preferences.setOpensAtLogin(enabled) { onError(message) }
                    }
                ))
                if preferences.loginItemNeedsApproval {
                    LabeledContent {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Text("Waiting for approval")
                        Text("Allow Mic Mini in System Settings to start it at login.")
                    }
                }
            }

            Section {
                HStack {
                    Button("Quit Mic Mini") { NSApp.terminate(nil) }
                    Spacer()
                    Button("Open Folder") {
                        if let message = preferences.openDirectory() { onError(message) }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseDirectory() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = true
        picker.directoryURL = preferences.directory
        picker.prompt = "Choose"
        let preferences = preferences
        let handler: (NSApplication.ModalResponse) -> Void = { result in
            guard result == .OK, let directory = picker.url else { return }
            preferences.directory = directory
        }
        if let window = NSApp.keyWindow {
            picker.beginSheetModal(for: window, completionHandler: handler)
        } else {
            picker.begin(completionHandler: handler)
        }
    }
}

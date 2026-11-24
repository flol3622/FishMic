import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = MeetingRecorder()
    private let preferences = Preferences()
    private lazy var island = IslandController(recorder: recorder)
    private var settingsWindow: SettingsWindow?
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        recorder.onStateChange = { [weak self] state in self?.island.recordingStateChanged(state) }
        recorder.onSaved = { [weak self] url, duration in
            guard let self, !isQuitting else { return }
            island.showSaved(url, duration: duration)
        }
        recorder.onError = { [weak self] message in self?.showError(message) }

        let model = island.model
        model.onRecord = { [weak self] in self?.toggleRecording() }
        model.onPause = { [weak self] in self?.togglePause() }
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onOpenFolder = { [weak self] in
            guard let self, let message = preferences.openDirectory() else { return }
            showError(message)
        }
        model.onReveal = { url in NSWorkspace.shared.activateFileViewerSelecting([url]) }
        island.startMonitoring()
        preferences.setOpensAtLogin(preferences.opensAtLogin)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        island.reveal()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isQuitting = true
        recorder.stop()
        island.stopMonitoring()
        return .terminateNow
    }

    private func toggleRecording() {
        switch recorder.state {
        case .idle:
            recorder.start(in: preferences.directory, bitRate: preferences.bitRate)
        case .recording, .paused:
            recorder.stop()
        case .requestingPermission:
            return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func togglePause() {
        switch recorder.state {
        case .recording: recorder.pause()
        case .paused: recorder.resume()
        case .idle, .requestingPermission: return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(preferences: preferences) { [weak self] message in
                self?.showError(message)
            }
        }

        NSApp.activate()
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Mic Mini"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}

@main
struct MicMini {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

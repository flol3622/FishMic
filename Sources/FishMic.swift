import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = MeetingRecorder()
    private let preferences = Preferences()
    private lazy var island = IslandController(recorder: recorder)
    private lazy var menuBar = MenuBarController(recorder: recorder)
    private var settingsWindow: SettingsWindow?
    private var isQuitting = false
    private var waitsForExport = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        recorder.onStateChange = { [weak self] state in
            self?.island.recordingStateChanged(state)
            self?.menuBar.recordingStateChanged(state)
        }
        recorder.onSaved = { [weak self] url, duration in
            guard let self, !isQuitting else { return }
            menuBar.showSaved(url, duration: duration)
        }
        recorder.onError = { [weak self] message in self?.showError(message) }
        recorder.onExportingChange = { [weak self] exporting in
            guard let self else { return }
            menuBar.exportingChanged(exporting)
            if !exporting, waitsForExport {
                waitsForExport = false
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }

        let model = menuBar.model
        model.onRecord = { [weak self] in self?.toggleRecording() }
        model.onPause = { [weak self] in self?.togglePause() }
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onOpenFolder = { [weak self] in
            guard let self, let message = preferences.openDirectory() else { return }
            showError(message)
        }
        model.onReveal = { url in NSWorkspace.shared.activateFileViewerSelecting([url]) }
        island.onCatch = { [weak self] in self?.toggleRecording() }
        island.start()
        preferences.setOpensAtLogin(preferences.opensAtLogin)
        SpotlightLauncher.install()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar.showPopover()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isQuitting = true
        recorder.stop()
        island.stop()
        // Let a conversion to MP3 finish first, so the recording isn't left half-converted.
        if recorder.isExporting {
            waitsForExport = true
            return .terminateLater
        }
        return .terminateNow
    }

    private func toggleRecording() {
        switch recorder.state {
        case .idle:
            recorder.start(in: preferences.directory, bitRate: preferences.bitRate, format: preferences.format)
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
        alert.messageText = "FishMic"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}

@main
struct FishMic {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

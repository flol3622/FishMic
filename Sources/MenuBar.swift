import AppKit
import SwiftUI

// MARK: - Model

@MainActor
@Observable
final class PanelModel {
    struct Recording: Equatable {
        var url: URL
        var duration: TimeInterval
    }

    var recorderState: MeetingRecorder.State = .idle
    var inputName: String?
    var lastRecording: Recording?
    /// A finished recording is being converted to MP3.
    var isExporting = false

    @ObservationIgnored var onRecord: () -> Void = {}
    @ObservationIgnored var onPause: () -> Void = {}
    @ObservationIgnored var onSettings: () -> Void = {}
    @ObservationIgnored var onOpenFolder: () -> Void = {}
    @ObservationIgnored var onReveal: (URL) -> Void = { _ in }
    @ObservationIgnored var dismiss: () -> Void = {}
}

// MARK: - Menu bar item

/// FishMic's home: a menu bar icon that opens the controls in a popover.
/// Right-click (or Control-click) for a small menu with Settings and Quit.
@MainActor
final class MenuBarController: NSObject {
    let model = PanelModel()

    private let recorder: MeetingRecorder
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var savedTask: DispatchWorkItem?
    private var showsSaved = false

    init(recorder: MeetingRecorder) {
        self.recorder = recorder
        super.init()

        popover.behavior = .transient
        let host = NSHostingController(rootView: PanelView(model: model))
        host.sizingOptions = []
        // A fixed size: the popover is positioned from it, so a size that settles later leaves a gap under the icon.
        popover.contentSize = PanelView.size
        popover.contentViewController = host
        model.dismiss = { [weak self] in self?.popover.performClose(nil) }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()
    }

    func recordingStateChanged(_ state: MeetingRecorder.State) {
        model.recorderState = state
        model.inputName = recorder.inputName
        if state != .idle { setSaved(false) }
        updateIcon()
    }

    func exportingChanged(_ exporting: Bool) {
        model.isExporting = exporting
        updateIcon()
    }

    /// Flashes a checkmark in the menu bar and remembers the recording for the popover.
    func showSaved(_ url: URL, duration: TimeInterval) {
        model.lastRecording = .init(url: url, duration: duration)
        setSaved(true)
        let task = DispatchWorkItem { [weak self] in self?.setSaved(false) }
        savedTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        model.inputName = recorder.inputName
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func setSaved(_ saved: Bool) {
        savedTask?.cancel()
        savedTask = nil
        showsSaved = saved
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        let tint: NSColor?
        let label: String
        if showsSaved {
            (symbol, tint, label) = ("checkmark.circle.fill", nil, "FishMic, recording saved")
        } else {
            switch model.recorderState {
            case .recording: (symbol, tint, label) = ("fish.fill", .systemRed, "FishMic, recording")
            case .paused: (symbol, tint, label) = ("pause.circle.fill", nil, "FishMic, paused")
            case .idle where model.isExporting: (symbol, tint, label) = ("arrow.down.circle", nil, "FishMic, saving MP3")
            case .idle, .requestingPermission: (symbol, tint, label) = ("fish", nil, "FishMic")
            }
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.contentTintColor = tint
        button.toolTip = "FishMic"
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FishMic", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() { model.onSettings() }
    @objc private func openFolder() { model.onOpenFolder() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Popover

struct PanelView: View {
    let model: PanelModel

    static let size = CGSize(width: 380, height: 72)

    @Namespace private var glass

    var body: some View {
        HStack(spacing: 12) {
            details
                .frame(maxWidth: .infinity, alignment: .leading)
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    if model.recorderState == .idle || model.recorderState == .requestingPermission {
                        roundButton("folder", label: "Open Recordings Folder", id: "secondary", action: model.onOpenFolder)
                        roundButton("gearshape", label: "Settings", id: "tertiary", action: model.onSettings)
                        roundButton("fish", label: "Record", id: "primary", tint: .teal, action: model.onRecord)
                            .disabled(model.recorderState == .requestingPermission)
                    } else {
                        let paused = model.recorderState == .paused
                        roundButton(paused ? "record.circle" : "pause.fill",
                                    label: paused ? "Resume" : "Pause", id: "secondary", closes: false, action: model.onPause)
                        roundButton("stop.fill", label: "Stop and Save", id: "primary", tint: .red, action: model.onRecord)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @ViewBuilder
    private var details: some View {
        let (title, subtitle) = detailText
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .contentTransition(.interpolate)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .overlay {
            if model.recorderState == .idle, !model.isExporting, let recording = model.lastRecording {
                Button {
                    model.onReveal(recording.url)
                    model.dismiss()
                } label: { Color.clear.contentShape(.rect) }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                    .accessibilityLabel("Show last recording in Finder")
            }
        }
    }

    private var detailText: (String, String) {
        let microphone = model.inputName ?? "No microphone found"
        switch model.recorderState {
        case .idle:
            if model.isExporting {
                return ("Saving MP3…", "Converting the recording")
            }
            if let recording = model.lastRecording {
                return ("Saved · \(spokenDuration(recording.duration))", recording.url.deletingPathExtension().lastPathComponent)
            }
            return ("Ready to record", microphone)
        case .requestingPermission:
            return ("Waiting for access", "Allow the microphone when macOS asks")
        case .recording:
            return ("Recording", microphone)
        case .paused:
            return ("Paused", "Resume to keep adding to this recording")
        }
    }

    /// A Liquid Glass control; the primary action gets a tinted fill and glyph.
    /// Most actions close the popover, so it gets out of the way.
    private func roundButton(
        _ symbol: String, label: String, id: String, tint: Color? = nil, closes: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            if closes { model.dismiss() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .frame(width: 40, height: 40)
                .background(tint?.opacity(0.3) ?? .clear, in: .circle)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID(id, in: glass)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Formatting

func spokenDuration(_ interval: TimeInterval) -> String {
    let units: Set<Duration.UnitsFormatStyle.Unit> = interval < 60 ? [.seconds] : [.hours, .minutes]
    return Duration.seconds(max(0, interval.rounded())).formatted(.units(allowed: units, width: .abbreviated))
}

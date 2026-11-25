import AppKit
import SwiftUI

// MARK: - Model

@MainActor
@Observable
final class IslandModel {
    enum Mode: Equatable {
        /// Tucked behind the notch, invisible.
        case hidden
        /// A recording is live: a level meter and timer flank the notch.
        case compact
        /// A short confirmation after a recording is saved.
        case saved
        /// The pointer is over the island: full controls.
        case expanded
    }

    struct Recording: Equatable {
        var url: URL
        var duration: TimeInterval
    }

    /// Width of the content on each side of the notch in the saved confirmation.
    static let side: CGFloat = 72
    static let rowHeight: CGFloat = 66

    var hasNotch = false
    /// The hardware notch, or a small virtual gap on displays without one.
    var notch = CGSize(width: 10, height: 30)

    var isHovering = false
    var isConfirmingSave = false
    var recorderState: MeetingRecorder.State = .idle
    var levels: [Double] = Array(repeating: 0, count: 5)
    var inputName: String?
    var lastRecording: Recording?

    @ObservationIgnored var onRecord: () -> Void = {}
    @ObservationIgnored var onPause: () -> Void = {}
    @ObservationIgnored var onSettings: () -> Void = {}
    @ObservationIgnored var onOpenFolder: () -> Void = {}
    @ObservationIgnored var onReveal: (URL) -> Void = { _ in }

    var mode: Mode {
        if isHovering { return .expanded }
        if recorderState != .idle { return .compact }
        if isConfirmingSave { return .saved }
        return .hidden
    }

    /// The top row shares the notch's height and keeps its content clear of the notch.
    var showsTopRow: Bool { hasNotch || recorderState != .idle }

    /// Width of the concave curves that blend the island into the top edge of the screen.
    var earRadius: CGFloat { hasNotch ? 7 : 0 }

    var maximumSize: CGSize { size(for: .expanded) }

    /// Width of the fish's lane right of the notch while recording. On a notched display it's wide
    /// enough to cover the menu bar next to the notch, where macOS shows its microphone indicator
    /// and the nearest tray icons.
    var swimLane: CGFloat { hasNotch ? 230 : Self.side }

    func size(for mode: Mode) -> CGSize {
        switch mode {
        case .hidden:
            hasNotch
                ? CGSize(width: max(0, notch.width - 2 * earRadius - 8), height: max(0, notch.height - 2))
                : CGSize(width: notch.width + swimLane, height: notch.height)
        case .compact:
            // Only the fish, right of the notch.
            CGSize(width: notch.width + swimLane, height: notch.height)
        case .saved:
            CGSize(width: notch.width + 2 * Self.side, height: notch.height)
        case .expanded:
            CGSize(
                width: max(notch.width + 2 * swimLane, 410),
                height: (showsTopRow ? notch.height : 0) + Self.rowHeight
            )
        }
    }

    /// Horizontal shift from the notch's center. The compact island grows to the right only.
    func offset(for mode: Mode) -> CGFloat {
        mode == .compact && hasNotch ? swimLane / 2 : 0
    }

    func bottomRadius(for mode: Mode) -> CGFloat {
        switch mode {
        case .hidden: hasNotch ? 8 : notch.height / 2
        case .compact, .saved: hasNotch ? 13 : notch.height / 2
        case .expanded: hasNotch ? 26 : 24
        }
    }
}

// MARK: - Window

@MainActor
final class IslandController: NSObject {
    let model = IslandModel()

    private let recorder: MeetingRecorder
    private let panel = IslandPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var monitors: [Any] = []
    private var meterTimer: Timer?
    private var hoverTimer: Timer?
    private var collapseTask: DispatchWorkItem?
    private var savedTask: DispatchWorkItem?

    /// Screen position of the island's top center.
    private var anchor = NSPoint.zero
    /// Hovering here reveals the island while it's hidden.
    private var revealArea = NSRect.zero

    private static let shadowMargin: CGFloat = 40
    private static let menuBarGap: CGFloat = 6

    init(recorder: MeetingRecorder) {
        self.recorder = recorder
        super.init()

        panel.title = "Mic Mini"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        // Above the menu bar, so the island can grow out of the notch.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [
            .canJoinAllSpaces, .canJoinAllApplications, .stationary, .fullScreenAuxiliary, .ignoresCycle
        ]

        let host = IslandHostingView(rootView: IslandView(model: model))
        host.sizingOptions = []
        panel.contentView = host
    }

    func startMonitoring() {
        reposition()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in self?.pointerMoved() }
        ) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
                self?.pointerMoved()
                return event
            }
        ) {
            monitors.append(local)
        }
    }

    func stopMonitoring() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        collapseTask?.cancel()
        savedTask?.cancel()
        stopMeter()
        stopHoverTimer()
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
    }

    /// Shows the controls briefly, for example when the app is opened again from Finder.
    func reveal() {
        expand()
        scheduleCollapse(after: 2.5)
    }

    func recordingStateChanged(_ state: MeetingRecorder.State) {
        model.recorderState = state
        model.inputName = recorder.inputName
        if state == .idle {
            stopMeter()
            model.levels = model.levels.map { _ in 0 }
        } else {
            isConfirmingSave(false)
            startMeter()
        }
        updatePointerPassthrough()
    }

    func showSaved(_ url: URL, duration: TimeInterval) {
        model.lastRecording = .init(url: url, duration: duration)
        isConfirmingSave(true)
        let task = DispatchWorkItem { [weak self] in self?.isConfirmingSave(false) }
        savedTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }

    private func isConfirmingSave(_ confirming: Bool) {
        savedTask?.cancel()
        savedTask = nil
        model.isConfirmingSave = confirming
        updatePointerPassthrough()
    }

    // MARK: Level meter

    private func startMeter() {
        guard meterTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleMeter() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
        sampleMeter()
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func sampleMeter() {
        var levels = model.levels
        levels.removeFirst()
        levels.append(recorder.level())
        model.levels = levels
    }

    // MARK: Hover

    private func islandRect(for mode: IslandModel.Mode) -> NSRect {
        let size = model.size(for: mode)
        let width = size.width + 2 * model.earRadius
        return NSRect(x: anchor.x + model.offset(for: mode) - width / 2, y: anchor.y - size.height, width: width, height: size.height)
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        let mode = model.mode
        let overIsland = mode != .hidden && islandRect(for: mode).insetBy(dx: -4, dy: -4).contains(point)
        let over = overIsland || revealArea.contains(point)

        if model.isHovering {
            if over {
                collapseTask?.cancel()
                collapseTask = nil
            } else if collapseTask == nil {
                scheduleCollapse(after: 0.3)
            }
        } else if over {
            expand()
        }
        updatePointerPassthrough()
    }

    private func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        guard !model.isHovering else { return }
        model.isHovering = true
        model.inputName = recorder.inputName
        startHoverTimer()
        updatePointerPassthrough()
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            collapseTask = nil
            let point = NSEvent.mouseLocation
            guard !islandRect(for: .expanded).contains(point), !revealArea.contains(point) else { return }
            model.isHovering = false
            stopHoverTimer()
            updatePointerPassthrough()
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    /// Mouse events can be missed when the pointer leaves quickly, so check while expanded.
    private func startHoverTimer() {
        guard hoverTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    /// The panel is larger than the island. Let clicks outside the island reach the apps below.
    private func updatePointerPassthrough() {
        let mode = model.mode
        let inside = mode != .hidden && islandRect(for: mode).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
    }

    // MARK: Layout

    @objc private func reposition() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main ?? NSScreen.screens.first
        else { return }

        let panelTop: CGFloat
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // Measure from the left area's edge, so the result doesn't depend on its coordinate origin.
            let center = screen.frame.minX + (left.maxX + right.minX) / 2 - left.minX
            let height = screen.safeAreaInsets.top
            model.hasNotch = true
            model.notch = CGSize(width: right.minX - left.maxX, height: height)
            panelTop = screen.frame.maxY
            anchor = NSPoint(x: center, y: panelTop)
            revealArea = NSRect(x: center - 39, y: panelTop - height - 12, width: 78, height: height + 12)
        } else {
            let menuBarBottom = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
            let center = screen.frame.midX
            model.hasNotch = false
            model.notch = CGSize(width: 10, height: 30)
            panelTop = menuBarBottom
            anchor = NSPoint(x: center, y: menuBarBottom - Self.menuBarGap)
            revealArea = NSRect(x: center - 39, y: menuBarBottom - 12, width: 78, height: 12)
        }

        let maximum = model.maximumSize
        let width = maximum.width + 2 * model.earRadius + 2 * Self.shadowMargin
        let height = (panelTop - anchor.y) + maximum.height + Self.shadowMargin
        panel.setFrame(
            NSRect(x: anchor.x - width / 2, y: panelTop - height, width: width, height: height),
            display: true
        )
        updatePointerPassthrough()
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Lets a click act on the island's buttons while another app is active.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Views

struct IslandView: View {
    let model: IslandModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemColorScheme
    @Namespace private var glass

    var body: some View {
        let mode = model.mode
        let size = model.size(for: mode)

        island(mode: mode, size: size)
            .offset(x: model.offset(for: mode))
            .padding(.top, model.hasNotch ? 0 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, model.hasNotch ? .dark : systemColorScheme)
            // The panel never becomes key; draw its controls as active anyway, with their tints.
            .environment(\.appearsActive, true)
            .animation(animation, value: mode)
            .animation(reduceMotion ? nil : .smooth(duration: 0.12), value: model.levels)
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.26)
    }

    @ViewBuilder
    private func island(mode: IslandModel.Mode, size: CGSize) -> some View {
        let content = content(mode: mode)
            .frame(width: size.width, height: size.height, alignment: .top)
            .padding(.horizontal, model.earRadius)

        if model.hasNotch {
            // Black like the notch it grows from.
            let shape = IslandShape(earRadius: model.earRadius, bottomRadius: model.bottomRadius(for: mode))
            content
                .background(.black, in: shape)
                .clipShape(shape)
                .shadow(color: .black.opacity(mode == .expanded ? 0.32 : 0), radius: 16, y: 6)
        } else {
            let shape = RoundedRectangle(cornerRadius: model.bottomRadius(for: mode), style: .continuous)
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
                .opacity(mode == .hidden ? 0 : 1)
                .scaleEffect(mode == .hidden && !reduceMotion ? 0.6 : 1, anchor: .top)
        }
    }

    @ViewBuilder
    private func content(mode: IslandModel.Mode) -> some View {
        switch mode {
        case .hidden:
            Color.clear
        case .compact:
            topRow(leadingWidth: 0, trailingWidth: model.swimLane) { EmptyView() } trailing: { activityIndicator }
                .transition(contentTransition)
        case .saved:
            topRow(leadingWidth: IslandModel.side, trailingWidth: IslandModel.side) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.symbolEffect(.drawOn))
            } trailing: {
                Text("Saved")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .transition(contentTransition)
            .accessibilityElement(children: .combine)
        case .expanded:
            VStack(spacing: 0) {
                if model.showsTopRow {
                    topRow(leadingWidth: model.swimLane, trailingWidth: model.swimLane) {
                        EmptyView()
                    } trailing: {
                        if model.recorderState != .idle { activityIndicator }
                    }
                }
                controls
                    .frame(height: IslandModel.rowHeight)
            }
            .transition(contentTransition)
        }
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }

    /// Content beside the notch, keeping the middle clear.
    private func topRow<Leading: View, Trailing: View>(
        leadingWidth: CGFloat, trailingWidth: CGFloat,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 0) {
            if leadingWidth > 0 {
                leading()
                    .frame(width: leadingWidth - 20, alignment: .leading)
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
            }
            Color.clear.frame(width: model.notch.width)
            if trailingWidth > 0 {
                trailing()
                    .frame(width: trailingWidth - 20, alignment: .trailing)
                    .padding(.leading, 6)
                    .padding(.trailing, 14)
            }
        }
        .frame(height: model.notch.height)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var activityIndicator: some View {
        switch model.recorderState {
        case .requestingPermission:
            ProgressView().controlSize(.mini)
        case .recording, .paused:
            SwimmingFish(levels: model.levels, isPaused: model.recorderState == .paused, reduceMotion: reduceMotion)
        case .idle:
            EmptyView()
        }
    }

    // MARK: Expanded controls

    private var controls: some View {
        HStack(spacing: 12) {
            details
            Spacer(minLength: 8)
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
                                    label: paused ? "Resume" : "Pause", id: "secondary", action: model.onPause)
                        roundButton("stop.fill", label: "Stop and Save", id: "primary", tint: .red, action: model.onRecord)
                    }
                }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.bottom, model.showsTopRow ? 6 : 0)
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
            if model.recorderState == .idle, let recording = model.lastRecording {
                Button { model.onReveal(recording.url) } label: { Color.clear.contentShape(.rect) }
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

    /// A Liquid Glass control. On the black island, glass alone can't show a tint, so the primary
    /// action gets a tinted fill and glyph, as Live Activity controls do.
    private func roundButton(
        _ symbol: String, label: String, id: String, tint: Color? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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

/// A blue fish that swims back and forth right of the notch while recording.
/// It beats its tail harder when the microphone hears sound, and rests while paused.
private struct SwimmingFish: View {
    let levels: [Double]
    let isPaused: Bool
    let reduceMotion: Bool

    private static let size: CGFloat = 22
    /// Seconds for one lap there and back: at least 8, and longer in a wide lane so the fish doesn't speed up.
    private static func lap(travel: CGFloat) -> Double { max(8, 8 * travel / 47) }

    var body: some View {
        let level = levels.suffix(3).reduce(0, +) / 3
        let still = isPaused || reduceMotion

        GeometryReader { proxy in
            let travel = max(0, (proxy.size.width - Self.size) / 2)
            TimelineView(.animation(paused: still)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let angle = 2 * .pi * time / Self.lap(travel: travel)
                let bob = 2 * .pi * time / 8 * 2.6
                // Turning squeezes the fish through zero width, so it reads as a turn rather than a flip.
                let facing = still ? 1 : max(-1, min(1, 3 * cos(angle)))
                let tail = still ? 0 : (3 + 14 * level) * sin(time * 11)

                Image(systemName: "fish.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isPaused ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.blue.gradient))
                    .opacity(reduceMotion && !isPaused ? 0.55 + 0.45 * level : 1)
                    .rotationEffect(.degrees(tail), anchor: UnitPoint(x: 0.7, y: 0.5))
                    .scaleEffect(x: facing, y: 1)
                    .offset(
                        x: still ? 0 : travel * sin(angle),
                        y: still ? 0 : 1.5 * sin(bob)
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .frame(height: Self.size)
        .animation(.smooth(duration: 0.3), value: isPaused)
        .accessibilityElement()
        .accessibilityLabel(isPaused ? "Paused" : "Recording")
    }
}

/// A notch extension: flush with the top edge, with concave top corners and rounded bottom corners.
struct IslandShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set { (earRadius, bottomRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let ear = min(earRadius, rect.width / 4, rect.height / 2)
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * ear) / 2, rect.height - ear))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
            control: CGPoint(x: rect.minX + ear, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + ear, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - ear - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - ear, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - ear, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - ear, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Formatting

func spokenDuration(_ interval: TimeInterval) -> String {
    let units: Set<Duration.UnitsFormatStyle.Unit> = interval < 60 ? [.seconds] : [.hours, .minutes]
    return Duration.seconds(max(0, interval.rounded())).formatted(.units(allowed: units, width: .abbreviated))
}

import AppKit
import SwiftUI

// MARK: - Model

/// The island only shows the swimming fish while a recording is live. Everything else lives in the menu bar.
@MainActor
@Observable
final class IslandModel {
    enum Mode: Equatable {
        /// Tucked behind the notch, invisible.
        case hidden
        /// A recording is live: the fish swims beside the notch.
        case compact
    }

    /// Width of the fish's lane right of the notch. On a notched display it's wide enough to cover
    /// the menu bar next to the notch, where macOS shows its microphone indicator and the nearest tray icons.
    var swimLane: CGFloat { hasNotch ? 418 : 72 }

    var hasNotch = false
    /// The hardware notch, or a small virtual gap on displays without one.
    var notch = CGSize(width: 10, height: 30)

    var recorderState: MeetingRecorder.State = .idle
    var levels: [Double] = Array(repeating: 0, count: 5)

    /// Called when the swimming fish is clicked.
    @ObservationIgnored var onCatch: () -> Void = {}

    /// Where the fish was, left or right of the lane's center, when it was caught. Set while the catch animation plays.
    var catchOffset: CGFloat?

    var mode: Mode { recorderState == .idle && catchOffset == nil ? .hidden : .compact }

    /// Width of the concave curves that blend the island into the top edge of the screen.
    var earRadius: CGFloat { hasNotch ? 7 : 0 }

    var maximumSize: CGSize { size(for: .compact) }

    func size(for mode: Mode) -> CGSize {
        switch mode {
        case .hidden:
            hasNotch
                ? CGSize(width: max(0, notch.width - 2 * earRadius - 8), height: max(0, notch.height - 2))
                : CGSize(width: notch.width + swimLane, height: notch.height)
        case .compact:
            CGSize(width: notch.width + swimLane, height: notch.height)
        }
    }

    /// Horizontal shift from the notch's center. The island grows to the right only.
    func offset(for mode: Mode) -> CGFloat {
        mode == .compact && hasNotch ? swimLane / 2 : 0
    }

    func bottomRadius(for mode: Mode) -> CGFloat {
        switch mode {
        case .hidden: hasNotch ? 8 : notch.height / 2
        case .compact: hasNotch ? 13 : notch.height / 2
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
    private var meterTimer: Timer?
    private var pointerTimer: Timer?
    private var catchTask: DispatchWorkItem?
    /// The cursor FishMic last set, so it restores the arrow only once when the pointer leaves.
    private var cursor: PointerCursor = .untouched
    private var isPressing = false
    private var monitors: [Any] = []
    /// Screen position of the island's top center.
    private var anchor = NSPoint.zero

    /// Called after the fish is caught: stops and saves the recording.
    var onCatch: () -> Void = {}

    private static let catchDuration: TimeInterval = 1
    /// How far from the fish's center a click still catches it.
    private static let catchSlack: CGFloat = 20

    private enum PointerCursor { case untouched, arrow, openHand, closedHand }

    private static let shadowMargin: CGFloat = 40
    private static let menuBarGap: CGFloat = 6

    init(recorder: MeetingRecorder) {
        self.recorder = recorder
        super.init()

        panel.title = "FishMic"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Clicks pass through while the island is hidden. While it shows, it takes every click on it,
        // so the menu bar items it covers can't be clicked by accident.
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        // Above the menu bar, so the island can grow out of the notch.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [
            .canJoinAllSpaces, .canJoinAllApplications, .stationary, .fullScreenAuxiliary, .ignoresCycle
        ]

        model.onCatch = { [weak self] in self?.catchFish() }
        panel.onMouseDown = { [weak self] in self?.mouseDown() }
        panel.onMouseUp = { [weak self] in self?.mouseUp() }
        enableBackgroundCursor()

        let host = NSHostingView(rootView: IslandView(model: model))
        host.sizingOptions = []
        panel.contentView = host
    }

    func start() {
        reposition()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in self?.updatePointer() }
        ) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
                self?.updatePointer()
                return event
            }
        ) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        catchTask?.cancel()
        stopMeter()
        stopPointerTimer()
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
    }

    func recordingStateChanged(_ state: MeetingRecorder.State) {
        model.recorderState = state
        if state == .idle {
            stopMeter()
            model.levels = model.levels.map { _ in 0 }
        } else {
            endCatch()
            startMeter()
            startPointerTimer()
        }
        updatePointer()
    }

    /// Plays the catch animation where the fish is, and stops the recording right away.
    private func catchFish() {
        guard model.recorderState == .recording || model.recorderState == .paused else { return }
        model.catchOffset = fishOffset()
        let task = DispatchWorkItem { [weak self] in self?.endCatch() }
        catchTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.catchDuration, execute: task)
        onCatch()
    }

    private func endCatch() {
        catchTask?.cancel()
        catchTask = nil
        model.catchOffset = nil
    }

    // MARK: Pointer

    /// How far the fish is from the lane's center at a given moment.
    private func fishOffset(at time: TimeInterval = Date.timeIntervalSinceReferenceDate) -> CGFloat {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let still = model.recorderState != .recording || reduceMotion
        return still ? 0 : SwimmingFish.offset(at: time, travel: SwimmingFish.travel(lane: model.swimLane))
    }

    /// Whether a click here catches the fish. It also counts where the fish was a moment ago,
    /// so a click that lands just behind a swimming fish isn't a miss.
    private func isOverFish(_ point: NSPoint) -> Bool {
        guard model.recorderState == .recording || model.recorderState == .paused else { return false }
        let centerY = anchor.y - model.notch.height / 2
        guard abs(point.y - centerY) <= model.notch.height / 2 + 4 else { return false }
        let laneCenter = anchor.x + model.offset(for: .compact) + model.notch.width / 2
        let now = Date.timeIntervalSinceReferenceDate
        return [0, 0.08, 0.16].contains { lag in
            abs(point.x - (laneCenter + fishOffset(at: now - lag))) <= Self.catchSlack
        }
    }

    /// The visible island, in screen coordinates.
    private func islandRect() -> NSRect {
        let size = model.size(for: .compact)
        let width = size.width + 2 * model.earRadius
        return NSRect(
            x: anchor.x + model.offset(for: .compact) - width / 2, y: anchor.y - size.height,
            width: width, height: size.height
        )
    }

    private func mouseDown() {
        guard isOverFish(NSEvent.mouseLocation) else { return }
        isPressing = true
        NSCursor.closedHand.set()
        cursor = .closedHand
        catchFish()
    }

    private func mouseUp() {
        isPressing = false
        updatePointer()
    }

    /// Takes the clicks on the visible island, and shows a grabbing hand over the fish.
    private func updatePointer() {
        let point = NSEvent.mouseLocation
        let overIsland = model.mode == .compact && islandRect().contains(point)
        if panel.ignoresMouseEvents == overIsland {
            panel.ignoresMouseEvents = !overIsland
        }

        let wanted: PointerCursor
        if !overIsland {
            wanted = .untouched
        } else if isPressing && (model.catchOffset != nil || isOverFish(point)) {
            wanted = .closedHand
        } else if isOverFish(point) {
            wanted = .openHand
        } else {
            wanted = .arrow
        }

        switch wanted {
        // Set on every update while over the fish, so the app below can't take the cursor back.
        case .openHand: NSCursor.openHand.set()
        case .closedHand: NSCursor.closedHand.set()
        case .arrow: if cursor != .arrow { NSCursor.arrow.set() }
        case .untouched: if cursor != .untouched { NSCursor.arrow.set() }
        }
        cursor = wanted
    }

    /// Checks the pointer often while the island shows: the fish moves even when the mouse doesn't.
    private func startPointerTimer() {
        guard pointerTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updatePointer()
                if self.model.mode == .hidden { self.stopPointerTimer() }
            }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopPointerTimer() {
        pointerTimer?.invalidate()
        pointerTimer = nil
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
            model.hasNotch = true
            model.notch = CGSize(width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            panelTop = screen.frame.maxY
            anchor = NSPoint(x: center, y: panelTop)
        } else {
            let menuBarBottom = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
            model.hasNotch = false
            model.notch = CGSize(width: 10, height: 30)
            panelTop = menuBarBottom
            anchor = NSPoint(x: screen.frame.midX, y: menuBarBottom - Self.menuBarGap)
        }

        let maximum = model.maximumSize
        // The island is centered on the notch, then shifted right: the window must cover the shift on both sides.
        let width = maximum.width + 2 * model.earRadius + 2 * abs(model.offset(for: .compact)) + 2 * Self.shadowMargin
        let height = (panelTop - anchor.y) + maximum.height + Self.shadowMargin
        panel.setFrame(
            NSRect(x: anchor.x - width / 2, y: panelTop - height, width: width, height: height),
            display: true
        )
    }
}

private final class IslandPanel: NSPanel {
    var onMouseDown: () -> Void = {}
    var onMouseUp: () -> Void = {}

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// The island has no controls of its own: it handles clicks here and swallows the rest.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: onMouseDown()
        case .leftMouseUp: onMouseUp()
        case .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel:
            break
        default: super.sendEvent(event)
        }
    }
}

/// Lets a background app change the cursor, so the grabbing hand shows while another app is active.
/// It's a private CoreGraphics call, looked up at run time: if it's missing, the cursor just stays an arrow.
private func enableBackgroundCursor() {
    typealias Connection = @convention(c) () -> Int32
    typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    let everywhere = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
    guard let connectionSymbol = dlsym(everywhere, "_CGSDefaultConnection"),
          let setSymbol = dlsym(everywhere, "CGSSetConnectionProperty")
    else { return }
    let connection = unsafeBitCast(connectionSymbol, to: Connection.self)()
    _ = unsafeBitCast(setSymbol, to: SetProperty.self)(
        connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue
    )
}

// MARK: - Views

struct IslandView: View {
    let model: IslandModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        let mode = model.mode
        let size = model.size(for: mode)

        island(mode: mode, size: size)
            .offset(x: model.offset(for: mode))
            .padding(.top, model.hasNotch ? 0 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, model.hasNotch ? .dark : systemColorScheme)
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
            HStack(spacing: 0) {
                Color.clear.frame(width: model.notch.width)
                activityIndicator
                    .frame(width: model.swimLane - 20)
                    .padding(.horizontal, 10)
            }
            .frame(height: model.notch.height)
            .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
        }
    }

    @ViewBuilder
    private var activityIndicator: some View {
        if let offset = model.catchOffset, model.recorderState == .idle {
            CaughtFish(offset: offset, reduceMotion: reduceMotion)
        } else {
            liveIndicator
        }
    }

    @ViewBuilder
    private var liveIndicator: some View {
        switch model.recorderState {
        case .requestingPermission:
            ProgressView().controlSize(.mini)
        case .recording, .paused:
            SwimmingFish(
                levels: model.levels, isPaused: model.recorderState == .paused,
                reduceMotion: reduceMotion, onCatch: model.onCatch
            )
        case .idle:
            EmptyView()
        }
    }
}

/// The one-second catch animation: the fish pops and wiggles where it was caught, then turns into a checkmark.
private struct CaughtFish: View {
    let offset: CGFloat
    let reduceMotion: Bool

    private struct Frame {
        var scale = 1.0
        var angle = 0.0
        var fish = 1.0
        var check = 0.0
    }

    var body: some View {
        if reduceMotion {
            check(scale: 1).frame(maxWidth: .infinity)
        } else {
            KeyframeAnimator(initialValue: Frame()) { frame in
                ZStack {
                    Image(systemName: "fish.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.blue.gradient)
                        .rotationEffect(.degrees(frame.angle))
                        .scaleEffect(frame.scale)
                        .opacity(frame.fish)
                    check(scale: frame.check)
                }
                .frame(maxWidth: .infinity)
                .offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.7, duration: 0.25, spring: .bouncy)
                    LinearKeyframe(1.7, duration: 0.2)
                    CubicKeyframe(0.2, duration: 0.2)
                    LinearKeyframe(0.2, duration: 0.35)
                }
                KeyframeTrack(\.angle) {
                    CubicKeyframe(-25, duration: 0.1)
                    CubicKeyframe(25, duration: 0.15)
                    CubicKeyframe(-15, duration: 0.1)
                    CubicKeyframe(0, duration: 0.1)
                    LinearKeyframe(0, duration: 0.55)
                }
                KeyframeTrack(\.fish) {
                    LinearKeyframe(1, duration: 0.5)
                    CubicKeyframe(0, duration: 0.15)
                    LinearKeyframe(0, duration: 0.35)
                }
                KeyframeTrack(\.check) {
                    LinearKeyframe(0, duration: 0.5)
                    SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                    LinearKeyframe(1, duration: 0.15)
                }
            }
        }
    }

    private func check(scale: Double) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.green)
            .scaleEffect(scale)
    }
}

/// A blue fish that swims back and forth right of the notch while recording.
/// It beats its tail harder when the microphone hears sound, and rests while paused.
private struct SwimmingFish: View {
    let levels: [Double]
    let isPaused: Bool
    let reduceMotion: Bool
    let onCatch: () -> Void

    private static let size: CGFloat = 22
    /// Seconds for one lap there and back: at least 8, and longer in a wide lane so the fish doesn't speed up.
    private static func lap(travel: CGFloat) -> Double { max(8, 8 * travel / 47) }

    /// How far the fish swims to each side of the lane's center.
    static func travel(lane: CGFloat) -> CGFloat { max(0, (lane - 20 - size) / 2) }

    /// The fish's horizontal offset from the lane's center. The island's controller uses it to know where to catch it.
    static func offset(at time: TimeInterval, travel: CGFloat) -> CGFloat {
        travel * sin(2 * .pi * time / lap(travel: travel))
    }

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
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isPaused ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.blue.gradient))
                    .opacity(reduceMotion && !isPaused ? 0.55 + 0.45 * level : 1)
                    .rotationEffect(.degrees(tail), anchor: UnitPoint(x: 0.7, y: 0.5))
                    .scaleEffect(x: facing, y: 1)
                    .offset(
                        x: still ? 0 : Self.offset(at: time, travel: travel),
                        y: still ? 0 : 1.5 * sin(bob)
                    )
                    // The fish itself is the button: you have to catch it to stop the recording.
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .frame(height: Self.size)
        .animation(.smooth(duration: 0.3), value: isPaused)
        .accessibilityElement()
        .accessibilityLabel(isPaused ? "Paused" : "Recording")
        .accessibilityHint("Click to stop and save")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onCatch)
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

import SwiftUI
import AppKit
import VeylumeCore

protocol SystemActivityPresenting {
    var available: Bool { get }
    var unavailabilityReason: String? { get }
}
struct SystemActivityPresenter: SystemActivityPresenting {
    // SDK 27.0 (26A425): native ActivityKit.ActivityAttributes/Activity explicitly
    // carry @available(macOS, unavailable). Never simulate a system activity.
    let available = false
    var unavailabilityReason: String? { I18n.tr("Live Activities недоступны для macOS. Используется индикатор Veylume.", "macOS Live Activities are unavailable. Veylume uses its own indicator.") }
}

struct MiniIndicator: View {
    @ObservedObject var session: SessionCoordinator
    var openControls: () -> Void
    var layout: IndicatorSurfaceLayout = .mini
    var body: some View {
        IndicatorSurface(phase: session.phase, meter: session.meter, layout: layout, status: session.status, openControls: openControls)
    }
}

/// The same production surface is used in native visual verification, without
/// constructing a session or requesting microphone/storage access.
struct IndicatorSurface: View {
    let phase: SessionPhase
    let meter: AudioMeter
    let layout: IndicatorSurfaceLayout
    var status = ""
    var openControls: () -> Void
    var body: some View {
        if case let .wings(cutoutWidth, height) = layout {
            HStack(spacing: 0) {
                control {
                    Image(systemName: phase == .recording ? "mic.fill" : phase == .cancelling ? "xmark" : "mic")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(phase == .recording ? .red : .white.opacity(0.8))
                        .frame(width: IndicatorSurfaceLayout.wingWidth, height: height)
                }
                Color.clear.frame(width: cutoutWidth, height: height).allowsHitTesting(false).accessibilityHidden(true)
                control {
                    activity(width: 34).frame(width: IndicatorSurfaceLayout.wingWidth, height: height)
                }
            }.background(.black, in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0))
        } else {
            control {
                HStack(spacing: 6) {
                    Circle().fill(phase == .recording ? Color.red : Color.white.opacity(0.8)).frame(width: 4, height: 4)
                    activity(width: layout.size.width - 38)
                }.frame(width: layout.size.width, height: 24).padding(.top, layout.cutoutHeight).background {
                    if layout.attached {
                        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0).fill(.black)
                    } else { Capsule().fill(.black) }
                }
            }
        }
    }
    private func control<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Button(action: openControls) {
            content().contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(status)
            .accessibilityHint(I18n.tr("Открыть остановку и отмену записи", "Open stop and cancel controls"))
    }
    @ViewBuilder private func activity(width: CGFloat) -> some View {
        if phase == .recording {
            MeterWaveform(meter: meter).frame(width: width, height: 16)
        } else if phase == .transcribing || phase == .finalizing || phase == .inserting || phase == .stopping {
            IndicatorProcessingSpinner().frame(width: 14, height: 14).frame(width: width, height: 16)
        } else {
            Image(systemName: phase == .cancelling ? "xmark" : "ellipsis").font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white).frame(width: width, height: 16)
        }
    }
}

struct MicrophoneLevel: View {
    @ObservedObject var meter: AudioMeter
    var body: some View {
        ProgressView(value: meter.level)
            .frame(width: 160).accessibilityLabel(I18n.tr("Уровень микрофона", "Microphone level"))
    }
}

struct ResultOverlayState {
    private(set) var entry: ResultEntry?
    mutating func show(_ entry: ResultEntry) { self.entry = entry }
    mutating func recordingBegan() { entry = nil }
    mutating func dismiss(_ id: UUID) -> Bool {
        guard entry?.id == id else { return false }
        entry = nil; return true
    }
}

@MainActor final class PresentationCoordinator {
    private let session: SessionCoordinator
    private var panel: NSPanel?
    private var overlay = ResultOverlayState()
    private var result: ResultEntry? { overlay.entry }
    private var displayedResultID: UUID?
    private var displayedLayout: IndicatorSurfaceLayout?
    private var menuProbe: Task<Void, Never>?
    private var menuProbeKey: String?
    private var protectedMenuRects: [CGRect]?
    private var recordingAnchor: Date?
    private var anchorScreenID: UInt32?
    private let controls = NSPopover()
    private var observer: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    init(session: SessionCoordinator) {
        self.session = session
        controls.behavior = .transient
        controls.contentViewController = NSHostingController(rootView: RecordingControls(session: session))
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.update() } }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.session.busy == true { self?.update() } }
        }
    }
    static func makeIndicatorPanel(content: NSView) -> NSPanel {
        let panel = IndicatorPanel(contentRect: NSRect(x: 0, y: 0, width: 72, height: 24), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // NSPanel already has a default contentView. A nil check cannot detect
        // the first presentation: install the real Mini explicitly.
        panel.contentView = content
        return panel
    }
    private func miniContent(layout: IndicatorSurfaceLayout) -> NSView {
        // Placement already accounts for the camera. Let the background fill
        // its curved edge pixels instead of applying another safe-area inset.
        NSHostingView(rootView: MiniIndicator(session: session, openControls: { [weak self] in self?.showControls() }, layout: layout).ignoresSafeArea())
    }
    func update() {
        let screens = NSScreen.screens
        if session.phase == .preparing {
            overlay.recordingBegan()
            if recordingAnchor != session.startedAt {
                recordingAnchor = session.startedAt
                anchorScreenID = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
            }
        }
        guard session.busy || result != nil else {
            panel?.orderOut(nil); controls.close(); menuProbe?.cancel(); menuProbe = nil
            panel?.contentView = nil; displayedLayout = nil
            menuProbeKey = nil; protectedMenuRects = nil; return
        }
        let preferred = session.preferences.value.screenID.flatMap { id in screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == id } }
        let anchored = anchorScreenID.flatMap { id in screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == id } }
        let pointerScreen = screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        guard let screen = preferred ?? anchored ?? pointerScreen ?? NSScreen.main ?? screens.first else { return }
        checkMenuSpace(on: screen)
        let placement = IndicatorGeometry.placement(screen: screen.frame, visible: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea, style: session.preferences.value.indicator,
            resultSize: result.map { CompactResultContent.size(for: $0) }, protectedMenuRects: protectedMenuRects)
        if panel == nil {
            panel = Self.makeIndicatorPanel(content: miniContent(layout: placement.layout))
            displayedLayout = placement.layout
        }
        if let result {
            controls.close()
            if displayedResultID != result.id {
                panel?.contentView = NSHostingView(rootView: CompactResultContent(entry: result, session: session, preferences: session.preferences,
                    close: { [weak self] in self?.hideResult(result.id) }))
                displayedResultID = result.id
            }
        } else if displayedResultID != nil || displayedLayout != placement.layout || panel?.contentView == nil {
            controls.close()
            panel?.contentView = miniContent(layout: placement.layout)
            displayedResultID = nil
            displayedLayout = placement.layout
        }
        panel?.level = result == nil ? .statusBar : .floating
        panel?.hasShadow = !placement.layout.attached
        (panel as? IndicatorPanel)?.acceptsKeyFocus = result != nil
        let theme = session.preferences.value.theme
        panel?.appearance = theme == .system ? nil : NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        let frame = placement.frame
        if panel?.frame != frame {
            let animate = result != nil && panel?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animate ? 0.18 : 0
                if animate { panel?.animator().setFrame(frame, display: true) } else { panel?.setFrame(frame, display: true) }
            }
        }
        panel?.orderFrontRegardless()
        panel?.contentView?.layoutSubtreeIfNeeded()
        panel?.displayIfNeeded()
    }
    private func checkMenuSpace(on screen: NSScreen) {
        let style = session.preferences.value.indicator
        guard result == nil, session.phase == .preparing || session.phase == .recording,
              screen.safeAreaInsets.top > 0, style == .auto || style == .notch,
              let began = session.startedAt, let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let primaryTop = NSScreen.screens.first?.frame.maxY else { return }
        let captureStarted = session.phase != .preparing
        let key = "\(began.timeIntervalSinceReferenceDate)/\(screen.frame)/\(frontPID)/\(captureStarted)"
        guard key != menuProbeKey else { return }
        menuProbe?.cancel(); menuProbeKey = key; protectedMenuRects = nil
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let screenFrame = screen.frame
        menuProbe = Task { [weak self] in
            let rectangles = await NotchMenuProbe.shared.read(frontPID: frontPID, primaryTop: primaryTop, ownPID: ownPID, screen: screenFrame)
            guard !Task.isCancelled, let self, self.menuProbeKey == key,
                  self.session.startedAt == began, self.session.busy, self.result == nil else { return }
            self.protectedMenuRects = rectangles
            self.update()
        }
    }
    func showResult(_ entry: ResultEntry) {
        guard session.phase != .preparing, session.phase != .recording, session.phase != .stopping else { return }
        if !session.busy { anchorScreenID = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
        overlay.show(entry); displayedResultID = nil; update()
    }
    private func hideResult(_ id: UUID) {
        guard overlay.dismiss(id) else { return }
        displayedResultID = nil; panel?.contentView = nil; update()
    }
    private func showControls() {
        guard let view = panel?.contentView else { return }
        controls.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

private final class IndicatorPanel: NSPanel {
    var acceptsKeyFocus = false
    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }
    // AppKit's default top constraint uses the menu bar's visibleFrame and can
    // push wings below the camera. IndicatorGeometry already validates the
    // complete screen coordinates; allow those coordinates for this panel only.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

struct RecordingControls: View {
    @ObservedObject var session: SessionCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.status).font(.headline)
            if let started = session.startedAt { Text(started, style: .timer).monospacedDigit() }
            HStack {
                Button(I18n.tr("Остановить", "Stop")) { session.stop() }.disabled(session.phase != .recording && session.phase != .preparing)
                Button(I18n.tr("Отменить", "Cancel")) { session.cancel() }.keyboardShortcut(.cancelAction)
            }
        }.padding(16).frame(width: 250).background(MaterialBackground(style: session.preferences.value.material))
    }
}

struct MaterialBackground: NSViewRepresentable {
    let style: MaterialStyle
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.blendingMode = .behindWindow; view.state = .active; return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .underWindowBackground
        view.wantsLayer = true
        let dense = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        view.layer?.backgroundColor = dense ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
    }
}

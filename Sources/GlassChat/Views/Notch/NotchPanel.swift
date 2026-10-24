import AppKit
import SwiftUI

/// A borderless panel above the menu bar, on every Space, that never activates the app.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click even while another app is active.
private final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Puts the notch panel on the screen with the notch and keeps it there: hover, clicks through its
/// transparent part, folding on Esc or a click elsewhere, and moving when the screens change.
@MainActor
final class NotchPanelController {
    static let shared = NotchPanelController()
    let model = NotchModel()

    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    /// The body of the expanded notch (the assistant), set before `install`.
    var content: () -> AnyView = { AnyView(Text("GlassChat").padding(16)) }

    private init() {}

    func install() {
        guard panel == nil else { return }
        let panel = NotchPanel(frame: .zero)
        let content = content
        let view = FirstMouseHostingView(rootView: NotchView(model: model) { content() })
        view.sizingOptions = []
        panel.contentView = view
        self.panel = panel
        reposition()
        panel.orderFrontRegardless()

        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Where an event happened is read from the event itself: the main actor may get to it late,
        // when the pointer is somewhere else.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { event in
            let point = Self.screenPoint(of: event)
            Task { @MainActor in NotchPanelController.shared.track(point) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { event in
            NotchPanelController.shared.track(Self.screenPoint(of: event))
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { event in
            let point = Self.screenPoint(of: event)
            voiceLog.debug("global click \(Self.describe(event), privacy: .public)")
            Task { @MainActor in NotchPanelController.shared.clicked(at: point) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown], handler: { event in
            NotchPanelController.shared.local(event)
        }) { monitors.append(local) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in NotchPanelController.shared.reposition() }
        }
    }

    func uninstall() {
        model.collapse()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// The shortcut: open and listen, or fold.
    func toggle() {
        voiceLog.debug("shortcut pressed")
        guard panel != nil else { return }
        if model.isExpanded { collapse() } else { expand() }
    }

    func expand() {
        model.expand()
        panel?.ignoresMouseEvents = false
        panel?.makeKey()
    }

    private func reposition() {
        guard let panel, let screen = NotchGeometry.screen() else { return }
        let notch = NotchGeometry.notchRect(on: screen)
        model.notchSize = notch.size
        let width = max(NotchGeometry.expandedWidth, notch.width + 2 * NotchGeometry.hoverGrow) + 12
        let height = NotchGeometry.maxExpandedHeight + 8
        panel.setFrame(CGRect(x: notch.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height), display: true)
    }

    /// The shape's frame on the screen, with a small margin.
    private var shapeFrame: CGRect {
        guard let panel else { return .zero }
        let size = model.shapeSize
        let width = size.width + 12
        return CGRect(x: panel.frame.midX - width / 2, y: panel.frame.maxY - size.height, width: width, height: size.height)
            .insetBy(dx: -4, dy: -4)
    }

    private nonisolated static func describe(_ event: NSEvent) -> String {
        let age = ProcessInfo.processInfo.systemUptime - event.timestamp
        // The process that posted it: 0 for the trackpad or the mouse.
        let source = event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? -1
        let state = event.cgEvent?.getIntegerValueField(.eventSourceStateID) ?? -1
        return "window \(event.window.map { String(describing: type(of: $0)) } ?? "none") number \(event.eventNumber) clicks \(event.clickCount) age \(String(format: "%.2f", age))s source pid \(source) state \(state)"
    }

    /// An event's place on the screen (a global event has no window: its location is already on the screen).
    private nonisolated static func screenPoint(of event: NSEvent) -> CGPoint {
        guard let window = event.window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    /// Whether the pointer is on the notch, and the wait before talking while it rests there.
    private var pointerInside = false
    private var hoverWait: Task<Void, Never>?

    private func track(_ point: CGPoint) {
        guard let panel else { return }
        let inside = shapeFrame.contains(point)
        if inside != pointerInside {
            pointerInside = inside
            inside ? pointerEntered() : pointerLeft()
        }
        panel.ignoresMouseEvents = !inside
        if !model.isExpanded, model.isHovering != inside { model.isHovering = inside }
        if inside, model.isExpanded, !panel.isKeyWindow { panel.makeKey() }
    }

    private func pointerEntered() {
        let settings = AppSettings.shared
        let delay = settings.hoverDelay
        hoverWait?.cancel()
        hoverWait = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, pointerInside,
                  HoverTalk.shouldStart(hovered: delay, delay: delay, enabled: settings.hoverToTalk,
                                        expanded: model.isExpanded, busy: model.isBusy) else { return }
            model.onHoverTalk?()
        }
    }

    private func pointerLeft() {
        hoverWait?.cancel()
        hoverWait = nil
        model.onHoverEnd?()
    }

    /// A click anywhere but on the open panel: one that went through the transparent panel onto the notch's
    /// shape opens it, one elsewhere folds it.
    private func clicked(at point: CGPoint) {
        switch NotchGeometry.click(at: point, shape: shapeFrame, expanded: model.isExpanded, busy: model.isBusy) {
        case .expand: expand()
        case .collapse:
            voiceLog.debug("click outside the notch at \(point.debugDescription, privacy: .public)")
            collapse()
        case .none: break
        }
    }

    private func local(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown where event.keyCode == 53 && model.isExpanded:
            voiceLog.debug("escape folds the notch")
            collapse()
            return nil
        case .leftMouseDown where event.window !== panel:
            voiceLog.debug("local click \(Self.describe(event), privacy: .public)")
            clicked(at: Self.screenPoint(of: event))
        case .leftMouseDown where !model.isExpanded && shapeFrame.contains(Self.screenPoint(of: event)):
            expand()
            return nil
        default:
            break
        }
        return event
    }

    func collapse() {
        model.collapse()
        panel?.resignKey()
        track(NSEvent.mouseLocation)
    }
}

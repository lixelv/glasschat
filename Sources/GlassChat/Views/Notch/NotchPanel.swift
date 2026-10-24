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
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { _ in
            Task { @MainActor in NotchPanelController.shared.track() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { event in
            NotchPanelController.shared.track()
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { _ in
            Task { @MainActor in NotchPanelController.shared.clickedOutside() }
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

    private func track() {
        guard let panel else { return }
        let inside = shapeFrame.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if !model.isExpanded, model.isHovering != inside { model.isHovering = inside }
        if inside, model.isExpanded, !panel.isKeyWindow { panel.makeKey() }
    }

    private func clickedOutside() {
        if model.isExpanded, !shapeFrame.contains(NSEvent.mouseLocation) { collapse() }
    }

    private func local(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown where event.keyCode == 53 && model.isExpanded:
            collapse()
            return nil
        case .leftMouseDown where event.window !== panel:
            clickedOutside()
        case .leftMouseDown where !model.isExpanded && shapeFrame.contains(NSEvent.mouseLocation):
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
        track()
    }
}

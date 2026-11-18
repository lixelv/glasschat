import SwiftUI

/// What the notch shows and how big it is.
@Observable
@MainActor
final class NotchModel {
    var notchSize = CGSize(width: 180, height: 32)
    private(set) var isExpanded = false
    var isHovering = false
    /// The assistant is working (listening, answering, speaking) while folded.
    var isBusy = false
    /// An answer came while folded.
    var hasUnread = false
    /// What the header shows beside the notch.
    var mood: AssistantAvatar.Mood = .idle
    var wave: Waveform.Mode = .idle
    var level = 0.0
    /// The height of the expanded body, measured.
    var contentHeight: CGFloat = 0
    /// How tall the open notch may get on this screen.
    var maxHeight = NotchGeometry.defaultMaxHeight
    var onExpand: (() -> Void)?
    var onCollapse: (() -> Void)?

    var state: NotchState {
        if isExpanded { return .expanded }
        if isHovering { return .hover }
        return isBusy || hasUnread ? .busy : .closed
    }

    var shapeSize: CGSize {
        NotchGeometry.shapeSize(state, notch: notchSize, contentHeight: contentHeight, maxHeight: maxHeight)
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        isHovering = false
        onExpand?()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        onCollapse?()
    }
}

/// The black shape over the notch; it grows into the expanded panel with `content` under the notch row.
struct NotchView<Content: View>: View {
    let model: NotchModel
    @ViewBuilder var content: () -> Content

    var body: some View {
        let size = model.shapeSize
        let ear: CGFloat = 6
        VStack(spacing: 0) {
            header
            if model.state == .expanded {
                content()
                    .frame(width: NotchGeometry.expandedWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.contentHeight = $0 }
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .padding(.horizontal, ear)
        .background(.black)
        .clipShape(NotchShape(bottomRadius: model.state == .expanded ? 24 : 10, earRadius: ear))
        .contentShape(NotchShape(bottomRadius: 10, earRadius: ear))
        .onTapGesture { if model.state != .expanded { model.expand() } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.state)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.contentHeight)
        .environment(\.colorScheme, .dark)
    }

    /// The face left of the notch, the bars right of it (small while folded).
    @ViewBuilder private var header: some View {
        let state = model.state
        let expanded = state == .expanded
        HStack(spacing: 0) {
            if state != .closed {
                AssistantAvatar(mood: model.mood, level: model.level, size: expanded ? 20 : 14)
                    .padding(.leading, expanded ? 10 : 4)
                Spacer(minLength: model.notchSize.width)
                Group {
                    if model.hasUnread && !expanded {
                        PulsingDot()
                    } else {
                        Waveform(mode: model.wave, level: model.level, bars: expanded ? 6 : 3,
                                 maxHeight: model.notchSize.height - (expanded ? 10 : 14))
                    }
                }
                .padding(.trailing, expanded ? 14 : 8)
                .transition(.opacity)
            }
        }
        .frame(height: model.notchSize.height)
    }
}

/// An answer is waiting.
private struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

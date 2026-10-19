import SwiftUI

struct ErrorBanner: View {
    let error: APIError
    let retry: () -> Void
    let dismiss: () -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.callout)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if error.status == 401 || error.status == 403 {
                Button("Settings…") { openSettings() }
                    .buttonStyle(.glass)
            }
            Button("Retry", action: retry)
                .buttonStyle(.glass)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .rect(cornerRadius: 16))
    }
}

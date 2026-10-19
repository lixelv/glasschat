import AppKit
import SwiftUI

/// A file attached to a message: a thumbnail for images, the file's icon otherwise.
struct AttachmentChip: View {
    let attachment: Attachment
    var remove: (() -> Void)?
    @Environment(Preview.self) private var preview

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 30, height: 30)
                .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 160, alignment: .leading)
            if let remove {
                Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove \(attachment.name)")
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, remove == nil ? 10 : 7)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        // A click opens it in Quick Look.
        .onTapGesture { preview.url = AttachmentStore.url(of: attachment) }
        .help("Preview \(attachment.name)")
    }

    @ViewBuilder private var thumbnail: some View {
        if attachment.kind == .image, let image = NSImage(contentsOf: AttachmentStore.url(of: attachment)) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            Image(nsImage: AttachmentStore.icon(for: attachment)).resizable().scaledToFit()
        }
    }
}

/// The attachments of a sent message: images as pictures, the rest as chips.
struct MessageAttachments: View {
    let attachments: [Attachment]
    @Environment(Preview.self) private var preview

    var body: some View {
        let images = attachments.filter { $0.kind == .image }
        let others = attachments.filter { $0.kind != .image }
        VStack(alignment: .trailing, spacing: 6) {
            if !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(images) { attachment in
                        if let image = NSImage(contentsOf: AttachmentStore.url(of: attachment)) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: images.count == 1 ? 240 : 120, height: images.count == 1 ? 180 : 120)
                                .clipShape(.rect(cornerRadius: 14))
                                .onTapGesture { preview.url = AttachmentStore.url(of: attachment) }
                                .help(attachment.name)
                        }
                    }
                }
            }
            ForEach(others) { AttachmentChip(attachment: $0) }
        }
    }
}

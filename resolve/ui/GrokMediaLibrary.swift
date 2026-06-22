import AppKit
import AVFoundation
import Foundation

struct MediaItem: Identifiable {
    let id: String
    let path: URL
    let name: String
    let kind: String
    let modified: Date
}

enum MediaLibrary {
    private static let videoExt: Set<String> = ["mp4", "mov", "m4v", "webm"]
    private static let imageExt: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]

    static func loadArtifacts(limit: Int = 48) -> [MediaItem] {
        let root = GrokPaths.root
        var items: [MediaItem] = []
        for (folder, kind) in [("video", "video"), ("image", "image")] {
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let ext = url.pathExtension.lowercased()
                let allowed = kind == "video" ? videoExt : imageExt
                guard allowed.contains(ext) else { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                items.append(MediaItem(id: url.path, path: url, name: url.lastPathComponent, kind: kind, modified: modified))
            }
        }
        return items.sorted { $0.modified > $1.modified }.prefix(limit).map { $0 }
    }

    static func thumbnail(for item: MediaItem, size: NSSize, completion: @escaping (NSImage) -> Void) {
        let placeholder = placeholder(for: item, size: size)
        completion(placeholder)
        if item.kind == "image", let image = NSImage(contentsOf: item.path) {
            completion(scaled(image, to: size))
            return
        }
        if item.kind == "video" {
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: item.path)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = size
                let time = CMTime(seconds: 0.2, preferredTimescale: 600)
                guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { return }
                let image = NSImage(cgImage: cg, size: size)
                DispatchQueue.main.async { completion(image) }
            }
        }
    }

    static func placeholder(for item: MediaItem, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        GrokTheme.field.setFill()
        NSRect(origin: .zero, size: size).fill()
        let label = (item.kind == "video" ? "▶ " : "◻ ") + item.name as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: GrokTheme.muted,
        ]
        let textSize = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(x: max(6, (size.width - textSize.width) / 2), y: (size.height - textSize.height) / 2),
            withAttributes: attrs
        )
        image.unlockFocus()
        return image
    }

    private static func scaled(_ image: NSImage, to size: NSSize) -> NSImage {
        let ratio = min(size.width / image.size.width, size.height / image.size.height)
        let newSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let out = NSImage(size: newSize)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }

    static func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Load media into Grok canvas"
        panel.message = "Choose a reference image or video from your machine"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["mp4", "mov", "m4v", "webm", "png", "jpg", "jpeg", "gif", "webp"]
        panel.directoryURL = GrokPaths.root
        return panel.runModal() == .OK ? panel.url : nil
    }
}
import AppKit
import AVFoundation
import Foundation

struct MediaMeta: Codable {
    let source: String?
    let file: String?
    let savedAt: String?
    let slug: String?
    let prompt: String?
    let duration: Int?
    let resolution: String?
    let aspectRatio: String?
    let lut: String?
    let detected: Bool?
    let detectReason: String?

    enum CodingKeys: String, CodingKey {
        case source, file, slug, prompt, duration, resolution, lut, detected
        case savedAt = "saved_at"
        case aspectRatio = "aspect_ratio"
        case detectReason = "detect_reason"
    }
}

struct MediaItem: Identifiable {
    let id: String
    let path: URL
    let name: String
    let kind: String
    let modified: Date
    let meta: MediaMeta?
}

enum ViewerMode: String {
    case media = "Media"
    case preset = "Preset"
}

enum MediaLibrary {
    private static let videoExt: Set<String> = ["mp4", "mov", "m4v", "webm"]
    private static let imageExt: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]

    static func sidecarURL(for mediaPath: URL) -> URL {
        let suffix = mediaPath.pathExtension
        let base = mediaPath.deletingPathExtension()
        return URL(fileURLWithPath: base.path + ".\(suffix).grok.json")
    }

    static func readSidecar(for mediaPath: URL) -> MediaMeta? {
        let url = sidecarURL(for: mediaPath)
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(MediaMeta.self, from: data) else {
            return nil
        }
        return raw
    }

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
                items.append(MediaItem(
                    id: url.path,
                    path: url,
                    name: url.lastPathComponent,
                    kind: kind,
                    modified: modified,
                    meta: readSidecar(for: url)
                ))
            }
        }
        return items.sorted { $0.modified > $1.modified }.prefix(limit).map { $0 }
    }

    static func metaLines(for item: MediaItem) -> [String] {
        var lines = [
            "FILE · \(item.name)",
            "KIND · \(item.kind.uppercased())",
            "PATH · \(item.path.path)",
            "MODIFIED · \(formatDate(item.modified))",
        ]
        if let meta = item.meta {
            if let slug = meta.slug, !slug.isEmpty { lines.append("SLUG · \(slug)") }
            if let prompt = meta.prompt, !prompt.isEmpty { lines.append("PROMPT · \(prompt)") }
            if let duration = meta.duration { lines.append("DURATION · \(duration)s") }
            if let resolution = meta.resolution, !resolution.isEmpty { lines.append("RESOLUTION · \(resolution)") }
            if let aspect = meta.aspectRatio, !aspect.isEmpty { lines.append("ASPECT · \(aspect)") }
            if let lut = meta.lut, !lut.isEmpty { lines.append("LUT · \(lut)") }
            if let saved = meta.savedAt, !saved.isEmpty { lines.append("SAVED · \(saved)") }
            if let detected = meta.detected { lines.append("DETECTED · \(detected ? "yes" : "no")") }
            if let reason = meta.detectReason, !reason.isEmpty { lines.append("REASON · \(reason)") }
        }
        return lines
    }

    static func metaLines(for preset: PresetEntry) -> [String] {
        var lines = [
            "PRESET · \(preset.display)",
            "SLUG · \(preset.slug)",
            "GROUP · \(preset.group)",
        ]
        if !preset.bestFor.isEmpty { lines.append("BEST FOR · \(preset.bestFor)") }
        if !preset.notes.isEmpty { lines.append("NOTES · \(preset.notes)") }
        if !preset.tags.isEmpty { lines.append("TAGS · \(preset.tags.joined(separator: ", "))") }
        if !preset.promptPreview.isEmpty { lines.append("PREVIEW · \(preset.promptPreview)") }
        return lines
    }

    static func metaLines(for lut: PresetEntry?) -> [String] {
        guard let lut else { return ["LUT · None selected"] }
        return metaLines(for: lut)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
            .font: GrokTypography.caption,
            .foregroundColor: GrokTheme.textSecondary,
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

enum BrowserBridge {
    static var binURL: URL { GrokPaths.root.appendingPathComponent("bin/browser") }

    static func run(_ args: [String]) -> (ok: Bool, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [binURL.path] + args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (task.terminationStatus == 0, text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
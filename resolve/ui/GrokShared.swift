import AppKit
import Foundation

enum GrokTheme {
    static let window = NSColor(calibratedRed: 0.137, green: 0.137, blue: 0.137, alpha: 1)
    static let header = NSColor(calibratedRed: 0.102, green: 0.102, blue: 0.102, alpha: 1)
    static let panel = NSColor(calibratedRed: 0.176, green: 0.176, blue: 0.176, alpha: 1)
    static let row = NSColor(calibratedRed: 0.208, green: 0.208, blue: 0.208, alpha: 1)
    static let rowHover = NSColor(calibratedRed: 0.255, green: 0.255, blue: 0.255, alpha: 1)
    static let border = NSColor(calibratedRed: 0.24, green: 0.24, blue: 0.24, alpha: 1)
    static let field = NSColor(calibratedRed: 0.118, green: 0.118, blue: 0.118, alpha: 1)
    static let text = NSColor(calibratedRed: 0.91, green: 0.91, blue: 0.91, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    static let accent = NSColor(calibratedRed: 1.0, green: 0.467, blue: 0.0, alpha: 1)
}

struct ThumbnailRef: Codable {
    let kind: String
    let path: String
}

struct PresetEntry: Codable {
    let slug: String
    let display: String
    let group: String
    let tags: [String]
    let bestFor: String
    let notes: String
    let promptPreview: String
    let thumbnail: ThumbnailRef
    let isLut: Bool

    enum CodingKeys: String, CodingKey {
        case slug, display, group, tags, thumbnail
        case bestFor = "best_for"
        case notes
        case promptPreview = "prompt_preview"
        case isLut = "is_lut"
    }
}

struct PresetGroup: Codable {
    let id: String
    let label: String
    let presets: [PresetEntry]
}

struct GenerateDefaults: Codable {
    let slug: String
    let prompt: String
    let durationSec: Int
    let resolution: String
    let aspectRatio: String
    let lutSlug: String
    let promptAdd: String
    let continuityNotes: String

    enum CodingKeys: String, CodingKey {
        case slug, prompt, resolution
        case durationSec = "duration_sec"
        case aspectRatio = "aspect_ratio"
        case lutSlug = "lut_slug"
        case promptAdd = "prompt_add"
        case continuityNotes = "continuity_notes"
    }
}

struct GenerateCatalog: Codable {
    let defaults: GenerateDefaults
    let groups: [PresetGroup]
    let lutPresets: [PresetEntry]
    let durations: [Int]
    let resolutions: [String]
    let aspectRatios: [String]

    enum CodingKeys: String, CodingKey {
        case defaults, groups, durations, resolutions
        case lutPresets = "lut_presets"
        case aspectRatios = "aspect_ratios"
    }
}

enum GrokPaths {
    static var root: URL {
        if let env = ProcessInfo.processInfo.environment["GROK_PUBLIC_FOLDER"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let bin = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        return bin.deletingLastPathComponent()
    }

    static var catalogURL: URL {
        root.appendingPathComponent("project/generate-ui.json")
    }
}

enum CatalogStore {
    static func load() -> GenerateCatalog {
        let url = GrokPaths.catalogURL
        guard let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(GenerateCatalog.self, from: data) else {
            return fallbackCatalog()
        }
        return catalog
    }

    static func fallbackCatalog() -> GenerateCatalog {
        let preset = PresetEntry(
            slug: "neo-noir",
            display: "Neo-Noir",
            group: "cinematic_genre",
            tags: ["noir", "rain"],
            bestFor: "moody urban night scenes",
            notes: "",
            promptPreview: "neo-noir cinematic, rain soaked streets…",
            thumbnail: ThumbnailRef(kind: "none", path: ""),
            isLut: false
        )
        let group = PresetGroup(id: "cinematic_genre", label: "Cinematic Genre", presets: [preset])
        let defaults = GenerateDefaults(
            slug: "neo-noir",
            prompt: "woman in rain on empty street at night",
            durationSec: 10,
            resolution: "720p",
            aspectRatio: "16:9",
            lutSlug: "",
            promptAdd: "",
            continuityNotes: ""
        )
        return GenerateCatalog(
            defaults: defaults,
            groups: [group],
            lutPresets: [],
            durations: [5, 8, 10, 12, 15],
            resolutions: ["480p", "720p"],
            aspectRatios: ["16:9", "9:16", "1:1"]
        )
    }
}

enum UIHelpers {
    static func grokRoot() -> URL { GrokPaths.root }

    static func headerView(title: String, subtitle: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = GrokTheme.header.cgColor

        let accent = NSView()
        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.wantsLayer = true
        accent.layer?.backgroundColor = GrokTheme.accent.cgColor

        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = GrokTheme.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = GrokTheme.muted
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(accent)
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 52),
            accent.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            accent.topAnchor.constraint(equalTo: container.topAnchor),
            accent.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            accent.widthAnchor.constraint(equalToConstant: 3),
            titleLabel.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
        return container
    }

    static func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = GrokTheme.muted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func styleField(_ field: NSTextField) {
        field.font = NSFont.systemFont(ofSize: 12)
        field.textColor = GrokTheme.text
        field.backgroundColor = GrokTheme.field
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    static func stylePopup(_ popup: NSPopUpButton) {
        popup.font = NSFont.systemFont(ofSize: 12)
        popup.contentTintColor = GrokTheme.text
        popup.translatesAutoresizingMaskIntoConstraints = false
    }

    static func flatButton(_ title: String, accent: Bool, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = (accent ? GrokTheme.accent : GrokTheme.row).cgColor
        button.layer?.cornerRadius = 3
        button.contentTintColor = accent ? NSColor.black : GrokTheme.text
        button.font = NSFont.systemFont(ofSize: 12, weight: accent ? .semibold : .regular)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    static func placeholderImage(for preset: PresetEntry) -> NSImage {
        let size = NSSize(width: 320, height: 180)
        let image = NSImage(size: size)
        image.lockFocus()
        let hue = CGFloat(abs(preset.slug.hashValue % 255)) / 255.0
        NSColor(calibratedHue: hue * 0.08 + 0.02, saturation: 0.35, brightness: 0.22, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        GrokTheme.border.setStroke()
        NSBezierPath(rect: NSRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)).stroke()

        let title = preset.display as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: GrokTheme.text,
        ]
        let textSize = title.size(withAttributes: attrs)
        title.draw(
            at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
            withAttributes: attrs
        )
        image.unlockFocus()
        return image
    }

    static func loadThumbnail(for preset: PresetEntry, into imageView: NSImageView) {
        let thumb = preset.thumbnail
        imageView.image = placeholderImage(for: preset)
        if thumb.kind == "file", !thumb.path.isEmpty,
           let image = NSImage(contentsOfFile: thumb.path) {
            imageView.image = image
            return
        }
        if thumb.kind == "url", let url = URL(string: thumb.path) {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { imageView.image = image }
            }
        }
    }

    static func thumbnailImage(for preset: PresetEntry, completion: @escaping (NSImage) -> Void) {
        let placeholder = placeholderImage(for: preset)
        completion(placeholder)
        let thumb = preset.thumbnail
        if thumb.kind == "file", !thumb.path.isEmpty,
           let image = NSImage(contentsOfFile: thumb.path) {
            completion(image)
            return
        }
        if thumb.kind == "url", let url = URL(string: thumb.path) {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { completion(image) }
            }
        }
    }
}
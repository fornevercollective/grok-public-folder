import AppKit
import Foundation

enum GrokBrand {
    static let appName = "Grok for Resolve"
    static let shortName = "Grok"
    static let source = "DaVinci Resolve → Workspace → Scripts → Grok"
    static let repo = "fornevercollective/grok-public-folder"
    static let trustLine = "Official Grok workflow · local scripts · x.ai API (your key)"
}

/// Resolve-inspired dark palette (Edit / Color / Fairlight inspector feel).
enum GrokTheme {
    static let window = rgb(0.145, 0.145, 0.145)       // #252525
    static let header = rgb(0.118, 0.118, 0.118)       // #1e1e1e
    static let panel = rgb(0.165, 0.165, 0.165)        // #2a2a2a
    static let row = rgb(0.192, 0.192, 0.192)          // #313131
    static let rowHover = rgb(0.235, 0.235, 0.235)     // #3c3c3c
    static let rowActive = rgb(0.255, 0.255, 0.255)    // #414141
    static let border = rgb(0.345, 0.345, 0.345)       // #585858
    static let borderSubtle = rgb(0.275, 0.275, 0.275) // #464646
    static let field = rgb(0.110, 0.110, 0.110)        // #1c1c1c
    static let fieldInset = rgb(0.135, 0.135, 0.135)   // #232323 — meta / log wells
    static let text = rgb(0.945, 0.945, 0.945)         // #f1f1f1 primary
    static let textSecondary = rgb(0.780, 0.780, 0.780) // #c7c7c7 body
    static let label = rgb(0.710, 0.710, 0.710)        // #b5b5b5 section labels
    static let muted = textSecondary                   // legacy alias — was too dim at 0.55
    static let textDim = rgb(0.600, 0.600, 0.600)      // #999999 footnotes only
    static let accent = rgb(0.976, 0.545, 0.078)       // #f98b14 Resolve orange
    static let accentText = rgb(0.08, 0.08, 0.08)

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}

enum GrokTypography {
    static let heading = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static let body = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let bodyStrong = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let caption = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let label = NSFont.systemFont(ofSize: 10, weight: .semibold)
    static let meta = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    static let tab = NSFont.systemFont(ofSize: 11, weight: .medium)
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

    static var catalogURL: URL { root.appendingPathComponent("project/generate-ui.json") }
    static var videoDir: URL { root.appendingPathComponent("video", isDirectory: true) }
    static var imageDir: URL { root.appendingPathComponent("image", isDirectory: true) }
    static var bridgeDir: URL { root.appendingPathComponent("bridge", isDirectory: true) }
    static var browserDir: URL { root.appendingPathComponent("browser", isDirectory: true) }
    static var projectDir: URL { root.appendingPathComponent("project", isDirectory: true) }
    static var binDir: URL { root.appendingPathComponent("bin", isDirectory: true) }
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

    static func applyResolveAppearance(to window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = GrokTheme.window
    }

    static func styleSectionHeading(_ field: NSTextField) {
        field.font = GrokTypography.heading
        field.textColor = GrokTheme.text
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    static func styleBodyText(_ field: NSTextField) {
        field.font = GrokTypography.body
        field.textColor = GrokTheme.textSecondary
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    static func styleCaption(_ field: NSTextField) {
        field.font = GrokTypography.caption
        field.textColor = GrokTheme.textSecondary
        field.translatesAutoresizingMaskIntoConstraints = false
    }

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
        titleLabel.font = GrokTypography.label
        titleLabel.textColor = GrokTheme.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = GrokTypography.caption
        subtitleLabel.textColor = GrokTheme.textSecondary
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
        label.font = GrokTypography.label
        label.textColor = GrokTheme.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func styleField(_ field: NSTextField) {
        field.font = GrokTypography.body
        field.textColor = GrokTheme.text
        field.backgroundColor = GrokTheme.field
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    static func stylePopup(_ popup: NSPopUpButton) {
        popup.font = GrokTypography.body
        popup.contentTintColor = GrokTheme.text
        popup.wantsLayer = true
        popup.layer?.backgroundColor = GrokTheme.field.cgColor
        popup.layer?.cornerRadius = 2
        popup.layer?.borderColor = GrokTheme.borderSubtle.cgColor
        popup.layer?.borderWidth = 1
        popup.translatesAutoresizingMaskIntoConstraints = false
    }

    static func styleSegmentedControl(_ control: NSSegmentedControl) {
        control.segmentStyle = .rounded
        control.font = GrokTypography.caption
        control.translatesAutoresizingMaskIntoConstraints = false
    }

    static func styleScrollView(_ scroll: NSScrollView) {
        scroll.drawsBackground = true
        scroll.backgroundColor = GrokTheme.fieldInset
        scroll.borderType = .lineBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
    }

    static func flatButton(_ title: String, accent: Bool, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = (accent ? GrokTheme.accent : GrokTheme.row).cgColor
        button.layer?.cornerRadius = 2
        if !accent {
            button.layer?.borderColor = GrokTheme.border.cgColor
            button.layer?.borderWidth = 1
        }
        button.contentTintColor = accent ? GrokTheme.accentText : GrokTheme.text
        button.font = GrokTypography.bodyStrong
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

    static func actionFooter(close: NSButton, generate: NSButton) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = GrokTheme.panel.cgColor
        container.layer?.borderColor = GrokTheme.border.cgColor
        container.layer?.borderWidth = 1

        let row = NSStackView(views: [close, generate])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(row)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 40),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    static func panelShell() -> NSView {
        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = GrokTheme.panel.cgColor
        panel.layer?.cornerRadius = 2
        panel.layer?.borderColor = GrokTheme.borderSubtle.cgColor
        panel.layer?.borderWidth = 1
        panel.translatesAutoresizingMaskIntoConstraints = false
        return panel
    }

    static func metaTextView() -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = true
        view.backgroundColor = GrokTheme.fieldInset
        view.textColor = GrokTheme.textSecondary
        view.font = GrokTypography.meta
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.isRichText = false
        return view
    }

    static func trustFooter() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = GrokTheme.header.cgColor
        container.layer?.borderColor = GrokTheme.border.cgColor
        container.layer?.borderWidth = 1

        let source = NSTextField(labelWithString: GrokBrand.source)
        source.font = GrokTypography.caption
        source.textColor = GrokTheme.textSecondary
        source.translatesAutoresizingMaskIntoConstraints = false

        let detail = NSTextField(labelWithString: "\(GrokBrand.trustLine)\n\(GrokPaths.root.path)")
        detail.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        detail.textColor = GrokTheme.textDim
        detail.maximumNumberOfLines = 2
        detail.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(source)
        container.addSubview(detail)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            source.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            source.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            source.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            detail.topAnchor.constraint(equalTo: source.bottomAnchor, constant: 2),
            detail.leadingAnchor.constraint(equalTo: source.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: source.trailingAnchor),
        ])
        return container
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
import AppKit
import Foundation

enum GrokEditMenu {
    static func install() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: GrokBrand.appName)
        mainMenu.addItem(appItem)
        appItem.submenu?.addItem(
            withTitle: "Close Grok",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "w"
        )

        let editItem = NSMenuItem()
        editItem.submenu = NSMenu(title: "Edit")
        mainMenu.addItem(editItem)
        guard let editMenu = editItem.submenu else { return }

        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Delete",
            action: #selector(NSText.delete(_:)),
            keyEquivalent: "\u{8}"
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        NSApp.mainMenu = mainMenu
    }
}

enum GrokBrand {
    static let appName = "Grok for Resolve"
    static let shortName = "Grok"
    static let source = "DaVinci Resolve → Workspace → Scripts → Grok"
    static let repo = "fornevercollective/grok-public-folder"
    static let trustLine = "Official Grok workflow · local scripts · x.ai API (your key)"
}

/// DaVinci Resolve cool blue-grey palette (Edit / Color inspector).
enum GrokTheme {
    static let window = rgb(0.106, 0.114, 0.125)       // #1b1d20
    static let header = rgb(0.090, 0.098, 0.110)       // #17191c
    static let panel = rgb(0.145, 0.153, 0.169)        // #25272b
    static let row = rgb(0.176, 0.184, 0.200)          // #2d2f33
    static let rowHover = rgb(0.208, 0.216, 0.231)     // #35373b
    static let rowActive = rgb(0.231, 0.239, 0.255)    // #3b3d41
    static let border = rgb(0.290, 0.302, 0.325)       // #4a4d53
    static let borderSubtle = rgb(0.235, 0.245, 0.265) // #3c3e43
    static let field = rgb(0.082, 0.090, 0.102)        // #15171a
    static let fieldInset = rgb(0.110, 0.118, 0.133)   // #1c1e22
    static let text = rgb(0.910, 0.918, 0.931)         // #e8eaed
    static let textSecondary = rgb(0.753, 0.765, 0.784) // #c0c3c8
    static let label = rgb(0.682, 0.698, 0.722)        // #aeb2b8
    static let muted = textSecondary
    static let textDim = rgb(0.541, 0.557, 0.580)      // #8a8e94
    static let accent = rgb(0.976, 0.545, 0.078)       // #f98b14
    static let accentText = rgb(0.06, 0.07, 0.09)

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
    static var imdbDir: URL { root.appendingPathComponent("imdb", isDirectory: true) }
    static var streamingDir: URL { root.appendingPathComponent("streaming", isDirectory: true) }
    static var blankDir: URL { root.appendingPathComponent("blank", isDirectory: true) }
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

    static func headerView(
        title: String,
        subtitle: String,
        includeMonitor: Bool = false
    ) -> (view: NSView, monitor: HeaderMonitorController?) {
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

        var monitor: HeaderMonitorController?
        container.addSubview(accent)
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)

        var constraints: [NSLayoutConstraint] = [
            container.heightAnchor.constraint(equalToConstant: includeMonitor ? 58 : 52),
            accent.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            accent.topAnchor.constraint(equalTo: container.topAnchor),
            accent.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            accent.widthAnchor.constraint(equalToConstant: 3),
            titleLabel.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: includeMonitor ? 10 : 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ]

        if includeMonitor {
            let monitorController = HeaderMonitorController()
            monitor = monitorController
            container.addSubview(monitorController.container)
            constraints += [
                monitorController.container.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
                monitorController.container.topAnchor.constraint(equalTo: container.topAnchor),
                monitorController.container.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                monitorController.container.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: monitorController.container.leadingAnchor, constant: -8),
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return (container, monitor)
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
        field.isEditable = true
        field.isSelectable = true
        field.allowsEditingTextAttributes = false
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    static func styleEditableTextView(_ view: NSTextView) {
        view.isEditable = true
        view.isSelectable = true
        view.allowsUndo = true
        view.isRichText = false
        view.usesFontPanel = false
        view.importsGraphics = false
    }

    static func styleReadableTextView(_ view: NSTextView) {
        view.isEditable = false
        view.isSelectable = true
        view.allowsUndo = false
        view.isRichText = false
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
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
    }

    static func configureMetaTextView(_ view: NSTextView, in scroll: NSScrollView) {
        styleReadableTextView(view)
        view.drawsBackground = true
        view.backgroundColor = GrokTheme.fieldInset
        view.textColor = GrokTheme.textSecondary
        view.font = GrokTypography.meta
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.isRichText = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    static func scrollMetaToTop(_ view: NSTextView, in scroll: NSScrollView) {
        if let container = view.textContainer {
            view.layoutManager?.ensureLayout(for: container)
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    static func scrollMetaToEnd(_ view: NSTextView) {
        if let container = view.textContainer {
            view.layoutManager?.ensureLayout(for: container)
        }
        let length = view.string.count
        guard length > 0 else { return }
        view.scrollRangeToVisible(NSRange(location: length - 1, length: 1))
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
        GrokTheme.fieldInset.setFill()
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
        styleReadableTextView(view)
        view.drawsBackground = true
        view.backgroundColor = GrokTheme.fieldInset
        view.textColor = GrokTheme.textSecondary
        view.font = GrokTypography.meta
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.isRichText = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
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
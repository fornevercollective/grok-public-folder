import AppKit
import AVKit
import Foundation

enum GrokTabs {
    static let all: [(id: String, title: String)] = [
        ("canvas", "Canvas"),
        ("import", "Import"),
        ("scan", "Scan"),
        ("bootstrap", "Bootstrap"),
        ("bridge", "Bridge"),
        ("folder", "Folder"),
    ]
}

final class CanvasWindowController: NSObject, NSWindowDelegate {
    var onComplete: ((String) -> Void)?

    private let catalog: GenerateCatalog
    private var window: NSWindow?
    private var finished = false
    private var activeTab = "canvas"
    private var selectedPreset: PresetEntry?
    private var selectedMedia: MediaItem?
    private var playerView: AVPlayerView?

    private let tabBar = NSStackView()
    private let contentHost = NSView()
    private var tabButtons: [String: TabButton] = [:]

    private let mediaView = NSImageView()
    private let mediaLabel = NSTextField(labelWithString: "Load a reference or pick from library")
    private let mediaStrip = NSStackView()
    private let playerHost = NSView()

    private let groupPopup = NSPopUpButton()
    private let presetPopup = NSPopUpButton()
    private let promptView = NSTextView()
    private let durationPopup = NSPopUpButton()
    private let resolutionPopup = NSPopUpButton()
    private let aspectPopup = NSPopUpButton()
    private let lutPopup = NSPopUpButton()
    private let promptAddField = NSTextField(string: "")
    private let continuityField = NSTextField(string: "")
    private let presetPreview = NSTextField(wrappingLabelWithString: "")

    init(catalog: GenerateCatalog) {
        self.catalog = catalog
        super.init()
    }

    func show() {
        let window = makeWindow()
        self.window = window
        window.delegate = self
        switchTab("canvas")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        complete("CANCELLED")
    }

    private func complete(_ value: String) {
        guard !finished else { return }
        finished = true
        onComplete?(value)
    }

    private func makeWindow() -> NSWindow {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: 1040, height: 700)
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = GrokBrand.appName
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 920, height: 620)
        window.backgroundColor = GrokTheme.window

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let header = UIHelpers.headerView(title: GrokBrand.appName, subtitle: "Imagine canvas → Resolve edit")
        let tabs = buildTabBar()
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        let trust = UIHelpers.trustFooter()

        root.addSubview(header)
        root.addSubview(tabs)
        root.addSubview(contentHost)
        root.addSubview(trust)
        window.contentView = root

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            tabs.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -10),
            contentHost.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            contentHost.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            trust.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            trust.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            trust.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: trust.topAnchor),
        ])

        populateGenerateControls()
        reloadMediaStrip()
        return window
    }

    private func buildTabBar() -> NSView {
        tabBar.orientation = .horizontal
        tabBar.spacing = 2
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        for tab in GrokTabs.all {
            let button = TabButton(title: tab.title, tabId: tab.id)
            button.target = self
            button.action = #selector(tabPressed(_:))
            tabButtons[tab.id] = button
            tabBar.addArrangedSubview(button)
        }
        tabBar.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return tabBar
    }

    @objc private func tabPressed(_ sender: TabButton) {
        switchTab(sender.tabId)
    }

    private func switchTab(_ tabId: String) {
        activeTab = tabId
        for (id, button) in tabButtons {
            button.isActive = id == tabId
        }
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        let panel: NSView
        switch tabId {
        case "canvas": panel = buildCanvasTab()
        case "import": panel = buildImportTab()
        case "scan": panel = buildSimpleTab(title: "Scan Downloads", body: "Find Grok media in Downloads and offer to move into artifacts folders.", action: "Scan Downloads", tabId: "scan")
        case "bootstrap": panel = buildSimpleTab(title: "Bootstrap", body: "Create 4K bins, timeline settings, and grok_generated import target in the open Resolve project.", action: "Run Bootstrap", tabId: "bootstrap")
        case "bridge": panel = buildSimpleTab(title: "Bridge", body: "Open Terminal bridge for chat and headless generate requests from Resolve.", action: "Start Bridge", tabId: "bridge")
        case "folder": panel = buildSimpleTab(title: "Folder", body: "Open grok-public-folder in Finder.", action: "Open Folder", tabId: "folder")
        default: panel = buildCanvasTab()
        }
        panel.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: contentHost.topAnchor),
            panel.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
    }

    private func buildSimpleTab(title: String, body: String, action: String, tabId: String) -> NSView {
        let panel = NSView()
        let heading = NSTextField(labelWithString: title)
        heading.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        heading.textColor = GrokTheme.text
        heading.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextField(wrappingLabelWithString: body)
        text.font = NSFont.systemFont(ofSize: 12)
        text.textColor = GrokTheme.muted
        text.translatesAutoresizingMaskIntoConstraints = false
        let button = UIHelpers.flatButton(action, accent: true, target: self, action: #selector(simpleActionPressed(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(tabId)
        panel.addSubview(heading)
        panel.addSubview(text)
        panel.addSubview(button)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            text.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            text.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 16),
            button.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
        ])
        return panel
    }

    @objc private func simpleActionPressed(_ sender: NSButton) {
        guard let tabId = sender.identifier?.rawValue else { return }
        runTabAction(tabId)
    }

    private func buildImportTab() -> NSView {
        let panel = NSView()
        let heading = NSTextField(labelWithString: "Import")
        heading.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        heading.textColor = GrokTheme.text
        heading.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextField(wrappingLabelWithString: "Import clips from video/ and image/ into the active Resolve media pool bin.")
        text.font = NSFont.systemFont(ofSize: 12)
        text.textColor = GrokTheme.muted
        text.translatesAutoresizingMaskIntoConstraints = false
        let importBtn = UIHelpers.flatButton("Import to Resolve", accent: true, target: self, action: #selector(simpleActionPressed(_:)))
        importBtn.identifier = NSUserInterfaceItemIdentifier("import")
        let scanImportBtn = UIHelpers.flatButton("Scan + Import", accent: false, target: self, action: #selector(scanImportPressed))
        let row = NSStackView(views: [importBtn, scanImportBtn])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(heading)
        panel.addSubview(text)
        panel.addSubview(row)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            text.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            text.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
        ])
        return panel
    }

    @objc private func scanImportPressed() {
        complete("ACTION:Scan + Import")
        window?.close()
    }

    private func runTabAction(_ tabId: String) {
        let map: [String: String] = [
            "import": "Import",
            "scan": "Scan Downloads",
            "bootstrap": "Bootstrap",
            "bridge": "Start Bridge",
            "folder": "Open Folder",
        ]
        guard let action = map[tabId] else { return }
        complete("ACTION:\(action)")
        window?.close()
    }

    private func buildCanvasTab() -> NSView {
        let panel = NSView()
        let left = buildMediaPanel()
        let right = buildPromptPanel()
        let split = NSStackView(views: [left, right])
        split.orientation = .horizontal
        split.spacing = 12
        split.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 8, right: 12)
        split.translatesAutoresizingMaskIntoConstraints = false
        left.widthAnchor.constraint(equalToConstant: 360).isActive = true
        panel.addSubview(split)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: panel.topAnchor),
            split.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])
        return panel
    }

    private func buildMediaPanel() -> NSView {
        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = GrokTheme.panel.cgColor
        panel.layer?.cornerRadius = 4
        panel.layer?.borderColor = GrokTheme.border.cgColor
        panel.layer?.borderWidth = 1
        panel.translatesAutoresizingMaskIntoConstraints = false

        let title = UIHelpers.fieldLabel("Canvas viewer")
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.imageScaling = .scaleProportionallyUpOrDown
        mediaView.wantsLayer = true
        mediaView.layer?.backgroundColor = GrokTheme.field.cgColor
        mediaView.layer?.cornerRadius = 3

        playerHost.translatesAutoresizingMaskIntoConstraints = false
        playerHost.isHidden = true

        mediaLabel.font = NSFont.systemFont(ofSize: 10)
        mediaLabel.textColor = GrokTheme.muted
        mediaLabel.maximumNumberOfLines = 2
        mediaLabel.translatesAutoresizingMaskIntoConstraints = false

        let loadBtn = UIHelpers.flatButton("Load…", accent: false, target: self, action: #selector(loadPressed))
        let refreshBtn = UIHelpers.flatButton("Refresh", accent: false, target: self, action: #selector(refreshMediaPressed))
        let btnRow = NSStackView(views: [loadBtn, refreshBtn])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        let stripLabel = UIHelpers.fieldLabel("Library")
        mediaStrip.orientation = .horizontal
        mediaStrip.spacing = 6
        mediaStrip.translatesAutoresizingMaskIntoConstraints = false
        let stripScroll = NSScrollView()
        stripScroll.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.hasHorizontalScroller = true
        stripScroll.drawsBackground = false
        stripScroll.documentView = mediaStrip
        mediaStrip.topAnchor.constraint(equalTo: stripScroll.contentView.topAnchor).isActive = true
        mediaStrip.leadingAnchor.constraint(equalTo: stripScroll.contentView.leadingAnchor).isActive = true
        mediaStrip.heightAnchor.constraint(equalToConstant: 56).isActive = true

        panel.addSubview(title)
        panel.addSubview(mediaView)
        panel.addSubview(playerHost)
        panel.addSubview(mediaLabel)
        panel.addSubview(btnRow)
        panel.addSubview(stripLabel)
        panel.addSubview(stripScroll)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            mediaView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            mediaView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            mediaView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            mediaView.heightAnchor.constraint(equalToConstant: 220),
            playerHost.topAnchor.constraint(equalTo: mediaView.topAnchor),
            playerHost.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            playerHost.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            playerHost.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
            mediaLabel.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 6),
            mediaLabel.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            mediaLabel.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            btnRow.topAnchor.constraint(equalTo: mediaLabel.bottomAnchor, constant: 8),
            btnRow.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            stripLabel.topAnchor.constraint(equalTo: btnRow.bottomAnchor, constant: 10),
            stripLabel.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            stripScroll.topAnchor.constraint(equalTo: stripLabel.bottomAnchor, constant: 4),
            stripScroll.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            stripScroll.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            stripScroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
            stripScroll.heightAnchor.constraint(equalToConstant: 60),
        ])
        return panel
    }

    private func buildPromptPanel() -> NSView {
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let genreLabel = UIHelpers.fieldLabel("Genre")
        let presetLabel = UIHelpers.fieldLabel("Preset")
        UIHelpers.stylePopup(groupPopup)
        UIHelpers.stylePopup(presetPopup)
        groupPopup.target = self
        groupPopup.action = #selector(groupChanged)
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)

        let promptLabel = UIHelpers.fieldLabel("Prompt")
        let promptScroll = NSScrollView()
        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.hasVerticalScroller = true
        promptScroll.borderType = .bezelBorder
        promptView.font = NSFont.systemFont(ofSize: 13)
        promptView.textColor = GrokTheme.text
        promptView.backgroundColor = GrokTheme.field
        promptView.isRichText = false
        promptView.textContainerInset = NSSize(width: 8, height: 8)
        promptScroll.documentView = promptView

        presetPreview.font = NSFont.systemFont(ofSize: 10)
        presetPreview.textColor = GrokTheme.muted
        presetPreview.maximumNumberOfLines = 0
        presetPreview.translatesAutoresizingMaskIntoConstraints = false

        let outputGrid = NSGridView(views: [
            [UIHelpers.fieldLabel("Duration"), durationPopup],
            [UIHelpers.fieldLabel("Resolution"), resolutionPopup],
            [UIHelpers.fieldLabel("Aspect"), aspectPopup],
            [UIHelpers.fieldLabel("LUT"), lutPopup],
        ])
        outputGrid.translatesAutoresizingMaskIntoConstraints = false
        outputGrid.rowSpacing = 6
        outputGrid.columnSpacing = 8
        for popup in [durationPopup, resolutionPopup, aspectPopup, lutPopup] { UIHelpers.stylePopup(popup) }
        lutPopup.target = self
        lutPopup.action = #selector(lutChanged)

        UIHelpers.styleField(promptAddField)
        UIHelpers.styleField(continuityField)
        let generate = UIHelpers.flatButton("Generate Video", accent: true, target: self, action: #selector(generatePressed))
        generate.keyEquivalent = "\r"
        let cancel = UIHelpers.flatButton("Close", accent: false, target: self, action: #selector(cancelPressed))

        panel.addSubview(genreLabel)
        panel.addSubview(groupPopup)
        panel.addSubview(presetLabel)
        panel.addSubview(presetPopup)
        panel.addSubview(promptLabel)
        panel.addSubview(promptScroll)
        panel.addSubview(presetPreview)
        panel.addSubview(outputGrid)
        let lutNotesLabel = UIHelpers.fieldLabel("LUT notes")
        let continuityLabel = UIHelpers.fieldLabel("Continuity")
        panel.addSubview(lutNotesLabel)
        panel.addSubview(promptAddField)
        panel.addSubview(continuityLabel)
        panel.addSubview(continuityField)
        panel.addSubview(cancel)
        panel.addSubview(generate)

        NSLayoutConstraint.activate([
            genreLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 4),
            genreLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            groupPopup.topAnchor.constraint(equalTo: genreLabel.bottomAnchor, constant: 4),
            groupPopup.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            groupPopup.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            presetLabel.topAnchor.constraint(equalTo: groupPopup.bottomAnchor, constant: 8),
            presetLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            presetPopup.topAnchor.constraint(equalTo: presetLabel.bottomAnchor, constant: 4),
            presetPopup.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            presetPopup.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            promptLabel.topAnchor.constraint(equalTo: presetPopup.bottomAnchor, constant: 8),
            promptLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            promptScroll.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            promptScroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            promptScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            promptScroll.heightAnchor.constraint(equalToConstant: 120),
            presetPreview.topAnchor.constraint(equalTo: promptScroll.bottomAnchor, constant: 6),
            presetPreview.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            presetPreview.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            outputGrid.topAnchor.constraint(equalTo: presetPreview.bottomAnchor, constant: 8),
            outputGrid.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            lutNotesLabel.topAnchor.constraint(equalTo: outputGrid.bottomAnchor, constant: 8),
            lutNotesLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            promptAddField.topAnchor.constraint(equalTo: lutNotesLabel.bottomAnchor, constant: 4),
            promptAddField.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            promptAddField.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            continuityLabel.topAnchor.constraint(equalTo: promptAddField.bottomAnchor, constant: 8),
            continuityLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            continuityField.topAnchor.constraint(equalTo: continuityLabel.bottomAnchor, constant: 4),
            continuityField.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            continuityField.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            generate.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            generate.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),
            cancel.trailingAnchor.constraint(equalTo: generate.leadingAnchor, constant: -8),
            cancel.bottomAnchor.constraint(equalTo: generate.bottomAnchor),
        ])
        return panel
    }

    private func populateGenerateControls() {
        groupPopup.removeAllItems()
        for group in catalog.groups {
            groupPopup.addItem(withTitle: group.label)
            groupPopup.lastItem?.representedObject = group.id
        }
        durationPopup.removeAllItems()
        for value in catalog.durations {
            durationPopup.addItem(withTitle: "\(value)s")
            durationPopup.lastItem?.representedObject = value
        }
        resolutionPopup.removeAllItems()
        for value in catalog.resolutions { resolutionPopup.addItem(withTitle: value) }
        aspectPopup.removeAllItems()
        for value in catalog.aspectRatios { aspectPopup.addItem(withTitle: value) }
        lutPopup.removeAllItems()
        lutPopup.addItem(withTitle: "None")
        lutPopup.lastItem?.representedObject = ""
        for preset in catalog.lutPresets {
            lutPopup.addItem(withTitle: preset.display)
            lutPopup.lastItem?.representedObject = preset.slug
        }
        let d = catalog.defaults
        promptView.string = d.prompt
        promptAddField.stringValue = d.promptAdd
        continuityField.stringValue = d.continuityNotes
        selectPopupItem(groupPopup, matching: d.slug)
        selectPopupTitle(durationPopup, title: "\(d.durationSec)s")
        selectPopupTitle(resolutionPopup, title: d.resolution)
        selectPopupTitle(aspectPopup, title: d.aspectRatio)
        reloadPresets(selectSlug: d.slug)
    }

    @objc private func loadPressed() {
        guard let url = MediaLibrary.pickFile() else { return }
        let ext = url.pathExtension.lowercased()
        let kind = ["mp4", "mov", "m4v", "webm"].contains(ext) ? "video" : "image"
        let item = MediaItem(id: url.path, path: url, name: url.lastPathComponent, kind: kind, modified: Date())
        showMedia(item)
    }

    @objc private func refreshMediaPressed() { reloadMediaStrip() }

    private func reloadMediaStrip() {
        mediaStrip.arrangedSubviews.forEach { mediaStrip.removeArrangedSubview($0); $0.removeFromSuperview() }
        for item in MediaLibrary.loadArtifacts() {
            let button = MediaThumbButton(item: item)
            button.target = self
            button.action = #selector(mediaThumbPressed(_:))
            mediaStrip.addArrangedSubview(button)
        }
        if selectedMedia == nil, let first = MediaLibrary.loadArtifacts().first {
            showMedia(first)
        }
    }

    @objc private func mediaThumbPressed(_ sender: MediaThumbButton) {
        showMedia(sender.item)
        for case let button as MediaThumbButton in mediaStrip.arrangedSubviews {
            button.isSelected = button.item.id == sender.item.id
        }
    }

    private func showMedia(_ item: MediaItem) {
        selectedMedia = item
        mediaLabel.stringValue = "\(item.kind.uppercased()) · \(item.name)"
        playerView?.removeFromSuperview()
        playerView = nil
        playerHost.isHidden = true
        mediaView.isHidden = false
        if item.kind == "video" {
            mediaView.isHidden = true
            playerHost.isHidden = false
            let player = AVPlayerView()
            player.controlsStyle = .inline
            player.translatesAutoresizingMaskIntoConstraints = false
            player.player = AVPlayer(url: item.path)
            playerHost.addSubview(player)
            NSLayoutConstraint.activate([
                player.topAnchor.constraint(equalTo: playerHost.topAnchor),
                player.leadingAnchor.constraint(equalTo: playerHost.leadingAnchor),
                player.trailingAnchor.constraint(equalTo: playerHost.trailingAnchor),
                player.bottomAnchor.constraint(equalTo: playerHost.bottomAnchor),
            ])
            playerView = player
            player.player?.play()
        } else {
            MediaLibrary.thumbnail(for: item, size: NSSize(width: 640, height: 360)) { [weak self] image in
                self?.mediaView.image = image
            }
        }
    }

    @objc private func groupChanged() { reloadPresets(selectSlug: nil) }

    @objc private func presetChanged() {
        guard let group = currentGroup() else { return }
        let index = presetPopup.indexOfSelectedItem
        guard index >= 0, index < group.presets.count else { return }
        let preset = group.presets[index]
        selectedPreset = preset
        presetPreview.stringValue = preset.promptPreview
        if promptView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptView.string = catalog.defaults.prompt
        }
        if selectedMedia == nil {
            UIHelpers.loadThumbnail(for: preset, into: mediaView)
            playerHost.isHidden = true
            mediaView.isHidden = false
            playerView?.player?.pause()
            mediaLabel.stringValue = "Preset · \(preset.display)"
        }
    }

    @objc private func lutChanged() {
        guard let slug = lutPopup.selectedItem?.representedObject as? String, !slug.isEmpty else { return }
        if let lut = catalog.lutPresets.first(where: { $0.slug == slug }),
           promptAddField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptAddField.stringValue = "Apply \(lut.display) color grade"
        }
    }

    @objc private func generatePressed() {
        guard let preset = selectedPreset else { return }
        let prompt = promptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let duration = (durationPopup.selectedItem?.representedObject as? Int) ?? catalog.defaults.durationSec
        let resolution = resolutionPopup.titleOfSelectedItem ?? catalog.defaults.resolution
        let aspect = aspectPopup.titleOfSelectedItem ?? catalog.defaults.aspectRatio
        let lut = (lutPopup.selectedItem?.representedObject as? String) ?? ""
        let promptAdd = promptAddField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let continuity = continuityField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [
            "ACTION:Generate Video",
            "SLUG:\(preset.slug)",
            "PROMPT:\(prompt)",
            "DURATION:\(duration)",
            "RESOLUTION:\(resolution)",
            "ASPECT:\(aspect)",
            "LUT:\(lut)",
            "PROMPT_ADD:\(promptAdd)",
            "CONTINUITY:\(continuity)",
        ]
        if let media = selectedMedia {
            lines.append("REFERENCE:\(media.path.path)")
        }
        complete(lines.joined(separator: "\n"))
        window?.close()
    }

    @objc private func cancelPressed() {
        complete("CANCELLED")
        window?.close()
    }

    private func currentGroup() -> PresetGroup? {
        let index = groupPopup.indexOfSelectedItem
        guard index >= 0, index < catalog.groups.count else { return catalog.groups.first }
        return catalog.groups[index]
    }

    private func reloadPresets(selectSlug: String?) {
        guard let group = currentGroup() else { return }
        presetPopup.removeAllItems()
        for preset in group.presets {
            presetPopup.addItem(withTitle: preset.display)
            presetPopup.lastItem?.representedObject = preset.slug
        }
        selectPopupItem(presetPopup, matching: selectSlug ?? group.presets.first?.slug ?? "")
        presetChanged()
    }

    private func selectPopupItem(_ popup: NSPopUpButton, matching slug: String) {
        for index in 0..<popup.numberOfItems {
            if let value = popup.item(at: index)?.representedObject as? String, value == slug {
                popup.selectItem(at: index)
                return
            }
        }
        for group in catalog.groups where group.presets.contains(where: { $0.slug == slug }) {
            if let gIndex = catalog.groups.firstIndex(where: { $0.id == group.id }) {
                groupPopup.selectItem(at: gIndex)
                reloadPresets(selectSlug: slug)
            }
            return
        }
    }

    private func selectPopupTitle(_ popup: NSPopUpButton, title: String) {
        if let index = (0..<popup.numberOfItems).first(where: { popup.itemTitle(at: $0) == title }) {
            popup.selectItem(at: index)
        }
    }
}

final class TabButton: NSButton {
    let tabId: String
    var isActive = false { didSet { refresh() } }

    init(title: String, tabId: String) {
        self.tabId = tabId
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        font = NSFont.systemFont(ofSize: 12, weight: .medium)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    private func refresh() {
        layer?.backgroundColor = (isActive ? GrokTheme.rowHover : GrokTheme.row).cgColor
        layer?.cornerRadius = 3
        contentTintColor = isActive ? GrokTheme.accent : GrokTheme.text
    }
}

final class MediaThumbButton: NSButton {
    let item: MediaItem
    var isSelected = false { didSet { layer?.borderColor = (isSelected ? GrokTheme.accent : GrokTheme.border).cgColor; layer?.borderWidth = isSelected ? 2 : 1 } }

    init(item: MediaItem) {
        self.item = item
        super.init(frame: .zero)
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 3
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        widthAnchor.constraint(equalToConstant: 76).isActive = true
        heightAnchor.constraint(equalToConstant: 52).isActive = true
        MediaLibrary.thumbnail(for: item, size: NSSize(width: 76, height: 52)) { [weak self] img in self?.image = img }
    }

    required init?(coder: NSCoder) { nil }
}
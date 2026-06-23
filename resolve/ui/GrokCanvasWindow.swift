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
        ("terminal", "Terminal"),
        ("timeline", "Timeline"),
        ("browser", "Browser"),
        ("imdb", "IMDb"),
        ("stream", "Stream"),
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
    private var selectedLut: PresetEntry?
    private var customLutDisplay: String?
    private var customLutPrompt: String?
    private var customLutPosterPath: String?
    private var viewerMode: ViewerMode = .media
    private var playerView: AVPlayerView?

    private let tabBar = NSStackView()
    private let contentHost = NSView()
    private var tabButtons: [String: TabButton] = [:]

    private let closeButton = UIHelpers.flatButton("Close", accent: false, target: nil, action: nil)
    private let generateButton = UIHelpers.flatButton("Generate Video", accent: true, target: nil, action: nil)
    private let actionFooterHost = NSView()

    private let mediaView = NSImageView()
    private let mediaLabel = NSTextField(labelWithString: "Load a reference or pick from library")
    private let mediaStrip = NSStackView()
    private let playerHost = NSView()
    private let viewerModeControl = NSSegmentedControl(labels: ["Media", "Preset"], trackingMode: .selectOne, target: nil, action: nil)
    private let metaView = UIHelpers.metaTextView()
    private let metaScroll = NSScrollView()

    private let lutPreviewView = NSImageView()
    private let lutMetaView = UIHelpers.metaTextView()
    private let lutMetaScroll = NSScrollView()
    private let lutTitle = NSTextField(labelWithString: "LUT viewer")

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

    private let browserStatus = NSTextField(wrappingLabelWithString: "Safari handoff via browser/inbox.json and clipboard")
    private let canvasBridgeStatus = NSTextField(wrappingLabelWithString: "Imagine + bridge — start bin/bridge for headless image/video")
    private var imdbController: ImdbTabController?
    private var streamController: StreamTabController?
    private var terminalController: TerminalTabController?
    private var timelineController: TimelineTabController?
    private var headerMonitor: HeaderMonitorController?

    init(catalog: GenerateCatalog) {
        self.catalog = catalog
        super.init()
    }

    func show(initialTab: String = "canvas") {
        let window = makeWindow()
        self.window = window
        window.delegate = self
        switchTab(initialTab)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        headerMonitor?.stop()
        complete("CANCELLED")
    }

    private func complete(_ value: String) {
        guard !finished else { return }
        finished = true
        onComplete?(value)
    }

    private func makeWindow() -> NSWindow {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: 1200, height: 780)
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
        window.minSize = NSSize(width: 980, height: 640)
        UIHelpers.applyResolveAppearance(to: window)

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let (header, monitor) = UIHelpers.headerView(
            title: GrokBrand.appName,
            subtitle: "Imagine canvas → Resolve edit",
            includeMonitor: true
        )
        headerMonitor = monitor
        let tabs = buildTabBar()
        contentHost.translatesAutoresizingMaskIntoConstraints = false

        closeButton.target = self
        closeButton.action = #selector(cancelPressed)
        generateButton.target = self
        generateButton.action = #selector(generatePressed)
        generateButton.keyEquivalent = "\r"
        let actionFooter = UIHelpers.actionFooter(close: closeButton, generate: generateButton)
        let trust = UIHelpers.trustFooter()

        root.addSubview(header)
        root.addSubview(tabs)
        root.addSubview(contentHost)
        root.addSubview(actionFooter)
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
            actionFooter.topAnchor.constraint(equalTo: contentHost.bottomAnchor),
            actionFooter.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            actionFooter.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            trust.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            trust.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            trust.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            actionFooter.bottomAnchor.constraint(equalTo: trust.topAnchor),
        ])

        populateGenerateControls()
        reloadMediaStrip()
        updateActionFooter()
        headerMonitor?.start()
        return window
    }

    private func updateActionFooter() {
        let onCanvas = activeTab == "canvas"
        generateButton.isHidden = !onCanvas
        generateButton.isEnabled = onCanvas && selectedPreset != nil
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
        terminalController?.stopPolling()
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
        case "terminal": panel = buildTerminalTab()
        case "timeline": panel = buildTimelineTab()
        case "browser": panel = buildBrowserTab()
        case "imdb": panel = buildImdbTab()
        case "stream": panel = buildStreamTab()
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
        updateActionFooter()
    }

    private func buildSimpleTab(title: String, body: String, action: String, tabId: String) -> NSView {
        let panel = NSView()
        let heading = NSTextField(labelWithString: title)
        UIHelpers.styleSectionHeading(heading)
        let text = NSTextField(wrappingLabelWithString: body)
        UIHelpers.styleBodyText(text)
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
        UIHelpers.styleSectionHeading(heading)
        let text = NSTextField(wrappingLabelWithString: "Import clips from video/ and image/ into the active Resolve media pool bin.")
        UIHelpers.styleBodyText(text)
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

    private func buildBrowserTab() -> NSView {
        let panel = NSView()
        let heading = NSTextField(labelWithString: "Grok Browser (Safari)")
        UIHelpers.styleSectionHeading(heading)

        let text = NSTextField(wrappingLabelWithString:
            "Talk between grok.com/imagine in Safari and this Resolve workflow. " +
            "Pull reads browser/inbox.json or clipboard; Push writes browser/outbox.json and copies your prompt."
        )
        UIHelpers.styleBodyText(text)

        browserStatus.font = GrokTypography.meta
        browserStatus.textColor = GrokTheme.textSecondary
        browserStatus.translatesAutoresizingMaskIntoConstraints = false

        let openBtn = UIHelpers.flatButton("Open Safari (Imagine)", accent: true, target: self, action: #selector(browserOpenPressed))
        let pullBtn = UIHelpers.flatButton("Pull Prompt", accent: false, target: self, action: #selector(browserPullPressed))
        let pushBtn = UIHelpers.flatButton("Push Prompt", accent: false, target: self, action: #selector(browserPushPressed))
        let folderBtn = UIHelpers.flatButton("Open browser/", accent: false, target: self, action: #selector(browserFolderPressed))
        let row = NSStackView(views: [openBtn, pullBtn, pushBtn, folderBtn])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(heading)
        panel.addSubview(text)
        panel.addSubview(row)
        panel.addSubview(browserStatus)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            text.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            text.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            browserStatus.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 14),
            browserStatus.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            browserStatus.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
        ])
        refreshBrowserStatus()
        return panel
    }

    @objc private func browserOpenPressed() {
        let result = BrowserBridge.run(["open"])
        browserStatus.stringValue = result.ok ? "Opened Safari → grok.com/imagine" : "Failed: \(result.output)"
    }

    @objc private func browserPullPressed() {
        let result = BrowserBridge.run(["pull"])
        if result.ok, !result.output.isEmpty {
            promptView.string = result.output
            browserStatus.stringValue = "Pulled prompt into Canvas (\(result.output.prefix(60))…)"
            switchTab("canvas")
        } else {
            browserStatus.stringValue = result.output.isEmpty ? "Pull failed" : result.output
        }
    }

    @objc private func browserPushPressed() {
        let prompt = promptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            browserStatus.stringValue = "Enter a prompt on the Canvas tab first"
            return
        }
        let result = BrowserBridge.run(["push", prompt])
        browserStatus.stringValue = result.ok ? "Pushed to Safari + browser/outbox.json" : "Failed: \(result.output)"
    }

    @objc private func browserFolderPressed() {
        NSWorkspace.shared.open(GrokPaths.browserDir)
    }

    private func refreshBrowserStatus() {
        let result = BrowserBridge.run(["status"])
        if result.ok {
            browserStatus.stringValue = result.output
        }
    }

    private func buildImdbTab() -> NSView {
        let controller = ImdbTabController()
        controller.promptView = promptView
        controller.onSwitchToCanvas = { [weak self] in self?.switchTab("canvas") }
        controller.onApplyLut = { [weak self] slug, display, promptAdd, lutPrompt, posterPath in
            self?.applyGeneratedLut(slug: slug, display: display, promptAdd: promptAdd, lutPrompt: lutPrompt, posterPath: posterPath)
        }
        imdbController = controller
        return controller.buildView()
    }

    private func buildStreamTab() -> NSView {
        let controller = StreamTabController()
        streamController = controller
        return controller.buildView()
    }

    private func buildTerminalTab() -> NSView {
        let controller = TerminalTabController()
        controller.onStartBridge = { [weak self] in self?.startBridgeInBackground() }
        controller.onOpenTerminal = { [weak self] in self?.openGrokConsoleTerminal() }
        terminalController = controller
        let view = controller.buildView()
        controller.startPolling()
        return view
    }

    private func startBridgeInBackground() {
        let bridge = GrokPaths.binDir.appendingPathComponent("bridge")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [
            "-lc",
            "export GROK_PUBLIC_FOLDER='\(GrokPaths.root.path)'; "
                + "export XAI_API_KEY=\"${XAI_API_KEY:-}\"; "
                + "'\(bridge.path)' >> '\(GrokPaths.bridgeDir.path)/menu-last.log' 2>&1 &",
        ]
        try? task.run()
    }

    private func openGrokConsoleTerminal() {
        let launcher = GrokPaths.binDir.appendingPathComponent("grok-terminal")
        let grok = GrokPaths.binDir.appendingPathComponent("grok")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [launcher.path, grok.path, "Grok Console"]
        try? task.run()
    }

    private func buildTimelineTab() -> NSView {
        let controller = TimelineTabController()
        controller.promptView = promptView
        controller.onScanTimeline = { [weak self] in
            self?.complete("ACTION:Scan Timeline")
            self?.window?.close()
        }
        controller.onBatchRegenerate = { [weak self] in
            self?.complete("ACTION:Batch Regenerate Timeline")
            self?.window?.close()
        }
        timelineController = controller
        return controller.buildView()
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
        let center = buildPromptPanel()
        let right = buildLutPanel()
        let split = NSStackView(views: [left, center, right])
        split.orientation = .horizontal
        split.spacing = 10
        split.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 8, right: 12)
        split.translatesAutoresizingMaskIntoConstraints = false
        left.widthAnchor.constraint(equalToConstant: 330).isActive = true
        right.widthAnchor.constraint(equalToConstant: 240).isActive = true
        panel.addSubview(split)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: panel.topAnchor),
            split.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])
        refreshViewer()
        updateLutViewer()
        return panel
    }

    private func buildMediaPanel() -> NSView {
        let panel = UIHelpers.panelShell()

        let title = UIHelpers.fieldLabel("Canvas viewer")
        viewerModeControl.selectedSegment = 0
        viewerModeControl.target = self
        viewerModeControl.action = #selector(viewerModeChanged)
        UIHelpers.styleSegmentedControl(viewerModeControl)

        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.imageScaling = .scaleProportionallyUpOrDown
        mediaView.wantsLayer = true
        mediaView.layer?.backgroundColor = GrokTheme.field.cgColor
        mediaView.layer?.cornerRadius = 3

        playerHost.translatesAutoresizingMaskIntoConstraints = false
        playerHost.isHidden = true

        UIHelpers.styleCaption(mediaLabel)
        mediaLabel.maximumNumberOfLines = 2

        metaScroll.hasVerticalScroller = true
        metaScroll.autohidesScrollers = false
        UIHelpers.styleScrollView(metaScroll)
        metaScroll.documentView = metaView
        UIHelpers.configureMetaTextView(metaView, in: metaScroll)

        let metaLabel = UIHelpers.fieldLabel("Content meta")

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
        mediaStrip.heightAnchor.constraint(equalToConstant: 52).isActive = true

        panel.addSubview(title)
        panel.addSubview(viewerModeControl)
        panel.addSubview(mediaView)
        panel.addSubview(playerHost)
        panel.addSubview(mediaLabel)
        panel.addSubview(metaLabel)
        panel.addSubview(metaScroll)
        panel.addSubview(btnRow)
        panel.addSubview(stripLabel)
        panel.addSubview(stripScroll)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            viewerModeControl.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            viewerModeControl.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            mediaView.topAnchor.constraint(equalTo: viewerModeControl.bottomAnchor, constant: 6),
            mediaView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            mediaView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            mediaView.heightAnchor.constraint(equalToConstant: 130),
            playerHost.topAnchor.constraint(equalTo: mediaView.topAnchor),
            playerHost.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            playerHost.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            playerHost.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
            mediaLabel.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 4),
            mediaLabel.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            mediaLabel.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: mediaLabel.bottomAnchor, constant: 6),
            metaLabel.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            metaScroll.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 4),
            metaScroll.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            metaScroll.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            metaScroll.bottomAnchor.constraint(equalTo: btnRow.topAnchor, constant: -8),
            metaScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
            btnRow.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            btnRow.bottomAnchor.constraint(equalTo: stripLabel.topAnchor, constant: -8),
            stripLabel.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            stripLabel.bottomAnchor.constraint(equalTo: stripScroll.topAnchor, constant: -4),
            stripScroll.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            stripScroll.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            stripScroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
            stripScroll.heightAnchor.constraint(equalToConstant: 56),
        ])
        return panel
    }

    private func buildLutPanel() -> NSView {
        let panel = UIHelpers.panelShell()

        lutTitle.font = GrokTypography.label
        lutTitle.textColor = GrokTheme.label
        lutTitle.stringValue = "LUT VIEWER"
        lutTitle.translatesAutoresizingMaskIntoConstraints = false

        lutPreviewView.translatesAutoresizingMaskIntoConstraints = false
        lutPreviewView.imageScaling = .scaleProportionallyUpOrDown
        lutPreviewView.wantsLayer = true
        lutPreviewView.layer?.backgroundColor = GrokTheme.field.cgColor
        lutPreviewView.layer?.cornerRadius = 3

        lutMetaScroll.hasVerticalScroller = true
        lutMetaScroll.autohidesScrollers = false
        UIHelpers.styleScrollView(lutMetaScroll)
        lutMetaScroll.documentView = lutMetaView
        UIHelpers.configureMetaTextView(lutMetaView, in: lutMetaScroll)

        panel.addSubview(lutTitle)
        panel.addSubview(lutPreviewView)
        panel.addSubview(lutMetaScroll)

        NSLayoutConstraint.activate([
            lutTitle.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            lutTitle.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            lutPreviewView.topAnchor.constraint(equalTo: lutTitle.bottomAnchor, constant: 6),
            lutPreviewView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            lutPreviewView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            lutPreviewView.heightAnchor.constraint(equalToConstant: 130),
            lutMetaScroll.topAnchor.constraint(equalTo: lutPreviewView.bottomAnchor, constant: 8),
            lutMetaScroll.leadingAnchor.constraint(equalTo: lutPreviewView.leadingAnchor),
            lutMetaScroll.trailingAnchor.constraint(equalTo: lutPreviewView.trailingAnchor),
            lutMetaScroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
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
        promptScroll.hasVerticalScroller = true
        UIHelpers.styleScrollView(promptScroll)
        promptView.font = GrokTypography.body
        promptView.textColor = GrokTheme.text
        promptView.backgroundColor = GrokTheme.field
        promptView.isRichText = false
        promptView.textContainerInset = NSSize(width: 8, height: 8)
        promptScroll.documentView = promptView

        presetPreview.font = GrokTypography.caption
        presetPreview.textColor = GrokTheme.textSecondary
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
        let bridgeLabel = UIHelpers.fieldLabel("Imagine + bridge")
        canvasBridgeStatus.font = GrokTypography.caption
        canvasBridgeStatus.textColor = GrokTheme.textDim
        canvasBridgeStatus.maximumNumberOfLines = 2
        canvasBridgeStatus.translatesAutoresizingMaskIntoConstraints = false

        let imagineOpenBtn = UIHelpers.flatButton("Open Imagine", accent: false, target: self, action: #selector(canvasOpenImagine))
        let imaginePullBtn = UIHelpers.flatButton("Pull", accent: false, target: self, action: #selector(canvasPullImagine))
        let imaginePushBtn = UIHelpers.flatButton("Push", accent: false, target: self, action: #selector(canvasPushImagine))
        let bridgeImgBtn = UIHelpers.flatButton("Bridge Image", accent: false, target: self, action: #selector(canvasBridgeImage))
        let bridgeVidBtn = UIHelpers.flatButton("Bridge Video", accent: true, target: self, action: #selector(canvasBridgeVideo))
        let bridgePingBtn = UIHelpers.flatButton("Ping", accent: false, target: self, action: #selector(canvasBridgePing))
        let bridgeRow = NSStackView(views: [imagineOpenBtn, imaginePullBtn, imaginePushBtn, bridgeImgBtn, bridgeVidBtn, bridgePingBtn])
        bridgeRow.orientation = .horizontal
        bridgeRow.spacing = 6
        bridgeRow.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(lutNotesLabel)
        panel.addSubview(promptAddField)
        panel.addSubview(continuityLabel)
        panel.addSubview(continuityField)
        panel.addSubview(bridgeLabel)
        panel.addSubview(bridgeRow)
        panel.addSubview(canvasBridgeStatus)

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
            promptScroll.heightAnchor.constraint(equalToConstant: 110),
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
            bridgeLabel.topAnchor.constraint(equalTo: continuityField.bottomAnchor, constant: 10),
            bridgeLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            bridgeRow.topAnchor.constraint(equalTo: bridgeLabel.bottomAnchor, constant: 4),
            bridgeRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            canvasBridgeStatus.topAnchor.constraint(equalTo: bridgeRow.bottomAnchor, constant: 4),
            canvasBridgeStatus.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            canvasBridgeStatus.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            canvasBridgeStatus.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -8),
        ])
        return panel
    }

    private func currentCanvasGenerationOptions() -> (slug: String, prompt: String, duration: Int, resolution: String, aspect: String, lut: String, promptAdd: String) {
        let slug = (presetPopup.selectedItem?.representedObject as? String) ?? (selectedPreset?.slug ?? catalog.defaults.slug)
        let prompt = promptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = (durationPopup.selectedItem?.representedObject as? Int) ?? catalog.defaults.durationSec
        let resolution = resolutionPopup.titleOfSelectedItem ?? catalog.defaults.resolution
        let aspect = aspectPopup.titleOfSelectedItem ?? catalog.defaults.aspectRatio
        let lut = (lutPopup.selectedItem?.representedObject as? String) ?? ""
        let promptAdd = promptAddField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return (slug, prompt, duration, resolution, aspect, lut, promptAdd)
    }

    @objc private func canvasOpenImagine() {
        let result = CanvasBridge.run(["open"])
        canvasBridgeStatus.stringValue = result.ok ? "Opened grok.com/imagine in Safari" : "Failed: \(result.output)"
    }

    @objc private func canvasPullImagine() {
        let result = CanvasBridge.run(["pull"])
        let parsed = CanvasBridge.parse(result)
        if let payload = parsed.payload, let prompt = payload.prompt, !prompt.isEmpty {
            promptView.string = prompt
            canvasBridgeStatus.stringValue = "Pulled prompt from Imagine"
        } else {
            canvasBridgeStatus.stringValue = parsed.error ?? result.output
        }
    }

    @objc private func canvasPushImagine() {
        let prompt = promptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            canvasBridgeStatus.stringValue = "Enter a prompt first"
            return
        }
        let result = CanvasBridge.run(["push", prompt])
        canvasBridgeStatus.stringValue = result.ok ? "Pushed prompt to Imagine + clipboard" : "Failed: \(result.output)"
    }

    @objc private func canvasBridgeImage() {
        let opts = currentCanvasGenerationOptions()
        guard !opts.prompt.isEmpty else {
            canvasBridgeStatus.stringValue = "Enter a prompt first"
            return
        }
        canvasBridgeStatus.stringValue = "Bridge image… (start bin/bridge if needed)"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var args = ["image", "--prompt", opts.prompt, "--slug", opts.slug, "--aspect", opts.aspect]
            if !opts.promptAdd.isEmpty { args += ["--prompt-add", opts.promptAdd] }
            if !opts.lut.isEmpty { args += ["--lut", opts.lut] }
            let result = CanvasBridge.run(args)
            let parsed = CanvasBridge.parse(result)
            DispatchQueue.main.async {
                self?.canvasBridgeStatus.stringValue = parsed.payload?.message ?? parsed.error ?? result.output
            }
        }
    }

    @objc private func canvasBridgeVideo() {
        let opts = currentCanvasGenerationOptions()
        guard !opts.prompt.isEmpty else {
            canvasBridgeStatus.stringValue = "Enter a prompt first"
            return
        }
        canvasBridgeStatus.stringValue = "Bridge video… (start bin/bridge if needed)"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var args = [
                "video", "--prompt", opts.prompt, "--slug", opts.slug,
                "--duration", String(opts.duration), "--resolution", opts.resolution, "--aspect", opts.aspect,
            ]
            if !opts.promptAdd.isEmpty { args += ["--prompt-add", opts.promptAdd] }
            if !opts.lut.isEmpty { args += ["--lut", opts.lut] }
            let result = CanvasBridge.run(args)
            let parsed = CanvasBridge.parse(result)
            DispatchQueue.main.async {
                self?.canvasBridgeStatus.stringValue = parsed.payload?.message ?? parsed.error ?? result.output
            }
        }
    }

    @objc private func canvasBridgePing() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let message = CanvasBridge.ping()
            DispatchQueue.main.async {
                self?.canvasBridgeStatus.stringValue = message
            }
        }
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
        if !d.lutSlug.isEmpty {
            selectPopupItem(lutPopup, matching: d.lutSlug)
            lutChanged()
        }
    }

    @objc private func viewerModeChanged() {
        viewerMode = viewerModeControl.selectedSegment == 1 ? .preset : .media
        refreshViewer()
    }

    private func refreshViewer() {
        switch viewerMode {
        case .media:
            if let media = selectedMedia {
                showMedia(media, updateMode: false)
            } else if let preset = selectedPreset {
                showPresetInViewer(preset)
            } else {
                mediaLabel.stringValue = "Load a reference or pick from library"
                metaView.string = "No media selected"
            }
        case .preset:
            if let preset = selectedPreset {
                showPresetInViewer(preset)
            } else {
                mediaLabel.stringValue = "Select a preset"
                metaView.string = "No preset selected"
                mediaView.image = nil
                playerHost.isHidden = true
                mediaView.isHidden = false
            }
        }
    }

    private func showPresetInViewer(_ preset: PresetEntry) {
        playerView?.player?.pause()
        playerView?.removeFromSuperview()
        playerView = nil
        playerHost.isHidden = true
        mediaView.isHidden = false
        UIHelpers.loadThumbnail(for: preset, into: mediaView)
        mediaLabel.stringValue = "Preset · \(preset.display)"
        metaView.string = MediaLibrary.metaLines(for: preset).joined(separator: "\n")
        UIHelpers.scrollMetaToTop(metaView, in: metaScroll)
    }

    private func updateMetaPanel() {
        switch viewerMode {
        case .media:
            if let media = selectedMedia {
                metaView.string = MediaLibrary.metaLines(for: media).joined(separator: "\n")
            }
        case .preset:
            if let preset = selectedPreset {
                metaView.string = MediaLibrary.metaLines(for: preset).joined(separator: "\n")
            }
        }
        UIHelpers.scrollMetaToTop(metaView, in: metaScroll)
    }

    private func updateLutViewer() {
        if selectedLut == nil, let custom = customLutPrompt, !custom.isEmpty {
            lutTitle.stringValue = (customLutDisplay ?? "FILM LUT").uppercased()
            if let path = customLutPosterPath, !path.isEmpty, let image = NSImage(contentsOfFile: path) {
                lutPreviewView.image = image
            } else {
                lutPreviewView.image = nil
            }
            lutMetaView.string = custom
            UIHelpers.scrollMetaToTop(lutMetaView, in: lutMetaScroll)
            return
        }
        guard let lut = selectedLut else {
            lutTitle.stringValue = "LUT VIEWER"
            lutPreviewView.image = nil
            lutMetaView.string = "Select a LUT from the dropdown"
            return
        }
        lutTitle.stringValue = lut.display.uppercased()
        UIHelpers.loadThumbnail(for: lut, into: lutPreviewView)
        var lines = MediaLibrary.metaLines(for: lut)
        if let custom = customLutPrompt, !custom.isEmpty {
            lines.append("")
            lines.append("FILM GRADE")
            lines.append(custom)
        }
        lutMetaView.string = lines.joined(separator: "\n")
        UIHelpers.scrollMetaToTop(lutMetaView, in: lutMetaScroll)
    }

    func applyGeneratedLut(slug: String, display: String, promptAdd: String, lutPrompt: String, posterPath: String) {
        customLutDisplay = display
        customLutPrompt = lutPrompt
        customLutPosterPath = posterPath
        promptAddField.stringValue = promptAdd
        if slug.isEmpty {
            selectedLut = nil
            lutPopup.selectItem(at: 0)
        } else {
            selectPopupItem(lutPopup, matching: slug)
            let matchedSlug = (lutPopup.selectedItem?.representedObject as? String) ?? ""
            if matchedSlug == slug {
                selectedLut = catalog.lutPresets.first(where: { $0.slug == slug })
            } else {
                selectedLut = nil
                lutPopup.selectItem(at: 0)
            }
        }
        updateLutViewer()
        switchTab("canvas")
    }

    @objc private func loadPressed() {
        guard let url = MediaLibrary.pickFile() else { return }
        let ext = url.pathExtension.lowercased()
        let kind = ["mp4", "mov", "m4v", "webm"].contains(ext) ? "video" : "image"
        let item = MediaItem(id: url.path, path: url, name: url.lastPathComponent, kind: kind, modified: Date(), meta: MediaLibrary.readSidecar(for: url))
        viewerMode = .media
        viewerModeControl.selectedSegment = 0
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
        viewerMode = .media
        viewerModeControl.selectedSegment = 0
        showMedia(sender.item)
        for case let button as MediaThumbButton in mediaStrip.arrangedSubviews {
            button.isSelected = button.item.id == sender.item.id
        }
    }

    private func showMedia(_ item: MediaItem, updateMode: Bool = true) {
        selectedMedia = item
        if updateMode { viewerMode = .media; viewerModeControl.selectedSegment = 0 }
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
        updateMetaPanel()
    }

    @objc private func groupChanged() { reloadPresets(selectSlug: nil) }

    @objc private func presetChanged() {
        guard let group = currentGroup() else { return }
        let index = presetPopup.indexOfSelectedItem
        guard index >= 0, index < group.presets.count else { return }
        let preset = group.presets[index]
        selectedPreset = preset
        presetPreview.stringValue = preset.promptPreview
        updateActionFooter()
        if promptView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptView.string = catalog.defaults.prompt
        }
        if viewerMode == .preset || selectedMedia == nil {
            showPresetInViewer(preset)
        }
    }

    @objc private func lutChanged() {
        customLutDisplay = nil
        customLutPrompt = nil
        customLutPosterPath = nil
        let slug = (lutPopup.selectedItem?.representedObject as? String) ?? ""
        if slug.isEmpty {
            selectedLut = nil
        } else {
            selectedLut = catalog.lutPresets.first(where: { $0.slug == slug })
            if let lut = selectedLut,
               promptAddField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                promptAddField.stringValue = "Apply \(lut.display) color grade"
            }
        }
        updateLutViewer()
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
        font = GrokTypography.tab
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    private func refresh() {
        layer?.backgroundColor = (isActive ? GrokTheme.rowActive : GrokTheme.row).cgColor
        layer?.cornerRadius = 2
        layer?.borderWidth = isActive ? 1 : 0
        layer?.borderColor = (isActive ? GrokTheme.accent : GrokTheme.borderSubtle).cgColor
        contentTintColor = isActive ? GrokTheme.text : GrokTheme.textSecondary
        font = NSFont.systemFont(ofSize: 11, weight: isActive ? .semibold : .medium)
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
import AppKit
import Foundation

struct BlankScene: Codable {
    let start: Double
    let end: Double?
    let title: String?
    let live: Bool?
}

struct BlankIntel: Codable {
    let ok: Bool?
    let error: String?
    let url: String?
    let kind: String?
    let title: String?
    let durationLabel: String?
    let isLive: Bool?
    let scenes: [BlankScene]?

    enum CodingKeys: String, CodingKey {
        case ok, error, url, kind, title, scenes
        case durationLabel = "duration_label"
        case isLive = "is_live"
    }
}

struct BlankResolve: Codable {
    let ok: Bool?
    let error: String?
    let url: String?
    let kind: String?
    let title: String?
    let streamUrl: String?

    enum CodingKeys: String, CodingKey {
        case ok, error, url, kind, title
        case streamUrl = "stream_url"
    }
}

struct BlankSnapshot: Codable {
    let ok: Bool?
    let error: String?
    let path: String?
    let t: Double?
    let cached: Bool?
}

struct BlankSnapshotsResponse: Codable {
    let ok: Bool?
    let error: String?
    let title: String?
    let snapshots: [BlankSnapshotRow]?
    let errors: [BlankSnapshotError]?
}

struct BlankSnapshotRow: Codable {
    let t: Double?
    let title: String?
    let path: String?
}

struct BlankSnapshotError: Codable {
    let t: Double?
    let title: String?
    let error: String?
}

struct BlankDownload: Codable {
    let name: String
    let path: String
    let sizeBytes: Int?

    enum CodingKeys: String, CodingKey {
        case name, path
        case sizeBytes = "size_bytes"
    }
}

struct BlankDownloadsResponse: Codable {
    let ok: Bool?
    let downloads: [BlankDownload]?
}

struct BlankCommand: Codable {
    let section: String?
    let label: String
    let cmd: String
}

struct BlankCommandsResponse: Codable {
    let ok: Bool?
    let error: String?
    let url: String?
    let kindLabel: String?
    let commands: [BlankCommand]?

    enum CodingKeys: String, CodingKey {
        case ok, error, url, commands
        case kindLabel = "kind_label"
    }
}

struct BlankToolStatus: Codable {
    let found: Bool
    let path: String?
}

struct BlankStatusResponse: Codable {
    let ok: Bool?
    let blankDir: String?
    let tools: [String: BlankToolStatus]?
    let downloads: [BlankDownload]?

    enum CodingKeys: String, CodingKey {
        case ok, tools, downloads
        case blankDir = "blank_dir"
    }
}

enum BlankBridge {
    static var binURL: URL { GrokPaths.root.appendingPathComponent("bin/blank") }

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

    static func status() -> BlankStatusResponse? {
        let result = run(["status"])
        guard let data = result.output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BlankStatusResponse.self, from: data)
    }

    static func resolve(_ url: String) -> (payload: BlankResolve?, error: String?) {
        let result = run(["resolve", url])
        guard let data = result.output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BlankResolve.self, from: data) else {
            return (nil, result.output.isEmpty ? "Resolve failed" : result.output)
        }
        if payload.ok == false {
            return (nil, payload.error ?? "Resolve failed")
        }
        if !result.ok, let err = payload.error {
            return (nil, err)
        }
        return (payload, nil)
    }

    static func intel(_ url: String) -> (payload: BlankIntel?, error: String?) {
        let result = run(["intel", url])
        guard let data = result.output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BlankIntel.self, from: data) else {
            return (nil, result.output.isEmpty ? "Intel failed" : result.output)
        }
        if payload.ok == false {
            return (nil, payload.error ?? "Intel failed")
        }
        return (payload, nil)
    }

    static func snapshot(_ url: String, t: Double) -> (payload: BlankSnapshot?, error: String?) {
        let result = run(["snapshot", url, String(Int(t))])
        guard let data = result.output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BlankSnapshot.self, from: data) else {
            return (nil, result.output.isEmpty ? "Snapshot failed" : result.output)
        }
        if payload.ok == false {
            return (nil, payload.error ?? "Snapshot failed")
        }
        return (payload, nil)
    }

    static func snapshots(_ url: String, limit: Int = 8) -> (payload: BlankSnapshotsResponse?, error: String?) {
        let result = run(["snapshots", "--limit", String(limit), url])
        guard let data = result.output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BlankSnapshotsResponse.self, from: data) else {
            return (nil, result.output.isEmpty ? "Snapshots failed" : result.output)
        }
        if payload.ok == false {
            return (nil, payload.error ?? "Snapshots failed")
        }
        return (payload, nil)
    }

    static func commands(_ url: String) -> (payload: BlankCommandsResponse?, error: String?) {
        let result = run(["commands", url])
        guard let data = result.output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BlankCommandsResponse.self, from: data) else {
            return (nil, result.output.isEmpty ? "Commands failed" : result.output)
        }
        return (payload, nil)
    }

    static func listDownloads() -> [BlankDownload] {
        let result = run(["list-downloads"])
        guard let data = result.output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BlankDownloadsResponse.self, from: data) else {
            return []
        }
        return payload.downloads ?? []
    }
}

final class MkvTabController: NSObject {
    private let urlField = NSTextField(string: "")
    private let timeField = NSTextField(string: "60")
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailView = UIHelpers.metaTextView()
    private let detailScroll = NSScrollView()
    private let commandsView = UIHelpers.metaTextView()
    private let commandsScroll = NSScrollView()
    private let previewView = NSImageView()
    private let scenesStack = NSStackView()
    private let scenesScroll = NSScrollView()
    private let downloadsPopup = NSPopUpButton()

    private var currentUrl = ""
    private var lastSnapshotPath = ""
    private var sceneButtons: [NSButton] = []

    func buildView() -> NSView {
        let panel = NSView()
        let heading = NSTextField(labelWithString: "MKV / ffplay Ingest")
        UIHelpers.styleSectionHeading(heading)

        let intro = NSTextField(wrappingLabelWithString:
            "Paste a watch URL — resolve with yt-dlp, pull high-res scene snapshots via ffmpeg, archive MKV, and ffplay streams or local files. Terminal recipes mirror fornevercollective/blank."
        )
        UIHelpers.styleBodyText(intro)

        statusLabel.font = GrokTypography.caption
        statusLabel.textColor = GrokTheme.textDim
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        refreshStatus()

        UIHelpers.styleField(urlField)
        urlField.placeholderString = "https://youtube.com/watch?v=… or TikTok / HLS / direct URL"
        UIHelpers.styleField(timeField)
        timeField.placeholderString = "seconds"

        let resolveBtn = UIHelpers.flatButton("Resolve", accent: true, target: self, action: #selector(resolvePressed))
        let intelBtn = UIHelpers.flatButton("Scenes", accent: false, target: self, action: #selector(intelPressed))
        let snapBtn = UIHelpers.flatButton("Snapshot @", accent: false, target: self, action: #selector(snapshotPressed))
        let snapsBtn = UIHelpers.flatButton("Pull Scenes", accent: true, target: self, action: #selector(snapshotsPressed))
        let dlBtn = UIHelpers.flatButton("Download MKV", accent: false, target: self, action: #selector(downloadPressed))
        let playBtn = UIHelpers.flatButton("ffplay Stream", accent: false, target: self, action: #selector(playStreamPressed))
        let playFileBtn = UIHelpers.flatButton("ffplay MKV", accent: false, target: self, action: #selector(playFilePressed))
        let cmdsBtn = UIHelpers.flatButton("Terminal Cmds", accent: false, target: self, action: #selector(commandsPressed))
        let folderBtn = UIHelpers.flatButton("blank/", accent: false, target: self, action: #selector(folderPressed))
        let importBtn = UIHelpers.flatButton("Import Still", accent: false, target: self, action: #selector(importStillPressed))

        let row1 = NSStackView(views: [resolveBtn, intelBtn, snapBtn, timeField, snapsBtn])
        row1.orientation = .horizontal
        row1.spacing = 8
        row1.translatesAutoresizingMaskIntoConstraints = false

        let row2 = NSStackView(views: [dlBtn, playBtn, playFileBtn, cmdsBtn, folderBtn, importBtn])
        row2.orientation = .horizontal
        row2.spacing = 8
        row2.translatesAutoresizingMaskIntoConstraints = false

        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = GrokTheme.field.cgColor
        previewView.translatesAutoresizingMaskIntoConstraints = false

        scenesStack.orientation = .vertical
        scenesStack.spacing = 4
        scenesStack.translatesAutoresizingMaskIntoConstraints = false
        scenesScroll.hasVerticalScroller = true
        UIHelpers.styleScrollView(scenesScroll)
        scenesScroll.documentView = scenesStack
        scenesStack.topAnchor.constraint(equalTo: scenesScroll.contentView.topAnchor).isActive = true
        scenesStack.leadingAnchor.constraint(equalTo: scenesScroll.contentView.leadingAnchor).isActive = true
        scenesStack.widthAnchor.constraint(equalTo: scenesScroll.contentView.widthAnchor).isActive = true

        detailScroll.hasVerticalScroller = true
        UIHelpers.styleScrollView(detailScroll)
        detailScroll.documentView = detailView
        detailView.translatesAutoresizingMaskIntoConstraints = false
        detailView.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor).isActive = true

        commandsScroll.hasVerticalScroller = true
        UIHelpers.styleScrollView(commandsScroll)
        commandsScroll.documentView = commandsView
        commandsView.translatesAutoresizingMaskIntoConstraints = false
        commandsView.widthAnchor.constraint(equalTo: commandsScroll.contentView.widthAnchor).isActive = true

        downloadsPopup.translatesAutoresizingMaskIntoConstraints = false
        reloadDownloads()

        let left = UIHelpers.panelShell()
        let center = UIHelpers.panelShell()
        let right = UIHelpers.panelShell()
        let scenesLabel = UIHelpers.fieldLabel("Scenes / snapshots")
        let previewLabel = UIHelpers.fieldLabel("Preview")
        let cmdsLabel = UIHelpers.fieldLabel("Terminal commands")
        let mkvLabel = UIHelpers.fieldLabel("Local MKV")

        left.addSubview(scenesLabel)
        left.addSubview(scenesScroll)
        center.addSubview(previewLabel)
        center.addSubview(previewView)
        center.addSubview(detailScroll)
        right.addSubview(mkvLabel)
        right.addSubview(downloadsPopup)
        right.addSubview(cmdsLabel)
        right.addSubview(commandsScroll)

        panel.addSubview(heading)
        panel.addSubview(intro)
        panel.addSubview(statusLabel)
        panel.addSubview(urlField)
        panel.addSubview(row1)
        panel.addSubview(row2)
        panel.addSubview(left)
        panel.addSubview(center)
        panel.addSubview(right)

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            intro.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            intro.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            intro.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            statusLabel.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            urlField.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            urlField.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            urlField.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            row1.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 8),
            row1.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            row2.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 8),
            row2.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            left.topAnchor.constraint(equalTo: row2.bottomAnchor, constant: 10),
            left.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            left.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
            left.widthAnchor.constraint(equalTo: panel.widthAnchor, multiplier: 0.30),
            center.topAnchor.constraint(equalTo: left.topAnchor),
            center.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 10),
            center.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            center.widthAnchor.constraint(equalTo: panel.widthAnchor, multiplier: 0.34),
            right.topAnchor.constraint(equalTo: left.topAnchor),
            right.leadingAnchor.constraint(equalTo: center.trailingAnchor, constant: 10),
            right.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            right.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            scenesLabel.topAnchor.constraint(equalTo: left.topAnchor, constant: 10),
            scenesLabel.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            scenesScroll.topAnchor.constraint(equalTo: scenesLabel.bottomAnchor, constant: 6),
            scenesScroll.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            scenesScroll.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -10),
            scenesScroll.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -10),
            previewLabel.topAnchor.constraint(equalTo: center.topAnchor, constant: 10),
            previewLabel.leadingAnchor.constraint(equalTo: center.leadingAnchor, constant: 10),
            previewView.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 6),
            previewView.leadingAnchor.constraint(equalTo: previewLabel.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: center.trailingAnchor, constant: -10),
            previewView.heightAnchor.constraint(equalToConstant: 200),
            detailScroll.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
            detailScroll.leadingAnchor.constraint(equalTo: previewLabel.leadingAnchor),
            detailScroll.trailingAnchor.constraint(equalTo: center.trailingAnchor, constant: -10),
            detailScroll.bottomAnchor.constraint(equalTo: center.bottomAnchor, constant: -10),
            mkvLabel.topAnchor.constraint(equalTo: right.topAnchor, constant: 10),
            mkvLabel.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 10),
            downloadsPopup.topAnchor.constraint(equalTo: mkvLabel.bottomAnchor, constant: 6),
            downloadsPopup.leadingAnchor.constraint(equalTo: mkvLabel.leadingAnchor),
            downloadsPopup.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -10),
            cmdsLabel.topAnchor.constraint(equalTo: downloadsPopup.bottomAnchor, constant: 10),
            cmdsLabel.leadingAnchor.constraint(equalTo: mkvLabel.leadingAnchor),
            commandsScroll.topAnchor.constraint(equalTo: cmdsLabel.bottomAnchor, constant: 6),
            commandsScroll.leadingAnchor.constraint(equalTo: mkvLabel.leadingAnchor),
            commandsScroll.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -10),
            commandsScroll.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -10),
            timeField.widthAnchor.constraint(equalToConstant: 56),
        ])
        return panel
    }

    private func refreshStatus() {
        if let status = BlankBridge.status() {
            let ytdlp = status.tools?["yt-dlp"]?.found == true ? "yt-dlp ✓" : "yt-dlp ✗"
            let ffmpeg = status.tools?["ffmpeg"]?.found == true ? "ffmpeg ✓" : "ffmpeg ✗"
            let ffplay = status.tools?["ffplay"]?.found == true ? "ffplay ✓" : "ffplay ✗"
            statusLabel.stringValue = "\(ytdlp) · \(ffmpeg) · \(ffplay) · blank/downloads/"
        }
    }

    private func normalizedUrl() -> String? {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            statusLabel.stringValue = "Paste a watch URL first"
            return nil
        }
        return raw
    }

    private func setDetail(_ text: String) {
        detailView.string = text
        UIHelpers.scrollMetaToEnd(detailView)
    }

    private func reloadDownloads() {
        downloadsPopup.removeAllItems()
        let items = BlankBridge.listDownloads()
        if items.isEmpty {
            downloadsPopup.addItem(withTitle: "(no MKV yet)")
        } else {
            for item in items {
                downloadsPopup.addItem(withTitle: item.name)
            }
        }
    }

    private func reloadScenes(_ scenes: [BlankScene]) {
        scenesStack.arrangedSubviews.forEach { scenesStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        sceneButtons.removeAll()
        for scene in scenes {
            let t = Int(scene.start)
            let title = scene.title ?? "Scene \(t)s"
            let btn = UIHelpers.flatButton("\(title) · \(t)s", accent: false, target: self, action: #selector(scenePressed(_:)))
            btn.identifier = NSUserInterfaceItemIdentifier(String(t))
            sceneButtons.append(btn)
            scenesStack.addArrangedSubview(btn)
        }
    }

    private func loadPreview(path: String) {
        guard let image = NSImage(contentsOfFile: path) else { return }
        lastSnapshotPath = path
        previewView.image = image
    }

    @objc private func resolvePressed() {
        guard let url = normalizedUrl() else { return }
        currentUrl = url
        statusLabel.stringValue = "Resolving stream…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = BlankBridge.resolve(url)
            DispatchQueue.main.async {
                guard let self else { return }
                if let payload = result.payload {
                    self.currentUrl = payload.url ?? url
                    let title = payload.title ?? "(no title)"
                    let kind = payload.kind ?? "page"
                    let stream = payload.streamUrl ?? ""
                    self.setDetail("Resolved · \(kind)\n\(title)\n\n\(stream)")
                    self.statusLabel.stringValue = "Resolved · \(title)"
                    _ = BlankBridge.run(["commands", self.currentUrl])
                    self.loadCommands()
                } else {
                    self.statusLabel.stringValue = result.error ?? "Resolve failed"
                }
            }
        }
    }

    @objc private func intelPressed() {
        guard let url = normalizedUrl() else { return }
        currentUrl = url
        statusLabel.stringValue = "Fetching chapters…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = BlankBridge.intel(url)
            DispatchQueue.main.async {
                guard let self else { return }
                if let payload = result.payload {
                    let scenes = payload.scenes ?? []
                    self.reloadScenes(scenes)
                    let title = payload.title ?? url
                    let dur = payload.durationLabel ?? "?"
                    let live = payload.isLive == true ? "LIVE" : "VOD"
                    self.setDetail("\(title)\n\(live) · \(dur) · \(scenes.count) scenes")
                    self.statusLabel.stringValue = "\(scenes.count) scenes · \(title)"
                    self.loadCommands()
                } else {
                    self.statusLabel.stringValue = result.error ?? "Intel failed"
                }
            }
        }
    }

    @objc private func snapshotPressed() {
        guard let url = normalizedUrl() else { return }
        let t = Double(timeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 60
        currentUrl = url
        statusLabel.stringValue = "Capturing frame @ \(Int(t))s…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = BlankBridge.snapshot(url, t: t)
            DispatchQueue.main.async {
                guard let self else { return }
                if let payload = result.payload, let path = payload.path {
                    self.loadPreview(path: path)
                    self.setDetail("Snapshot @ \(Int(t))s\n\(path)")
                    self.statusLabel.stringValue = "Snapshot saved"
                } else {
                    self.statusLabel.stringValue = result.error ?? "Snapshot failed"
                }
            }
        }
    }

    @objc private func snapshotsPressed() {
        guard let url = normalizedUrl() else { return }
        currentUrl = url
        statusLabel.stringValue = "Pulling scene snapshots…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = BlankBridge.snapshots(url, limit: 8)
            DispatchQueue.main.async {
                guard let self else { return }
                if let payload = result.payload {
                    let snaps = payload.snapshots ?? []
                    self.scenesStack.arrangedSubviews.forEach { self.scenesStack.removeArrangedSubview($0); $0.removeFromSuperview() }
                    for snap in snaps {
                        let t = Int(snap.t ?? 0)
                        let title = snap.title ?? "Scene \(t)s"
                        let btn = UIHelpers.flatButton("✓ \(title)", accent: false, target: self, action: #selector(self.sceneSnapshotPressed(_:)))
                        btn.identifier = NSUserInterfaceItemIdentifier(snap.path ?? String(t))
                        self.scenesStack.addArrangedSubview(btn)
                    }
                    if let first = snaps.first?.path {
                        self.loadPreview(path: first)
                    }
                    let errCount = payload.errors?.count ?? 0
                    self.statusLabel.stringValue = "\(snaps.count) snapshots" + (errCount > 0 ? " · \(errCount) errors" : "")
                    self.setDetail("Pulled \(snaps.count) high-res stills into blank/snapshots/")
                } else {
                    self.statusLabel.stringValue = result.error ?? "Snapshots failed"
                }
            }
        }
    }

    @objc private func scenePressed(_ sender: NSButton) {
        guard let url = normalizedUrl() else { return }
        let t = Double(sender.identifier?.rawValue ?? "0") ?? 0
        timeField.stringValue = String(Int(t))
        statusLabel.stringValue = "Capturing \(Int(t))s…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = BlankBridge.snapshot(url, t: t)
            DispatchQueue.main.async {
                guard let self else { return }
                if let path = result.payload?.path {
                    self.loadPreview(path: path)
                    self.statusLabel.stringValue = "Snapshot @ \(Int(t))s"
                }
            }
        }
    }

    @objc private func sceneSnapshotPressed(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, !path.isEmpty else { return }
        loadPreview(path: path)
    }

    @objc private func downloadPressed() {
        guard let url = normalizedUrl() else { return }
        let result = BlankBridge.run(["download-mkv", url])
        if result.ok {
            statusLabel.stringValue = "MKV download started → blank/downloads/"
            reloadDownloads()
        } else {
            statusLabel.stringValue = result.output
        }
    }

    @objc private func playStreamPressed() {
        guard let url = normalizedUrl() else { return }
        _ = BlankBridge.run(["play", url])
        statusLabel.stringValue = "ffplay stream launched"
    }

    @objc private func playFilePressed() {
        let title = downloadsPopup.titleOfSelectedItem ?? ""
        guard title != "(no MKV yet)" else {
            statusLabel.stringValue = "Download an MKV first"
            return
        }
        let items = BlankBridge.listDownloads()
        guard let item = items.first(where: { $0.name == title }) else { return }
        _ = BlankBridge.run(["play-file", item.path])
        statusLabel.stringValue = "ffplay · \(item.name)"
    }

    @objc private func commandsPressed() {
        loadCommands()
    }

    private func loadCommands() {
        let url = currentUrl.isEmpty ? (normalizedUrl() ?? "") : currentUrl
        guard !url.isEmpty else { return }
        let result = BlankBridge.commands(url)
        guard let payload = result.payload else { return }
        var lines: [String] = []
        if let kind = payload.kindLabel {
            lines.append("# \(kind) · \(payload.url ?? url)\n")
        }
        var lastSection = ""
        for cmd in payload.commands ?? [] {
            let section = cmd.section ?? ""
            if section != lastSection {
                lines.append("\n## \(section)")
                lastSection = section
            }
            lines.append("\n# \(cmd.label)\n\(cmd.cmd)")
        }
        commandsView.string = lines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(commandsView.string, forType: .string)
        statusLabel.stringValue = "Terminal commands copied to clipboard"
    }

    @objc private func folderPressed() {
        _ = BlankBridge.run(["open-folder"])
    }

    @objc private func importStillPressed() {
        let path = lastSnapshotPath.isEmpty
            ? scenesStack.arrangedSubviews.compactMap({ ($0 as? NSButton)?.identifier?.rawValue }).first(where: { $0.hasSuffix(".jpg") }) ?? ""
            : lastSnapshotPath
        guard !path.isEmpty else {
            statusLabel.stringValue = "Capture a snapshot first"
            return
        }
        let src = URL(fileURLWithPath: path)
        let dest = GrokPaths.imageDir.appendingPathComponent(src.lastPathComponent)
        try? FileManager.default.createDirectory(at: GrokPaths.imageDir, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: src, to: dest)
        statusLabel.stringValue = "Imported → image/\(src.lastPathComponent)"
    }
}
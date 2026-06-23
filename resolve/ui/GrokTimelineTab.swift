import AppKit
import Foundation

struct TimelineScan: Codable {
    let scannedAt: String?
    let projectName: String?
    let timelineName: String?
    let clipCount: Int?
    let clips: [TimelineClip]

    enum CodingKeys: String, CodingKey {
        case clips
        case scannedAt = "scanned_at"
        case projectName = "project_name"
        case timelineName = "timeline_name"
        case clipCount = "clip_count"
    }
}

struct TimelineClip: Codable {
    let id: String
    let track: Int
    let name: String
    let filePath: String?
    let timelineIn: String?
    let timelineOut: String?
    let prompt: String?
    let slug: String?
    let lut: String?
    let continuity: String?
    let promptAdd: String?

    enum CodingKeys: String, CodingKey {
        case id, track, name, prompt, slug, lut, continuity
        case filePath = "file_path"
        case timelineIn = "timeline_in"
        case timelineOut = "timeline_out"
        case promptAdd = "prompt_add"
    }
}

struct TimelineScanResponse: Codable {
    let ok: Bool?
    let error: String?
    let clipCount: Int?
    let fallback: Bool?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case ok, error, fallback, note
        case clipCount = "clip_count"
    }
}

enum TimelineBridge {
    static var binURL: URL { GrokPaths.root.appendingPathComponent("bin/timeline") }

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
            return (task.terminationStatus == 0, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    static func load() -> TimelineScan? {
        let result = run(["load"])
        guard result.ok, let data = result.output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TimelineScan.self, from: data)
    }

    static func scanTimeline(artifactsOnly: Bool = false) -> (ok: Bool, needsLuaScan: Bool, message: String) {
        var args = ["scan"]
        if artifactsOnly { args.append("--artifacts-only") }
        let result = run(args)
        guard let data = result.output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TimelineScanResponse.self, from: data) else {
            let text = result.output.isEmpty ? "Timeline scan failed" : result.output
            return (false, false, text)
        }
        if payload.ok == true {
            let count = payload.clipCount ?? 0
            var msg = "Scanned \(count) Grok clip(s)"
            if payload.fallback == true {
                msg += " (artifacts fallback — no timeline positions)"
            }
            return (true, false, msg)
        }
        let err = payload.error ?? "Timeline scan failed"
        let needsLua = err.localizedCaseInsensitiveContains("resolve not connected")
        return (false, needsLua, err)
    }
}

final class TimelineTabController: NSObject {
    weak var promptView: NSTextView?
    var onScanTimeline: (() -> Void)?
    var onBatchRegenerate: (() -> Void)?

    private var clips: [TimelineClip] = []
    private var selectedIds: Set<String> = []
    private let statusLabel = NSTextField(labelWithString: "")
    private let clipList = NSStackView()
    private let clipScroll = NSScrollView()
    private let promptField = NSTextField(string: "")
    private let slugField = NSTextField(string: "")
    private let lutField = NSTextField(string: "")
    private let continuityField = NSTextField(string: "")
    private let metaView = UIHelpers.metaTextView()
    private var activeClipId: String?

    func buildView() -> NSView {
        let panel = NSView()
        let heading = NSTextField(labelWithString: "Timeline Grok Clips")
        UIHelpers.styleSectionHeading(heading)

        let intro = NSTextField(wrappingLabelWithString:
            "Scan the active timeline for Grok footage (stays in this panel). Edit prompts per clip, or batch-update and queue regenerates."
        )
        UIHelpers.styleBodyText(intro)

        statusLabel.font = GrokTypography.caption
        statusLabel.textColor = GrokTheme.textSecondary
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let scanBtn = UIHelpers.flatButton("Scan Timeline", accent: true, target: self, action: #selector(scanPressed))
        let refreshBtn = UIHelpers.flatButton("Refresh", accent: false, target: self, action: #selector(refreshPressed))
        let artifactBtn = UIHelpers.flatButton("Scan Artifacts", accent: false, target: self, action: #selector(artifactsPressed))
        let saveBtn = UIHelpers.flatButton("Save Meta", accent: false, target: self, action: #selector(savePressed))
        let batchSaveBtn = UIHelpers.flatButton("Batch Save", accent: false, target: self, action: #selector(batchSavePressed))
        let batchGenBtn = UIHelpers.flatButton("Batch Regenerate", accent: true, target: self, action: #selector(batchGenPressed))
        let addPromptBtn = UIHelpers.flatButton("Add to Prompt", accent: false, target: self, action: #selector(addPromptPressed))
        let topRow = NSStackView(views: [scanBtn, refreshBtn, artifactBtn, saveBtn, batchSaveBtn, batchGenBtn, addPromptBtn])
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.translatesAutoresizingMaskIntoConstraints = false

        clipList.orientation = .vertical
        clipList.spacing = 4
        clipList.translatesAutoresizingMaskIntoConstraints = false
        clipScroll.hasVerticalScroller = true
        clipScroll.autohidesScrollers = false
        UIHelpers.styleScrollView(clipScroll)
        clipScroll.documentView = clipList
        clipList.topAnchor.constraint(equalTo: clipScroll.contentView.topAnchor).isActive = true
        clipList.leadingAnchor.constraint(equalTo: clipScroll.contentView.leadingAnchor).isActive = true
        clipList.widthAnchor.constraint(equalTo: clipScroll.contentView.widthAnchor).isActive = true

        let editorLabel = UIHelpers.fieldLabel("Clip editor")
        UIHelpers.styleField(promptField)
        promptField.placeholderString = "Prompt"
        UIHelpers.styleField(slugField)
        slugField.placeholderString = "Preset slug"
        UIHelpers.styleField(lutField)
        lutField.placeholderString = "LUT slug"
        UIHelpers.styleField(continuityField)
        continuityField.placeholderString = "Continuity notes"

        let metaScroll = NSScrollView()
        metaScroll.hasVerticalScroller = true
        UIHelpers.styleScrollView(metaScroll)
        metaScroll.documentView = metaView
        UIHelpers.configureMetaTextView(metaView, in: metaScroll)

        let left = UIHelpers.panelShell()
        let right = UIHelpers.panelShell()
        let listLabel = UIHelpers.fieldLabel("Clips on timeline")
        left.addSubview(listLabel)
        left.addSubview(clipScroll)
        right.addSubview(editorLabel)
        right.addSubview(promptField)
        right.addSubview(slugField)
        right.addSubview(lutField)
        right.addSubview(continuityField)
        right.addSubview(metaScroll)

        panel.addSubview(heading)
        panel.addSubview(intro)
        panel.addSubview(statusLabel)
        panel.addSubview(topRow)
        panel.addSubview(left)
        panel.addSubview(right)

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            intro.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            intro.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            intro.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            statusLabel.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            topRow.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            topRow.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            left.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 10),
            left.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            left.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
            left.widthAnchor.constraint(equalTo: panel.widthAnchor, multiplier: 0.42),
            right.topAnchor.constraint(equalTo: left.topAnchor),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 10),
            right.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            right.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            listLabel.topAnchor.constraint(equalTo: left.topAnchor, constant: 10),
            listLabel.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            clipScroll.topAnchor.constraint(equalTo: listLabel.bottomAnchor, constant: 6),
            clipScroll.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            clipScroll.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -10),
            clipScroll.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -10),
            editorLabel.topAnchor.constraint(equalTo: right.topAnchor, constant: 10),
            editorLabel.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 10),
            promptField.topAnchor.constraint(equalTo: editorLabel.bottomAnchor, constant: 6),
            promptField.leadingAnchor.constraint(equalTo: editorLabel.leadingAnchor),
            promptField.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -10),
            slugField.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 6),
            slugField.leadingAnchor.constraint(equalTo: promptField.leadingAnchor),
            slugField.trailingAnchor.constraint(equalTo: promptField.trailingAnchor),
            lutField.topAnchor.constraint(equalTo: slugField.bottomAnchor, constant: 6),
            lutField.leadingAnchor.constraint(equalTo: promptField.leadingAnchor),
            lutField.trailingAnchor.constraint(equalTo: promptField.trailingAnchor),
            continuityField.topAnchor.constraint(equalTo: lutField.bottomAnchor, constant: 6),
            continuityField.leadingAnchor.constraint(equalTo: promptField.leadingAnchor),
            continuityField.trailingAnchor.constraint(equalTo: promptField.trailingAnchor),
            metaScroll.topAnchor.constraint(equalTo: continuityField.bottomAnchor, constant: 8),
            metaScroll.leadingAnchor.constraint(equalTo: promptField.leadingAnchor),
            metaScroll.trailingAnchor.constraint(equalTo: promptField.trailingAnchor),
            metaScroll.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -10),
        ])
        reloadFromDisk()
        return panel
    }

    @objc private func scanPressed() {
        statusLabel.stringValue = "Scanning timeline…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = TimelineBridge.scanTimeline()
            DispatchQueue.main.async {
                guard let self else { return }
                if outcome.ok {
                    self.reloadFromDisk()
                    self.statusLabel.stringValue = outcome.message
                    return
                }
                if outcome.needsLuaScan {
                    self.statusLabel.stringValue = "Using Resolve script scan…"
                    self.onScanTimeline?()
                    return
                }
                self.statusLabel.stringValue = outcome.message
            }
        }
    }

    @objc private func refreshPressed() { reloadFromDisk() }

    @objc private func artifactsPressed() {
        _ = TimelineBridge.run(["scan", "--artifacts-only"])
        reloadFromDisk()
    }

    private func reloadFromDisk() {
        guard let scan = TimelineBridge.load() else {
            statusLabel.stringValue = "No scan yet — use Scan Timeline (inside Resolve) or Scan Artifacts"
            clips = []
            rebuildClipList()
            return
        }
        clips = scan.clips
        let proj = scan.projectName ?? ""
        let tl = scan.timelineName ?? ""
        let when = scan.scannedAt ?? ""
        statusLabel.stringValue = "\(proj) · \(tl) · \(clips.count) clip(s) · \(when)"
        rebuildClipList()
        if let first = clips.first {
            selectClip(first.id)
        }
    }

    private func rebuildClipList() {
        clipList.arrangedSubviews.forEach { clipList.removeArrangedSubview($0); $0.removeFromSuperview() }
        for clip in clips {
            let row = TimelineClipRow(clip: clip, selected: selectedIds.contains(clip.id))
            row.target = self
            row.action = #selector(clipRowPressed(_:))
            row.toggle.target = self
            row.toggle.action = #selector(togglePressed(_:))
            clipList.addArrangedSubview(row)
        }
    }

    @objc private func clipRowPressed(_ sender: TimelineClipRow) {
        selectClip(sender.clip.id)
    }

    @objc private func togglePressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
        rebuildClipList()
    }

    private func selectClip(_ id: String) {
        activeClipId = id
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        promptField.stringValue = clip.prompt ?? ""
        slugField.stringValue = clip.slug ?? ""
        lutField.stringValue = clip.lut ?? ""
        continuityField.stringValue = clip.continuity ?? ""
        var lines = [
            "ID · \(clip.id)",
            "TRACK · \(clip.track)",
            "FILE · \(clip.name)",
            "IN · \(clip.timelineIn ?? "") → OUT · \(clip.timelineOut ?? "")",
            "PATH · \(clip.filePath ?? "")",
        ]
        if let add = clip.promptAdd, !add.isEmpty { lines.append("PROMPT_ADD · \(add)") }
        metaView.string = lines.joined(separator: "\n")
    }

    @objc private func savePressed() {
        guard let id = activeClipId else { return }
        let args = [
            "update", "--id", id,
            "--prompt", promptField.stringValue,
            "--slug", slugField.stringValue,
            "--lut", lutField.stringValue,
            "--continuity", continuityField.stringValue,
        ]
        _ = TimelineBridge.run(args)
        reloadFromDisk()
        selectClip(id)
    }

    @objc private func batchSavePressed() {
        var updates: [[String: String]] = []
        let ids = selectedIds.isEmpty ? Set(clips.map(\.id)) : selectedIds
        for clip in clips where ids.contains(clip.id) {
            var item: [String: String] = ["id": clip.id]
            if clip.id == activeClipId {
                item["prompt"] = promptField.stringValue
                item["slug"] = slugField.stringValue
                item["lut"] = lutField.stringValue
                item["continuity"] = continuityField.stringValue
            } else {
                item["prompt"] = clip.prompt ?? ""
                item["slug"] = clip.slug ?? ""
                item["lut"] = clip.lut ?? ""
                item["continuity"] = clip.continuity ?? ""
            }
            updates.append(item)
        }
        let tmp = GrokPaths.projectDir.appendingPathComponent("timeline-batch-save.json")
        try? JSONSerialization.data(withJSONObject: updates).write(to: tmp)
        _ = TimelineBridge.run(["batch-save", tmp.path])
        reloadFromDisk()
    }

    @objc private func batchGenPressed() {
        let ids = Array(selectedIds.isEmpty ? clips.map(\.id) : Array(selectedIds))
        guard !ids.isEmpty else { return }
        _ = TimelineBridge.run(["batch-prepare"] + ids)
        onBatchRegenerate?()
    }

    @objc private func addPromptPressed() {
        guard let id = activeClipId, let clip = clips.first(where: { $0.id == id }) else { return }
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = prompt.isEmpty ? (clip.prompt ?? "") : prompt
        guard !text.isEmpty, let promptView else { return }
        let existing = promptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = "[\(clip.name) @ \(clip.timelineIn ?? "")] \(text)"
        promptView.string = existing.isEmpty ? line : existing + "\n\n" + line
    }
}

final class TimelineClipRow: NSButton {
    let clip: TimelineClip
    let toggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(clip: TimelineClip, selected: Bool) {
        self.clip = clip
        super.init(frame: .zero)
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = GrokTheme.row.cgColor
        layer?.cornerRadius = 2
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 44).isActive = true

        toggle.state = selected ? .on : .off
        toggle.identifier = NSUserInterfaceItemIdentifier(clip.id)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggle)

        let label = "\(clip.name) · V\(clip.track) · \(clip.timelineIn ?? "")"
        title = label
        font = GrokTypography.caption
        contentTintColor = GrokTheme.text
        alignment = .left

        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }
}
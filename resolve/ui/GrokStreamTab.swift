import AppKit
import Foundation

final class StreamTabController: NSObject {
    private let titleField = NSTextField(string: "Grok Resolve Live Session")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let overlayLabel = NSTextField(labelWithString: "")

    func buildView() -> NSView {
        let panel = NSView()
        let heading = NSTextField(labelWithString: "X.com Live Stream")
        UIHelpers.styleSectionHeading(heading)

        let intro = NSTextField(wrappingLabelWithString:
            "Stream your Resolve + Grok workflow to X. Open X Media Studio for RTMP keys, OBS for capture, and use the local browser overlay in OBS Sources."
        )
        UIHelpers.styleBodyText(intro)

        UIHelpers.styleField(titleField)
        titleField.placeholderString = "Stream / workflow title"

        statusLabel.font = GrokTypography.meta
        statusLabel.textColor = GrokTheme.textSecondary
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        overlayLabel.font = GrokTypography.caption
        overlayLabel.textColor = GrokTheme.textDim
        overlayLabel.lineBreakMode = .byTruncatingMiddle
        overlayLabel.translatesAutoresizingMaskIntoConstraints = false

        let studioBtn = UIHelpers.flatButton("Open X Studio", accent: true, target: self, action: #selector(studioPressed))
        let obsBtn = UIHelpers.flatButton("Open OBS", accent: false, target: self, action: #selector(obsPressed))
        let startBtn = UIHelpers.flatButton("Start Workflow", accent: true, target: self, action: #selector(startPressed))
        let stopBtn = UIHelpers.flatButton("Stop", accent: false, target: self, action: #selector(stopPressed))
        let announceBtn = UIHelpers.flatButton("Announce on X", accent: false, target: self, action: #selector(announcePressed))
        let overlayBtn = UIHelpers.flatButton("Open Overlay", accent: false, target: self, action: #selector(overlayPressed))
        let folderBtn = UIHelpers.flatButton("streaming/", accent: false, target: self, action: #selector(folderPressed))

        let row1 = NSStackView(views: [studioBtn, obsBtn, overlayBtn, folderBtn])
        row1.orientation = .horizontal
        row1.spacing = 8
        row1.translatesAutoresizingMaskIntoConstraints = false

        let row2 = NSStackView(views: [startBtn, stopBtn, announceBtn])
        row2.orientation = .horizontal
        row2.spacing = 8
        row2.translatesAutoresizingMaskIntoConstraints = false

        let steps = NSTextField(wrappingLabelWithString:
            "1. Start Workflow → writes overlay.html for OBS Browser Source\n" +
            "2. Open X Studio → copy stream key into OBS → Stream (Custom RTMP)\n" +
            "3. Go Live on X · optional: Announce on X (needs X_BEARER_TOKEN)"
        )
        steps.font = GrokTypography.caption
        steps.textColor = GrokTheme.textSecondary
        steps.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(heading)
        panel.addSubview(intro)
        panel.addSubview(titleField)
        panel.addSubview(row1)
        panel.addSubview(row2)
        panel.addSubview(steps)
        panel.addSubview(statusLabel)
        panel.addSubview(overlayLabel)

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            intro.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            intro.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            intro.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            titleField.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 12),
            titleField.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            titleField.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            row1.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 12),
            row1.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            row2.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 8),
            row2.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            steps.topAnchor.constraint(equalTo: row2.bottomAnchor, constant: 14),
            steps.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            steps.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: steps.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            overlayLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            overlayLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            overlayLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
        ])
        refreshStatus()
        return panel
    }

    private func refreshStatus() {
        let result = StreamBridge.run(["status"])
        if result.ok {
            statusLabel.stringValue = result.output
            if let status = StreamBridge.status() {
                let live = status.live ? "🔴 LIVE" : "Offline"
                overlayLabel.stringValue = "\(live) · overlay: \(status.overlayHtml ?? GrokPaths.streamingDir.path + "/overlay.html")"
            }
        } else {
            statusLabel.stringValue = result.output
        }
    }

    @objc private func studioPressed() {
        _ = StreamBridge.run(["open-studio"])
        refreshStatus()
    }

    @objc private func obsPressed() {
        _ = StreamBridge.run(["open-obs"])
    }

    @objc private func startPressed() {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = StreamBridge.run(["start", title.isEmpty ? "Grok Resolve Session" : title])
        refreshStatus()
    }

    @objc private func stopPressed() {
        _ = StreamBridge.run(["stop"])
        refreshStatus()
    }

    @objc private func announcePressed() {
        _ = StreamBridge.run(["announce"])
        refreshStatus()
    }

    @objc private func overlayPressed() {
        let path = GrokPaths.streamingDir.appendingPathComponent("overlay.html")
        if FileManager.default.fileExists(atPath: path.path) {
            NSWorkspace.shared.open(path)
        } else {
            _ = StreamBridge.run(["start", titleField.stringValue])
            refreshStatus()
            if FileManager.default.fileExists(atPath: path.path) {
                NSWorkspace.shared.open(path)
            }
        }
    }

    @objc private func folderPressed() {
        NSWorkspace.shared.open(GrokPaths.streamingDir)
    }
}
import AppKit
import Foundation

enum WorkflowLogBridge {
    static var binURL: URL { GrokPaths.root.appendingPathComponent("bin/logs") }

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

    static func tail(lines: Int = 250) -> String {
        let result = run(["tail", String(lines)])
        return result.output
    }
}

final class TerminalTabController: NSObject {
    var onStartBridge: (() -> Void)?
    var onOpenTerminal: (() -> Void)?

    private let logView = NSTextView()
    private let logScroll = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let commandField = NSTextField(string: "")
    private var pollTimer: Timer?

    func buildView() -> NSView {
        let panel = NSView()
        let heading = NSTextField(labelWithString: "Workflow Terminal")
        UIHelpers.styleSectionHeading(heading)

        let intro = NSTextField(wrappingLabelWithString:
            "Live view of Grok workflow logs inside Resolve — bridge status, menu actions, and quick commands without leaving the canvas."
        )
        UIHelpers.styleBodyText(intro)

        statusLabel.font = GrokTypography.caption
        statusLabel.textColor = GrokTheme.textSecondary
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        logScroll.hasVerticalScroller = true
        logScroll.autohidesScrollers = false
        UIHelpers.styleScrollView(logScroll)
        logView.isEditable = false
        logView.isSelectable = true
        logView.drawsBackground = true
        logView.backgroundColor = GrokTheme.field
        logView.textColor = GrokTheme.textSecondary
        logView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        logView.textContainerInset = NSSize(width: 8, height: 8)
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = true
        logScroll.documentView = logView
        UIHelpers.configureMetaTextView(logView, in: logScroll)

        UIHelpers.styleField(commandField)
        commandField.placeholderString = "Quick command (status, resolve-check, scan, catalog)"

        let refreshBtn = UIHelpers.flatButton("Refresh", accent: false, target: self, action: #selector(refreshPressed))
        let runBtn = UIHelpers.flatButton("Run", accent: true, target: self, action: #selector(runPressed))
        let bridgeBtn = UIHelpers.flatButton("Start Bridge", accent: false, target: self, action: #selector(bridgePressed))
        let termBtn = UIHelpers.flatButton("Open Terminal", accent: false, target: self, action: #selector(terminalPressed))
        let folderBtn = UIHelpers.flatButton("bridge/", accent: false, target: self, action: #selector(folderPressed))
        let row = NSStackView(views: [refreshBtn, runBtn, bridgeBtn, termBtn, folderBtn])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(heading)
        panel.addSubview(intro)
        panel.addSubview(statusLabel)
        panel.addSubview(logScroll)
        panel.addSubview(commandField)
        panel.addSubview(row)

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            intro.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            intro.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            intro.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            statusLabel.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            logScroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            logScroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            logScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            logScroll.bottomAnchor.constraint(equalTo: commandField.topAnchor, constant: -10),
            commandField.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            commandField.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            commandField.bottomAnchor.constraint(equalTo: row.topAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            row.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
        ])
        refreshLogs()
        return panel
    }

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshLogs()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func refreshPressed() { refreshLogs() }

    private func refreshLogs() {
        let tail = WorkflowLogBridge.tail(lines: 280)
        logView.string = tail
        UIHelpers.scrollMetaToEnd(logView)
        let status = WorkflowLogBridge.run(["status"])
        if status.ok {
            statusLabel.stringValue = status.output
                .components(separatedBy: "\n")
                .prefix(3)
                .joined(separator: " · ")
        }
    }

    @objc private func runPressed() {
        let cmd = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        appendOutput("▶ bin/logs run \(cmd)\n")
        let result = WorkflowLogBridge.run(["run", cmd])
        appendOutput(result.output + "\n")
        if !result.ok {
            appendOutput("(exit error)\n")
        }
        refreshLogs()
    }

    @objc private func bridgePressed() {
        onStartBridge?()
        appendOutput("▶ Start Bridge requested — opening Terminal listener\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refreshLogs() }
    }

    @objc private func terminalPressed() {
        onOpenTerminal?()
    }

    @objc private func folderPressed() {
        NSWorkspace.shared.open(GrokPaths.bridgeDir)
    }

    private func appendOutput(_ text: String) {
        logView.string += text
        logView.scrollToEndOfDocument(nil)
    }
}
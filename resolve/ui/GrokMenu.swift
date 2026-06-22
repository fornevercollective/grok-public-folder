import AppKit
import Foundation
import ObjectiveC

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

enum MenuItems {
    static let all = [
        "Bootstrap",
        "Scan Downloads",
        "Import",
        "Scan + Import",
        "Open Folder",
        "Start Bridge",
        "Generate Video",
    ]
}

final class GrokApp: NSObject, NSApplicationDelegate {
    private var resultLine = "CANCELLED"
    private var didFinish = false
    private var mode = "choose"
    private var promptTitle = "Grok"
    private var promptDefault = ""
    private var alertTitle = "Grok"
    private var alertMessage = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments.dropFirst()
        if let first = args.first {
            mode = first
        }

        switch mode {
        case "choose":
            showChooseMenu()
        case "prompt":
            promptTitle = args.dropFirst().first ?? "Grok"
            promptDefault = args.dropFirst().dropFirst().joined(separator: " ")
            showPrompt()
        case "generate":
            showGenerateForm()
        case "alert":
            alertTitle = args.dropFirst().first ?? "Grok"
            alertMessage = args.dropFirst().dropFirst().joined(separator: " ")
            showAlert()
        default:
            finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        print(resultLine)
        fflush(stdout)
        NSApp.terminate(nil)
    }

    private func makeWindow(width: CGFloat, height: CGFloat, title: String) -> NSWindow {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = NSPoint(
            x: screen.midX - width / 2,
            y: screen.midY - height / 2
        )
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = GrokTheme.window
        window.isReleasedWhenClosed = false
        return window
    }

    private func headerView(title: String, subtitle: String) -> NSView {
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

    private func actionButton(_ title: String, action: Selector) -> NSButton {
        let button = ResolveActionButton(title: title)
        button.target = self
        button.action = action
        return button
    }

    private func showChooseMenu() {
        let window = makeWindow(width: 340, height: 420, title: "Grok")
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = headerView(title: "Grok", subtitle: "Resolve workflow")
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        for item in MenuItems.all {
            let button = actionButton(item, action: #selector(menuChosen(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(item)
            stack.addArrangedSubview(button)
        }

        let footer = NSTextField(labelWithString: "Workspace → Scripts → Grok")
        footer.font = NSFont.systemFont(ofSize: 10)
        footer.textColor = GrokTheme.muted
        footer.alignment = .center
        footer.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(stack)
        root.addSubview(footer)
        window.contentView = root

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
        ])

        present(window)
    }

    @objc private func menuChosen(_ sender: NSButton) {
        resultLine = sender.title
        finish()
    }

    private func showPrompt() {
        let window = makeWindow(width: 420, height: 180, title: promptTitle)
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = headerView(title: promptTitle, subtitle: "Enter value")
        let field = NSTextField(string: promptDefault)
        styleField(field)

        let cancel = flatButton("Cancel", accent: false)
        cancel.action = #selector(cancelPressed)
        let ok = flatButton("OK", accent: true)
        ok.keyEquivalent = "\r"
        ok.action = #selector(promptOK(_:))
        ok.tag = 1

        let buttonRow = NSStackView(views: [cancel, ok])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(field)
        root.addSubview(buttonRow)
        window.contentView = root
        objc_setAssociatedObject(window, "promptField", field, .OBJC_ASSOCIATION_RETAIN)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            field.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            buttonRow.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 14),
            buttonRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
        ])

        present(window)
        window.makeFirstResponder(field)
    }

    @objc private func promptOK(_ sender: NSButton) {
        guard let window = NSApp.keyWindow,
              let field = objc_getAssociatedObject(window, "promptField") as? NSTextField else {
            finish()
            return
        }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            resultLine = "CANCELLED"
        } else {
            resultLine = value
        }
        finish()
    }

    private func showGenerateForm() {
        let window = makeWindow(width: 460, height: 280, title: "Generate Video")
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = headerView(title: "Generate Video", subtitle: "Imagine preset + prompt")
        let slugLabel = fieldLabel("Preset slug")
        let slugField = NSTextField(string: "neo-noir")
        styleField(slugField)
        let promptLabel = fieldLabel("Prompt")
        let promptField = NSTextField(string: "woman in rain on empty street at night")
        styleField(promptField)

        let cancel = flatButton("Cancel", accent: false)
        cancel.action = #selector(cancelPressed)
        let ok = flatButton("Generate", accent: true)
        ok.keyEquivalent = "\r"
        ok.action = #selector(generateOK)

        let buttonRow = NSStackView(views: [cancel, ok])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(slugLabel)
        root.addSubview(slugField)
        root.addSubview(promptLabel)
        root.addSubview(promptField)
        root.addSubview(buttonRow)
        window.contentView = root
        objc_setAssociatedObject(window, "slugField", slugField, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(window, "promptField", promptField, .OBJC_ASSOCIATION_RETAIN)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            slugLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            slugLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            slugField.topAnchor.constraint(equalTo: slugLabel.bottomAnchor, constant: 4),
            slugField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            slugField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            promptLabel.topAnchor.constraint(equalTo: slugField.bottomAnchor, constant: 12),
            promptLabel.leadingAnchor.constraint(equalTo: slugLabel.leadingAnchor),
            promptField.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            promptField.leadingAnchor.constraint(equalTo: slugField.leadingAnchor),
            promptField.trailingAnchor.constraint(equalTo: slugField.trailingAnchor),
            buttonRow.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 16),
            buttonRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
        ])

        present(window)
        window.makeFirstResponder(slugField)
    }

    @objc private func generateOK() {
        guard let window = NSApp.keyWindow,
              let slugField = objc_getAssociatedObject(window, "slugField") as? NSTextField,
              let promptField = objc_getAssociatedObject(window, "promptField") as? NSTextField else {
            finish()
            return
        }
        let slug = slugField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if slug.isEmpty || prompt.isEmpty {
            resultLine = "CANCELLED"
        } else {
            resultLine = "SLUG:\(slug)\nPROMPT:\(prompt)"
        }
        finish()
    }

    private func showAlert() {
        let window = makeWindow(width: 400, height: 200, title: alertTitle)
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = headerView(title: alertTitle, subtitle: "Grok")
        let body = NSTextField(wrappingLabelWithString: alertMessage)
        body.font = NSFont.systemFont(ofSize: 12)
        body.textColor = GrokTheme.text
        body.translatesAutoresizingMaskIntoConstraints = false

        let ok = flatButton("OK", accent: true)
        ok.keyEquivalent = "\r"
        ok.action = #selector(alertOK)

        root.addSubview(header)
        root.addSubview(body)
        root.addSubview(ok)
        window.contentView = root

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            ok.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 14),
            ok.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
        ])

        present(window)
    }

    @objc private func alertOK() {
        resultLine = "OK"
        finish()
    }

    @objc private func cancelPressed() {
        resultLine = "CANCELLED"
        finish()
    }

    private func present(_ window: NSWindow) {
        window.delegate = WindowCloser(delegate: self)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowClosed() {
        guard !didFinish else { return }
        resultLine = "CANCELLED"
        finish()
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = GrokTheme.muted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func styleField(_ field: NSTextField) {
        field.font = NSFont.systemFont(ofSize: 12)
        field.textColor = GrokTheme.text
        field.backgroundColor = GrokTheme.field
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private func flatButton(_ title: String, accent: Bool) -> NSButton {
        let button = NSButton(title: title, target: self, action: nil)
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
}

final class WindowCloser: NSObject, NSWindowDelegate {
    private weak var owner: GrokApp?
    init(delegate: GrokApp) { owner = delegate }
    func windowWillClose(_ notification: Notification) {
        owner?.windowClosed()
    }
}

final class ResolveActionButton: NSButton {
    private let accentBar = NSView()

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = .inline
        self.isBordered = false
        self.alignment = .left
        self.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        self.contentTintColor = GrokTheme.text
        self.wantsLayer = true
        self.layer?.backgroundColor = GrokTheme.row.cgColor
        self.layer?.cornerRadius = 3
        self.translatesAutoresizingMaskIntoConstraints = false
        self.heightAnchor.constraint(equalToConstant: 34).isActive = true

        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = GrokTheme.accent.cgColor
        accentBar.isHidden = true
        addSubview(accentBar)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        accentBar.frame = NSRect(x: 0, y: 0, width: 3, height: bounds.height)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = GrokTheme.rowHover.cgColor
        accentBar.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = GrokTheme.row.cgColor
        accentBar.isHidden = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let grok = GrokApp()
app.delegate = grok
app.run()
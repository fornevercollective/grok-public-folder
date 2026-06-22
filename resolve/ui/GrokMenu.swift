import AppKit
import Foundation
import ObjectiveC

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
    private var generateController: GeneratePanelController?
    private var windowClosers: [WindowCloser] = []

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
            ensureCatalog()
            showGenerateForm()
        case "alert":
            alertTitle = args.dropFirst().first ?? "Grok"
            alertMessage = args.dropFirst().dropFirst().joined(separator: " ")
            showAlert()
        default:
            finish()
        }
    }

    private func ensureCatalog() {
        let catalogURL = GrokPaths.catalogURL
        let builder = GrokPaths.root.appendingPathComponent("grok_generate_catalog.py")
        if !FileManager.default.fileExists(atPath: catalogURL.path)
            || (try? builder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .map({ mod in
                    (try? catalogURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                        .map { $0 < mod } ?? true
                }) ?? true {
            let python = "/usr/bin/env"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: python)
            task.arguments = ["python3", builder.path]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
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
        let origin = NSPoint(x: screen.midX - width / 2, y: screen.midY - height / 2)
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

        let header = UIHelpers.headerView(title: "Grok", subtitle: "Resolve workflow")
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

        let header = UIHelpers.headerView(title: promptTitle, subtitle: "Enter value")
        let field = NSTextField(string: promptDefault)
        UIHelpers.styleField(field)

        let cancel = UIHelpers.flatButton("Cancel", accent: false, target: self, action: #selector(cancelPressed))
        let ok = UIHelpers.flatButton("OK", accent: true, target: self, action: #selector(promptOK))
        ok.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [cancel, ok])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
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

    @objc private func promptOK() {
        guard let window = NSApp.keyWindow,
              let field = objc_getAssociatedObject(window, "promptField") as? NSTextField else {
            finish()
            return
        }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        resultLine = value.isEmpty ? "CANCELLED" : value
        finish()
    }

    private func showGenerateForm() {
        let catalog = CatalogStore.load()
        let controller = GeneratePanelController(catalog: catalog)
        generateController = controller
        controller.onComplete = { [weak self] output in
            self?.resultLine = output
            self?.finish()
        }
        controller.show()
    }

    private func showAlert() {
        let window = makeWindow(width: 400, height: 200, title: alertTitle)
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = UIHelpers.headerView(title: alertTitle, subtitle: "Grok")
        let body = NSTextField(wrappingLabelWithString: alertMessage)
        body.font = NSFont.systemFont(ofSize: 12)
        body.textColor = GrokTheme.text
        body.translatesAutoresizingMaskIntoConstraints = false

        let ok = UIHelpers.flatButton("OK", accent: true, target: self, action: #selector(alertOK))
        ok.keyEquivalent = "\r"

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
        let closer = WindowCloser(delegate: self)
        windowClosers.append(closer)
        window.delegate = closer
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowClosed() {
        guard !didFinish else { return }
        resultLine = "CANCELLED"
        finish()
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


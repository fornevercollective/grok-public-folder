import AppKit
import Foundation

final class GeneratePanelController: NSObject, NSWindowDelegate {
    var onComplete: ((String) -> Void)?

    private let catalog: GenerateCatalog
    private var window: NSWindow?
    private var finished = false
    private var selectedPreset: PresetEntry?

    private let heroImage = NSImageView()
    private let presetTitle = NSTextField(labelWithString: "")
    private let presetMeta = NSTextField(wrappingLabelWithString: "")
    private let promptPreview = NSTextField(wrappingLabelWithString: "")
    private let thumbStrip = NSStackView()

    private let groupPopup = NSPopUpButton()
    private let presetPopup = NSPopUpButton()
    private let promptView = NSTextView()
    private let durationPopup = NSPopUpButton()
    private let resolutionPopup = NSPopUpButton()
    private let aspectPopup = NSPopUpButton()
    private let lutPopup = NSPopUpButton()
    private let promptAddField = NSTextField(string: "")
    private let continuityField = NSTextField(string: "")

    init(catalog: GenerateCatalog) {
        self.catalog = catalog
        super.init()
    }

    func show() {
        let window = makeWindow()
        self.window = window
        window.delegate = self
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
        let size = NSSize(width: 900, height: 620)
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "\(GrokBrand.appName) · Generate Video"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 820, height: 560)
        UIHelpers.applyResolveAppearance(to: window)

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let header = UIHelpers.headerView(title: "Generate Video", subtitle: GrokBrand.source)

        let leftPanel = buildLeftPanel()
        let rightPanel = buildRightPanel()
        let split = NSStackView(views: [leftPanel, rightPanel])
        split.orientation = .horizontal
        split.spacing = 12
        split.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 12, right: 12)
        split.translatesAutoresizingMaskIntoConstraints = false
        leftPanel.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let cancel = UIHelpers.flatButton("Cancel", accent: false, target: self, action: #selector(cancelPressed))
        let generate = UIHelpers.flatButton("Generate", accent: true, target: self, action: #selector(generatePressed))
        generate.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [cancel, generate])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let trust = UIHelpers.trustFooter()

        root.addSubview(header)
        root.addSubview(split)
        root.addSubview(buttonRow)
        root.addSubview(trust)
        window.contentView = root

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            trust.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            trust.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            trust.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: trust.topAnchor, constant: -10),
            split.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -10),
        ])

        populateControls()
        return window
    }

    private func buildLeftPanel() -> NSView {
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        panel.layer?.backgroundColor = GrokTheme.panel.cgColor
        panel.layer?.cornerRadius = 4
        panel.layer?.borderColor = GrokTheme.border.cgColor
        panel.layer?.borderWidth = 1

        heroImage.translatesAutoresizingMaskIntoConstraints = false
        heroImage.imageScaling = .scaleProportionallyUpOrDown
        heroImage.wantsLayer = true
        heroImage.layer?.backgroundColor = GrokTheme.field.cgColor
        heroImage.layer?.cornerRadius = 3

        presetTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        presetTitle.textColor = GrokTheme.text
        presetTitle.translatesAutoresizingMaskIntoConstraints = false

        presetMeta.font = GrokTypography.caption
        presetMeta.textColor = GrokTheme.textSecondary
        presetMeta.maximumNumberOfLines = 2
        presetMeta.translatesAutoresizingMaskIntoConstraints = false

        let previewLabel = UIHelpers.fieldLabel("Preset prompt")
        promptPreview.font = GrokTypography.caption
        promptPreview.textColor = GrokTheme.textSecondary
        promptPreview.maximumNumberOfLines = 0
        promptPreview.translatesAutoresizingMaskIntoConstraints = false

        let previewScroll = NSScrollView()
        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.hasVerticalScroller = true
        previewScroll.drawsBackground = false
        previewScroll.documentView = promptPreview
        promptPreview.leadingAnchor.constraint(equalTo: previewScroll.contentView.leadingAnchor).isActive = true
        promptPreview.trailingAnchor.constraint(equalTo: previewScroll.contentView.trailingAnchor).isActive = true
        promptPreview.topAnchor.constraint(equalTo: previewScroll.contentView.topAnchor).isActive = true
        promptPreview.widthAnchor.constraint(equalTo: previewScroll.widthAnchor, constant: -16).isActive = true

        thumbStrip.orientation = .horizontal
        thumbStrip.spacing = 6
        thumbStrip.translatesAutoresizingMaskIntoConstraints = false

        let stripScroll = NSScrollView()
        stripScroll.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.hasHorizontalScroller = true
        stripScroll.drawsBackground = false
        stripScroll.documentView = thumbStrip
        thumbStrip.topAnchor.constraint(equalTo: stripScroll.contentView.topAnchor).isActive = true
        thumbStrip.leadingAnchor.constraint(equalTo: stripScroll.contentView.leadingAnchor).isActive = true
        thumbStrip.heightAnchor.constraint(equalToConstant: 54).isActive = true

        panel.addSubview(heroImage)
        panel.addSubview(presetTitle)
        panel.addSubview(presetMeta)
        panel.addSubview(previewLabel)
        panel.addSubview(previewScroll)
        panel.addSubview(stripScroll)

        NSLayoutConstraint.activate([
            heroImage.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            heroImage.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            heroImage.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            heroImage.heightAnchor.constraint(equalToConstant: 156),
            presetTitle.topAnchor.constraint(equalTo: heroImage.bottomAnchor, constant: 8),
            presetTitle.leadingAnchor.constraint(equalTo: heroImage.leadingAnchor),
            presetTitle.trailingAnchor.constraint(equalTo: heroImage.trailingAnchor),
            presetMeta.topAnchor.constraint(equalTo: presetTitle.bottomAnchor, constant: 2),
            presetMeta.leadingAnchor.constraint(equalTo: presetTitle.leadingAnchor),
            presetMeta.trailingAnchor.constraint(equalTo: presetTitle.trailingAnchor),
            previewLabel.topAnchor.constraint(equalTo: presetMeta.bottomAnchor, constant: 8),
            previewLabel.leadingAnchor.constraint(equalTo: presetTitle.leadingAnchor),
            previewScroll.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 4),
            previewScroll.leadingAnchor.constraint(equalTo: presetTitle.leadingAnchor),
            previewScroll.trailingAnchor.constraint(equalTo: presetTitle.trailingAnchor),
            previewScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            stripScroll.topAnchor.constraint(equalTo: previewScroll.bottomAnchor, constant: 8),
            stripScroll.leadingAnchor.constraint(equalTo: presetTitle.leadingAnchor),
            stripScroll.trailingAnchor.constraint(equalTo: presetTitle.trailingAnchor),
            stripScroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
            stripScroll.heightAnchor.constraint(equalToConstant: 58),
        ])
        return panel
    }

    private func buildRightPanel() -> NSView {
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let genreLabel = UIHelpers.fieldLabel("Genre")
        let presetLabel = UIHelpers.fieldLabel("Preset")
        let sceneLabel = UIHelpers.fieldLabel("Scene prompt")
        UIHelpers.stylePopup(groupPopup)
        UIHelpers.stylePopup(presetPopup)
        groupPopup.target = self
        groupPopup.action = #selector(groupChanged)
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)

        let promptScroll = NSScrollView()
        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.hasVerticalScroller = true
        promptScroll.borderType = .bezelBorder
        promptView.font = NSFont.systemFont(ofSize: 12)
        promptView.textColor = GrokTheme.text
        promptView.backgroundColor = GrokTheme.field
        promptView.isRichText = false
        promptView.textContainerInset = NSSize(width: 6, height: 6)
        promptScroll.documentView = promptView

        let outputLabel = UIHelpers.fieldLabel("Output")
        for popup in [durationPopup, resolutionPopup, aspectPopup, lutPopup] {
            UIHelpers.stylePopup(popup)
        }
        lutPopup.target = self
        lutPopup.action = #selector(lutChanged)

        let outputRow = NSGridView(views: [
            [UIHelpers.fieldLabel("Duration"), durationPopup],
            [UIHelpers.fieldLabel("Resolution"), resolutionPopup],
            [UIHelpers.fieldLabel("Aspect"), aspectPopup],
            [UIHelpers.fieldLabel("LUT overlay"), lutPopup],
        ])
        outputRow.translatesAutoresizingMaskIntoConstraints = false
        outputRow.column(at: 0).xPlacement = .leading
        outputRow.rowSpacing = 8
        outputRow.columnSpacing = 10
        for row in 0..<outputRow.numberOfRows {
            if let label = outputRow.cell(atColumnIndex: 0, rowIndex: row).contentView as? NSTextField {
                label.widthAnchor.constraint(equalToConstant: 88).isActive = true
            }
            if let popup = outputRow.cell(atColumnIndex: 1, rowIndex: row).contentView as? NSPopUpButton {
                popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
            }
        }

        let lutLabel = UIHelpers.fieldLabel("LUT notes")
        UIHelpers.styleField(promptAddField)
        let continuityLabel = UIHelpers.fieldLabel("Continuity")
        UIHelpers.styleField(continuityField)

        panel.addSubview(genreLabel)
        panel.addSubview(groupPopup)
        panel.addSubview(presetLabel)
        panel.addSubview(presetPopup)
        panel.addSubview(sceneLabel)
        panel.addSubview(promptScroll)
        panel.addSubview(outputLabel)
        panel.addSubview(outputRow)
        panel.addSubview(lutLabel)
        panel.addSubview(promptAddField)
        panel.addSubview(continuityLabel)
        panel.addSubview(continuityField)

        NSLayoutConstraint.activate([
            genreLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 4),
            genreLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            groupPopup.topAnchor.constraint(equalTo: genreLabel.bottomAnchor, constant: 4),
            groupPopup.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            groupPopup.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            presetLabel.topAnchor.constraint(equalTo: groupPopup.bottomAnchor, constant: 10),
            presetLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            presetPopup.topAnchor.constraint(equalTo: presetLabel.bottomAnchor, constant: 4),
            presetPopup.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            presetPopup.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            sceneLabel.topAnchor.constraint(equalTo: presetPopup.bottomAnchor, constant: 10),
            sceneLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            promptScroll.topAnchor.constraint(equalTo: sceneLabel.bottomAnchor, constant: 4),
            promptScroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            promptScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            promptScroll.heightAnchor.constraint(equalToConstant: 88),
            outputLabel.topAnchor.constraint(equalTo: promptScroll.bottomAnchor, constant: 10),
            outputLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            outputRow.topAnchor.constraint(equalTo: outputLabel.bottomAnchor, constant: 6),
            outputRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            outputRow.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor),
            lutLabel.topAnchor.constraint(equalTo: outputRow.bottomAnchor, constant: 10),
            lutLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            promptAddField.topAnchor.constraint(equalTo: lutLabel.bottomAnchor, constant: 4),
            promptAddField.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            promptAddField.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            continuityLabel.topAnchor.constraint(equalTo: promptAddField.bottomAnchor, constant: 8),
            continuityLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            continuityField.topAnchor.constraint(equalTo: continuityLabel.bottomAnchor, constant: 4),
            continuityField.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            continuityField.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
        ])
        return panel
    }

    private func populateControls() {
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
        for value in catalog.resolutions {
            resolutionPopup.addItem(withTitle: value)
        }

        aspectPopup.removeAllItems()
        for value in catalog.aspectRatios {
            aspectPopup.addItem(withTitle: value)
        }

        lutPopup.removeAllItems()
        lutPopup.addItem(withTitle: "None")
        lutPopup.lastItem?.representedObject = ""
        for preset in catalog.lutPresets {
            lutPopup.addItem(withTitle: preset.display)
            lutPopup.lastItem?.representedObject = preset.slug
        }

        let defaults = catalog.defaults
        promptView.string = defaults.prompt
        promptAddField.stringValue = defaults.promptAdd
        continuityField.stringValue = defaults.continuityNotes
        selectPopupItem(groupPopup, matching: defaults.slug)
        selectPopupTitle(durationPopup, title: "\(defaults.durationSec)s")
        selectPopupTitle(resolutionPopup, title: defaults.resolution)
        selectPopupTitle(aspectPopup, title: defaults.aspectRatio)
        if !defaults.lutSlug.isEmpty {
            selectPopupItem(lutPopup, matching: defaults.lutSlug)
        }
        reloadPresets(selectSlug: defaults.slug)
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
        let slug = selectSlug ?? group.presets.first?.slug
        if let slug {
            selectPopupItem(presetPopup, matching: slug)
        }
        presetChanged()
    }

    @objc private func groupChanged() {
        reloadPresets(selectSlug: nil)
    }

    @objc private func presetChanged() {
        guard let group = currentGroup() else { return }
        let index = presetPopup.indexOfSelectedItem
        guard index >= 0, index < group.presets.count else { return }
        let preset = group.presets[index]
        selectedPreset = preset
        presetTitle.stringValue = preset.display
        let tags = preset.tags.joined(separator: " · ")
        presetMeta.stringValue = [tags, preset.bestFor].filter { !$0.isEmpty }.joined(separator: "\n")
        promptPreview.stringValue = preset.promptPreview
        UIHelpers.loadThumbnail(for: preset, into: heroImage)
        rebuildThumbStrip(group: group, selected: preset)
    }

    @objc private func lutChanged() {
        guard let slug = lutPopup.selectedItem?.representedObject as? String, !slug.isEmpty else { return }
        if let lut = catalog.lutPresets.first(where: { $0.slug == slug }) {
            if promptAddField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                promptAddField.stringValue = "Apply \(lut.display) color grade"
            }
        }
    }

    private func rebuildThumbStrip(group: PresetGroup, selected: PresetEntry) {
        thumbStrip.arrangedSubviews.forEach { thumbStrip.removeArrangedSubview($0); $0.removeFromSuperview() }
        for preset in group.presets.prefix(18) {
            let button = ThumbButton(preset: preset)
            button.target = self
            button.action = #selector(thumbPressed(_:))
            button.isSelected = preset.slug == selected.slug
            thumbStrip.addArrangedSubview(button)
        }
    }

    @objc private func thumbPressed(_ sender: ThumbButton) {
        selectPopupItem(presetPopup, matching: sender.preset.slug)
        presetChanged()
        for case let button as ThumbButton in thumbStrip.arrangedSubviews {
            button.isSelected = button.preset.slug == sender.preset.slug
        }
    }

    @objc private func cancelPressed() {
        complete("CANCELLED")
        window?.close()
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

        let lines = [
            "SLUG:\(preset.slug)",
            "PROMPT:\(prompt)",
            "DURATION:\(duration)",
            "RESOLUTION:\(resolution)",
            "ASPECT:\(aspect)",
            "LUT:\(lut)",
            "PROMPT_ADD:\(promptAdd)",
            "CONTINUITY:\(continuity)",
        ]
        complete(lines.joined(separator: "\n"))
        window?.close()
    }

    private func selectPopupItem(_ popup: NSPopUpButton, matching slug: String) {
        for index in 0..<popup.numberOfItems {
            if let value = popup.item(at: index)?.representedObject as? String, value == slug {
                popup.selectItem(at: index)
                return
            }
        }
        for group in catalog.groups {
            guard group.presets.contains(where: { $0.slug == slug }) else { continue }
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

final class ThumbButton: NSButton {
    let preset: PresetEntry
    var isSelected = false {
        didSet { updateBorder() }
    }

    init(preset: PresetEntry) {
        self.preset = preset
        super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 48))
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 3
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        image = UIHelpers.placeholderImage(for: preset)
        widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightAnchor.constraint(equalToConstant: 48).isActive = true
        UIHelpers.thumbnailImage(for: preset) { [weak self] loaded in
            self?.image = loaded
        }
        updateBorder()
    }

    required init?(coder: NSCoder) { nil }

    private func updateBorder() {
        layer?.borderWidth = isSelected ? 2 : 1
        layer?.borderColor = (isSelected ? GrokTheme.accent : GrokTheme.border).cgColor
    }
}
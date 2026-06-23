import AppKit
import Foundation

final class ImdbTabController: NSObject {
    weak var promptView: NSTextView?
    var onSwitchToCanvas: (() -> Void)?

    private let titleField = NSTextField(string: "")
    private let feelField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let resultsStack = NSStackView()
    private let resultsScroll = NSScrollView()
    private let posterView = NSImageView()
    private let detailView = UIHelpers.metaTextView()
    private let detailScroll = NSScrollView()
    private var selectedId: Int?
    private var results: [MovieSummary] = []

    func buildView() -> NSView {
        let panel = NSView()
        let heading = NSTextField(labelWithString: "IMDb / Movie Knowledge")
        UIHelpers.styleSectionHeading(heading)

        let intro = NSTextField(wrappingLabelWithString:
            "Search by title or creative feel. Pull posters, plot, credits, trivia, trailers, and like-minded films into your Grok prompt."
        )
        UIHelpers.styleBodyText(intro)

        statusLabel.font = GrokTypography.caption
        statusLabel.textColor = GrokTheme.textDim
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        refreshStatus()

        UIHelpers.styleField(titleField)
        titleField.placeholderString = "Search title…"
        UIHelpers.styleField(feelField)
        feelField.placeholderString = "Or mood / feel (neo-noir rain, cozy 90s romance…)"

        let searchBtn = UIHelpers.flatButton("Search Title", accent: true, target: self, action: #selector(searchPressed))
        let feelBtn = UIHelpers.flatButton("Search Feel", accent: false, target: self, action: #selector(feelPressed))
        let searchRow = NSStackView(views: [searchBtn, feelBtn])
        searchRow.orientation = .horizontal
        searchRow.spacing = 8
        searchRow.translatesAutoresizingMaskIntoConstraints = false

        resultsStack.orientation = .vertical
        resultsStack.spacing = 4
        resultsStack.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.hasVerticalScroller = true
        UIHelpers.styleScrollView(resultsScroll)
        resultsScroll.documentView = resultsStack
        resultsStack.topAnchor.constraint(equalTo: resultsScroll.contentView.topAnchor).isActive = true
        resultsStack.leadingAnchor.constraint(equalTo: resultsScroll.contentView.leadingAnchor).isActive = true
        resultsStack.widthAnchor.constraint(equalTo: resultsScroll.contentView.widthAnchor).isActive = true

        posterView.imageScaling = .scaleProportionallyUpOrDown
        posterView.wantsLayer = true
        posterView.layer?.backgroundColor = GrokTheme.field.cgColor
        posterView.translatesAutoresizingMaskIntoConstraints = false

        detailScroll.hasVerticalScroller = true
        UIHelpers.styleScrollView(detailScroll)
        detailScroll.documentView = detailView
        detailView.translatesAutoresizingMaskIntoConstraints = false
        detailView.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor).isActive = true

        let addPlot = UIHelpers.flatButton("Add to Prompt", accent: true, target: self, action: #selector(addPromptPressed))
        let addSimilar = UIHelpers.flatButton("Add Similar Films", accent: false, target: self, action: #selector(addSimilarPressed))
        let trailerBtn = UIHelpers.flatButton("Open Trailer", accent: false, target: self, action: #selector(trailerPressed))
        let imdbBtn = UIHelpers.flatButton("Open IMDb", accent: false, target: self, action: #selector(imdbPressed))
        let actionRow = NSStackView(views: [addPlot, addSimilar, trailerBtn, imdbBtn])
        actionRow.orientation = .horizontal
        actionRow.spacing = 6
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        let left = UIHelpers.panelShell()
        let right = UIHelpers.panelShell()
        let resultsLabel = UIHelpers.fieldLabel("Results")
        let detailLabel = UIHelpers.fieldLabel("Detail")
        left.addSubview(resultsLabel)
        left.addSubview(resultsScroll)
        right.addSubview(detailLabel)
        right.addSubview(posterView)
        right.addSubview(detailScroll)
        right.addSubview(actionRow)

        panel.addSubview(heading)
        panel.addSubview(intro)
        panel.addSubview(statusLabel)
        panel.addSubview(titleField)
        panel.addSubview(feelField)
        panel.addSubview(searchRow)
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
            titleField.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            titleField.trailingAnchor.constraint(equalTo: panel.centerXAnchor, constant: -6),
            feelField.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            feelField.leadingAnchor.constraint(equalTo: panel.centerXAnchor, constant: 6),
            feelField.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            searchRow.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 8),
            searchRow.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            left.topAnchor.constraint(equalTo: searchRow.bottomAnchor, constant: 10),
            left.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            left.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
            left.widthAnchor.constraint(equalTo: panel.widthAnchor, multiplier: 0.38),
            right.topAnchor.constraint(equalTo: left.topAnchor),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 10),
            right.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            right.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            resultsLabel.topAnchor.constraint(equalTo: left.topAnchor, constant: 10),
            resultsLabel.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            resultsScroll.topAnchor.constraint(equalTo: resultsLabel.bottomAnchor, constant: 6),
            resultsScroll.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            resultsScroll.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -10),
            resultsScroll.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -10),
            detailLabel.topAnchor.constraint(equalTo: right.topAnchor, constant: 10),
            detailLabel.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 10),
            posterView.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 6),
            posterView.leadingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
            posterView.widthAnchor.constraint(equalToConstant: 100),
            posterView.heightAnchor.constraint(equalToConstant: 150),
            detailScroll.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 6),
            detailScroll.leadingAnchor.constraint(equalTo: posterView.trailingAnchor, constant: 8),
            detailScroll.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -10),
            detailScroll.heightAnchor.constraint(equalToConstant: 150),
            actionRow.topAnchor.constraint(equalTo: posterView.bottomAnchor, constant: 8),
            actionRow.leadingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
            actionRow.bottomAnchor.constraint(lessThanOrEqualTo: right.bottomAnchor, constant: -10),
        ])
        return panel
    }

    private func refreshStatus() {
        if let status = MovieBridge.status() {
            let tmdb = status.tmdbConfigured ? "TMDB ✓" : "TMDB ✗ (set TMDB_API_KEY)"
            let xai = status.xaiConfigured ? "xAI ✓" : "xAI optional for feel/trivia"
            statusLabel.stringValue = "\(tmdb) · \(xai)"
        }
    }

    @objc private func searchPressed() {
        let q = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        results = MovieBridge.search(title: q)
        reloadResults()
    }

    @objc private func feelPressed() {
        let q = feelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        results = MovieBridge.feel(q)
        reloadResults()
    }

    private func reloadResults() {
        resultsStack.arrangedSubviews.forEach { resultsStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for movie in results {
            let row = MovieResultRow(movie: movie)
            row.target = self
            row.action = #selector(resultSelected(_:))
            resultsStack.addArrangedSubview(row)
        }
        if let first = results.first {
            showDetail(first.id)
        }
    }

    @objc private func resultSelected(_ sender: MovieResultRow) {
        showDetail(sender.movie.id)
    }

    private func showDetail(_ id: Int) {
        selectedId = id
        guard let detail = MovieBridge.detail(id) else {
            detailView.string = "Could not load detail — check TMDB_API_KEY"
            return
        }
        MovieBridge.loadPoster(detail: detail, into: posterView)
        var lines: [String] = [
            "\(detail.title) (\(detail.year))",
            detail.tagline ?? "",
            "",
            "PLOT",
            detail.plot ?? "",
            "",
            "GENRES · \((detail.genres ?? []).joined(separator: ", "))",
            "DIRECTORS · \((detail.directors ?? []).joined(separator: ", "))",
            "CAST · \((detail.cast ?? []).prefix(5).joined(separator: "; "))",
            "",
            "TRIVIA",
        ]
        lines.append(contentsOf: detail.trivia ?? [])
        lines.append("")
        lines.append("LIKE-MINDED")
        for sim in detail.similar ?? [] {
            lines.append("· \(sim.title) (\(sim.year))")
        }
        detailView.string = lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    @objc private func addPromptPressed() {
        guard let id = selectedId, let detail = MovieBridge.detail(id),
              let snippet = detail.promptSnippet, !snippet.isEmpty else { return }
        appendPrompt(snippet)
    }

    @objc private func addSimilarPressed() {
        guard let id = selectedId else { return }
        let text = MovieBridge.similarPrompt(id)
        guard !text.isEmpty else { return }
        appendPrompt(text)
    }

    private func appendPrompt(_ text: String) {
        guard let promptView else { return }
        let existing = promptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        promptView.string = existing.isEmpty ? text : existing + "\n\n" + text
        onSwitchToCanvas?()
    }

    @objc private func trailerPressed() {
        guard let id = selectedId, let detail = MovieBridge.detail(id),
              let url = detail.trailerUrl, let nsurl = URL(string: url) else { return }
        NSWorkspace.shared.open(nsurl)
    }

    @objc private func imdbPressed() {
        guard let id = selectedId, let detail = MovieBridge.detail(id) else { return }
        if let url = detail.imdbUrl, !url.isEmpty, let nsurl = URL(string: url) {
            NSWorkspace.shared.open(nsurl)
        }
    }
}

final class MovieResultRow: NSButton {
    let movie: MovieSummary
    private let thumb = NSImageView()

    init(movie: MovieSummary) {
        self.movie = movie
        super.init(frame: .zero)
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = GrokTheme.row.cgColor
        layer?.cornerRadius = 2
        layer?.borderColor = GrokTheme.borderSubtle.cgColor
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 56).isActive = true

        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumb)
        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            thumb.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 36),
            thumb.heightAnchor.constraint(equalToConstant: 52),
        ])
        MovieBridge.loadPoster(for: movie, into: thumb)
        let label = "\(movie.title) (\(movie.year))"
        let sub = movie.overview ?? ""
        title = label + (sub.isEmpty ? "" : " — " + sub)
        font = GrokTypography.caption
        contentTintColor = GrokTheme.text
        alignment = .left
        imagePosition = .noImage
    }

    required init?(coder: NSCoder) { nil }
}
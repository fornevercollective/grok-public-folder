import AppKit
import Foundation

struct MovieSummary: Codable, Identifiable {
    let id: Int
    let title: String
    let year: String
    let overview: String?
    let voteAverage: Double?
    let posterUrl: String?
    let imdbId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year, overview
        case voteAverage = "vote_average"
        case posterUrl = "poster_url"
        case imdbId = "imdb_id"
    }
}

struct MovieSimilar: Codable, Identifiable {
    let id: Int
    let title: String
    let year: String
    let posterUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year
        case posterUrl = "poster_url"
    }
}

struct MovieDetail: Codable {
    let id: Int
    let title: String
    let year: String
    let imdbId: String?
    let imdbUrl: String?
    let plot: String?
    let tagline: String?
    let genres: [String]?
    let runtime: Int?
    let directors: [String]?
    let writers: [String]?
    let cast: [String]?
    let trivia: [String]?
    let trailerYoutubeKey: String?
    let trailerUrl: String?
    let posterUrl: String?
    let posterLocal: String?
    let similar: [MovieSimilar]?
    let keywords: [String]?
    let promptSnippet: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year, plot, tagline, genres, runtime, directors, writers, cast, trivia, similar, keywords
        case imdbId = "imdb_id"
        case imdbUrl = "imdb_url"
        case trailerYoutubeKey = "trailer_youtube_key"
        case trailerUrl = "trailer_url"
        case posterUrl = "poster_url"
        case posterLocal = "poster_local"
        case promptSnippet = "prompt_snippet"
    }
}

struct MovieSearchResponse: Codable {
    let ok: Bool?
    let error: String?
    let results: [MovieSummary]
}

struct MovieStatusResponse: Codable {
    let tmdbConfigured: Bool
    let xaiConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case tmdbConfigured = "tmdb_configured"
        case xaiConfigured = "xai_configured"
    }
}

enum MovieBridge {
    static var binURL: URL { GrokPaths.root.appendingPathComponent("bin/imdb") }

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

    static func status() -> MovieStatusResponse? {
        let result = run(["status"])
        guard result.ok, let data = result.output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MovieStatusResponse.self, from: data)
    }

    static func search(title: String) -> (results: [MovieSummary], error: String?) {
        parseSearch(run(["search", title]))
    }

    static func feel(_ mood: String) -> (results: [MovieSummary], error: String?) {
        parseSearch(run(["feel", mood]))
    }

    private static func parseSearch(_ result: (ok: Bool, output: String)) -> (results: [MovieSummary], error: String?) {
        guard let data = result.output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(MovieSearchResponse.self, from: data) else {
            return ([], result.output.isEmpty ? "IMDb search failed" : result.output)
        }
        if payload.ok == false {
            return ([], payload.error ?? "IMDb search failed")
        }
        if !result.ok, let err = payload.error {
            return ([], err)
        }
        return (payload.results, nil)
    }

    static func detail(_ id: Int) -> MovieDetail? {
        let result = run(["detail", String(id)])
        guard result.ok, let data = result.output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MovieDetail.self, from: data)
    }

    static func similarPrompt(_ id: Int) -> String {
        let result = run(["similar-prompt", String(id)])
        return result.ok ? result.output : ""
    }

    static func loadPoster(for movie: MovieSummary, into imageView: NSImageView) {
        imageView.image = placeholderPoster(title: movie.title)
        guard let urlString = movie.posterUrl, let url = URL(string: urlString) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { imageView.image = image }
        }
    }

    static func loadPoster(detail: MovieDetail, into imageView: NSImageView) {
        if let local = detail.posterLocal, !local.isEmpty, let image = NSImage(contentsOfFile: local) {
            imageView.image = image
            return
        }
        if let urlString = detail.posterUrl, let url = URL(string: urlString),
           let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
            imageView.image = image
            return
        }
        imageView.image = placeholderPoster(title: detail.title)
    }

    static func placeholderPoster(title: String) -> NSImage {
        let size = NSSize(width: 120, height: 180)
        let image = NSImage(size: size)
        image.lockFocus()
        GrokTheme.fieldInset.setFill()
        NSRect(origin: .zero, size: size).fill()
        let label = title as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: GrokTypography.caption,
            .foregroundColor: GrokTheme.textSecondary,
        ]
        let textSize = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(x: max(4, (size.width - textSize.width) / 2), y: (size.height - textSize.height) / 2),
            withAttributes: attrs
        )
        image.unlockFocus()
        return image
    }
}

struct StreamStatusResponse: Codable {
    let live: Bool
    let overlayHtml: String?
    let xBearerConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case live
        case overlayHtml = "overlay_html"
        case xBearerConfigured = "x_bearer_configured"
    }
}

enum StreamBridge {
    static var binURL: URL { GrokPaths.root.appendingPathComponent("bin/stream") }

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

    static func status() -> StreamStatusResponse? {
        let result = run(["status"])
        guard result.ok, let data = result.output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StreamStatusResponse.self, from: data)
    }
}
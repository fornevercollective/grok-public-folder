import AppKit
import Foundation

struct MonitorStatusResponse: Codable {
    let ok: Bool?
    let clock: MonitorClock?
    let drift: MonitorDrift?
    let network: MonitorNetwork?
    let tokens: MonitorTokens?
}

struct MonitorClock: Codable {
    let unix: Double?
    let unixInt: Int?

    enum CodingKeys: String, CodingKey {
        case unix
        case unixInt = "unix_int"
    }
}

struct MonitorDrift: Codable {
    let ok: Bool?
    let driftMs: Double?
    let driftLabel: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case ok, status
        case driftMs = "drift_ms"
        case driftLabel = "drift_label"
    }
}

struct MonitorNetwork: Codable {
    let ok: Bool?
    let latencyMs: Double?
    let downloadMbps: Double?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case ok, status
        case latencyMs = "latency_ms"
        case downloadMbps = "download_mbps"
    }
}

struct MonitorTokens: Codable {
    let sessionTotal: Int?
    let lifetimeTotal: Int?
    let sessionRequests: Int?
    let lifetimeRequests: Int?

    enum CodingKeys: String, CodingKey {
        case sessionTotal = "session_total"
        case lifetimeTotal = "lifetime_total"
        case sessionRequests = "session_requests"
        case lifetimeRequests = "lifetime_requests"
    }
}

enum MonitorBridge {
    static var binURL: URL { GrokPaths.root.appendingPathComponent("bin/monitor") }

    static func run(_ args: [String]) -> (ok: Bool, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [binURL.path] + args
        task.environment = ProcessInfo.processInfo.environment.merging(
            ["GROK_PUBLIC_FOLDER": GrokPaths.root.path],
            uniquingKeysWith: { _, new in new }
        )
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

    static func fetchStatus(quick: Bool = false) -> MonitorStatusResponse? {
        var args = ["status"]
        if quick { args.append("--quick") }
        let result = run(args)
        guard let data = result.output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MonitorStatusResponse.self, from: data)
    }
}

final class HeaderMonitorController: NSObject {
    let container = NSView()
    private let tokenLabel = NSTextField(labelWithString: "TOKENS …")
    private let clockLabel = NSTextField(labelWithString: "UNIX …")
    private let netLabel = NSTextField(labelWithString: "NET …")
    private var clockTimer: Timer?
    private var refreshTimer: Timer?
    private var tokenTimer: Timer?
    private var driftText = "Δ…"
    private var sessionTokens = 0
    private var lifetimeTokens = 0
    private var latencyText = "…"
    private var speedText = "…"
    private var isRefreshing = false

    override init() {
        super.init()
        setupViews()
    }

    private func setupViews() {
        container.translatesAutoresizingMaskIntoConstraints = false
        for label in [tokenLabel, clockLabel, netLabel] {
            label.font = GrokTypography.meta
            label.textColor = GrokTheme.textSecondary
            label.alignment = .right
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
        }
        tokenLabel.textColor = GrokTheme.text
        tokenLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)

        NSLayoutConstraint.activate([
            tokenLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            tokenLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tokenLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            clockLabel.topAnchor.constraint(equalTo: tokenLabel.bottomAnchor, constant: 2),
            clockLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            clockLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            netLabel.topAnchor.constraint(equalTo: clockLabel.bottomAnchor, constant: 2),
            netLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            netLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            netLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
        ])
        renderLabels(unix: Int(Date().timeIntervalSince1970))
    }

    func start() {
        stop()
        refresh(full: true)
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickClock()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refresh(full: true)
        }
        tokenTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh(full: false)
        }
    }

    func stop() {
        clockTimer?.invalidate()
        refreshTimer?.invalidate()
        tokenTimer?.invalidate()
        clockTimer = nil
        refreshTimer = nil
        tokenTimer = nil
    }

    private func tickClock() {
        renderLabels(unix: Int(Date().timeIntervalSince1970))
    }

    private func refresh(full: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = MonitorBridge.fetchStatus(quick: !full)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                if let status {
                    self.apply(status: status)
                }
            }
        }
    }

    private func apply(status: MonitorStatusResponse) {
        if let tokens = status.tokens {
            sessionTokens = tokens.sessionTotal ?? 0
            lifetimeTokens = tokens.lifetimeTotal ?? 0
        }
        if let drift = status.drift, let label = drift.driftLabel, !label.isEmpty {
            driftText = "Δ\(label)"
            if drift.status == "bad" {
                driftText += " ⚠"
            }
        }
        if let network = status.network {
            if let ms = network.latencyMs {
                latencyText = "\(Int(ms))ms"
            } else {
                latencyText = "offline"
            }
            if let mbps = network.downloadMbps {
                speedText = String(format: "%.1f Mbps", mbps)
            } else {
                speedText = "—"
            }
            if network.status == "bad" || network.status == "offline" {
                netLabel.textColor = GrokTheme.accent
            } else if network.status == "slow" {
                netLabel.textColor = NSColor.systemYellow
            } else {
                netLabel.textColor = GrokTheme.textSecondary
            }
        }
        let unix = status.clock?.unixInt ?? Int(Date().timeIntervalSince1970)
        renderLabels(unix: unix)
    }

    private func renderLabels(unix: Int) {
        tokenLabel.stringValue = "TOKENS \(formatCount(sessionTokens)) sess · \(formatCount(lifetimeTokens)) life"
        clockLabel.stringValue = "UNIX \(unix)  \(driftText)"
        netLabel.stringValue = "NET \(latencyText) · \(speedText)"
    }

    private func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        if value >= 1000 {
            return String(format: "%.2fK", Double(value) / 1000.0)
        }
        return "\(value)"
    }
}
import AppKit

@main
struct GrokMain {
    static func main() {
        ProcessInfo.processInfo.processName = GrokBrand.appName
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let grok = GrokApp()
        app.delegate = grok
        app.run()
    }
}
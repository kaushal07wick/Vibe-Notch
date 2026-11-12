import AppKit

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--export-style-gallery" {
    do {
        try exportInterfaceStyleGallery(to: CommandLine.arguments[2])
        exit(0)
    } catch {
        fputs("Could not export style gallery: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// Menu-bar agent: no Dock icon, no main menu focus stealing.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

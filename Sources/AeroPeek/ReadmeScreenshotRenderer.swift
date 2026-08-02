import AppKit

enum ReadmeScreenshotRenderer {
    static func render(to directory: URL) throws {
        let workspaces = sampleWorkspaces()
        let overview = OverviewView(workspaces: workspaces, maxHeight: 900)
        overview.blendingMode = .withinWindow
        try render(
            view: overview,
            to: directory.appendingPathComponent("overview.png")
        )

        let focusedCard = WorkspaceCardView(workspace: workspaces[0])
        let cardPadding: CGFloat = 20
        let detail = NSVisualEffectView(frame: NSRect(
            x: 0,
            y: 0,
            width: focusedCard.frame.width + cardPadding * 2,
            height: focusedCard.frame.height + cardPadding * 2
        ))
        detail.material = .hudWindow
        detail.blendingMode = .withinWindow
        detail.state = .active
        detail.wantsLayer = true
        detail.layer?.cornerRadius = 20
        detail.layer?.masksToBounds = true
        focusedCard.frame.origin = NSPoint(x: cardPadding, y: cardPadding)
        detail.addSubview(focusedCard)
        try render(
            view: detail,
            to: directory.appendingPathComponent("focused-workspace.png")
        )
    }

    private static func render(view: NSView, to outputURL: URL) throws {
        let size = view.frame.size
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        window.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        window.contentView = view
        window.displayIfNeeded()
        view.displayIfNeeded()

        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: outputURL, options: .atomic)
    }

    private static func sampleWorkspaces() -> [WorkspaceInfo] {
        [
            WorkspaceInfo(
                name: "1",
                monitorID: 1,
                isFocused: true,
                isVisible: true,
                rootLayout: "h_tiles",
                bindingMode: "main",
                windows: [
                    WindowInfo(
                        appName: "Safari",
                        bundleID: "com.apple.Safari",
                        bundlePath: "",
                        title: "AeroSpace documentation"
                    ),
                    WindowInfo(
                        appName: "Terminal",
                        bundleID: "com.apple.Terminal",
                        bundlePath: "",
                        title: "~/Projects/AeroPeek"
                    )
                ]
            ),
            WorkspaceInfo(
                name: "2",
                monitorID: 1,
                isFocused: false,
                isVisible: false,
                rootLayout: "v_tiles",
                bindingMode: "main",
                windows: [
                    WindowInfo(
                        appName: "Xcode",
                        bundleID: "com.apple.dt.Xcode",
                        bundlePath: "",
                        title: "AeroPeek — main.swift"
                    )
                ]
            ),
            WorkspaceInfo(
                name: "3",
                monitorID: 1,
                isFocused: false,
                isVisible: false,
                rootLayout: "h_tiles",
                bindingMode: "main",
                windows: [
                    WindowInfo(
                        appName: "Messages",
                        bundleID: "com.apple.MobileSMS",
                        bundlePath: "",
                        title: "Messages"
                    )
                ]
            ),
            WorkspaceInfo(
                name: "4",
                monitorID: 1,
                isFocused: false,
                isVisible: false,
                rootLayout: "h_accordion",
                bindingMode: "main",
                windows: [
                    WindowInfo(
                        appName: "Music",
                        bundleID: "com.apple.Music",
                        bundlePath: "",
                        title: "Focus Mix"
                    )
                ]
            ),
            WorkspaceInfo(
                name: "5",
                monitorID: 1,
                isFocused: false,
                isVisible: false,
                rootLayout: "v_tiles",
                bindingMode: "main",
                windows: [
                    WindowInfo(
                        appName: "Notes",
                        bundleID: "com.apple.Notes",
                        bundlePath: "",
                        title: "Project ideas"
                    )
                ]
            )
        ]
    }
}

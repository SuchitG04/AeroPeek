import AppKit
import Carbon.HIToolbox
import Darwin
import UniformTypeIdentifiers

private let appBundleID = "dev.windowhelper.AeroPeek"

struct WindowInfo {
    let appName: String
    let bundleID: String
    let bundlePath: String
    let title: String
}

struct WorkspaceInfo {
    let name: String
    let monitorID: Int
    let isFocused: Bool
    let isVisible: Bool
    let rootLayout: String
    let bindingMode: String
    var windows: [WindowInfo]
}

struct ShortcutConfig: Decodable {
    var modifiers: [String] = ["control", "option"]
    var keyCode: Int = 49

    static func load() -> ShortcutConfig {
        let url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".config/aeropeek/config.json")
        if let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            return config
        }
        return ShortcutConfig()
    }

    var carbonModifiers: UInt32 {
        modifiers.reduce(into: UInt32(0)) { result, modifier in
            switch modifier.lowercased() {
            case "command", "cmd": result |= UInt32(cmdKey)
            case "control", "ctrl": result |= UInt32(controlKey)
            case "option", "alt": result |= UInt32(optionKey)
            case "shift": result |= UInt32(shiftKey)
            default: break
            }
        }
    }
}

enum OverviewError: LocalizedError {
    case aerospaceNotFound
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .aerospaceNotFound:
            return "Couldn’t find the AeroSpace command-line tool."
        case .commandFailed(let message):
            return message.isEmpty ? "AeroSpace couldn’t list your windows." : message
        case .invalidResponse:
            return "AeroSpace returned data in an unexpected format."
        }
    }
}

final class AeroSpaceDataProvider {
    private let executable: String?

    init() {
        executable = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
            "/Applications/AeroSpace.app/Contents/MacOS/aerospace"
        ].first { access($0, X_OK) == 0 }
    }

    func load() throws -> [WorkspaceInfo] {
        guard let executable else { throw OverviewError.aerospaceNotFound }

        let workspaceRows = try run(
            executable,
            arguments: [
                "list-workspaces", "--all", "--json", "--format",
                "%{workspace}%{workspace-is-focused}%{workspace-is-visible}%{workspace-root-container-layout}%{monitor-id}"
            ]
        )
        let modeRows = try run(
            executable,
            arguments: ["list-modes", "--current", "--json"]
        )
        let currentMode = modeRows.first?["mode-id"] as? String ?? "unknown"
        let windowRows = try run(
            executable,
            arguments: [
                "list-windows", "--all", "--json", "--format",
                "%{workspace}%{app-bundle-id}%{app-name}%{window-title}%{app-bundle-path}%{monitor-id}"
            ]
        )

        var windowsByWorkspace: [String: [WindowInfo]] = [:]
        for row in windowRows {
            let bundleID = string(row, "app-bundle-id")
            guard bundleID != appBundleID else { continue }
            let workspace = string(row, "workspace")
            windowsByWorkspace[workspace, default: []].append(
                WindowInfo(
                    appName: string(row, "app-name", fallback: "Unknown application"),
                    bundleID: bundleID,
                    bundlePath: string(row, "app-bundle-path"),
                    title: string(row, "window-title")
                )
            )
        }

        return workspaceRows.map { row in
            let name = string(row, "workspace")
            return WorkspaceInfo(
                name: name,
                monitorID: integer(row, "monitor-id"),
                isFocused: boolean(row, "workspace-is-focused"),
                isVisible: boolean(row, "workspace-is-visible"),
                rootLayout: string(row, "workspace-root-container-layout", fallback: "unknown"),
                bindingMode: currentMode,
                windows: (windowsByWorkspace[name] ?? []).sorted {
                    ($0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending)
                }
            )
        }
        .filter { !$0.windows.isEmpty || $0.isFocused || $0.isVisible }
        .sorted(by: workspaceSort)
    }

    private func run(_ executable: String, arguments: [String]) throws -> [[String: Any]] {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw OverviewError.commandFailed(
                String(data: error, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        guard let rows = try JSONSerialization.jsonObject(with: output) as? [[String: Any]] else {
            throw OverviewError.invalidResponse
        }
        return rows
    }

    private func string(_ row: [String: Any], _ key: String, fallback: String = "") -> String {
        row[key] as? String ?? fallback
    }

    private func integer(_ row: [String: Any], _ key: String) -> Int {
        if let value = row[key] as? Int { return value }
        if let value = row[key] as? NSNumber { return value.intValue }
        return Int(row[key] as? String ?? "") ?? 0
    }

    private func boolean(_ row: [String: Any], _ key: String) -> Bool {
        if let value = row[key] as? Bool { return value }
        if let value = row[key] as? NSNumber { return value.boolValue }
        return (row[key] as? String)?.lowercased() == "true"
    }

    private func workspaceSort(_ lhs: WorkspaceInfo, _ rhs: WorkspaceInfo) -> Bool {
        if lhs.monitorID != rhs.monitorID { return lhs.monitorID < rhs.monitorID }
        if let left = Int(lhs.name), let right = Int(rhs.name) { return left < right }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

private func workspaceCardHeight(_ workspace: WorkspaceInfo) -> CGFloat {
    let rowCount = max(min(workspace.windows.count, 5), 1)
    let overflowHeight = workspace.windows.count > 5 ? 22 : 8
    let metadataHeight = workspace.isFocused ? 24 : 0
    return CGFloat(50 + rowCount * 42 + overflowHeight + metadataHeight)
}

final class WorkspaceCardView: NSView {
    private let width: CGFloat = 320

    init(workspace: WorkspaceInfo) {
        let displayedWindows = Array(workspace.windows.prefix(5))
        let height = workspaceCardHeight(workspace)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.075).cgColor
        layer?.borderWidth = workspace.isFocused ? 1.5 : 0.5
        layer?.borderColor = workspace.isFocused
            ? NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
            : NSColor.white.withAlphaComponent(0.12).cgColor

        let title = label(
            workspace.name,
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: .labelColor
        )
        title.frame = NSRect(x: 16, y: height - 36, width: 220, height: 22)
        addSubview(title)

        let statusText = workspace.isFocused ? "FOCUSED" : (workspace.isVisible ? "VISIBLE" : "")
        if !statusText.isEmpty {
            let status = label(
                statusText,
                font: .systemFont(ofSize: 10, weight: .bold),
                color: workspace.isFocused ? .controlAccentColor : .secondaryLabelColor
            )
            status.alignment = .right
            status.frame = NSRect(x: width - 92, y: height - 34, width: 76, height: 18)
            addSubview(status)
        }

        let rowOffset: CGFloat
        if workspace.isFocused {
            let appCount = Set(workspace.windows.map {
                $0.bundleID.isEmpty ? $0.appName : $0.bundleID
            }).count
            let windowLabel = workspace.windows.count == 1 ? "window" : "windows"
            let appLabel = appCount == 1 ? "app" : "apps"
            let layout = workspace.rootLayout.replacingOccurrences(of: "_", with: " ")
            let metadata = label(
                "\(workspace.bindingMode) mode  ·  \(layout)  ·  monitor \(workspace.monitorID)  ·  \(workspace.windows.count) \(windowLabel) / \(appCount) \(appLabel)",
                font: .systemFont(ofSize: 10.5, weight: .medium),
                color: .secondaryLabelColor
            )
            metadata.frame = NSRect(x: 16, y: height - 61, width: width - 32, height: 17)
            addSubview(metadata)
            rowOffset = 24
        } else {
            rowOffset = 0
        }

        if displayedWindows.isEmpty {
            let empty = label(
                "No windows",
                font: .systemFont(ofSize: 13),
                color: .tertiaryLabelColor
            )
            empty.frame = NSRect(x: 16, y: 14, width: width - 32, height: 24)
            addSubview(empty)
        } else {
            for (index, window) in displayedWindows.enumerated() {
                let y = height - 78 - rowOffset - CGFloat(index) * 42
                addWindowRow(window, y: y)
            }
        }

        if workspace.windows.count > displayedWindows.count {
            let more = label(
                "+\(workspace.windows.count - displayedWindows.count) more",
                font: .systemFont(ofSize: 11, weight: .medium),
                color: .secondaryLabelColor
            )
            more.frame = NSRect(x: 52, y: 7, width: width - 68, height: 18)
            addSubview(more)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addWindowRow(_ window: WindowInfo, y: CGFloat) {
        let imageView = NSImageView(frame: NSRect(x: 16, y: y, width: 28, height: 28))
        imageView.image = appIcon(for: window)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        let app = label(
            window.appName,
            font: .systemFont(ofSize: 12.5, weight: .medium),
            color: .labelColor
        )
        app.frame = NSRect(x: 54, y: y + 13, width: width - 70, height: 17)
        addSubview(app)

        let titleText = window.title.isEmpty ? "Untitled window" : window.title
        let title = label(
            titleText,
            font: .systemFont(ofSize: 11.5),
            color: .secondaryLabelColor
        )
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 54, y: y - 2, width: width - 70, height: 17)
        addSubview(title)
    }

    private func appIcon(for window: WindowInfo) -> NSImage {
        if !window.bundlePath.isEmpty {
            return NSWorkspace.shared.icon(forFile: window.bundlePath)
        }
        if !window.bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: window.bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

final class OverviewView: NSVisualEffectView {
    init(workspaces: [WorkspaceInfo], maxHeight: CGFloat) {
        let columns = workspaces.count <= 1 ? 1 : 2
        let cardWidth: CGFloat = 320
        let gap: CGFloat = 12
        let horizontalPadding: CGFloat = 20
        let headerHeight: CGFloat = 58
        let bottomPadding: CGFloat = 20
        let rows = stride(from: 0, to: workspaces.count, by: columns).map {
            Array(workspaces[$0..<min($0 + columns, workspaces.count)])
        }
        let rowHeights = rows.map { row in
            row.map(workspaceCardHeight).max() ?? 0
        }
        let contentHeight = headerHeight + rowHeights.reduce(0, +)
            + CGFloat(max(rows.count - 1, 0)) * gap + bottomPadding
        let visibleHeight = min(contentHeight, maxHeight)
        let totalWidth = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * gap + horizontalPadding * 2

        super.init(frame: NSRect(x: 0, y: 0, width: totalWidth, height: visibleHeight))
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = true

        let heading = NSTextField(labelWithString: "AeroPeek")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        heading.textColor = .labelColor
        heading.frame = NSRect(x: 22, y: visibleHeight - 39, width: 300, height: 24)
        addSubview(heading)

        let count = workspaces.reduce(0) { $0 + $1.windows.count }
        let summary = NSTextField(labelWithString: "\(workspaces.count) workspaces  ·  \(count) windows")
        summary.font = .systemFont(ofSize: 11.5)
        summary.textColor = .secondaryLabelColor
        summary.alignment = .right
        summary.frame = NSRect(x: totalWidth - 255, y: visibleHeight - 37, width: 233, height: 20)
        addSubview(summary)

        let scroll = NSScrollView(frame: NSRect(
            x: 0,
            y: 0,
            width: totalWidth,
            height: visibleHeight - headerHeight
        ))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = contentHeight > visibleHeight
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let documentHeight = contentHeight - headerHeight
        let document = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: documentHeight))
        var top = documentHeight - 2

        for (rowIndex, row) in rows.enumerated() {
            let rowHeight = rowHeights[rowIndex]
            for (columnIndex, workspace) in row.enumerated() {
                let card = WorkspaceCardView(workspace: workspace)
                card.frame.origin = NSPoint(
                    x: horizontalPadding + CGFloat(columnIndex) * (cardWidth + gap),
                    y: top - card.frame.height
                )
                document.addSubview(card)
            }
            top -= rowHeight + gap
        }
        scroll.documentView = document
        if documentHeight > scroll.contentView.bounds.height {
            scroll.contentView.scroll(to: NSPoint(
                x: 0,
                y: documentHeight - scroll.contentView.bounds.height
            ))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        addSubview(scroll)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isMovable = false
    }

    func show(workspaces: [WorkspaceInfo]) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let maxHeight = max(260, (screen?.visibleFrame.height ?? 800) - 100)
        let overview = OverviewView(workspaces: workspaces, maxHeight: maxHeight)
        let overviewSize = overview.frame.size
        setContentSize(overviewSize)
        overview.frame = NSRect(origin: .zero, size: overviewSize)
        overview.autoresizingMask = [.width, .height]
        contentView = overview
        if let screen {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(
                x: frame.midX - self.frame.width / 2,
                y: frame.midY - self.frame.height / 2
            ))
        }
        orderFrontRegardless()
    }

    func showError(_ message: String) {
        let view = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 470, height: 110))
        view.material = .hudWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 18

        let title = NSTextField(labelWithString: "AeroPeek")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.frame = NSRect(x: 20, y: 68, width: 430, height: 24)
        view.addSubview(title)

        let detail = NSTextField(wrappingLabelWithString: message)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 20, y: 18, width: 430, height: 44)
        view.addSubview(detail)

        let errorSize = view.frame.size
        setContentSize(errorSize)
        view.frame = NSRect(origin: .zero, size: errorSize)
        view.autoresizingMask = [.width, .height]
        contentView = view
        center()
        orderFrontRegardless()
    }
}

final class HotkeyMonitor {
    private let config: ShortcutConfig
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var pressed: (() -> Void)?
    var released: (() -> Void)?

    init(config: ShortcutConfig) {
        self.config = config
    }

    func start() -> Bool {
        stop()

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        let callback: EventHandlerUPP = { _, event, userInfo in
            guard let event, let userInfo else { return OSStatus(eventNotHandledErr) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            switch GetEventKind(event) {
            case UInt32(kEventHotKeyPressed):
                monitor.pressed?()
                return noErr
            case UInt32(kEventHotKeyReleased):
                monitor.released?()
                return noErr
            default:
                return OSStatus(eventNotHandledErr)
            }
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard handlerStatus == noErr else { return false }

        let hotkeyID = EventHotKeyID(
            signature: OSType(0x4150454B), // "APEK"
            id: 1
        )
        let registrationStatus = RegisterEventHotKey(
            UInt32(config.keyCode),
            config.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        guard registrationStatus == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        hotkeyRef = nil
        handlerRef = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let doubleTapInterval: TimeInterval = 0.42
    private let panel = OverlayPanel()
    private let provider = AeroSpaceDataProvider()
    private var hotkey: HotkeyMonitor!
    private var statusItem: NSStatusItem!
    private var loadGeneration = 0
    private var lastShortcutPress: TimeInterval?
    private var pendingHide: DispatchWorkItem?
    private var isPinned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenuBar()
        configureHotkey()
    }

    private func configureHotkey() {
        hotkey = HotkeyMonitor(config: .load())
        hotkey.pressed = { [weak self] in self?.shortcutPressed() }
        hotkey.released = { [weak self] in self?.shortcutReleased() }
        let started = hotkey.start()
        updateStatusItem(shortcutReady: started)
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "square.grid.2x2",
                accessibilityDescription: "AeroPeek"
            )
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Preview", action: #selector(showFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Hide Preview", action: #selector(hideFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Retry Shortcut Registration", action: #selector(retryShortcut), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitApplication), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func updateStatusItem(shortcutReady: Bool) {
        statusItem.button?.contentTintColor = shortcutReady ? nil : .systemOrange
        statusItem.button?.toolTip = shortcutReady
            ? "Hold Control–Option–Space"
            : "Shortcut unavailable — click the menu to retry"
    }

    private func showOverview() {
        loadGeneration += 1
        let generation = loadGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let workspaces = try self.provider.load()
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.loadGeneration else { return }
                    self.panel.show(workspaces: workspaces)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.loadGeneration else { return }
                    self.panel.showError(error.localizedDescription)
                }
            }
        }
    }

    private func hideOverview() {
        loadGeneration += 1
        panel.orderOut(nil)
    }

    private func shortcutPressed() {
        pendingHide?.cancel()
        pendingHide = nil

        if isPinned {
            isPinned = false
            lastShortcutPress = nil
            hideOverview()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let previousPress = lastShortcutPress,
           now - previousPress <= doubleTapInterval {
            isPinned = true
            lastShortcutPress = nil
            if !panel.isVisible {
                showOverview()
            }
            return
        }

        lastShortcutPress = now
        showOverview()
    }

    private func shortcutReleased() {
        guard !isPinned, let pressTime = lastShortcutPress else { return }

        let elapsed = ProcessInfo.processInfo.systemUptime - pressTime
        let remaining = doubleTapInterval - elapsed
        guard remaining > 0 else {
            lastShortcutPress = nil
            hideOverview()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isPinned, self.lastShortcutPress == pressTime else { return }
            self.lastShortcutPress = nil
            self.hideOverview()
        }
        pendingHide = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
    }

    @objc private func showFromMenu() {
        pendingHide?.cancel()
        pendingHide = nil
        lastShortcutPress = nil
        isPinned = true
        showOverview()
    }

    @objc private func hideFromMenu() {
        pendingHide?.cancel()
        pendingHide = nil
        lastShortcutPress = nil
        isPinned = false
        hideOverview()
    }

    @objc private func retryShortcut() {
        updateStatusItem(shortcutReady: hotkey.start())
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()

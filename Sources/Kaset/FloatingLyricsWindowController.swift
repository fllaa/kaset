import AppKit
import SwiftUI

// MARK: - FloatingLyricsWindowLaunch

/// Parameters needed to show the lyrics pop-out window (keeps call sites SwiftLint-friendly).
@available(macOS 26.0, *)
@MainActor
struct FloatingLyricsWindowLaunch {
    let coordinator: LyricsPresentationCoordinator
    let client: any YTMusicClientProtocol
    let playerService: PlayerService
    let webKitManager: WebKitManager
    let syncedLyricsService: SyncedLyricsService
    let pinned: Bool
}

// MARK: - FloatingLyricsWindowController

/// Manages the floating Picture-in-Picture style lyrics window.
@available(macOS 26.0, *)
@MainActor
final class FloatingLyricsWindowController {
    static let shared = FloatingLyricsWindowController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private weak var coordinator: LyricsPresentationCoordinator?

    private var isClosing = false

    private let frameAutosaveKey = "KasetLyricsWindow"

    private init() {}

    func show(launch: FloatingLyricsWindowLaunch) {
        self.coordinator = launch.coordinator

        if let existingWindow = self.window {
            self.isClosing = false
            existingWindow.level = launch.pinned ? .floating : .normal
            Self.hideStandardWindowControls(existingWindow)
            existingWindow.orderFront(nil)
            return
        }

        let contentView = FloatingLyricsWindow(client: launch.client)
            .environment(launch.playerService)
            .environment(launch.webKitManager)
            .environment(launch.syncedLyricsService)
            .environment(launch.coordinator)

        let hostingView = NSHostingView(rootView: AnyView(contentView))
        self.hostingView = hostingView

        let defaultRect = NSRect(x: 0, y: 0, width: 320, height: 480)
        let window = NSWindow(
            contentRect: defaultRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.title = String(localized: "Lyrics")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = launch.pinned ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 220, height: 240)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        window.setFrameAutosaveName(self.frameAutosaveKey)
        window.identifier = NSUserInterfaceItemIdentifier(AccessibilityID.LyricsWindow.container)

        Self.hideStandardWindowControls(window)

        if !window.setFrameUsingName(self.frameAutosaveKey) {
            self.positionAtDefaultLocation(window: window)
        }

        window.orderFront(nil)
        self.window = window
        self.isClosing = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )

        DiagnosticsLogger.ui.info("Floating lyrics window shown (pinned=\(launch.pinned))")
    }

    /// Programmatic close from ``LyricsPresentationCoordinator`` before mode transitions.
    func closeFromAppCoordinator() {
        guard !self.isClosing else { return }
        guard let window = self.window else { return }

        self.isClosing = true
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        window.saveFrame(usingName: self.frameAutosaveKey)

        self.window = nil
        self.hostingView = nil

        window.close()

        self.coordinator = nil
        self.isClosing = false
        DiagnosticsLogger.ui.debug("Floating lyrics window closed (coordinator)")
    }

    func setPinned(_ pinned: Bool) {
        self.window?.level = pinned ? .floating : .normal
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard !self.isClosing else { return }
        self.isClosing = true

        if let window = notification.object as? NSWindow {
            window.saveFrame(usingName: self.frameAutosaveKey)
        }

        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: notification.object)

        self.window = nil
        self.hostingView = nil

        self.coordinator?.handleFloatingWindowClosedByUser()
        self.coordinator = nil

        self.isClosing = false
        DiagnosticsLogger.ui.debug("Floating lyrics window will close (user)")
    }

    private func positionAtDefaultLocation(window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let padding: CGFloat = 40

        let origin = NSPoint(
            x: screenFrame.maxX - windowSize.width - padding,
            y: screenFrame.maxY - windowSize.height - padding
        )

        window.setFrameOrigin(origin)
    }

    /// Hides the system close / minimize / zoom controls so the chrome matches a PiP-style panel.
    private static func hideStandardWindowControls(_ window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

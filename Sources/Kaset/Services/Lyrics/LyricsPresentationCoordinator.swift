import Foundation
import Observation

// MARK: - LyricsPresentationMode

enum LyricsPresentationMode: Equatable {
    case hidden
    case sidebar
    case floating(pinned: Bool)

    var isFloating: Bool {
        if case .floating = self {
            true
        } else {
            false
        }
    }
}

// MARK: - LyricsPresentationCoordinator

@MainActor
@Observable
final class LyricsPresentationCoordinator {
    private(set) var mode: LyricsPresentationMode = .hidden

    let explanationViewModel = LyricsExplanationViewModel()

    private let playerService: PlayerService
    private let syncedLyricsService: SyncedLyricsService
    private let lyricsPolling: LyricsPollingControlling

    private weak var webKitManager: WebKitManager?
    private var sharedClient: (any YTMusicClientProtocol)?

    private var lastLyricsResult: LyricResult = .unavailable

    private let logger = DiagnosticsLogger.ui

    init(
        playerService: PlayerService,
        syncedLyricsService: SyncedLyricsService,
        lyricsPolling: LyricsPollingControlling
    ) {
        self.playerService = playerService
        self.syncedLyricsService = syncedLyricsService
        self.lyricsPolling = lyricsPolling
    }

    /// Late binding for the floating window host; set from ``KasetApp``.
    func configurePresenters(client: any YTMusicClientProtocol, webKitManager: WebKitManager) {
        self.sharedClient = client
        self.webKitManager = webKitManager
    }

    func handleLyricsResultChanged(_ result: LyricResult) {
        self.lastLyricsResult = result
        self.updatePolling()
    }

    func handlePlayerShowLyricsChanged(oldValue: Bool, newValue: Bool) {
        guard oldValue != newValue else { return }
        if newValue {
            if self.mode == .hidden {
                self.applyMode(.sidebar, updatePlayer: false)
            }
        } else {
            switch self.mode {
            case .sidebar:
                self.applyMode(.hidden, updatePlayer: false)
            case .floating:
                FloatingLyricsWindowController.shared.closeFromAppCoordinator()
                self.applyMode(.hidden, updatePlayer: false)
            case .hidden:
                break
            }
        }
    }

    func handleFloatingWindowClosedByUser() {
        if self.playerService.showLyrics {
            self.mode = .sidebar
        } else {
            self.mode = .hidden
        }
        self.updatePolling()
        self.logger.debug("Lyrics floating window closed by user; mode=\(String(describing: self.mode))")
    }

    func showInSidebar() {
        self.applyMode(.sidebar)
    }

    func hideLyricsPanel() {
        self.applyMode(.hidden)
    }

    func popOut() {
        let pinned = SettingsManager.shared.floatingLyricsPinned
        self.applyMode(.floating(pinned: pinned))
    }

    func popIn() {
        guard self.mode.isFloating else { return }
        FloatingLyricsWindowController.shared.closeFromAppCoordinator()
        self.applyMode(.sidebar, updatePlayer: false)
    }

    func toggleFloatingWindowShortcut() {
        switch self.mode {
        case .floating:
            self.popIn()
        case .sidebar:
            self.popOut()
        case .hidden:
            self.playerService.setShowLyricsFromCoordinator(true)
            let pinned = SettingsManager.shared.floatingLyricsPinned
            self.applyMode(.floating(pinned: pinned), updatePlayer: false)
        }
    }

    func togglePinned() {
        guard case let .floating(pinned) = self.mode else { return }
        let newPinned = !pinned
        SettingsManager.shared.floatingLyricsPinned = newPinned
        self.mode = .floating(pinned: newPinned)
        FloatingLyricsWindowController.shared.setPinned(newPinned)
    }

    private func applyMode(_ newMode: LyricsPresentationMode, updatePlayer: Bool = true) {
        let previous = self.mode
        guard previous != newMode else {
            self.updatePolling()
            return
        }

        if previous.isFloating, !newMode.isFloating {
            FloatingLyricsWindowController.shared.closeFromAppCoordinator()
        }

        self.mode = newMode

        if updatePlayer {
            let visible = newMode != .hidden
            self.playerService.setShowLyricsFromCoordinator(visible)
        }

        self.updatePolling()

        if case let .floating(pinned) = newMode {
            self.presentFloatingWindowIfNeeded(pinned: pinned)
        }
    }

    private func updatePolling() {
        let shouldPoll = self.mode != .hidden && self.pollableSyncedResult(self.lastLyricsResult)
        if shouldPoll {
            self.lyricsPolling.startLyricsPoll()
        } else {
            self.lyricsPolling.stopLyricsPoll()
        }
    }

    private func pollableSyncedResult(_ result: LyricResult) -> Bool {
        if case .synced = result {
            true
        } else {
            false
        }
    }

    private func presentFloatingWindowIfNeeded(pinned: Bool) {
        guard case .floating = self.mode else { return }
        guard let client = self.sharedClient, let webKit = self.webKitManager else {
            self.logger.warning("Lyrics pop-out requested before coordinator presenters were configured")
            return
        }
        FloatingLyricsWindowController.shared.show(
            launch: FloatingLyricsWindowLaunch(
                coordinator: self,
                client: client,
                playerService: self.playerService,
                webKitManager: webKit,
                syncedLyricsService: self.syncedLyricsService,
                pinned: pinned
            )
        )
    }
}

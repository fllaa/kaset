import Foundation
import Testing
@testable import Kaset

// MARK: - MockLyricsPollingController

@MainActor
final class MockLyricsPollingController: LyricsPollingControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startLyricsPoll() {
        self.startCount += 1
    }

    func stopLyricsPoll() {
        self.stopCount += 1
    }
}

// MARK: - FloatingLyricsCoordinatorTests

@MainActor
struct FloatingLyricsCoordinatorTests {
    private struct Harness {
        let coordinator: LyricsPresentationCoordinator
        let player: PlayerService
        let synced: SyncedLyricsService
        let poller: MockLyricsPollingController
    }

    private func makeLine(text: String = "Line") -> SyncedLyricLine {
        SyncedLyricLine(timeInMs: 0, duration: 1000, text: text, words: nil, romanizedText: nil)
    }

    private func makeHarness() -> Harness {
        let player = PlayerService()
        let synced = SyncedLyricsService(providers: [])
        let poller = MockLyricsPollingController()
        let coordinator = LyricsPresentationCoordinator(
            playerService: player,
            syncedLyricsService: synced,
            lyricsPolling: poller
        )
        player.lyricsPresentationCoordinator = coordinator
        coordinator.configurePresenters(
            client: MockUITestYTMusicClient(),
            webKitManager: WebKitManager.shared
        )
        return Harness(
            coordinator: coordinator,
            player: player,
            synced: synced,
            poller: poller
        )
    }

    @Test("mode defaults to hidden")
    func modeDefaultsHidden() {
        let harness = self.makeHarness()
        #expect(harness.coordinator.mode == .hidden)
    }

    @Test("showInSidebar updates mode")
    func showInSidebarUpdatesMode() {
        let harness = self.makeHarness()
        harness.coordinator.showInSidebar()
        #expect(harness.coordinator.mode == .sidebar)
        #expect(harness.player.showLyrics == true)
    }

    @Test("hide stops polling from synced state")
    func hideStopsPolling() {
        let harness = self.makeHarness()
        harness.synced.currentLyrics = .synced(SyncedLyrics(lines: [self.makeLine()], source: "t"))
        harness.coordinator.handleLyricsResultChanged(harness.synced.currentLyrics)
        harness.coordinator.showInSidebar()
        let startsAfterShow = harness.poller.startCount
        #expect(startsAfterShow >= 1)
        harness.coordinator.hideLyricsPanel()
        #expect(harness.coordinator.mode == .hidden)
        #expect(harness.player.showLyrics == false)
        #expect(harness.poller.stopCount >= 1)
    }

    @Test("plain lyrics never start polling")
    func plainLyricsNoPolling() {
        let harness = self.makeHarness()
        harness.synced.currentLyrics = .plain(Lyrics(text: "Hi", source: nil))
        harness.coordinator.handleLyricsResultChanged(harness.synced.currentLyrics)
        harness.coordinator.showInSidebar()
        #expect(harness.poller.startCount == 0)
    }

    @Test("popOut enters floating and showLyrics remains true")
    func popOutFloating() {
        let harness = self.makeHarness()
        defer {
            if harness.coordinator.mode.isFloating {
                harness.coordinator.popIn()
            }
        }
        harness.coordinator.showInSidebar()
        harness.coordinator.popOut()
        #expect(harness.coordinator.mode.isFloating)
        if case let .floating(pinned) = harness.coordinator.mode {
            #expect(pinned == SettingsManager.shared.floatingLyricsPinned)
        }
        #expect(harness.player.showLyrics == true)
    }

    @Test("togglePinned only applies while floating")
    func togglePinnedFloatingOnly() {
        let originalPinned = SettingsManager.shared.floatingLyricsPinned
        defer {
            SettingsManager.shared.floatingLyricsPinned = originalPinned
        }
        let harness = self.makeHarness()
        defer {
            if harness.coordinator.mode.isFloating {
                harness.coordinator.popIn()
            }
        }
        let before = SettingsManager.shared.floatingLyricsPinned
        harness.coordinator.togglePinned()
        #expect(SettingsManager.shared.floatingLyricsPinned == before)
        harness.coordinator.showInSidebar()
        harness.coordinator.popOut()
        harness.coordinator.togglePinned()
        #expect(SettingsManager.shared.floatingLyricsPinned == !before)
    }

    @Test("PlayerService showLyrics toggles sync with coordinator")
    func playerShowLyricsSync() {
        let harness = self.makeHarness()
        harness.synced.currentLyrics = .unavailable
        harness.coordinator.handleLyricsResultChanged(harness.synced.currentLyrics)
        harness.player.showLyrics = true
        #expect(harness.coordinator.mode == .sidebar)
        harness.player.showLyrics = false
        #expect(harness.coordinator.mode == .hidden)
    }

    @Test("Explanation resets when track identity changes via resetForNewTrack")
    func explanationResetsOnTrack() {
        let harness = self.makeHarness()
        harness.coordinator.explanationViewModel.lyricsSummary = LyricsSummary(themes: ["t"], mood: "m", explanation: "e")
        harness.coordinator.explanationViewModel.resetForNewTrack(videoId: "next")
        #expect(harness.coordinator.explanationViewModel.lyricsSummary == nil)
    }
}

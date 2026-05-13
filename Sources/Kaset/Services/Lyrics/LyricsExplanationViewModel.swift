import Foundation
import FoundationModels
import Observation

// MARK: - LyricsExplanationViewModel

/// Shared AI explanation state for sidebar and floating lyrics presentations.
@MainActor
@Observable
final class LyricsExplanationViewModel {
    var lyricsSummary: LyricsSummary?
    var partialSummary: LyricsSummary.PartiallyGenerated?
    var isExplaining = false
    var showExplanation = false
    var explanationError: String?

    /// Video id for which the visible explanation is valid; clears when the track changes.
    private(set) var explanationVideoId: String?

    private let logger = DiagnosticsLogger.ai

    func resetForNewTrack(videoId _: String?) {
        self.lyricsSummary = nil
        self.partialSummary = nil
        self.showExplanation = false
        self.explanationError = nil
        self.isExplaining = false
        self.explanationVideoId = nil
    }

    func noteExplanationCompletedForTrack(videoId: String) {
        self.explanationVideoId = videoId
    }

    func toggleExplainUI(
        syncedLyricsService: SyncedLyricsService,
        playerService: PlayerService,
        trackVideoId: String?
    ) async {
        if self.showExplanation {
            self.showExplanation = false
        } else if self.lyricsSummary != nil {
            self.showExplanation = true
        } else {
            await self.explainLyrics(
                syncedLyricsService: syncedLyricsService,
                playerService: playerService,
                trackVideoId: trackVideoId
            )
        }
    }

    func explainLyrics(
        syncedLyricsService: SyncedLyricsService,
        playerService: PlayerService,
        trackVideoId: String?
    ) async {
        guard syncedLyricsService.currentLyrics.isAvailable,
              let track = playerService.currentTrack
        else { return }

        let currentVideoId = track.videoId
        guard currentVideoId == trackVideoId else { return }

        self.isExplaining = true
        self.explanationError = nil
        self.partialSummary = nil
        self.logger.info("Explaining lyrics for: \(track.title)")

        let promptVersion = FoundationModelsPromptVersion.current
        let instructions = FoundationModelsPromptLibrary.lyricsExplanationInstructions(
            version: promptVersion
        )
        self.logger.debug("Using Foundation Models lyrics prompt version \(promptVersion.logDescription)")

        guard let session = FoundationModelsService.shared.createAnalysisSession(instructions: instructions) else {
            self.logger.warning("Apple Intelligence not available for lyrics explanation")
            self.explanationError = "Apple Intelligence is not available"
            self.isExplaining = false
            return
        }

        var textToExplain: String
        switch syncedLyricsService.currentLyrics {
        case let .synced(synced):
            textToExplain = synced.lines.map(\.text).joined(separator: "\n")
        case let .plain(plain):
            textToExplain = plain.text
        case .unavailable:
            self.isExplaining = false
            return
        }

        textToExplain = await FoundationModelsService.shared.fittedPromptContent(
            context: "lyrics explanation",
            instructions: instructions,
            content: textToExplain,
            generationSchema: LyricsSummary.generationSchema
        ) { fittedLyrics in
            FoundationModelsPromptLibrary.lyricsExplanationPrompt(
                trackTitle: track.title,
                artistsDisplay: track.artistsDisplay,
                lyrics: fittedLyrics,
                version: promptVersion
            )
        }

        let prompt = FoundationModelsPromptLibrary.lyricsExplanationPrompt(
            trackTitle: track.title,
            artistsDisplay: track.artistsDisplay,
            lyrics: textToExplain,
            version: promptVersion
        )

        do {
            let stream = session.streamResponse(
                to: prompt,
                generating: LyricsSummary.self
            )

            for try await snapshot in stream {
                self.partialSummary = snapshot.content
            }

            if let final = self.partialSummary,
               let mood = final.mood,
               let themes = final.themes,
               let explanation = final.explanation
            {
                self.lyricsSummary = LyricsSummary(
                    themes: themes,
                    mood: mood,
                    explanation: explanation
                )
                self.showExplanation = true
                self.noteExplanationCompletedForTrack(videoId: currentVideoId)
                self.logger.info("Generated lyrics explanation: mood=\(mood), themes=\(themes.joined(separator: ", "))")
            }
        } catch {
            if let message = AIErrorHandler.handleAndMessage(error, context: "lyrics explanation") {
                self.explanationError = message
            }
        }

        self.partialSummary = nil
        self.isExplaining = false
    }

    func retryExplain(
        syncedLyricsService: SyncedLyricsService,
        playerService: PlayerService,
        trackVideoId: String?
    ) async {
        self.explanationError = nil
        await self.explainLyrics(
            syncedLyricsService: syncedLyricsService,
            playerService: playerService,
            trackVideoId: trackVideoId
        )
    }
}

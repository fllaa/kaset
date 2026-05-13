import SwiftUI

// MARK: - LyricsContentView

/// Shared lyrics body (synced / plain / empty / loading) for sidebar and floating presentations.
@available(macOS 26.0, *)
struct LyricsContentView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(SyncedLyricsService.self) private var syncedLyricsService
    @Environment(LyricsPresentationCoordinator.self) private var lyricsCoordinator

    let client: any YTMusicClientProtocol

    /// Width used for synced line typography scaling; use ~280 for sidebar.
    let layoutWidth: CGFloat

    @State private var lastLoadedVideoId: String?
    @State private var isLoadingFallback = false

    var body: some View {
        @Bindable var explanationViewModel = self.lyricsCoordinator.explanationViewModel

        self.lyricsBody(explanationViewModel: explanationViewModel)
            .onChange(of: self.playerService.currentTrack?.videoId) { _, newVideoId in
                if let videoId = newVideoId, videoId != self.lastLoadedVideoId {
                    self.lyricsCoordinator.explanationViewModel.resetForNewTrack(videoId: newVideoId)
                    Task {
                        await self.loadLyrics(for: videoId)
                    }
                }
            }
            .task {
                if let videoId = self.playerService.currentTrack?.videoId {
                    await self.loadLyrics(for: videoId)
                }
            }
    }

    @ViewBuilder
    private func lyricsBody(explanationViewModel: LyricsExplanationViewModel) -> some View {
        if self.playerService.currentTrack == nil {
            self.noTrackPlayingView
        } else if self.syncedLyricsService.isLoading || self.isLoadingFallback {
            self.loadingView
        } else {
            switch self.syncedLyricsService.currentLyrics {
            case let .synced(synced):
                self.syncedLyricsContentView(synced, explanationViewModel: explanationViewModel)
            case let .plain(plain):
                self.plainLyricsContentView(plain, explanationViewModel: explanationViewModel)
            case .unavailable:
                self.noLyricsView
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .frame(width: 20, height: 20)
            Text("Loading lyrics...", comment: "Lyrics panel loading state")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncedLyricsContentView(
        _ synced: SyncedLyrics,
        explanationViewModel: LyricsExplanationViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if explanationViewModel.isExplaining || explanationViewModel.showExplanation || explanationViewModel.explanationError != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if explanationViewModel.isExplaining, let partial = explanationViewModel.partialSummary {
                            self.streamingExplanationSection(partial)
                        } else if explanationViewModel.showExplanation, let summary = explanationViewModel.lyricsSummary {
                            self.explanationSection(summary)
                        } else if let error = explanationViewModel.explanationError {
                            self.errorSection(error, explanationViewModel: explanationViewModel)
                        }
                    }
                }
                .frame(maxHeight: 200)
                Divider().opacity(0.3)
            }

            SyncedLyricsDisplayView(
                lyrics: synced,
                currentTimeMs: self.playerService.currentTimeMs,
                layoutWidth: self.layoutWidth,
                onSeek: { timeMs in
                    Task { await self.playerService.seek(to: Double(timeMs) / 1000.0) }
                }
            )
            .background(Color.clear)
        }
    }

    private func plainLyricsContentView(
        _ lyrics: Lyrics,
        explanationViewModel: LyricsExplanationViewModel
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if explanationViewModel.isExplaining, let partial = explanationViewModel.partialSummary {
                    self.streamingExplanationSection(partial)
                    Divider()
                        .padding(.vertical, 12)
                } else if explanationViewModel.showExplanation, let summary = explanationViewModel.lyricsSummary {
                    self.explanationSection(summary)
                    Divider()
                        .padding(.vertical, 12)
                } else if let error = explanationViewModel.explanationError {
                    self.errorSection(error, explanationViewModel: explanationViewModel)
                    Divider()
                        .padding(.vertical, 12)
                }

                Text(lyrics.text)
                    .font(.system(size: 15, weight: .medium))
                    .lineSpacing(8)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)

                if let source = lyrics.source {
                    Divider()
                        .padding(.horizontal, 16)

                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private func explanationSection(_ summary: LyricsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(.pink)
                Text(summary.mood.capitalized)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(summary.themes, id: \.self) { theme in
                        Text(theme)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.purple.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
            }

            Text(summary.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(.purple.opacity(0.05))
    }

    private func streamingExplanationSection(_ partial: LyricsSummary.PartiallyGenerated) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(.pink)
                if let mood = partial.mood {
                    Text(mood.capitalized)
                        .font(.subheadline.weight(.medium))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if let themes = partial.themes, !themes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(themes, id: \.self) { theme in
                            Text(theme)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.purple.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if let explanation = partial.explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                    Text("Analyzing...")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(.purple.opacity(0.05))
    }

    private func errorSection(_ message: String, explanationViewModel: LyricsExplanationViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") {
                Task {
                    await explanationViewModel.retryExplain(
                        syncedLyricsService: self.syncedLyricsService,
                        playerService: self.playerService,
                        trackVideoId: self.playerService.currentTrack?.videoId
                    )
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .background(.orange.opacity(0.05))
    }

    private var noLyricsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No Lyrics Available")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("There aren't any lyrics available for this song.", comment: "Lyrics unavailable message")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noTrackPlayingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No Song Playing")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Play a song to view its lyrics here.", comment: "No song playing lyrics message")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadLyrics(for videoId: String) async {
        self.lastLoadedVideoId = videoId
        self.isLoadingFallback = false

        guard let track = self.playerService.currentTrack else { return }
        guard track.videoId == videoId else { return }

        let info = LyricsSearchInfo(
            title: track.title,
            artist: track.artistsDisplay,
            album: track.album?.title,
            duration: track.duration,
            videoId: track.videoId
        )

        if SettingsManager.shared.syncedLyricsEnabled {
            await self.syncedLyricsService.fetchLyrics(for: info)
        } else {
            self.syncedLyricsService.currentLyrics = .unavailable
            self.syncedLyricsService.activeProvider = nil
        }

        guard self.lastLoadedVideoId == videoId else { return }
        guard self.playerService.currentTrack?.videoId == videoId else { return }

        if case .unavailable = self.syncedLyricsService.currentLyrics {
            self.isLoadingFallback = true
            defer {
                if self.lastLoadedVideoId == videoId {
                    self.isLoadingFallback = false
                }
            }

            do {
                let fetchedLyrics = try await self.client.getLyrics(videoId: videoId)
                if self.lastLoadedVideoId == videoId,
                   self.playerService.currentTrack?.videoId == videoId
                {
                    self.syncedLyricsService.fallbackToPlainLyrics(fetchedLyrics, videoId: videoId)
                }
            } catch {
                DiagnosticsLogger.api.error("Failed to load plain lyrics fallback: \(error.localizedDescription)")
            }
        }
    }
}

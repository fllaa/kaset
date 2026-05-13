import SwiftUI

// MARK: - SidebarLyricsView

/// Fixed-width sidebar glass panel with lyrics and pop-out control.
@available(macOS 26.0, *)
struct SidebarLyricsView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(SyncedLyricsService.self) private var syncedLyricsService
    @Environment(LyricsPresentationCoordinator.self) private var lyricsCoordinator

    let client: any YTMusicClientProtocol

    @Namespace private var lyricsNamespace

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                self.headerView
                Divider()
                    .opacity(0.3)
                LyricsContentView(client: self.client, layoutWidth: 280)
            }
            .frame(width: 280)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .glassEffectID("lyricsPanel", in: self.lyricsNamespace)
        }
        .glassEffectTransition(.materialize)
    }

    private var headerView: some View {
        HStack {
            Text("Lyrics")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()

            Button {
                self.lyricsCoordinator.popOut()
            } label: {
                Image(systemName: "pip.enter")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(String(localized: "Pop Out Lyrics"))
            .accessibilityLabel(String(localized: "Pop Out Lyrics"))

            if self.syncedLyricsService.currentLyrics.isAvailable {
                self.explainButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var explainButton: some View {
        Button {
            Task {
                await self.lyricsCoordinator.explanationViewModel.toggleExplainUI(
                    syncedLyricsService: self.syncedLyricsService,
                    playerService: self.playerService,
                    trackVideoId: self.playerService.currentTrack?.videoId
                )
            }
        } label: {
            if self.lyricsCoordinator.explanationViewModel.isExplaining {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)
            } else {
                Image(systemName: self.lyricsCoordinator.explanationViewModel.showExplanation ? "sparkles.rectangle.stack.fill" : "sparkles")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(self.lyricsCoordinator.explanationViewModel.showExplanation ? .purple : .secondary)
        .help(String(localized: "Explain lyrics with AI"))
        .accessibilityLabel(
            self.lyricsCoordinator.explanationViewModel.showExplanation
                ? String(localized: "Hide lyrics explanation")
                : String(localized: "Explain lyrics with AI")
        )
        .requiresIntelligence()
        .disabled(self.lyricsCoordinator.explanationViewModel.isExplaining)
    }
}

// MARK: - FloatingLyricsWindow

/// Resizable floating window hosting ``LyricsContentView``.
@available(macOS 26.0, *)
struct FloatingLyricsWindow: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(SyncedLyricsService.self) private var syncedLyricsService
    @Environment(LyricsPresentationCoordinator.self) private var lyricsCoordinator

    let client: any YTMusicClientProtocol

    @Namespace private var lyricsNamespace

    var body: some View {
        GeometryReader { geo in
            GlassEffectContainer(spacing: 0) {
                VStack(spacing: 0) {
                    self.headerView(containerWidth: geo.size.width)
                    Divider()
                        .opacity(0.3)
                    LyricsContentView(client: self.client, layoutWidth: geo.size.width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                .glassEffectID("lyricsFloatingPanel", in: self.lyricsNamespace)
            }
            .glassEffectTransition(.materialize)
            .padding(.top, 8)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .accessibilityIdentifier(AccessibilityID.LyricsWindow.container)
    }

    private var floatingPinned: Bool {
        if case let .floating(pinned) = self.lyricsCoordinator.mode {
            pinned
        } else {
            true
        }
    }

    private func headerView(containerWidth: CGFloat) -> some View {
        let isCompact = containerWidth < 260
        return HStack(spacing: 8) {
            Text("Lyrics")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.leading, 12)

            Spacer(minLength: 0)

            if isCompact {
                Menu {
                    Button {
                        self.lyricsCoordinator.togglePinned()
                    } label: {
                        Label(
                            self.floatingPinned ? String(localized: "Unpin Window") : String(localized: "Pin to Top"),
                            systemImage: self.floatingPinned ? "pin.slash" : "pin.fill"
                        )
                    }

                    Button {
                        self.lyricsCoordinator.popIn()
                    } label: {
                        Label(String(localized: "Return to Sidebar"), systemImage: "pip.exit")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28, height: 28)
                .fixedSize()

                if self.syncedLyricsService.currentLyrics.isAvailable {
                    self.floatingExplainButton
                }
            } else {
                self.pinToggleButton
                if self.syncedLyricsService.currentLyrics.isAvailable {
                    self.floatingExplainButton
                }
                Button {
                    self.lyricsCoordinator.popIn()
                } label: {
                    Image(systemName: "pip.exit")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "Return to Sidebar"))
                .accessibilityLabel(String(localized: "Return to Sidebar"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var pinToggleButton: some View {
        if case let .floating(pinned) = self.lyricsCoordinator.mode {
            Button {
                self.lyricsCoordinator.togglePinned()
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin.slash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(pinned ? String(localized: "Unpin Window") : String(localized: "Pin to Top"))
            .accessibilityLabel(pinned ? String(localized: "Unpin Window") : String(localized: "Pin to Top"))
        }
    }

    private var floatingExplainButton: some View {
        Button {
            Task {
                await self.lyricsCoordinator.explanationViewModel.toggleExplainUI(
                    syncedLyricsService: self.syncedLyricsService,
                    playerService: self.playerService,
                    trackVideoId: self.playerService.currentTrack?.videoId
                )
            }
        } label: {
            if self.lyricsCoordinator.explanationViewModel.isExplaining {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)
            } else {
                Image(systemName: self.lyricsCoordinator.explanationViewModel.showExplanation ? "sparkles.rectangle.stack.fill" : "sparkles")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(self.lyricsCoordinator.explanationViewModel.showExplanation ? .purple : .secondary)
        .help(String(localized: "Explain lyrics with AI"))
        .accessibilityLabel(
            self.lyricsCoordinator.explanationViewModel.showExplanation
                ? String(localized: "Hide lyrics explanation")
                : String(localized: "Explain lyrics with AI")
        )
        .requiresIntelligence()
        .disabled(self.lyricsCoordinator.explanationViewModel.isExplaining)
    }
}

// MARK: - LyricsView

/// Backward-compatible name for the sidebar lyrics panel.
@available(macOS 26.0, *)
typealias LyricsView = SidebarLyricsView

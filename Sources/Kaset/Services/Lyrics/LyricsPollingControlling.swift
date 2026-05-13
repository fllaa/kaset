import Foundation

// MARK: - LyricsPollingControlling

/// Abstraction over WebView lyrics time polling for ``LyricsPresentationCoordinator`` and tests.
@MainActor
protocol LyricsPollingControlling: AnyObject {
    func startLyricsPoll()
    func stopLyricsPoll()
}

// MARK: - SingletonLyricsPollingAdapter

/// Forwards polling calls to the hidden playback WebView.
@MainActor
final class SingletonLyricsPollingAdapter: LyricsPollingControlling {
    static let shared = SingletonLyricsPollingAdapter()

    private init() {}

    func startLyricsPoll() {
        SingletonPlayerWebView.shared.startLyricsPoll()
    }

    func stopLyricsPoll() {
        SingletonPlayerWebView.shared.stopLyricsPoll()
    }
}

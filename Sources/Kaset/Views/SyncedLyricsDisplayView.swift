import SwiftUI

// MARK: - SyncedLyricsLineFontMetrics

private struct SyncedLyricsLineFontMetrics {
    let currentLine: CGFloat
    let otherLine: CGFloat
    let currentRoman: CGFloat
    let otherRoman: CGFloat
}

// MARK: - SyncedLyricsDisplayView

struct SyncedLyricsDisplayView: View {
    let lyrics: SyncedLyrics
    let currentTimeMs: Int
    var layoutWidth: CGFloat = 280
    let onSeek: (Int) -> Void

    @State private var currentLineId: UUID?

    private var metrics: SyncedLyricsLineFontMetrics {
        Self.lineMetrics(width: self.layoutWidth)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .center, spacing: 20) {
                    Spacer().frame(height: 150)

                    ForEach(self.lyrics.lines) { line in
                        let status = self.currentStatus(for: line)
                        SyncedLineView(
                            line: line,
                            status: status,
                            currentFontSize: self.metrics.currentLine,
                            otherFontSize: self.metrics.otherLine,
                            currentRomanFontSize: self.metrics.currentRoman,
                            otherRomanFontSize: self.metrics.otherRoman,
                            onTap: { self.onSeek(line.timeInMs) }
                        )
                        .id(line.id)
                    }

                    Spacer().frame(height: 150)
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .onChange(of: self.currentTimeMs) { _, newTimeMs in
                if let currentIdx = lyrics.currentLineIndex(at: newTimeMs) {
                    let newId = self.lyrics.lines[currentIdx].id
                    if newId != self.currentLineId {
                        self.currentLineId = newId
                        withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func currentStatus(for line: SyncedLyricLine) -> SyncedLyrics.LineStatus {
        if line.timeInMs > self.currentTimeMs { return .upcoming }
        if self.currentTimeMs - line.timeInMs >= line.duration, line.duration > 0 { return .previous }
        return .current
    }

    private static func lineMetrics(width: CGFloat) -> SyncedLyricsLineFontMetrics {
        let current: CGFloat
        let other: CGFloat
        if width < 260 {
            current = 22
            other = 17
        } else if width < 420 {
            current = 26
            other = 20
        } else {
            current = 30
            other = 22
        }
        let curRom = max(14, current * (18.0 / 26.0))
        let othRom = max(12, other * (14.0 / 20.0))
        return SyncedLyricsLineFontMetrics(
            currentLine: current,
            otherLine: other,
            currentRoman: curRom,
            otherRoman: othRom
        )
    }
}

// MARK: - SyncedLineView

struct SyncedLineView: View {
    let line: SyncedLyricLine
    let status: SyncedLyrics.LineStatus
    var currentFontSize: CGFloat = 26
    var otherFontSize: CGFloat = 20
    var currentRomanFontSize: CGFloat = 18
    var otherRomanFontSize: CGFloat = 14
    let onTap: () -> Void

    private var animation: Animation {
        Animation.spring(response: 0.4, dampingFraction: 0.8)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(self.line.text.isEmpty ? "♪" : self.line.text)
                .font(.system(
                    size: self.status == .current ? self.currentFontSize : self.otherFontSize,
                    weight: self.status == .current ? .bold : .medium,
                    design: .default
                ))
                .foregroundStyle(self.status == .current ? .primary : (self.status == .previous ? .secondary : .tertiary))

            if let romaji = self.line.romanizedText {
                Text(romaji)
                    .font(.system(
                        size: self.status == .current ? self.currentRomanFontSize : self.otherRomanFontSize,
                        weight: .regular,
                        design: .default
                    ))
                    .italic()
                    .foregroundStyle(self.status == .current ? .secondary : .tertiary)
                    .opacity(self.status == .current ? 0.8 : 0.5)
            }
        }
        .opacity(self.status == .current ? 1.0 : (self.status == .previous ? 0.6 : 0.4))
        .scaleEffect(self.status == .current ? 1.05 : 1.0)
        .blur(radius: self.status == .current ? 0 : 0.5)
        .animation(self.animation, value: self.status)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .contentShape(Rectangle())
        .onTapGesture {
            self.onTap()
        }
        .padding(.vertical, 4)
    }
}

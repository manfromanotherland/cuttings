// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import SwiftUI

/// A video card that keeps its local poster in the layout while playing muted
/// video above it. The player is prepared on first entry, released offscreen,
/// and recreated at its saved playback position when the card returns.
struct AutoplayVideoCard: View {
    let row: ReadingRow
    let libraryURL: URL?
    let cardSize: CGSize
    let viewportSize: CGSize
    let playbackPositions: VideoPlaybackPositionStore
    var maxPixel: CGFloat = 800
    var autoplayEnabled = true
    var reduceMotion = false
    var scenePhase: ScenePhase = .active

    @State private var isInViewport = false
    @State private var loadedMediaKey: String?
    @State private var playback: CardVideoPlayback?

    var body: some View {
        LocalReadingImage(
            row: row,
            libraryURL: libraryURL,
            fallbackAspectRatio: row.standaloneMediaAspectRatio ?? 16 / 9,
            maxPixel: maxPixel,
            contentMode: .fit
        )
        .frame(width: cardSize.width, height: cardSize.height)
        .clipped()
        .overlay {
            if let playback {
                CardVideoPlayerLayer(player: playback.player)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .onGeometryChange(for: Bool.self) { proxy in
            VideoCardViewport.containsVisibleArea(
                of: proxy.frame(in: .scrollView(axis: .vertical)),
                in: CGRect(origin: .zero, size: viewportSize)
            )
        } action: { visible in
            isInViewport = visible
        }
        .task(id: playbackTaskID) {
            await synchronizePlayback()
        }
        .onDisappear {
            isInViewport = false
            pausePlayback()
            releasePlayback()
        }
    }

    private var shouldAutoplay: Bool {
        autoplayEnabled
            && isInViewport
            && !reduceMotion
            && scenePhase == .active
    }

    private var playbackTaskID: String {
        "\(mediaKey):autoplay=\(shouldAutoplay)"
    }

    private var mediaKey: String {
        "\(libraryURL?.path ?? ""):\(row.id):\(row.mediaUrl ?? "")"
    }

    @MainActor
    private func synchronizePlayback() async {
        let requestedMediaKey = mediaKey
        if loadedMediaKey != requestedMediaKey {
            pausePlayback(mediaKey: loadedMediaKey)
            releasePlayback()
            loadedMediaKey = requestedMediaKey
        }

        guard shouldAutoplay else {
            pausePlayback()
            releasePlayback()
            return
        }

        if let playback {
            playback.player.play()
            return
        }

        await loadAndPlay(requestedMediaKey: requestedMediaKey)
    }

    @MainActor
    private func loadAndPlay(requestedMediaKey: String) async {
        guard let url = playbackURL else { return }
        guard (try? url.resourceValues(
            forKeys: [.isRegularFileKey]
        ).isRegularFile) == true else { return }

        let asset = AVURLAsset(url: url)
        do {
            guard try await asset.load(.isPlayable),
                  try await !(asset.loadTracks(withMediaType: .video)).isEmpty,
                  !Task.isCancelled
            else { return }

            let loadedPlayback = CardVideoPlayback(
                item: AVPlayerItem(asset: asset)
            )
            guard !Task.isCancelled,
                  loadedMediaKey == requestedMediaKey,
                  shouldAutoplay
            else {
                loadedPlayback.stop()
                return
            }

            playback = loadedPlayback
            restorePosition(of: loadedPlayback.player, mediaKey: requestedMediaKey)
            loadedPlayback.player.play()
        } catch {
            // The saved poster remains the card's offline/failure presentation.
        }
    }

    @MainActor
    private func restorePosition(of player: AVPlayer, mediaKey: String) {
        guard let position = playbackPositions.position(for: mediaKey) else { return }
        player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    @MainActor
    private func pausePlayback(mediaKey: String? = nil) {
        guard let playback else { return }
        playback.player.pause()
        guard let mediaKey = mediaKey ?? loadedMediaKey else { return }
        playbackPositions.save(playback.player.currentTime(), for: mediaKey)
    }

    @MainActor
    private func releasePlayback() {
        playback?.stop()
        playback = nil
    }

    private var playbackURL: URL? {
        guard let reference = row.localVideoAssetReference else { return nil }
        let baseURL = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL,
            readingID: row.id
        )
        return AssetImageLoader.localURL(source: reference, assetBaseURL: baseURL)
    }
}

@MainActor
final class VideoPlaybackPositionStore {
    private var positions: [String: CMTime] = [:]

    func position(for mediaKey: String) -> CMTime? {
        positions[mediaKey]
    }

    func save(_ position: CMTime, for mediaKey: String) {
        let seconds = position.seconds
        guard seconds.isFinite, seconds > 0 else { return }
        positions[mediaKey] = position
    }
}

@MainActor
private final class CardVideoPlayback {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper

    init(item: AVPlayerItem) {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player
        looper = AVPlayerLooper(player: player, templateItem: item)
    }

    func stop() {
        player.pause()
        player.removeAllItems()
    }
}

private struct CardVideoPlayerLayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context _: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerView, context _: Context) {
        view.playerLayer.player = player
    }

    static func dismantleNSView(_ view: PlayerView, coordinator _: Void) {
        view.playerLayer.player = nil
    }

    final class PlayerView: NSView {
        var playerLayer: AVPlayerLayer {
            // `makeBackingLayer()` is the sole layer factory for this view.
            layer as! AVPlayerLayer // swiftlint:disable:this force_cast
        }

        override func makeBackingLayer() -> CALayer {
            let layer = AVPlayerLayer()
            layer.videoGravity = .resizeAspect
            return layer
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

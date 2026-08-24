// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import AVKit
import SwiftUI

/// Offline playback for source-less videos imported from Finder or the
/// pasteboard. Core persists the movie as
/// `cuttings-asset:assets/<content-hash>.<ext>`; only that explicit prefix and
/// the existing single-file asset-path rules are accepted here. Browser video
/// identities remain source-page cards and never enter this view.
struct LocalReadingVideo: View {
    let row: ReadingRow
    let libraryURL: URL?

    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.10)

            if let player {
                VideoPlayer(player: player)
                    .accessibilityLabel("Video: \(row.displayTitle)")
                    .accessibilityIdentifier(A11y.Detail.videoPlayer)
            } else if failed {
                ContentUnavailableView(
                    "Video unavailable",
                    systemImage: "play.slash",
                    description: Text("The saved video file could not be played.")
                )
                .foregroundStyle(.white)
                .accessibilityIdentifier(A11y.Detail.videoUnavailable)
            } else {
                ProgressView("Loading video…")
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .task(id: loadKey) {
            await load()
        }
        .onDisappear {
            releasePlayer()
        }
    }

    private var loadKey: String {
        "\(row.id):\(row.mediaUrl ?? "")"
    }

    @MainActor
    private func load() async {
        releasePlayer()
        failed = false

        guard let url = localVideoURL,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else {
            failed = true
            return
        }

        let asset = AVURLAsset(url: url)
        do {
            guard try await asset.load(.isPlayable),
                  try await !(asset.loadTracks(withMediaType: .video)).isEmpty,
                  !Task.isCancelled
            else {
                failed = true
                return
            }
            player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }

    @MainActor
    private func releasePlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private var localVideoURL: URL? {
        guard let reference = row.localVideoAssetReference else { return nil }
        let baseURL = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL, readingID: row.id
        )
        return AssetImageLoader.localURL(source: reference, assetBaseURL: baseURL)
    }
}

extension ReadingRow {
    private static let localVideoAssetPrefix = "cuttings-asset:"

    var localVideoAssetReference: String? {
        guard kind == .video,
              let mediaUrl,
              mediaUrl.hasPrefix(Self.localVideoAssetPrefix)
        else {
            return nil
        }
        return String(mediaUrl.dropFirst(Self.localVideoAssetPrefix.count))
    }

    var hasLocalVideoAsset: Bool {
        localVideoAssetReference != nil
    }
}

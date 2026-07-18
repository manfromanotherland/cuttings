// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// End-of-article rating: shown after the body so it surfaces when the
/// reader reaches the end — rating is a judgment formed once you've read.
struct RatingFooter: View {
    let row: FfiReadingRow

    /// Called with the new rating (0 clears back to unrated). The parent owns
    /// the optimistic swap and the reconcile after the write.
    let onRate: (UInt8) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Rate this article")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ratingControl
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private var ratingControl: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    // Clicking the current rating clears it back to unrated.
                    let target = UInt8(star)
                    onRate(row.rating == target ? 0 : target)
                } label: {
                    Image(systemName: UInt8(star) <= row.rating ? "star.fill" : "star")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Rate \(star) star\(star == 1 ? "" : "s")")
                .accessibilityLabel("Rate \(star) star\(star == 1 ? "" : "s")")
                .accessibilityIdentifier(A11y.RatingFooter.star(star))
            }
        }
        .font(.title3)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The quick appearance controls behind the gear at the foot of the sidebar:
/// theme, reader font, and the reader's size, width, and line height — the same
/// preferences Settings › Typography writes, reachable without leaving the
/// window. Split out of `SidebarView` to keep both files a readable length.
///
/// Width and line height are shown **icon-only** here (the popover is 240 pt
/// wide and has no room for five spelled-out width labels); Settings is the
/// place that names every option in words.
struct AppearancePopoverView: View {
    @AppStorage("appearanceMode", store: AppDefaults.store) private var appearanceMode: AppearanceMode = .system
    @AppStorage("readerFont", store: AppDefaults.store) private var readerFont: ReaderFont = .system
    @AppStorage("readerFontSize", store: AppDefaults.store) private var readerFontSize: ReaderFontSize = .medium
    @AppStorage("readerWidth", store: AppDefaults.store) private var readerWidth: ReaderWidth = .medium
    @AppStorage("readerLineHeight", store: AppDefaults.store) private var readerLineHeight: ReaderLineHeight = .normal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.headline)

            // Theme mode picker
            HStack(spacing: 4) {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        appearanceMode = mode
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14))
                            Text(mode.label)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            appearanceMode == mode
                                ? AnyShapeStyle(.secondary.opacity(0.25)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.Sidebar.themeButton(mode.id))
                    // Announce the active theme (the selection is otherwise only a
                    // background tint) — for VoiceOver and so tests can read it back.
                    .accessibilityAddTraits(appearanceMode == mode ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            // Font picker
            HStack {
                Text("Font")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Font", selection: $readerFont) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.label).tag(font)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.regular)
                .accessibilityIdentifier(A11y.Sidebar.fontPicker)
            }

            // Font size slider
            HStack(spacing: 8) {
                Text("Aa")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(
                    value: fontSizeBinding, in: 0 ... Double(ReaderFontSize.allCases.count - 1),
                    step: 1
                )
                .accessibilityIdentifier(A11y.Sidebar.fontSizeSlider)
                Text("Aa")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }

            // Reader width slider — same shape as the font-size slider above, with
            // narrow/wide end caps instead of small/large "Aa".
            HStack(spacing: 8) {
                endCap(ReaderWidth.narrowIcon)
                Slider(
                    value: widthBinding, in: 0 ... Double(ReaderWidth.allCases.count - 1),
                    step: 1
                )
                .accessibilityIdentifier(A11y.Sidebar.widthSlider)
                .accessibilityLabel("Width")
                .help("Width: \(readerWidth.label)")
                endCap(ReaderWidth.wideIcon)
            }

            // Line height slider — same shape again, capped with vertical
            // compress/expand glyphs.
            HStack(spacing: 8) {
                endCap(ReaderLineHeight.tightIcon)
                Slider(
                    value: lineHeightBinding, in: 0 ... Double(ReaderLineHeight.allCases.count - 1),
                    step: 1
                )
                .accessibilityIdentifier(A11y.Sidebar.lineHeightSlider)
                .accessibilityLabel("Line Height")
                .help("Line height: \(readerLineHeight.label)")
                endCap(ReaderLineHeight.looseIcon)
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    /// A muted glyph capping one end of a slider.
    private func endCap(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var fontSizeBinding: Binding<Double> {
        Binding {
            Double(ReaderFontSize.allCases.firstIndex(of: readerFontSize) ?? 1)
        } set: { val in
            let idx = min(max(Int(val.rounded()), 0), ReaderFontSize.allCases.count - 1)
            readerFontSize = ReaderFontSize.allCases[idx]
        }
    }

    /// Slider position as an index into `ReaderWidth.allCases` (which is ordered
    /// narrow → wide), clamped on write so a drag past either end can't crash.
    /// Defaults to Medium's index if the stored value somehow isn't a known case.
    private var widthBinding: Binding<Double> {
        Binding {
            Double(ReaderWidth.allCases.firstIndex(of: readerWidth)
                ?? ReaderWidth.allCases.firstIndex(of: .medium) ?? 0)
        } set: { val in
            let idx = min(max(Int(val.rounded()), 0), ReaderWidth.allCases.count - 1)
            readerWidth = ReaderWidth.allCases[idx]
        }
    }

    /// Slider position as an index into `ReaderLineHeight.allCases` (ordered
    /// tight → loose), clamped on write. Falls back to Normal's index if the
    /// stored value isn't a known case.
    private var lineHeightBinding: Binding<Double> {
        Binding {
            Double(ReaderLineHeight.allCases.firstIndex(of: readerLineHeight)
                ?? ReaderLineHeight.allCases.firstIndex(of: .normal) ?? 0)
        } set: { val in
            let idx = min(max(Int(val.rounded()), 0), ReaderLineHeight.allCases.count - 1)
            readerLineHeight = ReaderLineHeight.allCases[idx]
        }
    }
}

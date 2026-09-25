// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct InspectorSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.08)))
        }
    }
}

struct InspectorPill: View {
    let title: String
    var symbol: String?
    var action: () -> Void

    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                button.buttonStyle(.glass)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .font(.system(size: 12, weight: .medium))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).lineLimit(1).truncationMode(.middle).frame(maxWidth: 232)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
        }
    }
}

enum InspectorTab: String, CaseIterable { case discover = "Discover", details = "Details" }

struct InspectorTabs: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: InspectorTab
    @Namespace private var glassSelection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(InspectorTab.allCases, id: \.self) { tab in
                Button { selection = tab } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: selection == tab ? .semibold : .medium))
                        .foregroundStyle(selection == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == tab {
                        selectionSurface.matchedGeometryEffect(id: "selection", in: glassSelection)
                    }
                }
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: selection)
        .onKeyPress(.leftArrow) { selection = .discover; return .handled }
        .onKeyPress(.rightArrow) { selection = .details; return .handled }
        .accessibilityIdentifier(A11y.Inspector.tabs)
    }

    @ViewBuilder
    private var selectionSurface: some View {
        if #available(macOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule().fill(.regularMaterial).overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
        }
    }
}

struct InspectorSwatch: View {
    let color: InspectorColor
    var action: () -> Void

    private var fill: Color { Color(red: color.red, green: color.green, blue: color.blue) }

    var body: some View {
        Button(action: action) {
            ZStack {
                if #available(macOS 26.0, *) {
                    Circle().fill(.clear).frame(width: 34, height: 34)
                        .glassEffect(.clear.interactive(), in: Circle())
                }
                Circle().fill(fill).frame(width: 30, height: 30)
                    .overlay {
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.65), .black.opacity(0.12)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    }
            }
            .frame(width: 36, height: 38)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Search similar colours · \(color.hex)")
        .accessibilityLabel("Search colours similar to \(color.hex)")
        .accessibilityIdentifier(A11y.Inspector.colorPrefix + color.hex)
    }
}

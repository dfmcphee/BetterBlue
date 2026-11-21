//
//  NLinkWidgets.swift
//  Widget
//
//  The small and medium Home Screen widgets: car status beside a grid
//  of controls, on a dark surface. Orange marks the control that matters
//  right now (unlocked car, climate or charge running).
//

import AppIntents
import SwiftUI
import WidgetKit

private enum NLinkWidgetStyle {
    static let accent = Color(red: 234 / 255, green: 74 / 255, blue: 42 / 255)
    static let onAccent = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let padding: CGFloat = 16
    static let tileHeight: CGFloat = 44
    /// Widget corner (36) minus the padding, so the curves run parallel.
    static let tileRadius: CGFloat = 20
}

/// The default widget background, dark in both system appearances.
/// Widgets can't show the wallpaper through their background, so this
/// is an opaque dark sheen with a light rim.
struct NLinkDarkBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 34 / 255, green: 34 / 255, blue: 40 / 255),
                    Color(red: 13 / 255, green: 13 / 255, blue: 17 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            ContainerRelativeShape().strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

struct NLinkSmallWidget: View {
    let vehicle: VehicleEntity
    let buttons: [ConfiguredWidgetButton]
    let textColor: Color
    let showPercent: Bool

    private var percentage: Double { vehicle.batteryPercentage ?? 0 }

    private var statusText: String {
        guard showPercent, vehicle.batteryPercentage != nil else { return vehicle.rangeText }
        return "\(vehicle.rangeText) · \(Int(percentage.rounded()))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chargeBar.padding(.top, 5)
            Spacer(minLength: 8)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 8
            ) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    tile(button)
                }
            }
        }
        .padding(NLinkWidgetStyle.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(vehicle.displayName.uppercased())
                .font(.system(size: 20, weight: .bold).width(.condensed))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            if vehicle.isCharging == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NLinkWidgetStyle.accent)
                    .widgetAccentable()
                    .accessibilityLabel("Charging")
            }
            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(textColor.opacity(0.78))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: 20)
    }

    private var chargeBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(textColor.opacity(0.16))
                Capsule()
                    .fill(NLinkWidgetStyle.accent)
                    .widgetAccentable()
                    .frame(width: geo.size.width * min(max(percentage / 100, 0), 1))
                if let target = vehicle.targetStateOfCharge {
                    Rectangle()
                        .fill(textColor)
                        .frame(width: 2, height: 7)
                        .offset(x: geo.size.width * CGFloat(target) / 100 - 1)
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ button: ConfiguredWidgetButton) -> some View {
        if let intent = button.action.makeIntent(for: vehicle) {
            Button(intent: intent) {
                Image(systemName: button.action.displayIcon(for: vehicle))
                    .font(.system(size: 18, weight: .semibold))
                    .accessibilityLabel(button.action.kind.defaultTitle)
            }
            .buttonStyle(NLinkTileStyle(emphasis: button.emphasis(for: vehicle), textColor: textColor))
        }
    }
}

extension ConfiguredWidgetButton {
    /// Reflects the last known status only. Every tile stays tappable,
    /// because that status can be out of date.
    func emphasis(for vehicle: VehicleEntity) -> NLinkTileStyle.Emphasis {
        if colorName != nil { return .custom(color(for: vehicle)) }
        switch action.kind {
        case .lock: return state(active: vehicle.isLocked.map { !$0 }, idle: vehicle.isLocked)
        case .unlock: return state(active: nil, idle: vehicle.isLocked.map { !$0 })
        case .startClimate: return state(active: nil, idle: vehicle.isClimateOn)
        case .stopClimate: return state(active: vehicle.isClimateOn, idle: vehicle.isClimateOn.map { !$0 })
        case .startCharge: return state(active: nil, idle: vehicle.isCharging)
        case .stopCharge: return state(active: vehicle.isCharging, idle: vehicle.isCharging.map { !$0 })
        case .none: return .normal
        }
    }

    private func state(active: Bool?, idle: Bool?) -> NLinkTileStyle.Emphasis {
        if active == true { return .active }
        if idle == true { return .idle }
        return .normal
    }
}

struct NLinkTileStyle: ButtonStyle {
    enum Emphasis {
        case normal, active, idle
        case custom(Color)
    }

    let emphasis: Emphasis
    let textColor: Color

    private var fill: Color {
        switch emphasis {
        case .normal: textColor.opacity(0.13)
        case .active: NLinkWidgetStyle.accent
        case .idle: textColor.opacity(0.05)
        case let .custom(color): color.opacity(0.6)
        }
    }

    private var foreground: Color {
        switch emphasis {
        case .normal: textColor
        case .active: NLinkWidgetStyle.onAccent
        case .idle: textColor.opacity(0.62)
        case .custom: .white
        }
    }

    private var rim: Color {
        switch emphasis {
        case .normal: textColor.opacity(0.12)
        case .idle: textColor.opacity(0.07)
        case .active, .custom: .clear
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: NLinkWidgetStyle.tileRadius, style: .continuous)
        return configuration.label
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: NLinkWidgetStyle.tileHeight)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(rim, lineWidth: 1))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct NLinkMediumWidget: View {
    let vehicle: VehicleEntity
    let buttons: [ConfiguredWidgetButton]
    let textColor: Color
    let showPercent: Bool

    private static let ringSize: CGFloat = 112

    private var percentage: Double { vehicle.batteryPercentage ?? 0 }

    var body: some View {
        HStack(spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 8) {
                header
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 8
                ) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                        tile(button)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(NLinkWidgetStyle.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ring

    private var ring: some View {
        let lineWidth = Self.ringSize * 0.09
        let fraction = min(max(percentage / 100, 0), 1)
        return ZStack {
            Circle()
                .stroke(textColor.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(NLinkWidgetStyle.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            if let target = vehicle.targetStateOfCharge {
                Capsule()
                    .fill(textColor)
                    .frame(width: 2.5, height: lineWidth + 2)
                    .offset(y: -(Self.ringSize - lineWidth) / 2)
                    .rotationEffect(.degrees(Double(target) / 100 * 360))
            }
            VStack(spacing: 0) {
                if showPercent, vehicle.batteryPercentage != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(Int(percentage.rounded()))")
                            .font(.system(size: 38, weight: .bold).width(.condensed))
                        Text("%")
                            .font(.system(size: 18, weight: .semibold).width(.condensed))
                            .foregroundStyle(textColor.opacity(0.78))
                    }
                    .foregroundStyle(textColor)
                    Text(vehicle.rangeText)
                        .font(.system(size: 12))
                        .foregroundStyle(textColor.opacity(0.78))
                } else {
                    Text(vehicle.rangeText)
                        .font(.system(size: 22, weight: .bold).width(.condensed))
                        .foregroundStyle(textColor)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, lineWidth + 4)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ringAccessibilityLabel)
    }

    private var ringAccessibilityLabel: String {
        var parts: [String] = []
        if vehicle.batteryPercentage != nil { parts.append("\(Int(percentage.rounded())) percent") }
        parts.append(vehicle.rangeText)
        if let target = vehicle.targetStateOfCharge { parts.append("limit \(target) percent") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(vehicle.displayName.uppercased())
                .font(.system(size: 20, weight: .bold).width(.condensed))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(statusLine)
                .font(.system(size: 12))
                .foregroundStyle(textColor.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    /// "Locked · Climate off · 6:48 AM". While a command sent from a
    /// widget is waiting on the next status refresh, that shows instead.
    /// Times are absolute because widget text is frozen between reloads.
    private var statusLine: String {
        if let pending = pendingCommand {
            return "\(pending.command) sent \(pending.date.formatted(date: .omitted, time: .shortened))"
        }
        var parts: [String] = []
        if vehicle.isCharging == true { parts.append("Charging") }
        if let locked = vehicle.isLocked { parts.append(locked ? "Locked" : "Unlocked") }
        if let climate = vehicle.isClimateOn { parts.append(climate ? "Climate on" : "Climate off") }
        parts.append(updatedTime)
        return parts.joined(separator: " · ")
    }

    private var pendingCommand: (command: String, date: Date)? {
        guard let latest = WidgetCommandStatus.latest(vin: vehicle.vin) else { return nil }
        let lastUpdated = vehicle.lastUpdated ?? .distantPast
        guard latest.date > lastUpdated,
              Date().timeIntervalSince(latest.date) < 30 * 60 else { return nil }
        return latest
    }

    private var updatedTime: String {
        let date = vehicle.timestamp
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Controls

    @ViewBuilder
    private func tile(_ button: ConfiguredWidgetButton) -> some View {
        if let intent = button.action.makeIntent(for: vehicle) {
            Button(intent: intent) {
                HStack(spacing: 5) {
                    Image(systemName: button.action.displayIcon(for: vehicle))
                        .font(.system(size: 14, weight: .semibold))
                    Text(button.action.kind.tileTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(NLinkTileStyle(emphasis: button.emphasis(for: vehicle), textColor: textColor))
            .accessibilityLabel(button.action.kind.defaultTitle)
        }
    }
}

private extension WidgetActionKind {
    /// Fits a medium-widget tile; the icon says which system it acts on.
    var tileTitle: String {
        switch self {
        case .startClimate: "Start"
        case .startCharge: "Charge"
        case .stopClimate, .stopCharge: "Stop"
        default: defaultTitle
        }
    }
}

import ActivityKit
import AppIntents
import BetterBlueKit
import SwiftUI
import WidgetKit

struct VehicleActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VehicleActivityAttributes.self) { context in
            // Lock screen/banner UI
            VehicleActivityContentView(context: context)
        } dynamicIsland: { context in
            let model = VehicleActivityModel(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        ActivityCapsLabel(model.statusLabel, color: ActivityStyle.accent)
                        ActivityHeadline(model: model, size: 34)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivitySideMetric(model: model)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandExpandedContentView(context: context)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            } compactLeading: {
                if model.showsBattery {
                    CompactIslandText(
                        text: model.formattedRange(),
                        limitedWidthText: model.formattedRange(includesUnit: false),
                        cameraEdge: .trailing
                    )
                } else {
                    Image(systemName: model.statusIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ActivityStyle.accent)
                }
            } compactTrailing: {
                CompactIslandText(text: model.trailingMetric, cameraEdge: .leading, tint: ActivityStyle.accent)
            } minimal: {
                if model.showsBattery {
                    Text("\(model.batteryPercentage)%")
                        .font(ActivityStyle.display(13))
                        .foregroundStyle(ActivityStyle.accent)
                        .compactIslandText()
                } else {
                    Image(systemName: model.statusIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ActivityStyle.accent)
                }
            }
            .widgetURL(URL(string: "betterblue://vehicle/\(context.attributes.vin)"))
            .keylineTint(ActivityStyle.accent)
        }
    }
}

// MARK: - Style

/// The app's N Link "telemetry" tokens (`NTheme`, which the widget
/// extension doesn't compile): near-black ground, condensed numerals and a
/// single Luminous Orange accent.
private enum ActivityStyle {
    static let ground = Color(hex: 0x050505)
    static let track = Color(hex: 0x262626)
    static let border = Color(hex: 0x333333)
    static let text = Color(hex: 0xF2F2F2)
    static let textSecondary = Color(hex: 0xA3A3A3)
    /// Luminous Orange — the IONIQ 5 N highlight.
    static let accent = Color(hex: 0xEA4A2A)
    static let onAccent = Color(hex: 0x0A0A0A)
    static let warning = Color(hex: 0xF2B33D)

    static let margin: CGFloat = 16

    /// Condensed display numerals, as the app's gauges use.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Model

/// Everything the Live Activity shows, worked out once from its context
/// and phrased the way the app's charging and climate screens phrase it.
struct VehicleActivityModel {
    let state: VehicleActivityAttributes.ContentState
    let attributes: VehicleActivityAttributes
    /// Past the content's stale date: background wakeups have stopped
    /// arriving, so the numbers may be well behind the vehicle.
    let isStale: Bool

    init(context: ActivityViewContext<VehicleActivityAttributes>) {
        state = context.state
        attributes = context.attributes
        isStale = context.isStale
    }

    /// Charging (and the plain status activity) lead with the battery;
    /// climate and debug lead with their own status.
    var showsBattery: Bool {
        state.activityType == .charging || state.activityType == .none
    }

    var statusIcon: String {
        switch state.activityType {
        case .climate: state.climatePresetIcon ?? "fan"
        case .debug: "ant"
        case .charging, .none: "bolt.fill"
        }
    }

    var hasStopButton: Bool {
        state.activityType == .climate || state.activityType == .debug
    }

    /// The small caps line above the headline number, e.g.
    /// "CHARGING · 7.2 KW" — as the app's charging screen subtitle.
    var statusLabel: String {
        switch state.activityType {
        case .charging, .none:
            guard let evStatus else { return "Battery" }
            if evStatus.charging {
                return chargeSpeed.map { "Charging · \($0)" } ?? "Charging"
            }
            return evStatus.pluggedIn ? "Not charging" : "Unplugged"
        case .climate:
            guard state.activityState == .running else {
                return state.activityType.message(for: state.activityState)
            }
            return "Climate on"
        case .debug:
            return "Debug"
        }
    }

    // MARK: Charging

    var evStatus: VehicleStatus.EVStatus? { state.status.evStatus }

    var batteryPercentage: Int {
        if let evStatus = state.status.evStatus {
            return Int(evStatus.evRange.percentage.rounded())
        } else if let gasRange = state.status.gasRange {
            return Int(gasRange.percentage.rounded())
        }
        return 0
    }

    var chargeLimit: Double? {
        evStatus?.currentTargetSOC ?? evStatus?.targetSocAC
    }

    func formattedRange(includesUnit: Bool = true) -> String {
        let range: Distance
        if let evStatus = state.status.evStatus, evStatus.evRange.range.length > 0 {
            range = evStatus.evRange.range
        } else if let gasRange = state.status.gasRange, gasRange.range.length > 0 {
            range = gasRange.range
        } else {
            return "--"
        }
        let preferredUnit = AppSettings.liveDistanceUnit()
        guard includesUnit else {
            return range.units.convert(range.length, to: preferredUnit)
                .formatted(.number.precision(.fractionLength(0)))
        }
        return range.units.format(range.length, to: preferredUnit)
    }

    /// One decimal, as the app's charging screen.
    var chargeSpeed: String? {
        guard let evStatus, evStatus.chargeSpeed > 0 else { return nil }
        return String(format: "%.1f kW", evStatus.chargeSpeed)
    }

    /// When charging should finish. Absolute rather than "1h 20m left",
    /// because the activity's text only changes when a wakeup lands —
    /// a finish time stays right between updates; a countdown wouldn't.
    var finishDate: Date? {
        guard let evStatus, evStatus.charging else { return nil }
        let seconds = evStatus.chargeTime.components.seconds
        guard seconds > 0 else { return nil }
        let reported = state.status.syncDate ?? state.status.lastUpdated
        return reported.addingTimeInterval(TimeInterval(seconds))
    }

    // MARK: Climate

    var temperature: String? {
        let temp = state.status.climateStatus.temperature
        guard temp.isPlausibleForDisplay else { return nil }
        return temp.units.format(temp.value, to: AppSettings.liveTemperatureUnit())
    }

    var climateDetailText: String? {
        state.climatePresetName.map { "\($0) preset" }
    }

    // MARK: Debug

    var debugDetailText: String {
        if let lastWakeup = state.lastWakeupTime {
            return "Last wakeup \(lastWakeup.formatted(date: .omitted, time: .shortened))"
        }
        return "Waiting for wakeup…"
    }

    // MARK: Dynamic Island

    var trailingMetric: String {
        switch state.activityType {
        case .climate: temperature ?? "On"
        case .debug: "#\(state.wakeupCount)"
        case .charging, .none: "\(batteryPercentage)%"
        }
    }
}

// MARK: - Lock screen

/// Lock screen and banner presentation, laid out like the app's charging
/// card: vehicle name, the big condensed percentage beside the range, the
/// orange block bar with its limit tick, then the stats.
struct VehicleActivityContentView: View {
    let context: ActivityViewContext<VehicleActivityAttributes>

    private var model: VehicleActivityModel { VehicleActivityModel(context: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.vehicleName.uppercased())
                    .font(ActivityStyle.display(17, weight: .bold))
                    .foregroundStyle(ActivityStyle.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ActivityUpdatedText(model: model)
                    .font(.system(size: 11))
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    ActivityCapsLabel(model.statusLabel, color: ActivityStyle.accent)
                    ActivityHeadline(model: model, size: 40)
                }
                Spacer(minLength: 8)
                if model.hasStopButton {
                    ActivityStopButton(model: model, vin: context.attributes.vin, diameter: 44)
                } else {
                    ActivitySideMetric(model: model)
                }
            }

            switch context.state.activityType {
            case .charging, .none:
                ActivityBlockBar(model: model)
                ActivityStatsRow(model: model)
            case .climate:
                if let detail = model.climateDetailText {
                    ActivityDetailText(detail)
                }
            case .debug:
                ActivityDetailText(model.debugDetailText)
            }
        }
        .padding(ActivityStyle.margin)
        // The app's ground, so the activity reads as part of it on any
        // wallpaper; the content is drawn for that dark surface.
        .activityBackgroundTint(ActivityStyle.ground.opacity(0.94))
        .activitySystemActionForegroundColor(ActivityStyle.text)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Dynamic Island

/// Bottom of the expanded island: the bar and stats for charging, the
/// stop button for climate/debug, and an understated footer.
struct DynamicIslandExpandedContentView: View {
    let context: ActivityViewContext<VehicleActivityAttributes>

    private var model: VehicleActivityModel { VehicleActivityModel(context: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch context.state.activityType {
            case .charging, .none:
                ActivityBlockBar(model: model)
                ActivityStatsRow(model: model)
            case .climate, .debug:
                HStack(spacing: 12) {
                    ActivityDetailText(
                        context.state.activityType == .debug ? model.debugDetailText : model.climateDetailText ?? ""
                    )
                    Spacer(minLength: 0)
                    ActivityStopButton(model: model, vin: context.attributes.vin, diameter: 34)
                }
            }

            HStack {
                Text(context.attributes.vehicleName.uppercased())
                    .font(ActivityStyle.display(13, weight: .bold))
                    .foregroundStyle(ActivityStyle.textSecondary)
                    .lineLimit(1)
                Spacer()
                ActivityUpdatedText(model: model)
            }
            .font(.system(size: 11))
        }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Components

/// Small tracked caps label, e.g. "CHARGING · 7.2 KW" (`NCapsLabel`).
private struct ActivityCapsLabel: View {
    let text: String
    var color: Color = ActivityStyle.textSecondary

    init(_ text: String, color: Color = ActivityStyle.textSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// The headline number: "65%" for charging, the temperature for climate,
/// the wakeup count for debug — big condensed numerals with a smaller,
/// dimmer unit, as on the app's charging card.
private struct ActivityHeadline: View {
    let model: VehicleActivityModel
    let size: CGFloat

    var body: some View {
        Group {
            switch model.state.activityType {
            case .charging, .none:
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(model.batteryPercentage)")
                        .font(ActivityStyle.display(size, weight: .bold))
                        .monospacedDigit()
                    Text("%")
                        .font(ActivityStyle.display(size * 0.42))
                        .foregroundStyle(ActivityStyle.textSecondary)
                }
            case .climate:
                Text(model.temperature ?? "On")
                    .font(ActivityStyle.display(size, weight: .bold))
            case .debug:
                Text("#\(model.state.wakeupCount)")
                    .font(ActivityStyle.display(size, weight: .bold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(ActivityStyle.text)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Range on the right of the headline, as the app's charging card.
private struct ActivitySideMetric: View {
    let model: VehicleActivityModel

    var body: some View {
        if model.showsBattery {
            VStack(alignment: .trailing, spacing: 0) {
                Text(model.formattedRange())
                    .font(ActivityStyle.display(22))
                    .foregroundStyle(ActivityStyle.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("estimated range")
                    .font(.system(size: 11))
                    .foregroundStyle(ActivityStyle.textSecondary)
            }
        } else {
            Image(systemName: model.statusIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ActivityStyle.accent)
        }
    }
}

/// The app's segmented charge bar (`NBlockBar`): orange blocks up to the
/// charge level and a white tick at the limit.
private struct ActivityBlockBar: View {
    let model: VehicleActivityModel
    var blocks = 20
    var height: CGFloat = 14

    var body: some View {
        let value = Double(model.batteryPercentage) / 100
        let limit = model.chargeLimit.map { $0 / 100 }
        GeometryReader { geo in
            let spacing: CGFloat = 3
            let width = (geo.size.width - spacing * CGFloat(blocks - 1)) / CGFloat(blocks)
            let filled = Int((value * Double(blocks)).rounded())
            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    ForEach(0..<blocks, id: \.self) { index in
                        Rectangle()
                            .fill(index < filled ? ActivityStyle.accent : ActivityStyle.track)
                            .frame(width: width)
                    }
                }
                .frame(height: height)
                if let limit {
                    Rectangle()
                        .fill(ActivityStyle.text)
                        .frame(width: 2.5, height: height + 6)
                        .offset(x: geo.size.width * min(max(limit, 0), 1) - 1.25)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + 6)
        .accessibilityHidden(true)
    }
}

/// FINISH · POWER · LIMIT, as the stats under the app's charging card.
private struct ActivityStatsRow: View {
    let model: VehicleActivityModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            stat("Finish") {
                if let finish = model.finishDate {
                    Text(finish, style: .time)
                } else {
                    Text("—")
                }
            }
            stat("Power") { Text(model.chargeSpeed ?? "—") }
            stat("Limit") { Text(model.chargeLimit.map { "\(Int($0))%" } ?? "—") }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ActivityCapsLabel(label)
            value()
                .font(ActivityStyle.display(17))
                .foregroundStyle(ActivityStyle.text)
                .lineLimit(1)
        }
    }
}

private struct ActivityDetailText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(ActivityStyle.textSecondary)
            .lineLimit(1)
    }
}

/// Round stop button in the app's primary style: orange with a dark glyph.
private struct ActivityStopButton: View {
    let model: VehicleActivityModel
    let vin: String
    let diameter: CGFloat

    var body: some View {
        Button(intent: StopLiveActivityIntent(vin: vin, activityType: model.state.activityType)) {
            Image(systemName: "stop.fill")
                .font(.system(size: diameter * 0.38, weight: .semibold))
                .foregroundStyle(ActivityStyle.onAccent)
                .frame(width: diameter, height: diameter)
                .background(ActivityStyle.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.state.isRefreshing)
        .opacity(model.state.isRefreshing ? 0.45 : 1)
        .accessibilityLabel("Stop")
    }
}

private struct ActivityUpdatedText: View {
    let model: VehicleActivityModel

    var body: some View {
        if model.state.isRefreshing {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(ActivityStyle.textSecondary)
                Text("Refreshing…")
            }
            .foregroundStyle(ActivityStyle.textSecondary)
        } else if model.isStale {
            // A clock time reads as current; say how old it is instead,
            // and the system keeps the count going without an update.
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                Text("Updated \(model.state.status.lastUpdated, style: .relative) ago")
            }
            .foregroundStyle(ActivityStyle.warning)
        } else {
            Text("Updated \(model.state.status.lastUpdated, style: .time)")
                .foregroundStyle(ActivityStyle.textSecondary)
        }
    }
}

private extension Text {
    /// Compact/minimal Dynamic Island slots can be narrower than the text.
    /// Keep it on one line and shrink instead of wrapping ("329\nmi").
    func compactIslandText() -> some View {
        self
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// Text for a compact leading/trailing Dynamic Island slot.
///
/// When iOS 27 shares the island between activities
/// (`isDynamicIslandLimitedInWidth`), it stops sizing the slots to their
/// content: each gets a fixed 28 pt square with the content centered in it.
/// With three activities on iPhone 18 Pro those squares straddle the camera,
/// which hides about 5 pt of each one's inner side — "82%" read "32%" and
/// "255 mi" read "255 m" (#110). There, keep the text clear of the camera
/// and use the shorter text if there is one.
private struct CompactIslandText: View {
    let text: String
    /// Shown instead of `text` in a limited-width island, e.g. the range
    /// without its unit, which would otherwise shrink to half size.
    var limitedWidthText: String?
    /// The slot's side facing the camera: trailing for compact leading,
    /// leading for compact trailing.
    let cameraEdge: HorizontalEdge
    var tint: Color = ActivityStyle.text

    /// Covers the camera's overlap with a limited-width slot (4.3–5.7 pt).
    private static let cameraClearance: CGFloat = 7

    var body: some View {
        if #available(iOS 27.0, *) {
            LimitedWidthReader { isLimited in label(isLimited: isLimited) }
        } else {
            label(isLimited: false)
        }
    }

    private func label(isLimited: Bool) -> some View {
        Text(isLimited ? limitedWidthText ?? text : text)
            .font(ActivityStyle.display(14))
            .foregroundStyle(tint)
            .compactIslandText()
            .padding(cameraEdge == .leading ? .leading : .trailing, isLimited ? Self.cameraClearance : 0)
    }
}

@available(iOS 27.0, *)
private struct LimitedWidthReader<Content: View>: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited
    @ViewBuilder let content: (_ isLimited: Bool) -> Content

    var body: some View {
        content(isLimited)
    }
}


#Preview("Charging", as: .content, using: VehicleActivityAttributes(vehicleName: "My Ioniq 5", vin: "VIN123", vehicleId: UUID())) {
    VehicleActivityWidget()
} contentStates: {
    VehicleActivityAttributes.ContentState(
        status: VehicleStatus(
            vin: "VIN123",
            gasRange: nil,
            evStatus: VehicleStatus.EVStatus(
                charging: true,
                chargeSpeed: 7.2,
                evRange: VehicleStatus.FuelRange(
                    range: Distance(length: 200, units: .miles),
                    percentage: 65
                ),
                plugType: .acCharger,
                chargeTime: .seconds(3600),
                targetSocAC: 80,
                targetSocDC: 80
            ),
            location: VehicleStatus.Location(latitude: 0, longitude: 0),
            lockStatus: .locked,
            climateStatus: VehicleStatus.ClimateStatus(
                defrostOn: false,
                airControlOn: false,
                steeringWheelHeatingOn: false,
                temperature: Temperature(units: 1, value: "72")
            ),
            odometer: Distance(length: 10000, units: .miles),
            syncDate: Date()
        ),
        activityType: .charging
    )
}

#Preview("Climate", as: .content, using: VehicleActivityAttributes(vehicleName: "My EV6", vin: "VIN456", vehicleId: UUID())) {
    VehicleActivityWidget()
} contentStates: {
    VehicleActivityAttributes.ContentState(
        status: VehicleStatus(
            vin: "VIN456",
            gasRange: nil,
            evStatus: VehicleStatus.EVStatus(
                charging: false,
                chargeSpeed: 0,
                evRange: VehicleStatus.FuelRange(
                    range: Distance(length: 250, units: .miles),
                    percentage: 80
                ),
                plugType: .unplugged,
                chargeTime: .seconds(0)
            ),
            location: VehicleStatus.Location(latitude: 0, longitude: 0),
            lockStatus: .locked,
            climateStatus: VehicleStatus.ClimateStatus(
                defrostOn: false,
                airControlOn: true,
                steeringWheelHeatingOn: false,
                temperature: Temperature(units: 1, value: "70")
            ),
            odometer: Distance(length: 5000, units: .miles),
            syncDate: Date()
        ),
        activityType: .climate,
        climatePresetName: "Warm Up",
        climatePresetIcon: "sun.max"
    )
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: VehicleActivityAttributes(vehicleName: "My Ioniq 5", vin: "VIN123", vehicleId: UUID())) {
    VehicleActivityWidget()
} contentStates: {
    VehicleActivityAttributes.ContentState(
        status: VehicleStatus(
            vin: "VIN123",
            gasRange: nil,
            evStatus: VehicleStatus.EVStatus(
                charging: true,
                chargeSpeed: 150.0,
                evRange: VehicleStatus.FuelRange(
                    range: Distance(length: 120, units: .miles),
                    percentage: 45
                ),
                plugType: .dcCharger,
                chargeTime: .seconds(1800),
                targetSocAC: 80,
                targetSocDC: 80
            ),
            location: VehicleStatus.Location(latitude: 0, longitude: 0),
            lockStatus: .locked,
            climateStatus: VehicleStatus.ClimateStatus(
                defrostOn: false,
                airControlOn: false,
                steeringWheelHeatingOn: false,
                temperature: Temperature(units: 1, value: "72")
            ),
            odometer: Distance(length: 10000, units: .miles),
            syncDate: Date()
        ),
        activityType: .charging
    )
}

#Preview("Climate Dynamic Island", as: .dynamicIsland(.expanded), using: VehicleActivityAttributes(vehicleName: "My EV6", vin: "VIN456", vehicleId: UUID())) {
    VehicleActivityWidget()
} contentStates: {
    VehicleActivityAttributes.ContentState(
        status: VehicleStatus(
            vin: "VIN456",
            gasRange: nil,
            evStatus: VehicleStatus.EVStatus(
                charging: false,
                chargeSpeed: 0,
                evRange: VehicleStatus.FuelRange(
                    range: Distance(length: 250, units: .miles),
                    percentage: 80
                ),
                plugType: .unplugged,
                chargeTime: .seconds(0)
            ),
            location: VehicleStatus.Location(latitude: 0, longitude: 0),
            lockStatus: .locked,
            climateStatus: VehicleStatus.ClimateStatus(
                defrostOn: false,
                airControlOn: true,
                steeringWheelHeatingOn: false,
                temperature: Temperature(units: 1, value: "70")
            ),
            odometer: Distance(length: 5000, units: .miles),
            syncDate: Date()
        ),
        activityType: .climate,
        climatePresetName: "Warm Up",
        climatePresetIcon: "sun.max"
    )
}

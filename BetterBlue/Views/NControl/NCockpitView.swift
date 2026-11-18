//
//  NCockpitView.swift
//  N Link
//
//  Wide landscape layout — the iPhone Duo unfolded. The pane before the
//  seam is a permanent instrument cluster (gauge, telemetry, control
//  list); the pane after it is the workspace, where Climate, Charging
//  and Security open in place, and Map, Trips and Settings show.
//  Nothing interactive sits on the seam.
//

import BetterBlueKit
import SwiftData
import SwiftUI

struct NCockpitView: View {
    let vehicle: BBVehicle
    let vehicles: [BBVehicle]
    @Binding var selectedIndex: Int
    @Binding var tab: NTab

    @Environment(\.modelContext) private var modelContext
    @Environment(VehicleCommandRunner.self) private var runner

    @State private var panel: NDestination = .climate
    @State private var division: NDivision?

    /// Used when the system reports no division region: split at the
    /// middle of the window with a small gutter.
    private static let fallbackGutter: CGFloat = 16

    /// The system tab bar lives in the display's vertical bar, beside the
    /// workspace it switches. Each tab repeats the cluster so it never
    /// appears to change.
    var body: some View {
        TabView(selection: $tab) {
            ForEach(NTab.allCases) { item in
                Tab(item.rawValue, systemImage: item.systemImage, value: item) {
                    panes(showing: item)
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
    }

    /// Laid out inside the safe area, so the workspace stops at the
    /// vertical bar. The seam is measured in this same coordinate space.
    private func panes(showing section: NTab) -> some View {
        GeometryReader { geo in
            let seam = seamBounds(in: geo)
            HStack(spacing: 0) {
                clusterPane
                    .frame(width: max(seam.minX, 0))

                Color.clear
                    .frame(width: max(seam.maxX - seam.minX, 0))
                    .accessibilityHidden(true)

                workspace(showing: section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: 0x0A0A0A).ignoresSafeArea())
            }
            .background(NDivisionReader { division = $0 })
        }
        .background(NTheme.ground.ignoresSafeArea())
    }

    private func seamBounds(in geo: GeometryProxy) -> NDivision {
        if let division { return division }
        let mid = geo.size.width / 2
        return NDivision(minX: mid - Self.fallbackGutter / 2, maxX: mid + Self.fallbackGutter / 2)
    }

    // MARK: - Cluster pane

    private var clusterPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 12) {
                gauge
                VStack(spacing: 8) {
                    tile("Plug", plugText)
                    tile("12V · Tires", "\(vehicle.battery12V.map { "\($0)%" } ?? "—") · \(tireText)")
                    tile("Odometer", NFormat.distance(vehicle.odometer) ?? "—")
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                controlRow(.climate, title: "Climate", subtitle: climateSubtitle, icon: "fan.fill")
                if vehicle.isEV {
                    controlRow(.charging, title: "Charging", subtitle: chargingSubtitle, icon: "bolt.fill")
                }
                controlRow(.security, title: lockTitle, subtitle: NFormat.openingsSummary(vehicle).text,
                           icon: vehicle.lockStatus == .locked ? "lock.fill" : "lock.open.fill")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                NCapsLabel("N Link", color: NTheme.accent)
                Text(vehicle.displayName.uppercased())
                    .font(NTheme.display(28, weight: .bold))
                    .foregroundStyle(NTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(runner.isBusy(.refresh) ? "Refreshing…" : NFormat.updated(vehicle.lastUpdated, now: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(NTheme.textSecondary)
                }
            }
            Spacer()
            if vehicles.count > 1 {
                Menu {
                    ForEach(Array(vehicles.enumerated()), id: \.element.id) { index, item in
                        Button(item.displayName) { selectedIndex = index }
                    }
                } label: {
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(NTheme.text)
                        .background(NTheme.card, in: Circle())
                        .overlay(Circle().strokeBorder(NTheme.border))
                }
                .accessibilityLabel("Switch vehicle")
            }
            NIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Refresh status",
                        isBusy: runner.isBusy(.refresh)) {
                Task { await runner.refresh(modelContext: modelContext) }
            }
        }
    }

    private var gauge: some View {
        let ev = vehicle.evStatus
        let percentage = ev?.evRange.percentage ?? vehicle.gasRange?.percentage ?? 0
        let limit = ev?.currentTargetSOC ?? ev?.targetSocAC
        return ZStack {
            NArcGauge(value: percentage / 100, marker: limit.map { $0 / 100 }, lineWidth: 16, segments: 44)
            VStack(spacing: 0) {
                NCapsLabel(ev != nil ? "State of charge" : "Fuel")
                    .font(.system(size: 9, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(percentage.rounded()))")
                        .font(NTheme.display(60, weight: .bold))
                        .monospacedDigit()
                    Text("%").font(NTheme.display(22)).foregroundStyle(NTheme.textSecondary)
                }
                .foregroundStyle(NTheme.text)
                if let range = NFormat.distance(ev?.evRange.range ?? vehicle.gasRange?.range) {
                    Text(range).font(NTheme.display(19)).foregroundStyle(NTheme.text)
                }
            }
        }
        .frame(width: 196, height: 196)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(Int(percentage.rounded())) percent")
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NCapsLabel(label).font(.system(size: 10, weight: .semibold))
            Text(value)
                .font(NTheme.display(18))
                .foregroundStyle(NTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .nCard(radius: 12, padding: 10)
        .accessibilityElement(children: .combine)
    }

    private func controlRow(_ destination: NDestination, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = tab == .car && panel == destination
        return Button {
            panel = destination
            tab = .car
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isSelected ? NTheme.onAccent : NTheme.accent)
                    .background(isSelected ? NTheme.accent : NTheme.track,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(NTheme.text)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(NTheme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? NTheme.cardRaised : NTheme.card,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? NTheme.accent : NTheme.border)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Workspace pane

    @ViewBuilder
    private func workspace(showing section: NTab) -> some View {
        switch section {
        case .car:
            NavigationStack {
                Group {
                    switch panel {
                    case .climate: NClimateView(vehicle: vehicle)
                    case .charging: NChargingView(vehicle: vehicle)
                    case .security: NSecurityView(vehicle: vehicle)
                    }
                }
                .environment(\.nEmbeddedPane, true)
            }
            .id(panel)
        case .map:
            NMapView(vehicle: vehicle)
        case .trips:
            NavigationStack { NTripsView(vehicle: vehicle) }
        case .settings:
            SettingsView(isTab: true)
        }
    }

    // MARK: - Text

    private var plugText: String {
        guard let ev = vehicle.evStatus else { return "—" }
        switch ev.plugType {
        case .unplugged: return "Unplugged"
        case .acCharger:
            return ev.currentTargetSOC.map { "AC · limit \(Int($0))%" } ?? "AC"
        case .dcCharger:
            return ev.currentTargetSOC.map { "DC · limit \(Int($0))%" } ?? "DC"
        }
    }

    private var tireText: String {
        guard let warning = vehicle.tirePressureWarning else { return "—" }
        return warning.hasWarning ? "Check" : "OK"
    }

    private var climateSubtitle: String {
        if let status = runner.statusText[.climate] { return status }
        if vehicle.climateStatus?.airControlOn == true, let temp = vehicle.climateStatus?.temperature {
            return "Running · \(NFormat.temperature(temp))"
        }
        if let preset = vehicle.activeClimatePreset {
            return "Off · \(preset.name) \(NFormat.temperature(preset.climateOptions.temperature))"
        }
        return "Off"
    }

    private var chargingSubtitle: String {
        if let status = runner.statusText[.charge] { return status }
        guard let ev = vehicle.evStatus else { return "—" }
        if let done = NFormat.doneBy(ev) { return done }
        if ev.pluggedIn { return ev.currentTargetSOC.map { "Ready · limit \(Int($0))%" } ?? "Ready" }
        return "Not plugged in"
    }

    private var lockTitle: String {
        switch vehicle.lockStatus {
        case .locked: "Locked"
        case .unlocked: "Unlocked"
        default: "Security"
        }
    }
}

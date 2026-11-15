//
//  NHomeView.swift
//  N Control
//
//  The Car tab: state-of-charge gauge, quick telemetry, and the three
//  top jobs — climate, charging, lock.
//

import BetterBlueKit
import SwiftData
import SwiftUI

enum NDestination: Hashable {
    case climate, charging, security
}

struct NHomeView: View {
    let vehicle: BBVehicle
    let vehicles: [BBVehicle]
    @Binding var selectedIndex: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(VehicleCommandRunner.self) private var runner

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                gauge
                tiles
                climateCard
                if vehicle.isEV {
                    HStack(alignment: .top, spacing: 12) {
                        chargingCard
                        securityCard
                    }
                } else {
                    securityCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .refreshable { await runner.refresh(modelContext: modelContext) }
        .background(NTheme.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: NDestination.self) { destination in
            switch destination {
            case .climate: NClimateView(vehicle: vehicle)
            case .charging: NChargingView(vehicle: vehicle)
            case .security: NSecurityView(vehicle: vehicle)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                NCapsLabel("N Control", color: NTheme.accent)
                vehicleTitle
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(runner.isBusy(.refresh)
                         ? "Refreshing…"
                         : NFormat.updated(vehicle.lastUpdated, now: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(NTheme.textSecondary)
                }
            }
            Spacer()
            NIconButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: "Refresh status",
                isBusy: runner.isBusy(.refresh)
            ) {
                Task { await runner.refresh(modelContext: modelContext) }
            }
        }
    }

    @ViewBuilder
    private var vehicleTitle: some View {
        let title = Text(vehicle.displayName.uppercased())
            .font(NTheme.display(34, weight: .bold))
            .foregroundStyle(NTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        if vehicles.count > 1 {
            Menu {
                ForEach(Array(vehicles.enumerated()), id: \.element.id) { index, item in
                    Button {
                        selectedIndex = index
                    } label: {
                        if index == selectedIndex {
                            Label(item.displayName, systemImage: "checkmark")
                        } else {
                            Text(item.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    title
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NTheme.textSecondary)
                }
            }
            .accessibilityLabel("Switch vehicle, \(vehicle.displayName)")
        } else {
            title
        }
    }

    // MARK: - Gauge

    private var gauge: some View {
        let ev = vehicle.evStatus
        let percentage = ev?.evRange.percentage ?? vehicle.gasRange?.percentage ?? 0
        let range = NFormat.distance(ev?.evRange.range ?? vehicle.gasRange?.range)
        let limit = ev?.currentTargetSOC ?? ev?.targetSocAC
        return ZStack {
            NArcGauge(
                value: percentage / 100,
                marker: limit.map { $0 / 100 },
                lineWidth: 16
            )
            .padding(18)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(NTheme.borderStrong, style: StrokeStyle(lineWidth: 2, dash: [2, 9]))
                .rotationEffect(.degrees(135))
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                NCapsLabel(ev != nil ? "State of charge" : "Fuel")
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(percentage.rounded()))")
                        .font(NTheme.display(84, weight: .bold))
                        .monospacedDigit()
                    Text("%")
                        .font(NTheme.display(28))
                        .foregroundStyle(NTheme.textSecondary)
                }
                .foregroundStyle(NTheme.text)
                if let range {
                    Text(range)
                        .font(NTheme.display(22))
                        .foregroundStyle(NTheme.text)
                }
                if let ev {
                    Text(chargeLine(ev))
                        .font(.system(size: 13))
                        .foregroundStyle(ev.charging ? NTheme.accent : NTheme.textSecondary)
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: 280, height: 280)
        .frame(maxWidth: .infinity)
        // The 270° arc leaves its bottom quarter empty — tuck the tiles up.
        .padding(.bottom, -36)
        .accessibilityElement(children: .combine)
    }

    private func chargeLine(_ ev: VehicleStatus.EVStatus) -> String {
        if ev.charging {
            return NFormat.doneBy(ev) ?? "Charging"
        }
        if ev.pluggedIn {
            if let limit = ev.currentTargetSOC { return "Plugged in · limit \(Int(limit))%" }
            return "Plugged in"
        }
        return "Not plugged in"
    }

    // MARK: - Tiles

    private var tiles: some View {
        HStack(spacing: 10) {
            tile("Odometer", NFormat.distance(vehicle.odometer) ?? "—")
            tile("12V", vehicle.battery12V.map { "\($0)%" } ?? "—")
            tile("Tires", tireText, warn: vehicle.tirePressureWarning?.hasWarning == true)
        }
    }

    private var tireText: String {
        guard let warning = vehicle.tirePressureWarning else { return "—" }
        return warning.hasWarning ? "Check" : "OK"
    }

    private func tile(_ label: String, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NCapsLabel(label)
            Text(value)
                .font(NTheme.display(24))
                .foregroundStyle(warn ? NTheme.warning : NTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .nCard(radius: 14, padding: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Climate

    private var climateCard: some View {
        let isOn = vehicle.climateStatus?.airControlOn == true
        let preset = vehicle.activeClimatePreset
        let subtitle: String = {
            if isOn, let temp = vehicle.climateStatus?.temperature {
                return "On · \(NFormat.temperature(temp))"
            }
            if let preset {
                return "Off · \(preset.name) \(NFormat.temperature(preset.climateOptions.temperature))"
            }
            return "Off"
        }()
        return HStack(spacing: 14) {
            Image(systemName: "fan.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NTheme.accent)
                .symbolEffect(.rotate, isActive: isOn)
                .frame(width: 44, height: 44)
                .background(NTheme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            NavigationLink(value: NDestination.climate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Climate ›")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NTheme.text)
                    Text(runner.statusText[.climate] ?? subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(NTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            NCommandButton(
                title: isOn ? "Stop" : "Start",
                kind: isOn ? .secondary : .primary,
                height: 44,
                isBusy: runner.isBusy(.climate),
                busyText: ""
            ) {
                Task {
                    if isOn {
                        await runner.stopClimate(modelContext: modelContext)
                    } else {
                        await runner.startClimate(
                            options: preset?.climateOptions
                                ?? ClimateOptions(preferredUnits: NFormat.temperatureUnit),
                            presetName: preset?.name,
                            presetIcon: preset?.iconName,
                            modelContext: modelContext
                        )
                    }
                }
            }
            .frame(width: 92)
        }
        .nCard(radius: 18, padding: 14)
    }

    // MARK: - Charging

    private var chargingCard: some View {
        let ev = vehicle.evStatus
        let charging = ev?.charging == true
        let status: String = {
            guard let ev else { return "—" }
            if ev.charging {
                return ev.chargeSpeed > 0 ? String(format: "%.0f kW", ev.chargeSpeed) : "Charging"
            }
            return ev.pluggedIn ? "Ready" : "Unplugged"
        }()
        let subtitle: String = {
            guard let ev else { return "" }
            if let done = NFormat.doneBy(ev) { return done }
            if let limit = ev.currentTargetSOC ?? ev.targetSocAC { return "Limit \(Int(limit))%" }
            return ev.pluggedIn ? "Plugged in" : "Not plugged in"
        }()
        return halfCard(
            icon: "bolt.fill",
            iconColor: NTheme.accent,
            status: status,
            title: "Charging ›",
            subtitle: runner.statusText[.charge] ?? subtitle,
            destination: .charging
        ) {
            NCommandButton(
                title: charging ? "Stop charge" : "Start charge",
                kind: charging ? .secondary : .primary,
                height: 44,
                isBusy: runner.isBusy(.charge),
                busyText: ""
            ) {
                Task { await runner.setCharging(!charging, modelContext: modelContext) }
            }
            .disabled(ev?.pluggedIn != true)
        }
    }

    // MARK: - Security

    private var securityCard: some View {
        let locked = vehicle.lockStatus == .locked
        let openings = NFormat.openingsSummary(vehicle)
        let title: String = switch vehicle.lockStatus {
        case .locked: "Locked ›"
        case .unlocked: "Unlocked ›"
        default: "Security ›"
        }
        return halfCard(
            icon: locked ? "lock.fill" : "lock.open.fill",
            iconColor: locked ? NTheme.text : NTheme.accent,
            status: openings.text,
            title: title,
            subtitle: runner.statusText[.lock] ?? (locked ? "Tap to see details" : "Car is unlocked"),
            destination: .security
        ) {
            NCommandButton(
                title: locked ? "Unlock" : "Lock",
                kind: locked ? .secondary : .primary,
                height: 44,
                isBusy: runner.isBusy(.lock),
                busyText: ""
            ) {
                Task { await runner.setLocked(!locked, modelContext: modelContext) }
            }
        }
    }

    private func halfCard<Button: View>(
        icon: String,
        iconColor: Color,
        status: String,
        title: String,
        subtitle: String,
        destination: NDestination,
        @ViewBuilder button: () -> Button
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: destination) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(iconColor)
                        Text(status)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(NTheme.text)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(NTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            button()
        }
        .nCard(radius: 18, padding: 14)
    }
}

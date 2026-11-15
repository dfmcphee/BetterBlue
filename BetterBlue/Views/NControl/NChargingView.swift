//
//  NChargingView.swift
//  N Control
//
//  Battery, start/stop charge, and separate AC / DC charge limits.
//

import BetterBlueKit
import SwiftData
import SwiftUI

struct NChargingView: View {
    let vehicle: BBVehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(VehicleCommandRunner.self) private var runner

    @State private var acLimit: Double = 80
    @State private var dcLimit: Double = 90
    @State private var limitsLoaded = false

    private var ev: VehicleStatus.EVStatus? { vehicle.evStatus }

    private var reportedAC: Int? { ev?.targetSocAC.map { Int($0) } }
    private var reportedDC: Int? { ev?.targetSocDC.map { Int($0) } }
    private var limitsChanged: Bool {
        guard let reportedAC, let reportedDC else { return false }
        return Int(acLimit) != reportedAC || Int(dcLimit) != reportedDC
    }

    var body: some View {
        NPushedScreen(title: "Charging", subtitle: subtitle) {
            batteryCard
            chargeButton
            limits
            NGroup {
                NRow(title: "Charge port", subtitle: "Connector shown in plug icons") {
                    Menu {
                        Picker("Charge port", selection: Binding(
                            get: { vehicle.chargePortType },
                            set: { vehicle.chargePortTypeRaw = $0.rawValue; try? modelContext.save() }
                        )) {
                            ForEach(ChargePortType.allCases, id: \.self) { port in
                                Text(port.displayName).tag(port)
                            }
                        }
                    } label: {
                        Text("\(vehicle.chargePortType.displayName) ›")
                            .foregroundStyle(NTheme.textSecondary)
                            .frame(minHeight: 44)
                    }
                }
                NRow("Odometer", value: NFormat.distance(vehicle.odometer) ?? "—", showsDivider: false)
            }
        }
        .onAppear(perform: loadLimits)
        .onChange(of: reportedAC) { _, _ in if !runner.isBusy(.limits) { loadLimits(force: true) } }
        .onChange(of: reportedDC) { _, _ in if !runner.isBusy(.limits) { loadLimits(force: true) } }
    }

    private func loadLimits() { loadLimits(force: false) }

    private func loadLimits(force: Bool) {
        guard force || !limitsLoaded else { return }
        if let reportedAC { acLimit = Double(reportedAC) }
        if let reportedDC { dcLimit = Double(reportedDC) }
        limitsLoaded = true
    }

    private var subtitle: String {
        guard let ev else { return "No battery data" }
        var parts: [String] = []
        switch ev.plugType {
        case .unplugged: parts.append("Unplugged")
        case .acCharger: parts.append("Plugged in · AC")
        case .dcCharger: parts.append("Plugged in · DC fast")
        }
        if ev.charging {
            parts.append(ev.chargeSpeed > 0 ? String(format: "%.1f kW", ev.chargeSpeed) : "charging")
        } else if ev.pluggedIn {
            parts.append("not charging")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Battery

    private var batteryCard: some View {
        let percentage = ev?.evRange.percentage ?? 0
        let limit = ev?.currentTargetSOC ?? ev?.targetSocAC
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(percentage.rounded()))")
                        .font(NTheme.display(76, weight: .bold))
                        .monospacedDigit()
                    Text("%")
                        .font(NTheme.display(26))
                        .foregroundStyle(NTheme.textSecondary)
                }
                .foregroundStyle(NTheme.text)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(NFormat.distance(ev?.evRange.range) ?? "—")
                        .font(NTheme.display(26))
                        .foregroundStyle(NTheme.text)
                    Text("estimated range")
                        .font(.system(size: 12))
                        .foregroundStyle(NTheme.textSecondary)
                }
            }
            NBlockBar(value: percentage / 100, limit: limit.map { $0 / 100 })
            HStack {
                Text("0%")
                Spacer()
                if let limit { Text("Limit \(Int(limit))%") }
                Spacer()
                Text("100%")
            }
            .font(.system(size: 12))
            .foregroundStyle(NTheme.textSecondary)
            if let ev, ev.charging {
                HStack(spacing: 16) {
                    stat("Time left", NFormat.timeRemaining(ev) ?? "—")
                    stat("Finish", NFormat.doneBy(ev)?.replacingOccurrences(of: "Done by ", with: "") ?? "—")
                    stat("Power", ev.chargeSpeed > 0 ? String(format: "%.1f kW", ev.chargeSpeed) : "—")
                }
                .padding(.top, 4)
            }
        }
        .nCard(radius: 20, padding: 18)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NCapsLabel(label)
            Text(value)
                .font(NTheme.display(20))
                .foregroundStyle(NTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chargeButton: some View {
        let charging = ev?.charging == true
        return VStack(spacing: 6) {
            NCommandButton(
                title: charging ? "Stop charge" : "Start charge",
                systemImage: "bolt.fill",
                kind: charging ? .secondary : .primary,
                height: 56,
                isBusy: runner.isBusy(.charge),
                busyText: runner.statusText[.charge]
            ) {
                Task { await runner.setCharging(!charging, modelContext: modelContext) }
            }
            .disabled(ev?.pluggedIn != true)
            if ev?.pluggedIn != true {
                Text("Plug in to start charging")
                    .font(.system(size: 12))
                    .foregroundStyle(NTheme.textSecondary)
            }
        }
    }

    // MARK: - Limits

    private var limits: some View {
        VStack(alignment: .leading, spacing: 8) {
            NCapsLabel("Charge limits")
            VStack(spacing: 18) {
                limitSlider("AC · home charging", value: $acLimit)
                limitSlider("DC · fast charging", value: $dcLimit)
                if limitsChanged || runner.isBusy(.limits) {
                    NCommandButton(
                        title: "Save limits",
                        height: 46,
                        isBusy: runner.isBusy(.limits),
                        busyText: runner.statusText[.limits]
                    ) {
                        Task {
                            await runner.setChargeLimits(
                                ac: Int(acLimit), dc: Int(dcLimit), modelContext: modelContext
                            )
                        }
                    }
                }
            }
            .nCard(radius: 18, padding: 16)
            .disabled(reportedAC == nil || reportedDC == nil)
            if reportedAC == nil || reportedDC == nil {
                Text("Your car hasn't reported its charge limits yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(NTheme.textSecondary)
            }
        }
    }

    private func limitSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 15)).foregroundStyle(NTheme.text)
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .font(NTheme.display(22))
                    .foregroundStyle(NTheme.text)
                    .monospacedDigit()
            }
            Slider(value: value, in: 50...100, step: 10)
                .tint(NTheme.accent)
                .accessibilityLabel(title)
        }
    }
}

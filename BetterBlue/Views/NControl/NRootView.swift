//
//  NRootView.swift
//  N Link
//
//  Top-level N Link layout: Car / Map / Trips / Settings, with the
//  telemetry-style bottom bar and a shared error banner.
//

import BetterBlueKit
import Observation
import SwiftData
import SwiftUI

enum NTab: String, CaseIterable, Identifiable {
    case car = "Car", map = "Map", trips = "Trips", settings = "Settings"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .car: "car.fill"
        case .map: "map.fill"
        case .trips: "chart.bar.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// Keeps one command runner per vehicle so busy states survive tab
/// switches and pushes.
@MainActor
@Observable
final class VehicleRunnerStore {
    @ObservationIgnored private var runners: [UUID: VehicleCommandRunner] = [:]

    func runner(for vehicle: BBVehicle) -> VehicleCommandRunner {
        if let runner = runners[vehicle.id] { return runner }
        let runner = VehicleCommandRunner(vehicle: vehicle)
        runners[vehicle.id] = runner
        return runner
    }
}

struct NRootView: View {
    let vehicles: [BBVehicle]
    @Binding var selectedIndex: Int
    let mfaState: MFAFlowState
    let sheetPresentation: VehicleSheetPresentation

    @Environment(\.modelContext) private var modelContext
    @State private var tab: NTab = .car
    @State private var store = VehicleRunnerStore()

    private var vehicle: BBVehicle? {
        vehicles.indices.contains(selectedIndex) ? vehicles[selectedIndex] : vehicles.first
    }

    var body: some View {
        if let vehicle {
            let runner = store.runner(for: vehicle)
            GeometryReader { geo in
                let mode = NLayoutMode.resolve(for: CGSize(
                    width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                    height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                ))
                Group {
                    if mode == .cockpit {
                        NCockpitView(
                            vehicle: vehicle,
                            vehicles: vehicles,
                            selectedIndex: $selectedIndex,
                            tab: $tab
                        )
                    } else if mode == .glance {
                        glanceTabs(vehicle: vehicle)
                    } else {
                        content(vehicle: vehicle)
                    }
                }
                .animation(.snappy, value: mode)
            }
                .overlay(alignment: .top) { banner(runner: runner) }
                .environment(runner)
                .environment(sheetPresentation)
                .preferredColorScheme(.dark)
                .tint(NTheme.accent)
        }
    }

    /// iPhone Duo outer display: the system tab bar, which iOS hosts in
    /// the vertical bar beside the content.
    private func glanceTabs(vehicle: BBVehicle) -> some View {
        TabView(selection: $tab) {
            Tab(NTab.car.rawValue, systemImage: NTab.car.systemImage, value: NTab.car) {
                NavigationStack {
                    NGlanceHomeView(
                        vehicle: vehicle,
                        vehicles: vehicles,
                        selectedIndex: $selectedIndex
                    )
                }
            }
            Tab(NTab.map.rawValue, systemImage: NTab.map.systemImage, value: NTab.map) {
                NMapView(vehicle: vehicle)
            }
            Tab(NTab.trips.rawValue, systemImage: NTab.trips.systemImage, value: NTab.trips) {
                NavigationStack { NTripsView(vehicle: vehicle) }
            }
            Tab(NTab.settings.rawValue, systemImage: NTab.settings.systemImage, value: NTab.settings) {
                SettingsView(isTab: true)
            }
        }
    }

    @ViewBuilder
    private func content(vehicle: BBVehicle) -> some View {
        switch tab {
        case .car:
            NavigationStack {
                NHomeView(
                    vehicle: vehicle,
                    vehicles: vehicles,
                    selectedIndex: $selectedIndex
                )
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            }
        case .map:
            NMapView(vehicle: vehicle)
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        case .trips:
            NavigationStack {
                NTripsView(vehicle: vehicle)
                    .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            }
        case .settings:
            SettingsView(isTab: true)
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        }
    }

    private var tabBar: some View {
        NTabBar(selection: $tab)
            .padding(.horizontal, NTheme.screenHorizontal)
            .padding(.bottom, 12)
            .padding(.top, 8)
            .background(
                LinearGradient(
                    colors: [NTheme.ground.opacity(0), NTheme.ground],
                    startPoint: .top, endPoint: .center
                )
                .ignoresSafeArea()
            )
    }

    @ViewBuilder
    private func banner(runner: VehicleCommandRunner) -> some View {
        if let banner = runner.banner {
            Button {
                open(banner, runner: runner)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NTheme.accent)
                    Text(banner.message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NTheme.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture { runner.banner = nil }
                        .accessibilityLabel("Dismiss")
                        .accessibilityAddTraits(.isButton)
                }
                .padding(14)
                .background(NTheme.cardRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(NTheme.accent.opacity(0.5))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func open(_ banner: VehicleCommandRunner.Banner, runner: VehicleCommandRunner) {
        if let apiError = banner.apiError, apiError.errorType == .requiresMFA,
           let account = runner.vehicle.account {
            mfaState.start(from: apiError, account: account) {
                await MainActor.run { runner.banner = nil }
                await runner.refresh(modelContext: modelContext)
            }
        } else if let actionError = banner.actionError {
            sheetPresentation.show(.errorDetails(error: actionError, onClear: { runner.banner = nil }))
        }
    }
}

struct NTabBar: View {
    @Binding var selection: NTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 6) {
                        if isSelected {
                            Rectangle().fill(NTheme.accent).frame(width: 6, height: 6)
                        }
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundStyle(isSelected ? NTheme.text : NTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        isSelected ? NTheme.hairline : .clear,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(NTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(NTheme.border)
        )
    }
}

// MARK: - Shared vehicle formatting

@MainActor
enum NFormat {
    static var distanceUnit: Distance.Units { AppSettings.shared.preferredDistanceUnit }
    static var temperatureUnit: Temperature.Units { AppSettings.shared.preferredTemperatureUnit }

    static func distance(_ distance: Distance?) -> String? {
        guard let distance, distance.length > 0 else { return nil }
        return distance.units.format(distance.length, to: distanceUnit)
    }

    static func temperature(_ temperature: Temperature) -> String {
        temperature.units.format(temperature.value, to: temperatureUnit)
    }

    static func updated(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Not updated yet" }
        if now.timeIntervalSince(date) < 60 { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated " + formatter.localizedString(for: date, relativeTo: now)
    }

    /// "Done by 7:20 AM" while charging with a known time remaining.
    static func doneBy(_ ev: VehicleStatus.EVStatus, now: Date = .now) -> String? {
        guard ev.charging else { return nil }
        let seconds = ev.chargeTime.components.seconds
        guard seconds > 0 else { return nil }
        let done = now.addingTimeInterval(TimeInterval(seconds))
        return "Done by " + done.formatted(date: .omitted, time: .shortened)
    }

    static func timeRemaining(_ ev: VehicleStatus.EVStatus) -> String? {
        let seconds = ev.chargeTime.components.seconds
        guard ev.charging, seconds > 0 else { return nil }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func openingsSummary(_ vehicle: BBVehicle) -> (text: String, allClosed: Bool) {
        var open: [String] = []
        if vehicle.doorOpen?.anyOpen == true { open.append("Door") }
        if vehicle.trunkOpen == true { open.append("Trunk") }
        if vehicle.hoodOpen == true { open.append("Hood") }
        if open.isEmpty {
            let known = vehicle.doorOpen != nil || vehicle.trunkOpen != nil || vehicle.hoodOpen != nil
            return (known ? "All closed" : "Status unknown", known)
        }
        return (open.joined(separator: ", ") + " open", false)
    }
}

extension BBVehicle {
    /// Presets in display order.
    var sortedClimatePresets: [ClimatePreset] {
        safeClimatePresets.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Selected preset, falling back to the first one.
    var activeClimatePreset: ClimatePreset? {
        let presets = sortedClimatePresets
        return presets.first(where: \.isSelected) ?? presets.first
    }

    var isEV: Bool { evStatus != nil }
}

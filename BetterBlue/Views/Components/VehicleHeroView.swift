//
//  VehicleHeroView.swift
//  BetterBlue
//
//  The car-first stage behind the persistent vehicle sheet: the
//  selected vehicle drawn large, its energy readout, and status chips
//  for the things you check before walking out to the car. Replaces
//  the full-screen map, which now lives behind the Location chip
//  (`VehicleMapSheet`).
//

import BetterBlueKit
import MapKit
import SwiftUI

struct VehicleHeroView: View {
    let vehicle: BBVehicle
    /// Height of the collapsed vehicle card measured from the window's
    /// bottom edge, or 0 when the card is a column beside the stage
    /// (wide windows). The stage lays itself out in the space above it.
    let bottomInset: CGFloat
    let sheetPresentation: VehicleSheetPresentation

    @State private var appSettings = AppSettings.shared

    /// Width of the leading card column in wide windows — matches
    /// `VehicleSheetPager.maxSheetWidth` plus its outer inset.
    private static let columnWidth: CGFloat = 440 + 16

    var body: some View {
        if vehicle.isDeleted || vehicle.modelContext == nil {
            Color(uiColor: .systemBackground).ignoresSafeArea()
        } else {
            GeometryReader { geo in
                let isColumnLayout = bottomInset == 0 && geo.size.width > Self.columnWidth + 280
                stage(availableHeight: geo.size.height - max(0, bottomInset - geo.safeAreaInsets.bottom))
                    .padding(.leading, isColumnLayout ? Self.columnWidth : 0)
            }
            .background { HeroBackdrop(tint: vehicle.primaryColor).ignoresSafeArea() }
            .animation(.smooth(duration: 0.35), value: vehicle.vin)
        }
    }

    @ViewBuilder
    private func stage(availableHeight: CGFloat) -> some View {
        let compact = availableHeight < 420
        VStack(alignment: .leading, spacing: compact ? 8 : 16) {
            header
            Spacer(minLength: 0)
            car(height: min(availableHeight * (compact ? 0.32 : 0.38), 220))
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            chips
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, compact ? 12 : 20)
        .frame(height: max(0, availableHeight), alignment: .top)
        // Lines up under the floating settings button (44pt + 8pt gap),
        // at the navigation bar's 16pt margin.
        .overlay(alignment: .topTrailing) {
            mapButton
                .padding(.top, 52)
                .padding(.trailing, 16)
        }
        .id(vehicle.vin)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    // MARK: - Header (model + energy readout)

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(modelLine)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let readout = energyReadout {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(readout.value)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: readout.icon)
                        .foregroundStyle(readout.tint)
                        .symbolEffect(.pulse, isActive: readout.isCharging)
                    Text(readout.detail)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        // Leave the top-trailing corner to the floating settings button.
        .padding(.trailing, 52)
    }

    private var modelLine: String {
        if let year = vehicle.modelYear, year > 0 {
            return "\(year) \(vehicle.displayName)"
        }
        return vehicle.displayName
    }

    private struct EnergyReadout {
        let value: String
        let detail: String
        let icon: String
        let tint: Color
        let isCharging: Bool
    }

    /// EV battery when the vehicle has one (pure EV + PHEV), otherwise
    /// the fuel tank.
    private var energyReadout: EnergyReadout? {
        if let ev = vehicle.evStatus {
            var parts = [formatted(ev.evRange.range)]
            if ev.charging {
                parts.append(ev.chargeSpeed > 0 ? String(format: "Charging · %.0f kW", ev.chargeSpeed) : "Charging")
                if ev.chargeTime > .seconds(0) {
                    parts.append(ev.chargeTime.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                }
            } else if let gas = vehicle.gasRange, gas.range.length > 0 {
                parts.append("\(formatted(gas.range)) gas")
            }
            return EnergyReadout(
                value: "\(Int(ev.evRange.percentage.rounded()))",
                detail: parts.joined(separator: " · "),
                icon: ev.charging ? "bolt.fill" : "bolt.car.fill",
                tint: vehicle.chargingColor,
                isCharging: ev.charging
            )
        }
        if let gas = vehicle.gasRange {
            return EnergyReadout(
                value: "\(Int(gas.percentage.rounded()))",
                detail: "\(formatted(gas.range)) range",
                icon: "fuelpump.fill",
                tint: vehicle.gasColor,
                isCharging: false
            )
        }
        return nil
    }

    private func formatted(_ distance: Distance) -> String {
        guard distance.length > 0 else { return "--" }
        return distance.units.format(distance.length, to: appSettings.preferredDistanceUnit)
    }

    // MARK: - Car

    private func car(height: CGFloat) -> some View {
        let doorsOpen = vehicle.doorOpen?.anyOpen ?? false
        let symbol = doorsOpen
            ? Image("custom.car.side.rear.open.front.open")
            : Image(systemName: "car.side.fill")
        return ZStack(alignment: .bottom) {
            // Ground shadow.
            Ellipse()
                .fill(.black.opacity(0.28))
                .frame(width: height * 1.9, height: height * 0.12)
                .blur(radius: 10)
                .offset(y: height * 0.02)
            symbol
                .resizable()
                .scaledToFit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [vehicle.primaryColor.mix(with: .white, by: 0.25), vehicle.primaryColor.mix(with: .black, by: 0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: vehicle.primaryColor.opacity(0.35), radius: 24, y: 8)
                .frame(height: height)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: height * 1.08)
        .accessibilityElement()
        .accessibilityLabel("\(vehicle.displayName)\(doorsOpen ? ", door open" : "")")
    }

    // MARK: - Status chips

    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chipContent }
            ScrollView(.horizontal) {
                HStack(spacing: 8) { chipContent }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollEdgeEffectStyle(.none, for: .all)
        }
    }

    /// Walk-up checks the sheet's controls don't already show: lock,
    /// climate and charging have rows of their own right below.
    @ViewBuilder
    private var chipContent: some View {
        if let openings = openingsText {
            StatusChip(
                icon: openings.isOpen ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                text: openings.text,
                tint: openings.isOpen ? .orange : .green
            )
        }

        if let tires = vehicle.tirePressureWarning {
            StatusChip(
                icon: tires.hasWarning ? "exclamationmark.tirepressure" : "tirepressure",
                text: tires.hasWarning ? "Check Tires" : "Tires OK",
                tint: tires.hasWarning ? .orange : .green
            )
        }

        if let battery = vehicle.battery12V, (0...100).contains(battery) {
            StatusChip(
                icon: "minus.plus.batteryblock.fill",
                text: "12V \(battery)%",
                tint: battery < 30 ? .red : (battery < 50 ? .orange : .green)
            )
        }
    }

    /// Doors, trunk and hood rolled into one chip: what's open, or
    /// "All Closed".
    private var openingsText: (text: String, isOpen: Bool)? {
        let door = vehicle.doorOpen?.anyOpen
        let trunk = vehicle.trunkOpen
        let hood = vehicle.hoodOpen
        guard door != nil || trunk != nil || hood != nil else { return nil }
        var open: [String] = []
        if door == true { open.append("Door") }
        if trunk == true { open.append("Trunk") }
        if hood == true { open.append("Hood") }
        if open.isEmpty { return ("All Closed", false) }
        return ("\(open.formatted(.list(type: .and))) Open", true)
    }

    // MARK: - Map button

    /// Round glass button under the floating settings button that opens
    /// the vehicle's map.
    @ViewBuilder
    private var mapButton: some View {
        if vehicle.coordinate != nil {
            Button {
                sheetPresentation.show(.vehicleMap(vehicle: vehicle))
            } label: {
                Image(systemName: "map.fill")
                    .imageScale(.large)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show on Map")
        }
    }
}

// MARK: - Pieces

private struct StatusChip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.primary)
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }
}

/// Soft light behind the car in the vehicle's accent color, over the
/// system background so it reads in both light and dark mode.
private struct HeroBackdrop: View {
    let tint: Color

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            RadialGradient(
                colors: [tint.opacity(0.35), tint.opacity(0.08), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 10,
                endRadius: 420
            )
            LinearGradient(
                colors: [.clear, tint.opacity(0.12)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Map sheet

/// Full map for the selected vehicle, opened from the hero's Location
/// chip.
struct VehicleMapSheet: View {
    let vehicle: BBVehicle
    let onDone: () -> Void
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                if let coordinate = vehicle.coordinate {
                    Map(position: $position) {
                        Annotation(vehicle.displayName, coordinate: coordinate) {
                            VehicleMapMarker(vehicle: vehicle, coordinate: coordinate)
                        }
                        UserAnnotation()
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                    }
                    .onAppear {
                        position = .region(MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                    .safeAreaInset(edge: .bottom) {
                        navigateButton(to: coordinate)
                    }
                } else {
                    ContentUnavailableView(
                        "No Location",
                        systemImage: "location.slash",
                        description: Text("No location received from \(vehicle.displayName).")
                    )
                }
            }
            .navigationTitle(vehicle.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    @ViewBuilder
    private func navigateButton(to coordinate: CLLocationCoordinate2D) -> some View {
        let apps = NavigationHelper.availableMapApps
        Group {
            if apps.count == 1 {
                Button {
                    NavigationHelper.navigate(using: apps[0], to: coordinate, destinationName: vehicle.displayName)
                } label: {
                    navigateLabel
                }
            } else {
                Menu {
                    NavigationMenuContent(coordinate: coordinate, destinationName: vehicle.displayName)
                } label: {
                    navigateLabel
                }
            }
        }
        .buttonStyle(.glassProminent)
        .tint(vehicle.primaryColor)
        .padding()
    }

    private var navigateLabel: some View {
        Label("Navigate to Vehicle", systemImage: "location.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

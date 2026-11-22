//
//  NMapView.swift
//  N Link
//
//  Where the car is: dark map, accent marker, address, and Navigate.
//

import BetterBlueKit
import MapKit
import SwiftUI

struct NMapView: View {
    let vehicle: BBVehicle

    @State private var position: MapCameraPosition = .automatic
    @State private var address: String?
    @State private var geocodedFor: VehicleStatus.Location?

    var body: some View {
        ZStack(alignment: .top) {
            if let coordinate = vehicle.coordinate {
                Map(position: $position) {
                    Annotation(vehicle.displayName, coordinate: coordinate, anchor: .center) {
                        marker
                    }
                    .annotationTitles(.hidden)
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .mapControls { MapCompass() }
                .ignoresSafeArea(edges: .top)
                .onAppear { center(on: coordinate) }
                .onChange(of: vehicle.location) { _, _ in
                    if let coordinate = vehicle.coordinate { center(on: coordinate) }
                }
                .task(id: vehicle.location) { await geocode() }
                .safeAreaInset(edge: .bottom, spacing: 0) { card(coordinate: coordinate) }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 34))
                        .foregroundStyle(NTheme.textSecondary)
                    Text("No location received from \(vehicle.displayName)")
                        .font(.system(size: 15))
                        .foregroundStyle(NTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NTheme.ground.ignoresSafeArea())
            }
            HStack {
                Text("Map")
                    .font(NTheme.display(20))
                    .foregroundStyle(NTheme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(NTheme.ground.opacity(0.85), in: Capsule())
                    .overlay(Capsule().strokeBorder(NTheme.border))
                Spacer()
                if let coordinate = vehicle.coordinate {
                    NIconButton(systemImage: "scope", accessibilityLabel: "Center on car") {
                        withAnimation { center(on: coordinate) }
                    }
                }
            }
            .padding(.horizontal, NTheme.screenHorizontal)
            .padding(.top, NTheme.screenTop)
        }
    }

    private var marker: some View {
        ZStack {
            Circle()
                .fill(NTheme.accent.opacity(0.18))
                .frame(width: 66, height: 66)
            Circle()
                .fill(NTheme.accent)
                .frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(NTheme.ground, lineWidth: 3))
            Image(systemName: "car.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(NTheme.onAccent)
        }
        .accessibilityLabel(vehicle.displayName)
    }

    private func card(coordinate: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(address ?? vehicle.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NTheme.text)
                    .lineLimit(2)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(NFormat.updated(vehicle.lastUpdated, now: context.date)
                        .replacingOccurrences(of: "Updated", with: "Located"))
                        .font(.system(size: 13))
                        .foregroundStyle(NTheme.textSecondary)
                }
            }
            navigateButton(to: coordinate)
        }
        .padding(18)
        .background(NTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(NTheme.border))
        .padding(.horizontal, NTheme.screenHorizontal)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func navigateButton(to coordinate: CLLocationCoordinate2D) -> some View {
        let apps = NavigationHelper.availableMapApps
        if apps.count == 1 {
            Button {
                NavigationHelper.navigate(using: apps[0], to: coordinate, destinationName: vehicle.displayName)
            } label: {
                Label("Navigate", systemImage: "location.fill")
            }
            .menuStyle(.button)
            .buttonStyle(.nPrimary)
        } else {
            Menu {
                NavigationMenuContent(coordinate: coordinate, destinationName: vehicle.displayName)
            } label: {
                Label("Navigate", systemImage: "location.fill")
            }
            .menuStyle(.button)
            .buttonStyle(.nPrimary)
        }
    }

    private func center(on coordinate: CLLocationCoordinate2D) {
        position = .camera(MapCamera(centerCoordinate: coordinate, distance: 900, heading: 0, pitch: 0))
    }

    private func geocode() async {
        guard let location = vehicle.location, location.hasCoordinates, location != geocodedFor else { return }
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        guard let request = MKReverseGeocodingRequest(location: clLocation) else { return }
        do {
            let items = try await request.mapItems
            if let item = items.first {
                address = item.address?.shortAddress ?? item.name
                geocodedFor = location
            }
        } catch {
            BBLogger.debug(.app, "NMapView: reverse geocode failed: \(error.localizedDescription)")
        }
    }
}

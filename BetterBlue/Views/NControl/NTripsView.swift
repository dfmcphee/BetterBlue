//
//  NTripsView.swift
//  N Link
//
//  Week / month totals, distance per day, and recent trips — all
//  computed in the app from the EV trip summary list the server returns.
//

import BetterBlueKit
import SwiftData
import SwiftUI

struct NTripsView: View {
    let vehicle: BBVehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(VehicleSheetPresentation.self) private var sheetPresentation

    enum Period: String, CaseIterable { case week = "Week", month = "Month" }

    @State private var period: Period = .week
    @State private var trips: [EVTripSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var unsupported = false
    @State private var loadedVehicleID: UUID?

    private var distanceUnit: Distance.Units { NFormat.distanceUnit }
    private var efficiencyUnit: EfficiencyUnit { AppSettings.shared.preferredEfficiencyUnit }

    private var periodStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        switch period {
        case .week: return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        }
    }

    private var periodTrips: [EVTripSummary] {
        trips.filter { $0.startDate >= periodStart }.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if unsupported {
                    message("Trip history isn't available for this vehicle.")
                } else if let loadError, trips.isEmpty {
                    message(loadError)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.nSecondary)
                } else if isLoading && trips.isEmpty {
                    ProgressView().tint(NTheme.text).frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    totals
                    chart
                    recent
                    if trips.first.map({ $0.startDate > periodStart }) == true, period == .month {
                        Text("Hyundai only returns your most recent trips, so older days may be missing.")
                            .font(.system(size: 12))
                            .foregroundStyle(NTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, NTheme.screenHorizontal)
            .padding(.top, NTheme.screenTop)
            .padding(.bottom, NTheme.screenBottom)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
        .background(NTheme.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: vehicle.id) {
            if loadedVehicleID != vehicle.id {
                trips = []
                await load()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Trips")
                .font(NTheme.display(30))
                .foregroundStyle(NTheme.text)
            Spacer()
            HStack(spacing: 2) {
                ForEach(Period.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.snappy) { period = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: period == item ? .semibold : .regular))
                            .foregroundStyle(period == item ? NTheme.text : NTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(period == item ? NTheme.border : .clear,
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(period == item ? .isSelected : [])
                }
            }
            .padding(3)
            .background(NTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NTheme.border))
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(NTheme.textSecondary)
            .nCard()
    }

    // MARK: - Totals

    private var totals: some View {
        let list = periodTrips
        let distance = list.reduce(0.0) { $0 + $1.distance.units.convert($1.distance.length, to: distanceUnit) }
        let energy = list.reduce(0) { $0 + $1.totalEnergyUsed }
        let efficiency = efficiencyUnit.value(
            distance: Distance(length: distance, units: distanceUnit), energyWh: energy
        )
        return HStack(spacing: 8) {
            totalTile("Distance", value: distance.formatted(.number.precision(.fractionLength(0))),
                      unit: distanceUnit.abbreviation)
            totalTile("Efficiency",
                      value: efficiency.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                      unit: efficiencyUnit.abbreviation)
            totalTile("Energy", value: (Double(energy) / 1000).formatted(.number.precision(.fractionLength(0))),
                      unit: "kWh")
        }
    }

    private func totalTile(_ label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NCapsLabel(label)
            Text(value)
                .font(NTheme.display(26))
                .foregroundStyle(NTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(size: 12))
                .foregroundStyle(NTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .nCard(radius: 14, padding: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Chart

    private struct DayBucket: Identifiable {
        let date: Date
        let distance: Double
        var id: Date { date }
    }

    private var buckets: [DayBucket] {
        let calendar = Calendar.current
        let days = period == .week ? 7 : 30
        let today = calendar.startOfDay(for: .now)
        var totals: [Date: Double] = [:]
        for trip in periodTrips {
            let day = calendar.startOfDay(for: trip.startDate)
            totals[day, default: 0] += trip.distance.units.convert(trip.distance.length, to: distanceUnit)
        }
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map {
                DayBucket(date: $0, distance: totals[$0] ?? 0)
            }
        }
    }

    private var chart: some View {
        let data = buckets
        let maxDistance = max(data.map(\.distance).max() ?? 0, 1)
        let best = data.max { $0.distance < $1.distance }
        let blocks = 8
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Distance per day")
                    .font(.system(size: 13))
                    .foregroundStyle(NTheme.textSecondary)
                Spacer()
                if let best, best.distance > 0 {
                    Text("\(best.date.formatted(.dateTime.weekday(.abbreviated).day())) · \(best.distance.formatted(.number.precision(.fractionLength(0)))) \(distanceUnit.abbreviation)")
                        .font(.system(size: 13))
                        .foregroundStyle(NTheme.text)
                }
            }
            HStack(alignment: .bottom, spacing: period == .week ? 0 : 2) {
                ForEach(data) { bucket in
                    let lit = bucket.distance > 0
                        ? max(1, Int((bucket.distance / maxDistance * Double(blocks)).rounded()))
                        : 0
                    let isBest = bucket.id == best?.id && bucket.distance > 0
                    VStack(spacing: 3) {
                        ForEach((0..<blocks).reversed(), id: \.self) { index in
                            Rectangle()
                                .fill(index < lit ? (isBest ? NTheme.accent : Color(hex: 0x8A8A8A)) : NTheme.track)
                                .frame(height: 10)
                        }
                        if period == .week {
                            Text(bucket.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 12))
                                .foregroundStyle(isBest ? NTheme.text : NTheme.textSecondary)
                                .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: period == .week ? 22 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .nCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartAccessibilityLabel(best: best))
    }

    private func chartAccessibilityLabel(best: DayBucket?) -> String {
        guard let best, best.distance > 0 else { return "No trips in this period" }
        return "Distance per day. Most on \(best.date.formatted(.dateTime.weekday(.wide))), \(Int(best.distance)) \(distanceUnit.abbreviation)"
    }

    // MARK: - Recent

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NCapsLabel("Recent")
                Spacer()
                Button("Energy details ›") {
                    sheetPresentation.show(.tripDetails(vehicle: vehicle))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NTheme.textSecondary)
                .frame(minHeight: 44)
            }
            let list = Array(periodTrips.prefix(period == .week ? 6 : 15))
            if list.isEmpty {
                message("No trips in this period.")
            } else {
                NGroup {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, trip in
                        tripRow(trip, showsDivider: index < list.count - 1)
                    }
                }
            }
        }
    }

    private func tripRow(_ trip: EVTripSummary, showsDivider: Bool) -> some View {
        let distance = trip.distance.units.convert(trip.distance.length, to: distanceUnit)
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLabel(trip.startDate))
                        .font(.system(size: 15))
                        .foregroundStyle(NTheme.text)
                    Text("\(trip.formattedDuration) · \(efficiencyUnit.format(distance: trip.distance, energyWh: trip.totalEnergyUsed))")
                        .font(.system(size: 12))
                        .foregroundStyle(NTheme.textSecondary)
                }
                Spacer()
                Text("\(distance.formatted(.number.precision(.fractionLength(1)))) \(distanceUnit.abbreviation)")
                    .font(NTheme.display(20))
                    .foregroundStyle(NTheme.text)
            }
            .frame(minHeight: 60)
            .padding(.horizontal, 14)
            if showsDivider { Rectangle().fill(NTheme.hairline).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
    }

    private func dayLabel(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today, \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(time)"
    }

    // MARK: - Loading

    private func load() async {
        guard let account = vehicle.account else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let fetched = try await account.fetchEVTripSummary(for: vehicle, modelContext: modelContext) {
                trips = fetched
                unsupported = false
                loadError = nil
            } else {
                unsupported = true
            }
            loadedVehicleID = vehicle.id
        } catch is CancellationError {
            return
        } catch {
            let apiError = error as? APIError
            loadError = apiError.map { VehicleCommandRunner.friendlyMessage(for: $0, action: "Load trips") }
                ?? "Couldn't load trips: \(error.localizedDescription)"
        }
    }
}

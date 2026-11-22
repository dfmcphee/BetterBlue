//
//  NSecurityView.swift
//  N Link
//
//  Lock state, openings, tires and 12V, drawn around a top-down car.
//

import BetterBlueKit
import SwiftData
import SwiftUI

struct NSecurityView: View {
    let vehicle: BBVehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(VehicleCommandRunner.self) private var runner

    private var locked: Bool { vehicle.lockStatus == .locked }

    var body: some View {
        NPushedScreen(title: "Security", subtitle: NFormat.updated(vehicle.lastUpdated)) {
            stage
            HStack(spacing: 10) {
                NCommandButton(
                    title: "Lock",
                    systemImage: "lock.fill",
                    kind: locked ? .secondary : .primary,
                    height: 56,
                    isBusy: runner.pendingLockTarget == true,
                    busyText: runner.statusText[.lock]
                ) {
                    Task { await runner.setLocked(true, modelContext: modelContext) }
                }
                NCommandButton(
                    title: "Unlock",
                    systemImage: "lock.open.fill",
                    kind: locked ? .primary : .secondary,
                    height: 56,
                    isBusy: runner.pendingLockTarget == false,
                    busyText: runner.statusText[.lock]
                ) {
                    Task { await runner.setLocked(false, modelContext: modelContext) }
                }
            }
            .disabled(runner.isBusy(.lock))
            details
            NavigationLink {
                WalkAwayLockGuideView()
            } label: {
                HStack {
                    Text("Walk-away lock with Shortcuts")
                        .font(.system(size: 15))
                        .foregroundStyle(NTheme.text)
                    Spacer()
                    Text("›").foregroundStyle(NTheme.textSecondary)
                }
                .frame(minHeight: 52)
                .padding(.horizontal, 16)
                .background(NTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NTheme.border))
            }
            .buttonStyle(.plain)
        }
    }

    private var lockTitle: String {
        switch vehicle.lockStatus {
        case .locked: "LOCKED"
        case .unlocked: "UNLOCKED"
        default: "UNKNOWN"
        }
    }

    private var stage: some View {
        ZStack {
            NCarTopView(
                locked: locked,
                doors: vehicle.doorOpen,
                trunkOpen: vehicle.trunkOpen == true,
                hoodOpen: vehicle.hoodOpen == true
            )
            .frame(width: 150, height: 290)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            Text(lockTitle)
                .font(NTheme.display(18, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(locked ? NTheme.text : NTheme.accent)
                .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            Text(NFormat.openingsSummary(vehicle).text)
                .font(.system(size: 12))
                .foregroundStyle(NTheme.textSecondary)
                .padding(16)
        }
        .background(Color(hex: 0x0C0C0C), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(NTheme.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lockTitle.capitalized). \(NFormat.openingsSummary(vehicle).text)")
    }

    private var details: some View {
        NGroup {
            NRow("Doors", value: doorsText)
            NRow("Trunk & hood", value: trunkHoodText)
            NRow("Tire pressure", value: vehicle.tirePressureWarning.map { $0.hasWarning ? "Check \($0.warningDescription)" : "OK" } ?? "—")
            NRow("12V battery", value: vehicle.battery12V.map { "\($0)%" } ?? "—", showsDivider: false)
        }
    }

    private var doorsText: String {
        guard let doors = vehicle.doorOpen else { return "—" }
        return doors.anyOpen ? "Open: \(doors.openDoorsDescription)" : "All closed"
    }

    private var trunkHoodText: String {
        switch (vehicle.trunkOpen, vehicle.hoodOpen) {
        case (nil, nil): return "—"
        case (true, true): return "Both open"
        case (true, _): return "Trunk open"
        case (_, true): return "Hood open"
        default: return "Closed"
        }
    }
}

/// Simple top-down car. Open doors / trunk / hood light up in the accent.
struct NCarTopView: View {
    let locked: Bool
    let doors: VehicleStatus.DoorStatus?
    let trunkOpen: Bool
    let hoodOpen: Bool

    var body: some View {
        Canvas { context, size in
            let sx = size.width / 150, sy = size.height / 290
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)
            }
            let tire = Color(hex: 0x1F1F1F)
            for (x, y) in [(10.0, 44.0), (130.0, 44.0), (10.0, 204.0), (130.0, 204.0)] {
                context.fill(Path(roundedRect: rect(x, y, 10, 40), cornerRadius: 3), with: .color(tire))
            }
            let body = Path(roundedRect: rect(18, 8, 114, 274), cornerRadius: 34 * sx)
            context.fill(body, with: .color(Color(hex: 0x141414)))
            context.stroke(body, with: .color(Color(hex: 0x3A3A3A)), lineWidth: 1.5)

            // Hood / trunk panels.
            let accent = NTheme.accent
            if hoodOpen {
                context.fill(Path(roundedRect: rect(30, 24, 90, 52), cornerRadius: 14), with: .color(accent.opacity(0.85)))
            }
            if trunkOpen {
                context.fill(Path(roundedRect: rect(30, 238, 90, 30), cornerRadius: 10), with: .color(accent.opacity(0.85)))
            }

            var windshield = Path()
            windshield.move(to: CGPoint(x: 32 * sx, y: 84 * sy))
            windshield.addQuadCurve(to: CGPoint(x: 118 * sx, y: 84 * sy), control: CGPoint(x: 75 * sx, y: 64 * sy))
            windshield.addLine(to: CGPoint(x: 112 * sx, y: 120 * sy))
            windshield.addQuadCurve(to: CGPoint(x: 38 * sx, y: 120 * sy), control: CGPoint(x: 75 * sx, y: 110 * sy))
            windshield.closeSubpath()
            context.fill(windshield, with: .color(Color(hex: 0x0A0A0A)))
            context.stroke(windshield, with: .color(Color(hex: 0x2B2B2B)), lineWidth: 1.5)

            let roof = Path(roundedRect: rect(40, 126, 70, 70), cornerRadius: 8)
            context.fill(roof, with: .color(Color(hex: 0x101010)))
            context.stroke(roof, with: .color(Color(hex: 0x262626)), lineWidth: 1.5)

            var rear = Path()
            rear.move(to: CGPoint(x: 38 * sx, y: 202 * sy))
            rear.addQuadCurve(to: CGPoint(x: 112 * sx, y: 202 * sy), control: CGPoint(x: 75 * sx, y: 212 * sy))
            rear.addLine(to: CGPoint(x: 116 * sx, y: 230 * sy))
            rear.addQuadCurve(to: CGPoint(x: 34 * sx, y: 230 * sy), control: CGPoint(x: 75 * sx, y: 244 * sy))
            rear.closeSubpath()
            context.fill(rear, with: .color(Color(hex: 0x0A0A0A)))
            context.stroke(rear, with: .color(Color(hex: 0x2B2B2B)), lineWidth: 1.5)

            // Doors: thin bars along the sides, lit when open.
            let doorStates: [(CGFloat, CGFloat, Bool)] = [
                (14, 100, doors?.frontLeft == true), (130, 100, doors?.frontRight == true),
                (14, 162, doors?.backLeft == true), (130, 162, doors?.backRight == true),
            ]
            for (x, y, open) in doorStates {
                let bar = Path(roundedRect: rect(x, y, 6, 54), cornerRadius: 3)
                context.fill(bar, with: .color(open ? accent : Color(hex: 0x262626)))
            }

            // Headlights (white) and tail-lights (accent), pixel style.
            for x in [30.0, 39, 48, 96, 105, 114] {
                context.fill(Path(rect(x, 14, 6, 6)), with: .color(NTheme.text))
                context.fill(Path(rect(x, 270, 6, 6)), with: .color(accent))
            }
        }
        .overlay {
            Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(locked ? NTheme.onAccent : NTheme.onAccent)
                .frame(width: 44, height: 44)
                .background(locked ? NTheme.text : NTheme.accent, in: Circle())
                .offset(y: 16)
        }
        .accessibilityHidden(true)
    }
}

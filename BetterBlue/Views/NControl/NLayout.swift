//
//  NLayout.swift
//  N Link
//
//  Picks the N Link layout for the window, and finds where the
//  iPhone Duo's inner display divides into two panes.
//

import SwiftUI
import UIKit

enum NLayoutMode: Equatable {
    /// Regular phone: single column, bottom tab bar.
    case standard
    /// Short, wide window (iPhone Duo outer display, 466×678): quick
    /// controls without scrolling.
    case glance
    /// Wide landscape window (iPhone Duo unfolded, 951×669): instrument
    /// cluster on one pane, workspace on the other.
    case cockpit

    static func resolve(for size: CGSize) -> NLayoutMode {
        if size.width >= 820, size.width > size.height, size.height >= 560 {
            return .cockpit
        }
        // Squat portrait phone window: the Duo's outer display is about
        // 1.4:1, regular iPhones about 2:1. Width cap keeps iPads out.
        if size.height > size.width, size.width < 600, size.height / size.width < 1.6 {
            return .glance
        }
        return .standard
    }
}

/// Set on the right-hand pane of the cockpit: pushed-screen chrome drops
/// its back button there, since the screen is a pane, not a push.
private struct NEmbeddedPaneKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nEmbeddedPane: Bool {
        get { self[NEmbeddedPaneKey.self] }
        set { self[NEmbeddedPaneKey.self] = newValue }
    }
}

/// Where the display divides into two panes, in the reading view's
/// coordinate space — the hinge seam's "division" reserved region,
/// including its margins. `nil` on displays without one.
struct NDivision: Equatable {
    var minX: CGFloat
    var maxX: CGFloat
}

/// Reports the active division region (the Duo's seam) under the view
/// it backs. UIKit has no change callback for reserved regions, so this
/// re-reads them on every layout pass — which fires on rotation, fold
/// and window resize, the only times the seam can move.
struct NDivisionReader: UIViewRepresentable {
    let onChange: (NDivision?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
        view.setNeedsLayout()
    }

    final class ProbeView: UIView {
        var onChange: ((NDivision?) -> Void)?
        private var last: NDivision??

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        private func report() {
            var division: NDivision?
            if #available(iOS 27.1, *) {
                let regions = reservedRegions(kind: .division).filter(\.isActive)
                if let region = regions.first(where: { $0.frame.height >= $0.frame.width }) {
                    division = NDivision(minX: region.frame.minX, maxX: region.frame.maxX)
                }
            }
            guard last != .some(division) else { return }
            last = .some(division)
            let callback = onChange
            DispatchQueue.main.async { callback?(division) }
        }
    }
}

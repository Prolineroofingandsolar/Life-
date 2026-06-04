import SwiftUI
import MapKit
import CoreLocation

// MARK: - World Map View

struct WorldMapView: View {
    @Environment(AppState.self) private var appState
    @State private var locationManager: LocationManager?

    var body: some View {
        ZStack {
            FogMapView(visitedLocations: appState.visitedLocations)
                .ignoresSafeArea()

            if appState.visitedLocations.isEmpty {
                emptyState
            }

            VStack {
                Spacer()
                statsStrip
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            if locationManager == nil {
                locationManager = LocationManager(appState: appState)
            }
            locationManager?.requestPermissionAndStart()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "map.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.5))
            Text("Your World Awaits")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Open this tab while you're out and\nabout — the map reveals as you explore.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .background(.ultraThinMaterial.opacity(0.7))
        .cornerRadius(16)
        .padding(.horizontal, 40)
    }

    // MARK: - Stats Strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statItem(value: "\(appState.visitedLocations.count)", label: "Places")
            Divider().frame(height: 30).opacity(0.3)
            statItem(value: estimatedCountries, label: "Countries")
            Divider().frame(height: 30).opacity(0.3)
            statItem(value: exploredPercent, label: "Explored")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .padding(.bottom, 84)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "#30d158"))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var estimatedCountries: String {
        // Very rough estimate: each 500km cluster = 1 country
        guard !appState.visitedLocations.isEmpty else { return "0" }
        var clusters = 0
        var assigned: Set<String> = []
        for loc in appState.visitedLocations {
            guard !assigned.contains(loc.id) else { continue }
            clusters += 1
            assigned.insert(loc.id)
            let clusterCenter = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
            for other in appState.visitedLocations where !assigned.contains(other.id) {
                let otherLoc = CLLocation(latitude: other.latitude, longitude: other.longitude)
                if clusterCenter.distance(from: otherLoc) < 500_000 {
                    assigned.insert(other.id)
                }
            }
        }
        return "\(clusters)"
    }

    private var exploredPercent: String {
        // Total revealed area (assuming 2km radius per point, no overlap correction for simplicity)
        let radiusKm = 2.0
        let circleAreaKm2 = Double.pi * radiusKm * radiusKm
        let revealed = Double(appState.visitedLocations.count) * circleAreaKm2
        let earthSurfaceKm2 = 510_072_000.0
        let pct = min(100, revealed / earthSurfaceKm2 * 100)
        return String(format: "%.3f%%", pct)
    }
}

// MARK: - Fog Map View (UIViewRepresentable)

struct FogMapView: UIViewRepresentable {
    let visitedLocations: [VisitedLocation]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .standard
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = false
        map.showsUserLocation = true
        map.delegate = context.coordinator

        // Start zoomed to world view
        let worldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 180)
        )
        map.setRegion(worldRegion, animated: false)

        let fog = WorldFogOverlay(visitedLocations: visitedLocations)
        map.addOverlay(fog, level: .aboveRoads)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        let fog = WorldFogOverlay(visitedLocations: visitedLocations)
        map.addOverlay(fog, level: .aboveRoads)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let fog = overlay as? WorldFogOverlay {
                return WorldFogRenderer(overlay: fog)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Fog Overlay

final class WorldFogOverlay: NSObject, MKOverlay {
    let visitedLocations: [VisitedLocation]

    init(visitedLocations: [VisitedLocation]) {
        self.visitedLocations = visitedLocations
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    var boundingMapRect: MKMapRect { .world }
}

// MARK: - Fog Renderer

final class WorldFogRenderer: MKOverlayRenderer {
    private var fog: WorldFogOverlay { overlay as! WorldFogOverlay }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // Fill entire world with dark fog
        let fogColor = UIColor.black.withAlphaComponent(0.72)
        context.setFillColor(fogColor.cgColor)
        let rect = self.rect(for: .world)
        context.fill(rect)

        // Punch holes for each visited location
        context.setBlendMode(.clear)
        for loc in fog.visitedLocations {
            let center = MKMapPoint(CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude))
            let radiusMeters = loc.revealRadiusKm * 1000
            let metersPerMapPoint = MKMetersPerMapPointAtLatitude(loc.latitude)
            guard metersPerMapPoint > 0 else { continue }
            let radiusMapPoints = radiusMeters / metersPerMapPoint
            let circleRect = MKMapRect(
                x: center.x - radiusMapPoints,
                y: center.y - radiusMapPoints,
                width: radiusMapPoints * 2,
                height: radiusMapPoints * 2
            )
            let cgRect = self.rect(for: circleRect)
            context.fillEllipse(in: cgRect)
        }
        context.setBlendMode(.normal)
    }
}

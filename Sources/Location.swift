import CoreLocation
import Observation

/// Finds where you are (with permission) or looks up any place by name, and writes it into the settings.
@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var status: CLAuthorizationStatus
    var busy = false
    var message: String?
    var results: [CLPlacemark] = []

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private let state: WallState
    @ObservationIgnored private var wantsFix = false

    init(state: WallState) {
        self.state = state
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorized: Bool { status == .authorizedAlways }
    var denied: Bool { status == .denied || status == .restricted }

    /// Asks for permission the first time, then takes a single, city-level fix.
    func locate() {
        message = nil
        wantsFix = true
        busy = true
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorized {
            manager.requestLocation()
        } else {
            busy = false
            message = "Location access is off for Dayshade. Turn it on in System Settings › Privacy & Security › Location Services, or search for a place instead."
        }
    }

    /// Refreshes the position after waking, in case you have travelled. Never prompts.
    func refreshIfAuto() {
        if state.settings.locationMode == .auto && authorized { locate() }
    }

    func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        busy = true
        message = nil
        geocoder.geocodeAddressString(q) { [weak self] marks, _ in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.results = Array((marks ?? []).filter { $0.location != nil }.prefix(6))
                if self.results.isEmpty { self.message = "No place found for “\(q)”." }
            }
        }
    }

    func choose(_ mark: CLPlacemark) {
        guard let loc = mark.location else { return }
        state.settings.locationMode = .manual
        apply(loc.coordinate, name: Self.name(of: mark))
        results = []
    }

    static func name(of mark: CLPlacemark) -> String {
        [mark.locality ?? mark.name, mark.country].compactMap { $0 }.joined(separator: ", ")
    }

    private func apply(_ c: CLLocationCoordinate2D, name: String) {
        state.settings.latitude = (c.latitude * 100).rounded() / 100
        state.settings.longitude = (c.longitude * 100).rounded() / 100
        state.settings.place = name
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            guard self.wantsFix else { return }
            if self.authorized { self.manager.requestLocation() } else if s != .notDetermined { self.locate() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.wantsFix = false
            self.apply(loc.coordinate, name: self.state.settings.place)
            self.geocoder.reverseGeocodeLocation(loc) { [weak self] marks, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.busy = false
                    if let m = marks?.first { self.state.settings.place = Self.name(of: m) }
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in
            self.wantsFix = false
            self.busy = false
            self.message = "Couldn't find your location: \(text)"
        }
    }
}

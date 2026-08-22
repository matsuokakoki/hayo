import SwiftUI
import Combine
import GoogleMaps
import CoreLocation
import MapKit

// ② Group creation: name, destination (Google Maps), meet time.
struct CreateGroupView: View {
    @EnvironmentObject var app: AppState
    // Observed so the preview re-centers when the first GPS fix arrives.
    @ObservedObject private var location = LocationService.shared
    @State private var name = ""
    @State private var destination: CLLocationCoordinate2D?
    @State private var meetTime = Date().addingTimeInterval(3600)
    @State private var showPicker = false
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button { app.screen = .start } label: {
                Image(systemName: "chevron.left").font(.title3)
            }

            Text("グループ名").font(.headline)
            TextField("例: THE HACK 2026", text: $name)
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))

            Text("目的地").font(.headline)
            // Map + caption as one unit with a uniform 8pt gap (matches other screens).
            VStack(spacing: 8) {
                Button { showPicker = true } label: {
                    // Before a destination is chosen, preview the user's current location.
                    StaticMapPreview(coordinate: destination ?? currentCoordinate,
                                     showsMarker: destination != nil)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Text(destination == nil
                     ? "タッチして地図から目的地を選択"
                     : "タッチして目的地を変更")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text("集合時間").font(.headline)
            DatePicker("", selection: $meetTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ja_JP"))

            Spacer()

            HStack {
                Spacer()
                Button { create() } label: {
                    if isCreating {
                        ProgressView().frame(width: 220, height: 56)
                    } else {
                        Text("グループを作成")
                            .font(.headline).foregroundColor(.white)
                            .frame(width: 220, height: 56)
                            .background(Capsule().fill(canCreate ? Color.blue : Color.gray))
                    }
                }
                .disabled(!canCreate || isCreating)
                Spacer()
            }
        }
        .padding(24)
        // Start GPS early so the picker can open centered on the current location.
        .onAppear { LocationService.shared.start() }
        .sheet(isPresented: $showPicker) {
            DestinationPickerView(selected: $destination)
        }
    }

    private var canCreate: Bool { !name.isEmpty && destination != nil }

    /// Current location, falling back to Tokyo until the first GPS fix.
    private var currentCoordinate: CLLocationCoordinate2D {
        location.current?.coordinate
            ?? CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
    }

    private func create() {
        guard let destination else { return }
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                let result = try await GroupRepository.shared.createGroup(
                    name: name, destination: destination, meetTime: meetTime)
                app.screen = .inviteCode(groupId: result.groupId, code: result.code)
            } catch {
                app.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Non-interactive map preview

struct StaticMapPreview: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    /// Red destination pin. Off when previewing the user's own location.
    var showsMarker: Bool = true

    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView(frame: .zero,
                             camera: GMSCameraPosition(target: coordinate, zoom: 15))
        map.isUserInteractionEnabled = false
        map.isMyLocationEnabled = true
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        map.clear()
        map.animate(to: GMSCameraPosition(target: coordinate, zoom: 15))
        guard showsMarker else { return }
        let marker = GMSMarker(position: coordinate)
        marker.icon = GMSMarker.markerImage(with: .red)
        marker.map = map
    }
}

// MARK: - Full-screen destination picker (search or tap to drop pin)

struct DestinationPickerView: View {
    @Binding var selected: CLLocationCoordinate2D?
    @Environment(\.dismiss) var dismiss
    @State private var temp: CLLocationCoordinate2D?
    @State private var focus: CLLocationCoordinate2D?

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TapPickerMap(selected: $temp, focus: focus)
                .ignoresSafeArea()

            // Search bar + results (top)
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("場所を検索（例: 渋谷駅）", text: $query)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { search() }
                    if !query.isEmpty {
                        Button {
                            query = ""; results = []
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.thickMaterial))

                if searching {
                    ProgressView().padding(8)
                } else if !results.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.prefix(6).enumerated()), id: \.offset) { _, item in
                                Button {
                                    pick(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "名称不明")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.primary)
                                        if let address = item.placemark.title {
                                            Text(address)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.thickMaterial))
                    .padding(.top, 4)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Confirm (bottom)
            VStack(spacing: 8) {
                Text(temp == nil ? "検索するか、地図をタップして目的地を設定" : "この場所でよろしいですか？")
                    .font(.subheadline.bold())
                    .padding(8)
                    .background(Capsule().fill(.thinMaterial))
                Button {
                    selected = temp
                    dismiss()
                } label: {
                    Text("目的地に決定")
                        .font(.headline).foregroundColor(.white)
                        .frame(width: 220, height: 52)
                        .background(Capsule().fill(temp == nil ? Color.gray : Color.blue))
                }
                .disabled(temp == nil)
            }
            .padding(.bottom, 32)
        }
    }

    /// MKLocalSearch: POI search with no API key (keeps the Maps key restricted).
    private func search() {
        guard !query.isEmpty else { return }
        searching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let center = LocationService.shared.current?.coordinate {
            request.region = MKCoordinateRegion(center: center,
                                                latitudinalMeters: 50_000,
                                                longitudinalMeters: 50_000)
        }
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                searching = false
                results = response?.mapItems ?? []
            }
        }
    }

    private func pick(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        temp = coordinate
        focus = coordinate      // moves the camera and drops the pin
        results = []
        query = item.name ?? query
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

struct TapPickerMap: UIViewRepresentable {
    @Binding var selected: CLLocationCoordinate2D?
    var focus: CLLocationCoordinate2D?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        // Center on the user's current location; fall back to Tokyo until a GPS fix arrives.
        let current = LocationService.shared.current?.coordinate
        let target = current ?? CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
        let map = GMSMapView(frame: .zero,
                             camera: GMSCameraPosition(target: target, zoom: 15))
        map.delegate = context.coordinator
        map.isMyLocationEnabled = true
        map.settings.myLocationButton = true
        context.coordinator.observeLocation(map: map, alreadyCentered: current != nil)
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        // A search result was picked: move the camera there and drop the pin.
        if let focus, context.coordinator.lastFocus?.latitude != focus.latitude
            || context.coordinator.lastFocus?.longitude != focus.longitude {
            context.coordinator.lastFocus = focus
            context.coordinator.placeMarker(at: focus, on: map)
            map.animate(to: GMSCameraPosition(target: focus, zoom: 16))
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        let parent: TapPickerMap
        var marker: GMSMarker?
        var lastFocus: CLLocationCoordinate2D?
        private var cancellable: AnyCancellable?
        private var centered = false
        init(_ parent: TapPickerMap) { self.parent = parent }

        func placeMarker(at coordinate: CLLocationCoordinate2D, on map: GMSMapView) {
            marker?.map = nil
            let m = GMSMarker(position: coordinate)
            m.icon = GMSMarker.markerImage(with: .red)
            m.map = map
            marker = m
        }

        /// If no GPS fix existed when the map opened, recenter once when the first fix arrives.
        func observeLocation(map: GMSMapView, alreadyCentered: Bool) {
            centered = alreadyCentered
            guard !centered else { return }
            cancellable = LocationService.shared.$current
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak map] loc in
                    guard let self, let map, !self.centered else { return }
                    self.centered = true
                    map.animate(to: GMSCameraPosition(target: loc.coordinate, zoom: 15))
                }
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.selected = coordinate
            placeMarker(at: coordinate, on: mapView)
        }
    }
}

import SwiftUI
import GoogleMaps
import UIKit

// ⑥ Map: destination red pin + departed members as circular photo pins, realtime.
struct GroupMapView: View {
    @ObservedObject private var repo = GroupRepository.shared

    var body: some View {
        if let group = repo.group {
            // Own icon hidden — the blue "my location" dot already shows where I am.
            MembersMap(destination: group.destinationCoordinate,
                       members: repo.members.filter {
                           $0.status != .notDeparted && $0.id != repo.myUserId
                       })
                .ignoresSafeArea(edges: .horizontal)
        } else {
            ProgressView()
        }
    }
}

struct MembersMap: UIViewRepresentable {
    let destination: CLLocationCoordinate2D
    let members: [Member]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView(frame: .zero,
                             camera: GMSCameraPosition(target: destination, zoom: 14))
        map.isMyLocationEnabled = true
        map.settings.myLocationButton = true

        let dest = GMSMarker(position: destination)
        dest.icon = GMSMarker.markerImage(with: .red)
        dest.title = "目的地"
        dest.map = map
        context.coordinator.destinationMarker = dest
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        var activeIds = Set<String>()

        for member in members {
            guard let id = member.id, let coord = member.coordinate else { continue }
            activeIds.insert(id)
            let marker = coordinator.markers[id] ?? {
                let m = GMSMarker()
                m.map = map
                m.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                coordinator.markers[id] = m
                return m
            }()
            marker.position = coord
            marker.title = member.name
            coordinator.applyIcon(member: member, to: marker)
        }

        // Remove markers for members no longer shown.
        for (id, marker) in coordinator.markers where !activeIds.contains(id) {
            marker.map = nil
            coordinator.markers.removeValue(forKey: id)
        }
    }

    final class Coordinator {
        var destinationMarker: GMSMarker?
        var markers: [String: GMSMarker] = [:]
        private var iconCache: [String: UIImage] = [:]

        func applyIcon(member: Member, to marker: GMSMarker) {
            guard let urlString = member.iconUrl else { return }
            if let cached = iconCache[urlString] {
                marker.iconView = Self.circleView(image: cached, arrived: member.status == .arrived)
                return
            }
            guard let url = URL(string: urlString) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.iconCache[urlString] = image
                    marker.iconView = Self.circleView(image: image, arrived: member.status == .arrived)
                }
            }.resume()
        }

        /// Circular photo pin (BeReal-style icon on the map).
        static func circleView(image: UIImage, arrived: Bool) -> UIView {
            let size: CGFloat = 52
            let container = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            let imageView = UIImageView(frame: container.bounds)
            imageView.image = image
            imageView.contentMode = .scaleAspectFill
            imageView.layer.cornerRadius = size / 2
            imageView.layer.masksToBounds = true
            imageView.layer.borderWidth = 3
            imageView.layer.borderColor = (arrived ? UIColor.systemBlue : UIColor.white).cgColor
            container.addSubview(imageView)
            return container
        }
    }
}

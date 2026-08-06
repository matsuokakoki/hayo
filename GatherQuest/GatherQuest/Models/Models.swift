import Foundation
import FirebaseFirestore
import CoreLocation

// MARK: - Group

struct MeetGroup: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var destination: GeoPoint
    var meetTime: Date
    var status: GroupStatus
    var inviteCode: String
    var createdAt: Date
    var missionsScheduled: Bool?
    var finishedAt: Date?

    var destinationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)
    }
}

enum GroupStatus: String, Codable {
    case waiting, active, finished
}

// MARK: - Member

struct Member: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var name: String
    var expectedDepartureTime: Date
    /// Actual time the 出発 button was pressed.
    var departureTime: Date?
    var status: MemberStatus
    var location: GeoPoint?
    var iconUrl: String?
    var hayoCount: Int
    var arrivalTime: Date?
    var clearedCount: Int?

    var coordinate: CLLocationCoordinate2D? {
        guard let location else { return nil }
        return CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    static func == (lhs: Member, rhs: Member) -> Bool {
        lhs.id == rhs.id
            && lhs.status == rhs.status
            && lhs.hayoCount == rhs.hayoCount
            && lhs.location?.latitude == rhs.location?.latitude
            && lhs.location?.longitude == rhs.location?.longitude
            && lhs.iconUrl == rhs.iconUrl
    }
}

enum MemberStatus: String, Codable {
    case notDeparted = "not_departed"
    case departed
    case arrived
}

// MARK: - Mission

struct Mission: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var publishAt: Date
    var expiresAt: Date

    var isPublished: Bool { Date() >= publishAt }
    var isExpired: Bool { Date() > expiresAt }
    var isActive: Bool { isPublished && !isExpired }
}

// MARK: - Photo

/// photoType: "mission" | "snap" | "arrival"
struct SharedPhoto: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var missionId: String?
    var photoType: String
    var imageUrl: String
    var caption: String
    var timestamp: Date
    var isCleared: Bool
    var likeCount: Int?
    var hayoReactionCount: Int?
    /// One reaction per user: user IDs who already reacted.
    var likedBy: [String]?
    var hayoBy: [String]?
}

// MARK: - Ranking

struct RankingEntry: Identifiable {
    var id: String { member.id ?? UUID().uuidString }
    let rank: Int
    let member: Member
    /// Seconds relative to meetTime. Negative = early.
    let diffSeconds: Int
    let clearedCount: Int
    let totalMissions: Int

    var diffLabel: String {
        let sign = diffSeconds <= 0 ? "-" : "+"
        let s = abs(diffSeconds)
        return String(format: "%@%02d:%02d", sign, s / 60, s % 60)
    }
}

// MARK: - Camera purpose

enum CameraPurpose {
    case departure          // BeReal-style circular frame
    case arrival
    case mission(Mission)
    case snap

    var isCircular: Bool {
        if case .departure = self { return true }
        return false
    }
}

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

/// All Firestore reads/writes for a group session.
@MainActor
final class GroupRepository: ObservableObject {
    static let shared = GroupRepository()
    private let db = Firestore.firestore()

    @Published var group: MeetGroup?
    @Published var members: [Member] = []
    @Published var missions: [Mission] = []
    @Published var photos: [SharedPhoto] = []

    private var listeners: [ListenerRegistration] = []
    /// Timestamp of the last location write, for throttling.
    private var lastLocationWrite: Date = .distantPast
    private var lastWrittenLocation: CLLocation?

    var myUserId: String? { Auth.auth().currentUser?.uid }
    var me: Member? { members.first { $0.id == myUserId } }

    // MARK: - Create / Join

    func createGroup(name: String, destination: CLLocationCoordinate2D, meetTime: Date) async throws -> (groupId: String, code: String) {
        let code = Self.generateInviteCode()
        let ref = db.collection("groups").document()
        try await ref.setData([
            "name": name,
            "destination": GeoPoint(latitude: destination.latitude, longitude: destination.longitude),
            "meetTime": Timestamp(date: meetTime),
            "status": GroupStatus.waiting.rawValue,
            "inviteCode": code,
            "createdAt": Timestamp(date: Date()),
            "missionsScheduled": false
        ])
        return (ref.documentID, code)
    }

    func findGroup(byCode code: String) async throws -> String? {
        // Single equality filter (no composite index needed); status checked client-side.
        let snap = try await db.collection("groups")
            .whereField("inviteCode", isEqualTo: code.uppercased())
            .getDocuments()
        return snap.documents.first {
            ($0.data()["status"] as? String) != GroupStatus.finished.rawValue
        }?.documentID
    }

    func fetchGroup(_ groupId: String) async throws -> MeetGroup {
        try await db.collection("groups").document(groupId)
            .getDocument(as: MeetGroup.self)
    }

    func joinGroup(_ groupId: String, name: String, expectedDeparture: Date) async throws {
        guard let uid = myUserId else { throw AppError.notSignedIn }
        // Max 8 members.
        let count = try await db.collection("groups").document(groupId)
            .collection("members").count.getAggregation(source: .server).count.intValue
        guard count < 8 else { throw AppError.groupFull }
        try await db.collection("groups").document(groupId)
            .collection("members").document(uid).setData([
                "name": name,
                "expectedDepartureTime": Timestamp(date: expectedDeparture),
                "status": MemberStatus.notDeparted.rawValue,
                "hayoCount": 0,
                "clearedCount": 0
            ])
    }

    // MARK: - Listeners

    func startListening(groupId: String, onGroupDeleted: @escaping () -> Void) {
        stopListening()
        let groupRef = db.collection("groups").document(groupId)

        listeners.append(groupRef.addSnapshotListener { [weak self] snap, _ in
            guard let self else { return }
            guard let snap, snap.exists else {
                Task { @MainActor in onGroupDeleted() }
                return
            }
            self.group = try? snap.data(as: MeetGroup.self)
        })

        listeners.append(groupRef.collection("members").addSnapshotListener { [weak self] snap, _ in
            self?.members = snap?.documents.compactMap { try? $0.data(as: Member.self) } ?? []
        })

        listeners.append(groupRef.collection("missions")
            .order(by: "publishAt").addSnapshotListener { [weak self] snap, _ in
                self?.missions = snap?.documents.compactMap { try? $0.data(as: Mission.self) } ?? []
            })

        listeners.append(groupRef.collection("photos")
            .order(by: "timestamp", descending: true).addSnapshotListener { [weak self] snap, _ in
                self?.photos = snap?.documents.compactMap { try? $0.data(as: SharedPhoto.self) } ?? []
            })
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners = []
        group = nil; members = []; missions = []; photos = []
        lastLocationWrite = .distantPast
        lastWrittenLocation = nil
    }

    // MARK: - Member actions

    func pressHayo(groupId: String, targetUserId: String) async throws {
        try await db.collection("groups").document(groupId)
            .collection("members").document(targetUserId)
            .updateData(["hayoCount": FieldValue.increment(Int64(1))])
    }

    func markDeparted(groupId: String, iconUrl: String) async throws {
        guard let uid = myUserId else { throw AppError.notSignedIn }
        var data: [String: Any] = [
            "status": MemberStatus.departed.rawValue,
            "iconUrl": iconUrl,
            "departureTime": Timestamp(date: Date())
        ]
        // Write the current position immediately so the pin appears right away
        // (otherwise nothing shows until the next CL callback).
        if let loc = LocationService.shared.current {
            data["location"] = GeoPoint(latitude: loc.coordinate.latitude,
                                        longitude: loc.coordinate.longitude)
            lastLocationWrite = Date()
            lastWrittenLocation = loc
        }
        try await db.collection("groups").document(groupId)
            .collection("members").document(uid).updateData(data)
        // Activate group on first departure (Cloud Function schedules missions).
        try await db.collection("groups").document(groupId)
            .updateData(["status": GroupStatus.active.rawValue])
    }

    func markArrived(groupId: String) async throws {
        guard let uid = myUserId else { throw AppError.notSignedIn }
        try await db.collection("groups").document(groupId)
            .collection("members").document(uid).updateData([
                "status": MemberStatus.arrived.rawValue,
                "arrivalTime": Timestamp(date: Date())
            ])
    }

    /// Throttled location write: at most one write per 15 s
    /// (requirement: "15〜30秒に1回" — the 50 m gate made pins appear far too slowly).
    func updateLocationThrottled(groupId: String, location: CLLocation) {
        guard let uid = myUserId, me?.status == .departed else { return }
        let now = Date()
        guard now.timeIntervalSince(lastLocationWrite) >= 15 else { return }
        lastLocationWrite = now
        lastWrittenLocation = location
        db.collection("groups").document(groupId)
            .collection("members").document(uid).updateData([
                "location": GeoPoint(latitude: location.coordinate.latitude,
                                     longitude: location.coordinate.longitude)
            ])
    }

    // MARK: - Photos

    func postPhoto(groupId: String, imageUrl: String, caption: String, purpose: CameraPurpose) async throws {
        guard let uid = myUserId else { throw AppError.notSignedIn }
        var missionId: String? = nil
        var photoType = "snap"
        var isCleared = false

        switch purpose {
        case .mission(let mission):
            missionId = mission.id
            photoType = "mission"
            isCleared = Date() <= mission.expiresAt
        case .arrival:
            photoType = "arrival"
        case .snap, .departure:
            photoType = "snap"
        }

        try await db.collection("groups").document(groupId).collection("photos").addDocument(data: [
            "userId": uid,
            "missionId": missionId as Any,
            "photoType": photoType,
            "imageUrl": imageUrl,
            "caption": caption,
            "timestamp": Timestamp(date: Date()),
            "isCleared": isCleared,
            "likeCount": 0,
            "hayoReactionCount": 0
        ])

        if isCleared {
            try await db.collection("groups").document(groupId)
                .collection("members").document(uid)
                .updateData(["clearedCount": FieldValue.increment(Int64(1))])
        }
    }

    /// One reaction per user per photo (👍 / はよ).
    func react(groupId: String, photo: SharedPhoto, field: String) async throws {
        guard let uid = myUserId, let photoId = photo.id else { return }
        let arrayField = field == "likeCount" ? "likedBy" : "hayoBy"
        let alreadyReacted = (field == "likeCount" ? photo.likedBy : photo.hayoBy)?
            .contains(uid) ?? false
        guard !alreadyReacted else { return }

        try await db.collection("groups").document(groupId)
            .collection("photos").document(photoId)
            .updateData([
                field: FieldValue.increment(Int64(1)),
                arrayField: FieldValue.arrayUnion([uid])
            ])
        // はよ reaction also counts toward the owner's total shown on the lobby.
        if field == "hayoReactionCount" {
            try await db.collection("groups").document(groupId)
                .collection("members").document(photo.userId)
                .updateData(["hayoCount": FieldValue.increment(Int64(1))])
        }
    }

    // MARK: - Helpers

    /// Has the current user cleared this mission?
    func cleared(mission: Mission) -> Bool {
        photos.contains { $0.missionId == mission.id && $0.userId == myUserId && $0.isCleared }
    }

    func ranking() -> [RankingEntry] {
        guard let group else { return [] }
        let total = missions.count
        let arrived = members
            .filter { $0.arrivalTime != nil }
            .sorted { ($0.arrivalTime ?? .distantFuture) < ($1.arrivalTime ?? .distantFuture) }
        return arrived.enumerated().map { idx, m in
            RankingEntry(
                rank: idx + 1,
                member: m,
                diffSeconds: Int((m.arrivalTime ?? group.meetTime).timeIntervalSince(group.meetTime)),
                clearedCount: m.clearedCount ?? 0,
                totalMissions: max(total, 1)
            )
        }
    }

    static func generateInviteCode(length: Int = 6) -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

enum AppError: LocalizedError {
    case notSignedIn, groupFull, groupNotFound

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "サインインしていません"
        case .groupFull: return "グループが満員です（最大8人）"
        case .groupNotFound: return "グループが見つかりません"
        }
    }
}

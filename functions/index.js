const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "asia-northeast1", maxInstances: 10 });

const db = admin.firestore();

const MISSION_POOL = [
  "空の写真を撮れ！",
  "一番近くの信号機を撮れ！",
  "自撮りでピースしろ！",
  "何か赤いものを撮れ！",
  "今いる場所の看板を撮れ！",
  "靴を撮れ！",
  "変顔を撮れ！",
  "コンビニを見つけて撮れ！",
];

const MISSION_COUNT = 3;
const CLEAR_WINDOW_SEC = 120; // 2 minutes to clear
const CLEANUP_AFTER_MIN = 10; // delete group 10 min after everyone arrived

/**
 * Member status changes:
 *  - first "departed"  -> schedule random-timed photo missions
 *  - all "arrived"     -> mark the group finished (starts the 10-min deletion clock)
 */
exports.onMemberUpdate = onDocumentUpdated(
  "groups/{groupId}/members/{memberId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const groupId = event.params.groupId;
    const groupRef = db.collection("groups").doc(groupId);

    // --- First departure: schedule missions (transaction guards double-run) ---
    if (before.status !== "departed" && after.status === "departed") {
      const shouldSchedule = await db.runTransaction(async (tx) => {
        const g = await tx.get(groupRef);
        if (!g.exists || g.data().missionsScheduled) return false;
        tx.update(groupRef, { missionsScheduled: true, status: "active" });
        return true;
      });

      if (shouldSchedule) {
        const titles = [...MISSION_POOL].sort(() => Math.random() - 0.5).slice(0, MISSION_COUNT);
        const batch = db.batch();
        titles.forEach((title, i) => {
          // Random delivery: 1–10 min after first departure, spaced out per index.
          const offsetSec = 60 + i * 180 + Math.floor(Math.random() * 120);
          const publishAt = new Date(Date.now() + offsetSec * 1000);
          const expiresAt = new Date(publishAt.getTime() + CLEAR_WINDOW_SEC * 1000);
          const ref = groupRef.collection("missions").doc();
          batch.set(ref, {
            title,
            publishAt: admin.firestore.Timestamp.fromDate(publishAt),
            expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
          });
        });
        await batch.commit();
        console.log(`Scheduled ${MISSION_COUNT} missions for group ${groupId}`);
      }
    }

    // --- All arrived: finish the group ---
    if (before.status !== "arrived" && after.status === "arrived") {
      const members = await groupRef.collection("members").get();
      const allArrived =
        members.size > 0 && members.docs.every((d) => d.data().status === "arrived");
      if (allArrived) {
        await groupRef.update({
          status: "finished",
          finishedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Group ${groupId} finished — cleanup in ${CLEANUP_AFTER_MIN} min`);
      }
    }
  }
);

/**
 * Every minute: hard-delete groups (Firestore + Storage) that finished
 * more than 10 minutes ago. Also sweeps stale groups older than 24 h.
 */
exports.cleanupGroups = onSchedule("every 1 minutes", async () => {
  const cutoff = new Date(Date.now() - CLEANUP_AFTER_MIN * 60 * 1000);
  const staleCutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);

  const finished = await db
    .collection("groups")
    .where("status", "==", "finished")
    .where("finishedAt", "<=", admin.firestore.Timestamp.fromDate(cutoff))
    .get();

  const stale = await db
    .collection("groups")
    .where("createdAt", "<=", admin.firestore.Timestamp.fromDate(staleCutoff))
    .get();

  const targets = new Map();
  finished.docs.forEach((d) => targets.set(d.id, d.ref));
  stale.docs.forEach((d) => targets.set(d.id, d.ref));

  for (const [groupId, ref] of targets) {
    // Delete Storage files under groups/{groupId}/
    await admin
      .storage()
      .bucket()
      .deleteFiles({ prefix: `groups/${groupId}/` })
      .catch((e) => console.error(`Storage cleanup failed for ${groupId}:`, e.message));
    // Recursively delete the group document and all subcollections.
    await db.recursiveDelete(ref);
    console.log(`Deleted group ${groupId}`);
  }
});

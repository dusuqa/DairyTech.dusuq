/**
 * DUSUQ — Cloud Functions
 *
 * These run with Admin SDK privileges, so they can do things client-side
 * Flutter code is never trusted to do directly:
 *   - mint custom claims (role + orgId) on a user's auth token
 *   - create the FIRST OrgAdmin + their organization atomically
 *   - invite a Farmer into an existing org (without letting the inviter
 *     pick an arbitrary orgId — it's taken from the inviter's own claims)
 *
 * Why this can't live in Flutter: if "set my own role to SuperAdmin" were
 * just a Firestore write from the client, any user could grant themselves
 * full access. Privileged mutations must run server-side.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();

// ────────────────────────────────────────────────────────────────────────
// 1. syncUserClaims
// Firestore trigger: whenever users/{uid} is written, mirror role + orgId
// onto the Auth custom claims. This is what the security rules read via
// request.auth.token.role / request.auth.token.orgId.
//
// IMPORTANT: custom claims don't take effect on the client until the ID
// token refreshes. Flutter must call `await user.getIdToken(true)` (force
// refresh) right after login, or claims will be stale for up to 1 hour.
// See AuthService.refreshClaims() in the Flutter snippet below.
// ────────────────────────────────────────────────────────────────────────
exports.syncUserClaims = functions.firestore
  .document("users/{uid}")
  .onWrite(async (change, context) => {
    const uid = context.params.uid;

    // Document deleted -> revoke all claims
    if (!change.after.exists) {
      await auth.setCustomUserClaims(uid, null);
      return null;
    }

    const data = change.after.data();
    const { role, orgId, status } = data;

    if (!role) {
      console.warn(`User ${uid} has no role set; skipping claims sync.`);
      return null;
    }

    // Disabled users get claims wiped so their existing token (if not yet
    // expired) immediately fails belongsToCallerOrg() checks next request.
    if (status === "disabled") {
      await auth.setCustomUserClaims(uid, { role: "disabled", orgId: null });
      return null;
    }

    await auth.setCustomUserClaims(uid, {
      role,
      orgId: role === "SuperAdmin" ? null : orgId,
    });

    console.log(`Synced claims for ${uid}: role=${role}, orgId=${orgId}`);
    return null;
  });

// ────────────────────────────────────────────────────────────────────────
// 2. signUpOrgAdmin
// Callable function. Used during the first-time signup flow for a new
// farm/cooperative. Creates the organization doc AND the OrgAdmin's user
// doc in a single transaction, so you never end up with an org with no
// admin or a user pointing at a non-existent org.
//
// Called from Flutter as:
//   final result = await FirebaseFunctions.instance
//       .httpsCallable('signUpOrgAdmin')
//       .call({ 'orgName': 'Khanewal Dairy Cooperative' });
// ────────────────────────────────────────────────────────────────────────
exports.signUpOrgAdmin = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Must be signed in (email/password or phone) before completing signup."
    );
  }

  const uid = context.auth.uid;
  const orgName = (data.orgName || "").trim();
  if (!orgName) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "orgName is required."
    );
  }

  // Guard: a user who already has a profile can't run signup again to
  // create a second org for themselves.
  const existing = await db.collection("users").doc(uid).get();
  if (existing.exists) {
    throw new functions.https.HttpsError(
      "already-exists",
      "This account is already linked to an organization."
    );
  }

  const orgRef = db.collection("organizations").doc(); // auto-id
  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (tx) => {
    tx.set(orgRef, {
      name: orgName,
      ownerUid: uid,
      planTier: "trial",
      animalCount: 0,
      status: "active",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      settings: { currency: "PKR", defaultLanguage: "ur" },
    });

    tx.set(userRef, {
      uid,
      orgId: orgRef.id,
      role: "OrgAdmin",
      email: context.auth.token.email || null,
      phone: context.auth.token.phone_number || null,
      displayName: data.displayName || orgName,
      status: "active",
      invitedBy: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  // syncUserClaims trigger fires automatically from the user doc write above.
  return { orgId: orgRef.id, role: "OrgAdmin" };
});

// ────────────────────────────────────────────────────────────────────────
// 3. inviteFarmer
// Callable function. OrgAdmin invites a Farmer by phone or email. The new
// user's orgId is forced to match the CALLER's orgId — a Farmer can never
// be invited into an org the inviter doesn't belong to, even if the client
// sends a different orgId in the payload (we ignore it on purpose).
// ────────────────────────────────────────────────────────────────────────
exports.inviteFarmer = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }

  const callerClaims = context.auth.token;
  if (callerClaims.role !== "OrgAdmin" && callerClaims.role !== "SuperAdmin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only an OrgAdmin or SuperAdmin can invite farmers."
    );
  }

  const { email, phone, displayName, targetOrgId } = data;
  if (!email && !phone) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Provide either email or phone for the new farmer."
    );
  }

  // SuperAdmin must explicitly specify which org to invite into (they have
  // no orgId of their own). OrgAdmin can only ever use their own org.
  const orgId =
    callerClaims.role === "SuperAdmin" ? targetOrgId : callerClaims.orgId;

  if (!orgId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "targetOrgId is required when inviting as SuperAdmin."
    );
  }

  // Create the Auth user in a disabled/invited state. They complete
  // signup (set password, or verify phone OTP) on first login.
  const newUser = await auth.createUser({
    email: email || undefined,
    phoneNumber: phone || undefined,
    displayName: displayName || undefined,
  });

  await db.collection("users").doc(newUser.uid).set({
    uid: newUser.uid,
    orgId,
    role: "Farmer",
    email: email || null,
    phone: phone || null,
    displayName: displayName || "",
    status: "invited",
    invitedBy: context.auth.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    lastLoginAt: null,
  });

  return { uid: newUser.uid, orgId };
});

// ════════════════════════════════════════════════════════════════════════
// AGGREGATE COUNTERS — why this exists
//
// The Admin Dashboard needs numbers like "total milk this month" and
// "monthly revenue." The naive way is a live query: sum every milk_records
// doc where orgId == X and date is in the current month, every time the
// dashboard opens. That re-reads potentially thousands of documents on
// every page load, billed every time, and gets slower as the farm
// accumulates history.
//
// Instead, these triggers fire on every write to milk_records /
// finance_records / animals and apply an INCREMENT to a denormalized
// summary stored directly on organizations/{orgId}. The dashboard then
// reads exactly ONE document, no matter how many years of data exist.
//
// FieldValue.increment() is used instead of read-then-write specifically
// because it's atomic at the database level — two farmhands logging milk
// at the same second don't race and clobber each other's update the way a
// naive `get(); newTotal = old + delta; set(newTotal)` would.
//
// Trade-off being made explicitly: these are EVENTUALLY consistent. There
// is a brief (typically sub-second, occasionally a few seconds under load)
// delay between a write landing and the aggregate reflecting it. For a
// dashboard glanced at once a day, this is the correct trade — for
// something needing instant consistency (e.g. a balance check before
// allowing a withdrawal), you'd want a transaction instead. Not the case
// here.
// ════════════════════════════════════════════════════════════════════════

const FieldValue = admin.firestore.FieldValue;

function monthKey(date) {
  // "2026-06" — used as a map key on the org doc for per-month breakdowns,
  // so the dashboard can show "this month vs last month" from the same
  // single document read, without a date-range query.
  const d = date instanceof admin.firestore.Timestamp ? date.toDate() : new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

/**
 * Applies an increment-style update map to an organization doc.
 *
 * update() throws NOT_FOUND if the document doesn't exist yet (e.g. the
 * very first milk record ever logged for a brand-new org, before any other
 * write has touched the doc). In that specific case we fall back to a
 * merge-set. Any OTHER error (permission, network, malformed path) is
 * re-thrown — silently swallowing those would hide real bugs as if they
 * were the harmless "doc didn't exist yet" case.
 */
async function safeIncrement(orgRef, updates) {
  try {
    await orgRef.update(updates);
  } catch (err) {
    if (err.code === 5 || err.code === "not-found") {
      // gRPC code 5 = NOT_FOUND
      await orgRef.set(updates, { merge: true });
    } else {
      throw err;
    }
  }
}

// ── milk_records: maintain totalMilkLiters + monthly breakdown ──
exports.onMilkRecordWrite = functions.firestore
  .document("milk_records/{recordId}")
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    // Determine the org this write affects. orgId is immutable per the
    // security rules, so before/after always agree when both exist.
    const orgId = (after || before)?.orgId;
    if (!orgId) return null;

    const orgRef = db.collection("organizations").doc(orgId);

    let litersDelta = 0;
    let monthDeltas = {}; // { "2026-06": +9.5 }

    if (!before && after) {
      // Created
      litersDelta = Number(after.quantity || 0);
      const mk = monthKey(after.date);
      monthDeltas[mk] = (monthDeltas[mk] || 0) + litersDelta;
    } else if (before && !after) {
      // Deleted
      litersDelta = -Number(before.quantity || 0);
      const mk = monthKey(before.date);
      monthDeltas[mk] = (monthDeltas[mk] || 0) + litersDelta;
    } else if (before && after) {
      // Updated — quantity or date may have changed
      const oldQty = Number(before.quantity || 0);
      const newQty = Number(after.quantity || 0);
      const oldMk = monthKey(before.date);
      const newMk = monthKey(after.date);
      if (oldMk === newMk) {
        litersDelta = newQty - oldQty;
        monthDeltas[newMk] = (monthDeltas[newMk] || 0) + litersDelta;
      } else {
        // Record moved to a different month — back out of the old month,
        // into the new one.
        monthDeltas[oldMk] = (monthDeltas[oldMk] || 0) - oldQty;
        monthDeltas[newMk] = (monthDeltas[newMk] || 0) + newQty;
      }
    }

    const updates = {
      "aggregates.totalMilkLiters": FieldValue.increment(litersDelta),
      "aggregates.lastUpdated": FieldValue.serverTimestamp(),
    };
    for (const [mk, delta] of Object.entries(monthDeltas)) {
      if (delta !== 0) {
        updates[`aggregates.milkByMonth.${mk}`] = FieldValue.increment(delta);
      }
    }

    await safeIncrement(orgRef, updates);
    return null;
  });

// ── finance_records: maintain totalIncome, totalExpense, monthly revenue ──
exports.onFinanceRecordWrite = functions.firestore
  .document("finance_records/{recordId}")
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;
    const orgId = (after || before)?.orgId;
    if (!orgId) return null;

    const orgRef = db.collection("organizations").doc(orgId);

    function signedAmount(rec) {
      if (!rec) return 0;
      const amt = Number(rec.amount || 0);
      return rec.type === "Income" ? amt : -amt;
    }

    const updates = {};
    const oldSigned = signedAmount(before);
    const newSigned = signedAmount(after);
    const netDelta = newSigned - oldSigned;

    if (netDelta !== 0) {
      updates["aggregates.netRevenue"] = FieldValue.increment(netDelta);
    }

    // Income/expense tracked separately too (dashboard shows both, not just net)
    const oldIncome = before?.type === "Income" ? Number(before.amount || 0) : 0;
    const newIncome = after?.type === "Income" ? Number(after.amount || 0) : 0;
    const incomeDelta = newIncome - oldIncome;
    if (incomeDelta !== 0) {
      updates["aggregates.totalIncome"] = FieldValue.increment(incomeDelta);
    }

    const oldExpense = before?.type === "Expense" ? Number(before.amount || 0) : 0;
    const newExpense = after?.type === "Expense" ? Number(after.amount || 0) : 0;
    const expenseDelta = newExpense - oldExpense;
    if (expenseDelta !== 0) {
      updates["aggregates.totalExpense"] = FieldValue.increment(expenseDelta);
    }

    if (Object.keys(updates).length === 0) return null;
    updates["aggregates.lastUpdated"] = FieldValue.serverTimestamp();

    await safeIncrement(orgRef, updates);
    return null;
  });

// ── animals: maintain animalCount + lactatingCount ──
exports.onAnimalWrite = functions.firestore
  .document("animals/{animalId}")
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;
    const orgId = (after || before)?.orgId;
    if (!orgId) return null;

    const orgRef = db.collection("organizations").doc(orgId);
    const updates = {};

    if (!before && after) {
      updates["animalCount"] = FieldValue.increment(1);
      if (after.status === "Lactating") {
        updates["aggregates.lactatingCount"] = FieldValue.increment(1);
      }
    } else if (before && !after) {
      updates["animalCount"] = FieldValue.increment(-1);
      if (before.status === "Lactating") {
        updates["aggregates.lactatingCount"] = FieldValue.increment(-1);
      }
    } else if (before && after) {
      const wasLactating = before.status === "Lactating";
      const isLactating = after.status === "Lactating";
      if (wasLactating && !isLactating) {
        updates["aggregates.lactatingCount"] = FieldValue.increment(-1);
      } else if (!wasLactating && isLactating) {
        updates["aggregates.lactatingCount"] = FieldValue.increment(1);
      }
    }

    if (Object.keys(updates).length === 0) return null;

    await safeIncrement(orgRef, updates);
    return null;
  });

// ── users: maintain activeFarmerCount (for the dashboard's "Active Farmers" tile) ──
exports.onUserWriteUpdateFarmerCount = functions.firestore
  .document("users/{uid}")
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;
    const orgId = (after || before)?.orgId;
    if (!orgId) return null;

    function countsAsActiveFarmer(doc) {
      return !!doc && doc.role === "Farmer" && doc.status === "active";
    }

    const wasActive = countsAsActiveFarmer(before);
    const isActive = countsAsActiveFarmer(after);
    if (wasActive === isActive) return null;

    const orgRef = db.collection("organizations").doc(orgId);
    const delta = isActive ? 1 : -1;
    await safeIncrement(orgRef, { "aggregates.activeFarmerCount": FieldValue.increment(delta) });
    return null;
  });

// ════════════════════════════════════════════════════════════════════════
// SuperAdmin global rollup — scheduled, not real-time
//
// Per-org aggregates above are real-time and cheap (single doc read each).
// A SuperAdmin viewing "all organizations combined" needs a SUM across
// every org doc. With dozens of orgs that's still cheap as a live query
// (reading N org docs, not N×thousands of records), so this one IS done
// live in the Flutter screen via a Firestore query — no extra function
// needed. Documented here so the design choice is explicit, not missing.
// ════════════════════════════════════════════════════════════════════════

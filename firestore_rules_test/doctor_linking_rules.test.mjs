// Doctor Linking Security Rules tests (Task 3.2), run against the local
// Firestore emulator with real rules evaluation. No npm packages.
//
// Run from the project root (both rule test files):
//   npx -y firebase-tools@15.35.0 emulators:exec --only firestore --project demo-medfollow "node --test --test-concurrency=1 firestore_rules_test/users_rules.test.mjs firestore_rules_test/doctor_linking_rules.test.mjs"

import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-medfollow';
const HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const ROOT = `projects/${PROJECT}/databases/(default)/documents`;
const BASE = `http://${HOST}/v1/${ROOT}`;
const OK = 200;
const DENIED = 403;

// Fictional users. Doctor roles are self-declared (not verified).
const PATIENT = 'patientAlice';
const PATIENT2 = 'patientMallory';
const DOCTOR = 'doctorBob';
const DOCTOR2 = 'doctorCarol';
const OUTSIDER = 'doctorEve';
const NAMES = {
  [PATIENT]: 'Alice Patient',
  [PATIENT2]: 'Mallory Patient',
  [DOCTOR]: 'Dr Bob',
  [DOCTOR2]: 'Dr Carol',
  [OUTSIDER]: 'Dr Eve',
};
const CODE = 'ABCDEFGH23';
const CODE2 = 'CAROLCDE45';

function tokenFor(uid) {
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${enc({ alg: 'none', typ: 'JWT' })}.${enc({
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT, sub: uid, user_id: uid, iat: now, exp: now + 3600,
    auth_time: now, email: `${uid}@example.com`,
    firebase: { sign_in_provider: 'password', identities: {} },
  })}.`;
}
const as = (uid) => (uid ? { Authorization: `Bearer ${tokenFor(uid)}` } : {});
const ADMIN = { Authorization: 'Bearer owner' };

// Firestore REST value encoding.
function enc(v) {
  if (v === null) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: v.length ? { values: v.map(enc) } : {} };
  throw new Error(`unsupported ${v}`);
}
const fields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, enc(v)]));

async function call(method, url, headers, body) {
  const res = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.status;
}

/**
 * One write through :commit, like the Flutter SDK.
 * serverTime: field names set to the request time (server timestamp).
 * mask: update only these fields; exists: precondition.
 */
function write(headers, path, data, { serverTime = [], mask, exists } = {}) {
  const w = { update: { name: `${ROOT}/${path}`, fields: fields(data) } };
  if (serverTime.length) {
    w.updateTransforms = serverTime.map((f) => ({ fieldPath: f, setToServerValue: 'REQUEST_TIME' }));
  }
  if (mask) w.updateMask = { fieldPaths: mask };
  if (exists !== undefined) w.currentDocument = { exists };
  return call('POST', `${BASE}:commit`, headers, { writes: [w] });
}
const get = (headers, path) => call('GET', `${BASE}/${path}`, headers);
const del = (headers, path) => call('DELETE', `${BASE}/${path}`, headers);
function query(headers, collection, where) {
  const structuredQuery = { from: [{ collectionId: collection }] };
  if (where) {
    structuredQuery.where = {
      fieldFilter: { field: { fieldPath: where[0] }, op: 'EQUAL', value: enc(where[1]) },
    };
  }
  return call('POST', `${BASE}:runQuery`, headers, { structuredQuery });
}

// Admin seeding (bypasses rules).
async function seedUser(uid, role) {
  await write(ADMIN, `users/${uid}`, {
    displayName: NAMES[uid], email: `${uid}@example.com`, role, linkedDoctorIds: [],
  });
}
function seedCode(code, doctorId, { active = true, createdAt = new Date() } = {}) {
  return write(ADMIN, `doctorCodes/${code}`, {
    doctorId, doctorName: NAMES[doctorId], active, createdAt,
  });
}

// Client operations, as the app will perform them.
function createCode(uid, code, overrides = {}, serverTime = ['createdAt']) {
  return write(as(uid), `doctorCodes/${code}`, {
    doctorId: uid, doctorName: NAMES[uid], active: true, ...overrides,
  }, { serverTime, exists: false });
}
function linkData(patientId, doctorId, code, overrides = {}) {
  return {
    patientId, doctorId, patientName: NAMES[patientId], doctorName: NAMES[doctorId],
    linkCode: code, status: 'active', ...overrides,
  };
}
function createLink(uid, patientId, doctorId, code, overrides = {}, opts = {}) {
  return write(as(uid), `doctorLinks/${patientId}_${doctorId}`,
    linkData(patientId, doctorId, code, overrides),
    { serverTime: ['consentedAt'], exists: false, ...opts });
}
function revoke(uid, patientId, doctorId, revokedBy = uid) {
  return write(as(uid), `doctorLinks/${patientId}_${doctorId}`,
    { status: 'revoked', revokedBy },
    { serverTime: ['revokedAt'], mask: ['status', 'revokedBy'], exists: true });
}
function reactivate(uid, patientId, doctorId, code) {
  // Full replace removes revokedAt/revokedBy.
  return write(as(uid), `doctorLinks/${patientId}_${doctorId}`,
    linkData(patientId, doctorId, code), { serverTime: ['consentedAt'], exists: true });
}

beforeEach(async () => {
  const res = await fetch(`http://${HOST}/emulator/v1/${ROOT}`, { method: 'DELETE' });
  assert.equal(res.status, 200, 'emulator reset failed');
  await seedUser(PATIENT, 'patient');
  await seedUser(PATIENT2, 'patient');
  await seedUser(DOCTOR, 'doctor');
  await seedUser(DOCTOR2, 'doctor');
  await seedUser(OUTSIDER, 'doctor');
});

// ---------------------------------------------------------------- codes

test('codes: doctor creates own code with server time', async () => {
  assert.equal(await createCode(DOCTOR, CODE), OK);
});

test('codes: invalid creations are denied', async () => {
  assert.equal(await createCode(PATIENT, CODE), DENIED, 'patient role');
  assert.equal(await createCode(DOCTOR, CODE, { doctorId: DOCTOR2 }), DENIED, 'other doctor id');
  assert.equal(await createCode(DOCTOR, CODE, { doctorName: 'Dr Fake' }), DENIED, 'name differs from profile');
  assert.equal(await createCode(DOCTOR, CODE, { active: false }), DENIED, 'inactive');
  assert.equal(await createCode(DOCTOR, CODE, { extra: 'x' }), DENIED, 'extra field');
  assert.equal(await createCode(DOCTOR, 'short1'), DENIED, 'bad format');
  assert.equal(await createCode(DOCTOR, 'ABCDEFGHI1'), DENIED, 'look-alike characters');
  assert.equal(
    await createCode(DOCTOR, CODE, { createdAt: new Date(Date.now() + 864e5 * 365) }, []),
    DENIED,
    'client-chosen createdAt',
  );
  assert.equal(
    await write(as(null), `doctorCodes/${CODE}`,
      { doctorId: DOCTOR, doctorName: NAMES[DOCTOR], active: true },
      { serverTime: ['createdAt'], exists: false }),
    DENIED,
    'unauthenticated',
  );
});

test('codes: single lookup allowed, enumeration denied', async () => {
  await seedCode(CODE, DOCTOR);
  assert.equal(await get(as(PATIENT), `doctorCodes/${CODE}`), OK);
  assert.equal(await get(as(null), `doctorCodes/${CODE}`), DENIED);
  assert.equal(await query(as(PATIENT), 'doctorCodes'), DENIED, 'list all codes');
  assert.equal(await query(as(DOCTOR), 'doctorCodes'), DENIED, 'unfiltered list');
  assert.equal(await query(as(DOCTOR), 'doctorCodes', ['doctorId', DOCTOR]), OK, 'own codes');
  assert.equal(await query(as(DOCTOR2), 'doctorCodes', ['doctorId', DOCTOR]), DENIED, "another doctor's codes");
});

test('codes: owner may only deactivate; others denied', async () => {
  await seedCode(CODE, DOCTOR);
  const setActive = (uid, active) =>
    write(as(uid), `doctorCodes/${CODE}`, { active }, { mask: ['active'], exists: true });
  assert.equal(await setActive(DOCTOR2, false), DENIED, 'non-owner');
  assert.equal(await setActive(DOCTOR, false), OK, 'owner deactivates');
  assert.equal(await setActive(DOCTOR, true), DENIED, 'cannot reactivate');
  assert.equal(await del(as(DOCTOR2), `doctorCodes/${CODE}`), DENIED, 'non-owner delete');
  assert.equal(await del(as(DOCTOR), `doctorCodes/${CODE}`), OK, 'owner delete');
});

// ---------------------------------------------------------------- links

test('links: patient creates link with valid code and fresh consent', async () => {
  await seedCode(CODE, DOCTOR);
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, CODE), OK);
});

test('links: multiple doctors per patient via separate documents', async () => {
  await seedCode(CODE, DOCTOR);
  await seedCode(CODE2, DOCTOR2);
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, CODE), OK);
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR2, CODE2), OK);
});

test('links: invalid, deactivated, expired, or mismatched codes are rejected', async () => {
  await seedCode(CODE, DOCTOR, { active: false });
  await seedCode('EXPIREDXY2', DOCTOR, { createdAt: new Date(Date.now() - 31 * 864e5) });
  await seedCode(CODE2, DOCTOR2);
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, 'NOSUCHCD22'), DENIED, 'nonexistent');
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, CODE), DENIED, 'deactivated');
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, 'EXPIREDXY2'), DENIED, 'expired (>30 days)');
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, CODE2), DENIED, "another doctor's code");
});

test('links: unauthorized or malformed creations are denied', async () => {
  await seedCode(CODE, DOCTOR);
  assert.equal(await createLink(DOCTOR, PATIENT, DOCTOR, CODE), DENIED, 'doctor creates link');
  assert.equal(await createLink(PATIENT2, PATIENT, DOCTOR, CODE), DENIED, 'for another patient');
  assert.equal(await createLink(null, PATIENT, DOCTOR, CODE), DENIED, 'unauthenticated');
  assert.equal(
    await createLink(PATIENT, PATIENT, DOCTOR, CODE, { consentedAt: new Date() }, { serverTime: [] }),
    DENIED,
    'client-supplied consent time',
  );
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, CODE, { status: 'revoked' }), DENIED, 'non-active');
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, CODE, { doctorName: 'Dr Fake' }), DENIED, 'wrong doctor name');
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, CODE, { patientName: 'Someone' }), DENIED, 'wrong patient name');
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, CODE, { extra: 'x' }), DENIED, 'extra field');
  assert.equal(
    await write(as(PATIENT), `doctorLinks/wrongId`, linkData(PATIENT, DOCTOR, CODE),
      { serverTime: ['consentedAt'], exists: false }),
    DENIED,
    'document ID not patient_doctor',
  );
  await seedCode('MALLORYCD2', PATIENT2); // code owned by a patient account
  assert.equal(await createLink(PATIENT, PATIENT, PATIENT2, 'MALLORYCD2'), DENIED, 'target is not a doctor');
});

test('links: duplicate active link is rejected', async () => {
  await seedCode(CODE, DOCTOR);
  assert.equal(await createLink(PATIENT, PATIENT, DOCTOR, CODE), OK);
  // Overwrite without precondition is evaluated as an update of an active link.
  assert.equal(
    await createLink(PATIENT, PATIENT, DOCTOR, CODE, {}, { exists: undefined }),
    DENIED,
  );
});

test('links: only parties can read; queries must be scoped', async () => {
  await seedCode(CODE, DOCTOR);
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  const path = `doctorLinks/${PATIENT}_${DOCTOR}`;
  assert.equal(await get(as(PATIENT), path), OK);
  assert.equal(await get(as(DOCTOR), path), OK);
  assert.equal(await get(as(OUTSIDER), path), DENIED);
  assert.equal(await query(as(DOCTOR), 'doctorLinks', ['doctorId', DOCTOR]), OK);
  assert.equal(await query(as(PATIENT), 'doctorLinks', ['patientId', PATIENT]), OK);
  assert.equal(await query(as(DOCTOR), 'doctorLinks'), DENIED, 'unfiltered');
  assert.equal(await query(as(OUTSIDER), 'doctorLinks', ['doctorId', DOCTOR]), DENIED, "another doctor's links");
});

// ------------------------------------------------- profile access via link

test('profiles: linked doctor reads but cannot modify; others denied', async () => {
  await seedCode(CODE, DOCTOR);
  const profile = `users/${PATIENT}`;
  assert.equal(await get(as(DOCTOR), profile), DENIED, 'before linking');
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  assert.equal(await get(as(DOCTOR), profile), OK, 'linked doctor');
  assert.equal(await get(as(OUTSIDER), profile), DENIED, 'unlinked doctor');
  assert.equal(await query(as(DOCTOR), 'users'), DENIED, 'doctor listing users');
  assert.equal(
    await write(as(DOCTOR), profile, { displayName: 'Changed' }, { mask: ['displayName'], exists: true }),
    DENIED,
    'linked doctor edit',
  );
});

// ------------------------------------------- revocation and reactivation

test('revocation: doctor revokes, loses access, cannot reactivate', async () => {
  await seedCode(CODE, DOCTOR);
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  assert.equal(await revoke(OUTSIDER, PATIENT, DOCTOR), DENIED, 'third party');
  assert.equal(await revoke(DOCTOR, PATIENT, DOCTOR, PATIENT), DENIED, 'forged revokedBy');
  assert.equal(await revoke(DOCTOR, PATIENT, DOCTOR), OK, 'doctor revokes');
  assert.equal(await get(as(DOCTOR), `users/${PATIENT}`), DENIED, 'access after revocation');
  assert.equal(await reactivate(DOCTOR, PATIENT, DOCTOR, CODE), DENIED, 'doctor reactivates');
  assert.equal(await revoke(PATIENT, PATIENT, DOCTOR), DENIED, 'revoking twice');
});

test('revocation: patient revokes and later reactivates with fresh consent', async () => {
  await seedCode(CODE, DOCTOR);
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  assert.equal(await revoke(PATIENT, PATIENT, DOCTOR), OK, 'patient revokes');
  assert.equal(await get(as(DOCTOR), `users/${PATIENT}`), DENIED);
  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, 'NOSUCHCD22'), DENIED, 'invalid code');
  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, CODE), OK, 'patient reactivates');
  assert.equal(await get(as(DOCTOR), `users/${PATIENT}`), OK, 'access restored');
});

test('revocation: identities immutable, invalid transitions and deletes denied', async () => {
  await seedCode(CODE, DOCTOR);
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  const path = `doctorLinks/${PATIENT}_${DOCTOR}`;
  assert.equal(
    await write(as(PATIENT), path, { status: 'revoked', revokedBy: PATIENT, doctorId: DOCTOR2 },
      { serverTime: ['revokedAt'], mask: ['status', 'revokedBy', 'doctorId'], exists: true }),
    DENIED,
    'changing doctorId while revoking',
  );
  assert.equal(
    await write(as(PATIENT), path, { status: 'revoked', revokedBy: PATIENT, revokedAt: new Date() },
      { mask: ['status', 'revokedBy', 'revokedAt'], exists: true }),
    DENIED,
    'client-supplied revokedAt',
  );
  assert.equal(
    await write(as(PATIENT), path, { linkCode: CODE2 }, { mask: ['linkCode'], exists: true }),
    DENIED,
    'editing an active link',
  );
  assert.equal(await del(as(PATIENT), path), DENIED, 'patient delete');
  assert.equal(await del(as(DOCTOR), path), DENIED, 'doctor delete');
});

test('unrelated collections remain denied', async () => {
  await seedCode(CODE, DOCTOR);
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  assert.equal(await get(as(DOCTOR), 'medications/m1'), DENIED);
  assert.equal(
    await write(as(PATIENT), 'medications/m1', { patientId: PATIENT }, { exists: false }),
    DENIED,
  );
});

// ------------------------------------------- Task 3.2 review regressions

// Equality filters combined with AND (the dashboard's active-links query).
function queryAnd(headers, collection, filters) {
  return call('POST', `${BASE}:runQuery`, headers, {
    structuredQuery: {
      from: [{ collectionId: collection }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: filters.map(([f, v]) => ({
            fieldFilter: { field: { fieldPath: f }, op: 'EQUAL', value: enc(v) },
          })),
        },
      },
    },
  });
}

test('review: codes cannot be overwritten, reassigned, or re-dated', async () => {
  await seedCode(CODE, DOCTOR);
  const path = `doctorCodes/${CODE}`;
  // Another doctor "creating" an existing code is evaluated as an update.
  assert.equal(
    await write(as(DOCTOR2), path, { doctorId: DOCTOR2, doctorName: NAMES[DOCTOR2], active: true },
      { serverTime: ['createdAt'] }),
    DENIED,
    'overwrite by another doctor',
  );
  assert.equal(
    await write(as(DOCTOR), path, { doctorId: DOCTOR2 }, { mask: ['doctorId'], exists: true }),
    DENIED,
    'owner reassigns code',
  );
  assert.equal(
    await write(as(DOCTOR), path, {}, { serverTime: ['createdAt'], mask: [], exists: true }),
    DENIED,
    'owner refreshes createdAt to extend validity',
  );
});

test('review: reactivation requires a usable code', async () => {
  await seedCode(CODE, DOCTOR);
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  await revoke(PATIENT, PATIENT, DOCTOR);
  await seedCode(CODE, DOCTOR, { active: false }); // doctor deactivated it
  await seedCode('EXPIREDXY2', DOCTOR, { createdAt: new Date(Date.now() - 31 * 864e5) });
  await seedCode(CODE2, DOCTOR2);
  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, CODE), DENIED, 'deactivated code');
  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, 'EXPIREDXY2'), DENIED, 'expired code');
  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, CODE2), DENIED, "another doctor's code");
  assert.equal(await get(as(DOCTOR), `users/${PATIENT}`), DENIED, 'still no access');
});

test('review: dashboard and patient query contract', async () => {
  await seedCode(CODE, DOCTOR);
  await seedCode(CODE2, DOCTOR2);
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  await createLink(PATIENT, PATIENT, DOCTOR2, CODE2);
  assert.equal(
    await queryAnd(as(DOCTOR), 'doctorLinks', [['doctorId', DOCTOR], ['status', 'active']]),
    OK,
    'doctor active links',
  );
  assert.equal(
    await queryAnd(as(OUTSIDER), 'doctorLinks', [['doctorId', DOCTOR], ['status', 'active']]),
    DENIED,
    "cross-user doctor query",
  );
  assert.equal(
    await queryAnd(as(DOCTOR), 'doctorLinks', [['status', 'active']]),
    DENIED,
    'status-only query',
  );
  assert.equal(
    await query(as(PATIENT2), 'doctorLinks', ['patientId', PATIENT]),
    DENIED,
    'cross-user patient query',
  );
  // Linked doctors read profiles by ID only; revocation ends it.
  assert.equal(await get(as(DOCTOR2), `users/${PATIENT}`), OK);
  await revoke(DOCTOR2, PATIENT, DOCTOR2);
  assert.equal(await get(as(DOCTOR2), `users/${PATIENT}`), DENIED, 'after revocation');
  assert.equal(await get(as(DOCTOR), `users/${PATIENT}`), OK, 'other link unaffected');
});

// ------------------------- doctor revocation cannot be undone by old code

test('doctor-revoked: old code rejected, new post-revocation code accepted', async () => {
  await createCode(DOCTOR, CODE); // issued before revocation (server time)
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  assert.equal(await revoke(DOCTOR, PATIENT, DOCTOR), OK, 'doctor revokes');

  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, CODE), DENIED, 'old code still active');

  const NEW_CODE = 'NEWCDE2345';
  assert.equal(await createCode(DOCTOR, NEW_CODE), OK, 'doctor issues new code');
  assert.equal(await reactivate(DOCTOR, PATIENT, DOCTOR, NEW_CODE), DENIED, 'doctor reactivates');
  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, NEW_CODE), OK, 'patient uses new code');
  assert.equal(await get(as(DOCTOR), `users/${PATIENT}`), OK, 'access restored');
});

test('doctor-revoked: new but inactive, or expired, codes are rejected', async () => {
  await createCode(DOCTOR, CODE);
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  await revoke(DOCTOR, PATIENT, DOCTOR);

  const NEW_CODE = 'NEWCDE2345';
  await createCode(DOCTOR, NEW_CODE);
  await write(as(DOCTOR), `doctorCodes/${NEW_CODE}`, { active: false },
    { mask: ['active'], exists: true });
  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, NEW_CODE), DENIED, 'deactivated new code');

  await seedCode('EXPIREDXY2', DOCTOR, { createdAt: new Date(Date.now() - 31 * 864e5) });
  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, 'EXPIREDXY2'), DENIED, 'expired code');
});

test('patient-revoked: same valid code may reactivate', async () => {
  await createCode(DOCTOR, CODE);
  await createLink(PATIENT, PATIENT, DOCTOR, CODE);
  await revoke(PATIENT, PATIENT, DOCTOR);
  assert.equal(await reactivate(DOCTOR, PATIENT, DOCTOR, CODE), DENIED, 'doctor reactivates');
  assert.equal(await reactivate(PATIENT, PATIENT, DOCTOR, CODE), OK, 'patient reactivates');
});

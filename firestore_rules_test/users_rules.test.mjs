// Firestore Security Rules tests for users/{uid}, run against the local
// Firestore emulator. No npm packages: Node's built-in test runner plus the
// emulator REST API, so every check is a real rules evaluation.
//
// Run from the project root:
//   npx -y firebase-tools@15.35.0 emulators:exec --only firestore --project demo-medfollow "node --test --test-concurrency=1 firestore_rules_test/users_rules.test.mjs firestore_rules_test/doctor_linking_rules.test.mjs"

import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-medfollow';
const HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const BASE = `http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;

// Unsigned ID token; the emulator accepts these for request.auth.
function tokenFor(uid) {
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${enc({ alg: 'none', typ: 'JWT' })}.${enc({
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    sub: uid,
    user_id: uid,
    iat: now,
    exp: now + 3600,
    auth_time: now,
    email: `${uid}@example.com`,
    firebase: { sign_in_provider: 'password', identities: {} },
  })}.`;
}

const auth = (uid) => (uid ? { Authorization: `Bearer ${tokenFor(uid)}` } : {});
const ADMIN = { Authorization: 'Bearer owner' }; // bypasses rules (seeding)

// Mirrors UserProfile.toMap() as written by FirebaseAuthRepository.signUp().
function profile({ role = 'patient', linked = [], name = 'Alex Morgan' } = {}) {
  return {
    fields: {
      displayName: { stringValue: name },
      email: { stringValue: 'alex@example.com' },
      role: { stringValue: role },
      linkedDoctorIds: {
        arrayValue: linked.length
          ? { values: linked.map((v) => ({ stringValue: v })) }
          : {},
      },
    },
  };
}

async function req(method, path, headers, body) {
  const res = await fetch(`${BASE}/${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.status;
}

// set() on a missing doc is a create; PATCH with a field mask is an update.
const write = (path, headers, body) => req('PATCH', path, headers, body);
const read = (path, headers) => req('GET', path, headers);
const updateFields = (path, headers, body, fields) =>
  req(
    'PATCH',
    `${path}?${fields.map((f) => `updateMask.fieldPaths=${f}`).join('&')}`,
    headers,
    body,
  );

const OK = 200;
const DENIED = 403;

beforeEach(async () => {
  const res = await fetch(
    `http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  assert.equal(res.status, 200, 'emulator reset failed');
});

test('1. own profile creation with valid data is allowed', async () => {
  assert.equal(await write('users/alice', auth('alice'), profile()), OK);
  assert.equal(
    await write('users/drbob', auth('drbob'), profile({ role: 'doctor' })),
    OK,
  );
});

test('2. own profile read is allowed', async () => {
  await write('users/alice', ADMIN, profile());
  assert.equal(await read('users/alice', auth('alice')), OK);
});

test('3. unauthenticated access is denied', async () => {
  await write('users/alice', ADMIN, profile());
  assert.equal(await read('users/alice', auth(null)), DENIED);
  assert.equal(await write('users/eve', auth(null), profile()), DENIED);
});

test("4. reading another user's profile is denied (even as doctor)", async () => {
  await write('users/alice', ADMIN, profile());
  await write('users/drbob', ADMIN, profile({ role: 'doctor' }));
  assert.equal(await read('users/alice', auth('mallory')), DENIED);
  assert.equal(await read('users/alice', auth('drbob')), DENIED);
});

test("5. creating another user's profile is denied", async () => {
  assert.equal(await write('users/alice', auth('mallory'), profile()), DENIED);
});

test('6. invalid roles are rejected', async () => {
  for (const role of ['admin', 'Doctor', '']) {
    assert.equal(
      await write('users/alice', auth('alice'), profile({ role })),
      DENIED,
      `role "${role}" should be rejected`,
    );
  }
});

test('7. creating with linked doctor IDs is rejected', async () => {
  assert.equal(
    await write('users/alice', auth('alice'), profile({ linked: ['drbob'] })),
    DENIED,
  );
});

test('8. client-side role change is rejected', async () => {
  await write('users/alice', ADMIN, profile());
  assert.equal(
    await updateFields(
      'users/alice',
      auth('alice'),
      { fields: { role: { stringValue: 'doctor' } } },
      ['role'],
    ),
    DENIED,
  );
});

test('9. client-side doctor-link modification is rejected', async () => {
  await write('users/alice', ADMIN, profile());
  assert.equal(
    await updateFields(
      'users/alice',
      auth('alice'),
      { fields: { linkedDoctorIds: { arrayValue: { values: [{ stringValue: 'drbob' }] } } } },
      ['linkedDoctorIds'],
    ),
    DENIED,
  );
});

test('10. unrelated collections remain protected', async () => {
  const doc = { fields: { name: { stringValue: 'Aspirin' } } };
  assert.equal(await write('medications/m1', auth('alice'), doc), DENIED);
  assert.equal(await read('medications/m1', auth('alice')), DENIED);
  assert.equal(await write('users/alice/doses/d1', auth('alice'), doc), DENIED);
});

test('extra: invalid shapes are rejected, name-only update allowed', async () => {
  const extra = profile();
  extra.fields.isAdmin = { booleanValue: true };
  assert.equal(await write('users/alice', auth('alice'), extra), DENIED);
  assert.equal(
    await write('users/alice', auth('alice'), profile({ name: '   ' })),
    DENIED,
  );
  assert.equal(
    await write('users/alice', auth('alice'), profile({ name: 'x'.repeat(101) })),
    DENIED,
  );

  await write('users/alice', ADMIN, profile());
  assert.equal(
    await updateFields(
      'users/alice',
      auth('alice'),
      { fields: { displayName: { stringValue: 'Alex M.' } } },
      ['displayName'],
    ),
    OK,
  );
  assert.equal(await req('DELETE', 'users/alice', auth('alice')), DENIED);
});

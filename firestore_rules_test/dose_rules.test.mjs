// Real Firestore rules evaluation for doseRecords (Person 1), using only
// Node's built-in modules. Same helpers and fixtures as
// medication_rules.test.mjs. Run sequentially with the other suites in the
// disposable demo namespace (the emulator data is reset before each test).
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-medfollow';
const HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const BASE = 'http://' + HOST + '/v1/projects/' + PROJECT + '/databases/(default)/documents';
const ADMIN = { Authorization: 'Bearer owner' };
function auth(uid) {
  if (!uid) return {};
  const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const token = enc({alg: 'none', typ: 'JWT'}) + '.' + enc({
    iss: 'https://securetoken.google.com/' + PROJECT, aud: PROJECT,
    sub: uid, user_id: uid, iat: now, exp: now + 3600, auth_time: now,
    email: uid + '@example.com',
    firebase: {sign_in_provider: 'password', identities: {}},
  }) + '.';
  return { Authorization: 'Bearer ' + token };
}
function value(v) {
  if (v === null) return {nullValue: null};
  if (v instanceof Date) return {timestampValue: v.toISOString()};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'string') return {stringValue: v};
  if (typeof v === 'number') return Number.isInteger(v)
    ? {integerValue: String(v)} : {doubleValue: v};
  if (Array.isArray(v)) return {arrayValue: {values: v.map(value)}};
  return {mapValue: {fields: fields(v)}};
}
const fields = data => Object.fromEntries(Object.entries(data).map(([k,v]) => [k, value(v)]));
async function request(method, suffix, headers, body) {
  return fetch(BASE + suffix, {
    method, headers: {'Content-Type': 'application/json', ...headers},
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
const write = (path, uid, data) => request('PATCH', '/' + path, uid === 'ADMIN' ? ADMIN : auth(uid), {fields: fields(data)});
const read = (path, uid) => request('GET', '/' + path, uid === 'ADMIN' ? ADMIN : auth(uid));
const profile = (role = 'patient') => ({displayName: 'Fictional user', email: 'fixture@example.com', role, linkedDoctorIds: []});
const medication = (patientId) => ({
  patientId, name: 'Fictional vitamin', doseAmount: 1, doseUnit: 'tablet',
  scheduledTimes: ['08:00'], stockAmount: 8, refillThreshold: 7,
  isActive: true, stockUnit: 'tablet', unitsPerDose: 1, revision: 1,
});

const HOUR = 60 * 60 * 1000;
// One fixed time, so updates only change status/confirmedAt.
const SCHEDULED = new Date(Date.now() - 2 * HOUR);     // a dose 2 h ago
const future = () => new Date(Date.now() + 2 * HOUR); // a dose in 2 h
const ID = 'm1_20261113_0800';
const dose = (overrides = {}) => ({
  patientId: 'alice', medicationId: 'm1', medicationName: 'Fictional vitamin',
  scheduledTime: SCHEDULED, status: 'taken', confirmedAt: new Date(),
  doseAmount: 1, doseUnit: 'tablet', ...overrides,
});
const overdue = (overrides = {}) => dose({status: 'overdue', confirmedAt: null, ...overrides});

async function query(uid, patientId) {
  const filters = patientId === undefined ? {} : {where: {fieldFilter: {
    field: {fieldPath: 'patientId'}, op: 'EQUAL', value: {stringValue: patientId},
  }}};
  return request('POST', ':runQuery', auth(uid), {structuredQuery: {
    from: [{collectionId: 'doseRecords'}], ...filters,
  }});
}

beforeEach(async () => {
  const reset = await fetch('http://' + HOST + '/emulator/v1/projects/' + PROJECT + '/databases/(default)/documents',
    {method: 'DELETE'});
  assert.equal(reset.status, 200);
  for (const [uid, role] of [['alice','patient'], ['bob','patient'], ['doctor','doctor'], ['unlinked','doctor']]) {
    assert.equal((await write('users/' + uid, 'ADMIN', profile(role))).status, 200);
  }
  assert.equal((await write('medications/m1', 'ADMIN', medication('alice'))).status, 200);
  assert.equal((await write('medications/b1', 'ADMIN', medication('bob'))).status, 200);
});

test('doses: patient confirms own dose; transaction may read an absent dose', async () => {
  assert.equal((await read('doseRecords/' + ID, 'alice')).status, 404); // allowed, not found
  assert.equal((await write('doseRecords/' + ID, 'alice', dose())).status, 200);
  assert.equal((await read('doseRecords/' + ID, 'alice')).status, 200);
  assert.equal((await request('DELETE', '/doseRecords/' + ID, auth('alice'))).status, 403);
});

test('doses: cannot write for another patient or their medication', async () => {
  assert.equal((await write('doseRecords/' + ID, 'alice', dose({patientId: 'bob'}))).status, 403);
  assert.equal((await write('doseRecords/b1_20261113_0800', 'alice', dose({medicationId: 'b1'}))).status, 403);
  for (const uid of [null, 'bob', 'doctor']) {
    assert.equal((await write('doseRecords/' + ID, uid, dose())).status, 403);
  }
});

test('doses: ID must match the medication and format', async () => {
  assert.equal((await write('doseRecords/m1_20261113_0800', 'alice', dose({medicationId: 'b1'}))).status, 403);
  assert.equal((await write('doseRecords/random-id', 'alice', dose())).status, 403);
});

test('doses: validates status, times and fields', async () => {
  // "scheduled" is never stored.
  assert.equal((await write('doseRecords/' + ID, 'alice', dose({status: 'scheduled', confirmedAt: null}))).status, 403);
  // taken needs a real, current tap time.
  assert.equal((await write('doseRecords/' + ID, 'alice', dose({confirmedAt: null}))).status, 403);
  assert.equal((await write('doseRecords/' + ID, 'alice', dose({confirmedAt: new Date(Date.now() - 3 * HOUR)}))).status, 403);
  // A future dose cannot be overdue/missed yet.
  assert.equal((await write('doseRecords/' + ID, 'alice', overdue({scheduledTime: future()}))).status, 403);
  // Missed with a tap time, or an unknown extra field.
  assert.equal((await write('doseRecords/' + ID, 'alice', dose({status: 'missed'}))).status, 403);
  assert.equal((await write('doseRecords/' + ID, 'alice', {...dose(), extra: true})).status, 403);
});

test('doses: overdue may become taken; taken and missed are final', async () => {
  assert.equal((await write('doseRecords/' + ID, 'alice', overdue())).status, 200);
  assert.equal((await write('doseRecords/' + ID, 'alice', dose())).status, 200); // overdue -> taken
  assert.equal((await write('doseRecords/' + ID, 'alice', overdue())).status, 403); // taken -> overdue
  assert.equal((await write('doseRecords/' + ID, 'alice', dose({status: 'missed', confirmedAt: null}))).status, 403);

  const other = 'm1_20261113_0900';
  assert.equal((await write('doseRecords/' + other, 'alice', overdue())).status, 200);
  assert.equal((await write('doseRecords/' + other, 'alice', overdue({status: 'missed'}))).status, 200); // overdue -> missed
  assert.equal((await write('doseRecords/' + other, 'alice', dose())).status, 403); // missed -> taken
});

test('doses: update may only change status and confirmedAt', async () => {
  assert.equal((await write('doseRecords/' + ID, 'alice', overdue())).status, 200);
  assert.equal((await write('doseRecords/' + ID, 'alice', dose({medicationName: 'Renamed'}))).status, 403);
});

test('doses: queries need patient scope; linked doctors read only', async () => {
  await write('doseRecords/' + ID, 'alice', dose());
  assert.equal((await query('alice', 'alice')).status, 200);
  assert.equal((await query('alice', 'bob')).status, 403);
  assert.equal((await query('alice')).status, 403);
  assert.equal((await read('doseRecords/' + ID, 'bob')).status, 403);

  assert.equal((await read('doseRecords/' + ID, 'doctor')).status, 403);
  await write('doctorLinks/alice_doctor', 'ADMIN', {patientId: 'alice', doctorId: 'doctor', status: 'active'});
  assert.equal((await read('doseRecords/' + ID, 'doctor')).status, 200);
  assert.equal((await query('doctor', 'alice')).status, 200);
  assert.equal((await query('unlinked', 'alice')).status, 403);
  assert.equal((await write('doseRecords/' + ID, 'doctor', overdue())).status, 403);
});

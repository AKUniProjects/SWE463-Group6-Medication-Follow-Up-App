// Real Firestore rules evaluation, using only Node's built-in modules.
// Run sequentially with the existing rule suites in a disposable demo namespace.
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
const medication = (overrides = {}) => ({
  patientId: 'alice', name: 'Fictional vitamin', doseAmount: 500, doseUnit: 'mg',
  scheduledTimes: ['08:00', '20:00'], stockAmount: 8, refillThreshold: 7,
  isActive: true, stockUnit: 'tablet', unitsPerDose: 1, revision: 1, ...overrides,
});
async function query(uid, patientId) {
  const filters = patientId === undefined ? {} : {where: {fieldFilter: {
    field: {fieldPath: 'patientId'}, op: 'EQUAL', value: {stringValue: patientId},
  }}};
  return request('POST', ':runQuery', auth(uid), {structuredQuery: {
    from: [{collectionId: 'medications'}], ...filters,
  }});
}
beforeEach(async () => {
  const reset = await fetch('http://' + HOST + '/emulator/v1/projects/' + PROJECT + '/databases/(default)/documents',
    {method: 'DELETE'});
  assert.equal(reset.status, 200);
  for (const [uid, role] of [['alice','patient'], ['bob','patient'], ['doctor','doctor'], ['unlinked','doctor']]) {
    assert.equal((await write('users/' + uid, 'ADMIN', profile(role))).status, 200);
  }
});

test('medications: own CRUD, revision conflict, soft delete and retained history', async () => {
  const original = medication();
  assert.equal((await read('medications/new-random-id', 'alice')).status, 404); // creation transaction
  assert.equal((await write('medications/m1', 'alice', original)).status, 200);
  assert.equal((await read('medications/m1', 'alice')).status, 200);
  assert.equal((await write('doseRecords/history-1', 'ADMIN', {patientId: 'alice', medicationId: 'm1', status: 'taken'})).status, 200);
  const edited = medication({name: 'Updated fictional vitamin', revision: 2});
  assert.equal((await write('medications/m1', 'alice', edited)).status, 200);
  assert.equal((await write('medications/m1', 'alice', edited)).status, 403);
  const inactive = {...edited, isActive: false, revision: 3};
  assert.equal((await write('medications/m1', 'alice', inactive)).status, 200);
  assert.equal((await read('medications/m1', 'alice')).status, 200);
  assert.equal((await write('medications/m1', 'alice', {...inactive, isActive: true, revision: 4})).status, 403);
  assert.equal((await request('DELETE', '/medications/m1', auth('alice'))).status, 403);
  const history = await (await read('doseRecords/history-1', 'ADMIN')).json();
  assert.equal(history.fields.status.stringValue, 'taken');
});

test('medications: anonymous, other patient and doctor writes are denied', async () => {
  assert.equal((await write('medications/m1', 'alice', medication())).status, 200);
  for (const uid of [null, 'bob', 'doctor', 'unlinked']) {
    assert.equal((await write('medications/m1', uid, medication({stockAmount: 0, revision: 2}))).status, 403);
    assert.equal((await read('medications/m1', uid)).status, 403);
  }
  assert.equal((await write('medications/m2', 'alice', medication({patientId: 'bob'}))).status, 403);
  assert.equal((await write('medications/m1', 'alice', medication({patientId: 'bob', revision: 2}))).status, 403);
});

test('medications: queries require patient scope and linked doctors are read-only', async () => {
  await write('medications/m1', 'alice', medication());
  await write('medications/m2', 'bob', medication({patientId: 'bob'}));
  assert.equal((await query('alice', 'alice')).status, 200);
  assert.equal((await query('alice', 'bob')).status, 403);
  assert.equal((await query('alice')).status, 403);
  await write('doctorLinks/alice_doctor', 'ADMIN', {patientId: 'alice', doctorId: 'doctor', status: 'active'});
  assert.equal((await read('medications/m1', 'doctor')).status, 200);
  assert.equal((await query('doctor', 'alice')).status, 200);
  assert.equal((await query('doctor')).status, 403);
  assert.equal((await query('unlinked', 'alice')).status, 403);
  assert.equal((await write('medications/m1', 'doctor', medication({revision: 2}))).status, 403);
  await write('doctorLinks/alice_doctor', 'ADMIN', {patientId: 'alice', doctorId: 'doctor', status: 'revoked'});
  assert.equal((await read('medications/m1', 'doctor')).status, 403);
  assert.equal((await query('doctor', 'alice')).status, 403);
});

test('medications: validates all fields and all daily time positions on the server', async () => {
  const invalid = [
    {name: ''}, {name: '  '}, {name: ' untrimmed'}, {name: 'x'.repeat(101)},
    {doseAmount: 0}, {doseAmount: -1}, {doseAmount: 1000000001},
    {doseUnit: 'invalid'}, {stockUnit: 'invalid'},
    {stockAmount: -1}, {stockAmount: 1.5}, {refillThreshold: -1},
    {unitsPerDose: 0}, {unitsPerDose: 0.5}, {scheduledTimes: []},
    {scheduledTimes: ['08:00', '08:00']}, {scheduledTimes: ['08:00', '24:00']},
    {scheduledTimes: ['08:00', 9]}, {revision: 2}, {extraField: 'unexpected'},
  ];
  for (const [i, changes] of invalid.entries()) {
    assert.equal((await write('medications/bad-' + i, 'alice', medication(changes))).status, 403, JSON.stringify(changes));
  }
  const times = Array.from({length: 24}, (_, i) => String(i).padStart(2, '0') + ':00');
  assert.equal((await write('medications/maximum', 'alice', medication({scheduledTimes: times}))).status, 200);
  const badLast = [...times]; badLast[23] = '25:00';
  assert.equal((await write('medications/bad-last', 'alice', medication({scheduledTimes: badLast}))).status, 403);
  assert.equal((await write('medications/too-many', 'alice', medication({scheduledTimes: [...times, '00:01']}))).status, 403);
  assert.equal((await write('medications/zero', 'alice', medication({stockAmount: 0, unitsPerDose: null}))).status, 200);
});

const docName = path => 'projects/' + PROJECT + '/databases/(default)/documents/' + path;
async function consume(receiptId, stock, revision, uid = 'alice', includeStock = true) {
  const writes = [];
  if (includeStock) writes.push({
    update: {name: docName('medications/m1'), fields: fields(medication({stockAmount: stock, revision}))},
    currentDocument: {exists: true},
  });
  writes.push({
    update: {name: docName('medications/m1/consumptions/' + receiptId),
      fields: fields({patientId: 'alice', doseRecordId: receiptId, units: 1, revision})},
    currentDocument: {exists: false},
    updateTransforms: [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}],
  });
  return request('POST', ':commit', auth(uid), {writes});
}

test('consumption: atomic receipt/deduction, immutable receipt and restart read', async () => {
  await write('medications/m1', 'alice', medication());
  assert.equal((await read('medications/m1/consumptions/dose-1', 'alice')).status, 404);
  assert.equal((await consume('dose-1', 7, 2)).status, 200);
  const receipt = await read('medications/m1/consumptions/dose-1', 'alice');
  assert.equal(receipt.status, 200);
  assert.equal((await consume('dose-1', 6, 3)).status >= 400, true);
  assert.equal((await request('DELETE', '/medications/m1/consumptions/dose-1', auth('alice'))).status, 403);
  const freshRead = await (await read('medications/m1', 'alice')).json();
  assert.equal(Number(freshRead.fields.stockAmount.integerValue), 7);
  assert.equal((await read('medications/m1/consumptions/dose-1', 'bob')).status, 403);
});

test('consumption: no standalone/fake receipt, wrong delta, overdraft or cross-patient deduction', async () => {
  await write('medications/m1', 'alice', medication({stockAmount: 1}));
  assert.equal((await consume('alone', 1, 1, 'alice', false)).status, 403);
  assert.equal((await consume('wrong-delta', 1, 2)).status, 403);
  assert.equal((await consume('cross', 0, 2, 'bob')).status, 403);
  assert.equal((await consume('valid', 0, 2)).status, 200);
  assert.equal((await consume('overdraft', -1, 3)).status, 403);
  const finalRead = await (await read('medications/m1', 'alice')).json();
  assert.equal(Number(finalRead.fields.stockAmount.integerValue), 0);
});

// Runs Code.gs against in-memory stand-ins for the Apps Script services.
//   node --test submissions/test/
const test = require('node:test');
const assert = require('node:assert');

const {harness} = require('./gas_harness');

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]).toString('base64');
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).toString('base64');

function submission(over = {}) {
  return {
    kind: 'image', targetType: 'blades', targetId: '65', targetName: 'Dran Sword',
    username: 'kai', userId: 'u-1', credit: '@kai_photos', note: 'my own photo', consent: true,
    appVersion: '1.2.0', platform: 'android', image: {mimeType: 'image/jpeg', base64: JPEG},
    ...over,
  };
}

test('setup creates the sheet, the folder and both keys', () => {
  const h = harness();
  h.ctx.setup();
  assert.ok(h.store.ADMIN_KEY && h.store.SUBMIT_KEY && h.store.FOLDER_ID);
  assert.deepStrictEqual(h.sheets.Submissions.rows[0].slice(0, 3), ['id', 'submittedAt', 'status']);
});

test('a submission saves the picture and one row', () => {
  const h = harness({ADMIN_KEY: 'admin', SUBMIT_KEY: 'sk', FOLDER_ID: 'f'});
  const res = h.post({action: 'submit', submitKey: 'sk', submission: submission()});
  assert.strictEqual(res.ok, true);
  const rows = h.sheets.Submissions.getDataRange().getValues();
  assert.strictEqual(rows.length, 2);
  const head = rows[0];
  const row = Object.fromEntries(head.map((k, i) => [k, rows[1][i]]));
  assert.strictEqual(row.id, res.id);
  assert.strictEqual(row.status, 'new');
  assert.strictEqual(row.username, 'kai');
  assert.strictEqual(row.credit, '@kai_photos');
  assert.strictEqual(row.targetType, 'blades');
  assert.match(row.fileName, /_blades-65\.jpg$/);
  assert.strictEqual(Object.keys(h.files).length, 1);
});

test('wrong submit key, missing username, bad target, no consent and fake pictures are refused', () => {
  const h = harness({ADMIN_KEY: 'admin', SUBMIT_KEY: 'sk', FOLDER_ID: 'f'});
  const send = (s, key = 'sk') => h.post({action: 'submit', submitKey: key, submission: s});
  assert.strictEqual(send(submission(), 'nope').code, 'forbidden');
  assert.strictEqual(send(submission({username: '  '})).code, 'invalid');
  assert.strictEqual(send(submission({targetType: 'secrets'})).code, 'invalid');
  assert.strictEqual(send(submission({targetId: ''})).code, 'invalid');
  assert.strictEqual(send(submission({consent: false})).code, 'invalid');
  assert.strictEqual(send(submission({kind: 'fullBodyImage'})).code, 'invalid', 'full body only for bladers');
  assert.strictEqual(send(submission({image: {mimeType: 'image/gif', base64: JPEG}})).code, 'invalid');
  assert.strictEqual(send(submission({image: {mimeType: 'image/png', base64: JPEG}})).code, 'invalid',
      'a JPEG labelled PNG');
  assert.strictEqual(send(submission({image: {mimeType: 'image/jpeg', base64: '***'}})).code, 'invalid');
  assert.strictEqual(send(submission({targetType: 'other', targetId: '', note: ''})).code, 'invalid');
  assert.strictEqual(send(submission({targetType: 'other', targetId: '', note: 'a stadium'})).ok, true);
  assert.strictEqual(send(submission({kind: 'fullBodyImage', targetType: 'bladers', targetId: 'BL1',
    image: {mimeType: 'image/png', base64: PNG}})).ok, true);
});

test('too big pictures are refused', () => {
  const h = harness({ADMIN_KEY: 'a', FOLDER_ID: 'f'});
  const big = Buffer.alloc(6 * 1024 * 1024 + 1);
  big[0] = 0xff; big[1] = 0xd8; big[2] = 0xff;
  const res = h.post({action: 'submit', submission: submission({image: {mimeType: 'image/jpeg',
    base64: big.toString('base64')}})});
  assert.strictEqual(res.code, 'too_large');
});

test('one person is limited per hour', () => {
  const h = harness({ADMIN_KEY: 'a', FOLDER_ID: 'f', MAX_PER_HOUR: '2'});
  const send = () => h.post({action: 'submit', submission: submission()});
  assert.ok(send().ok);
  assert.ok(send().ok);
  assert.strictEqual(send().code, 'rate_limited');
  // someone else still can
  assert.ok(h.post({action: 'submit', submission: submission({userId: 'u-2', username: 'ren'})}).ok);
});

test('text that Sheets would run as a formula is stored as text', () => {
  const h = harness({ADMIN_KEY: 'a', FOLDER_ID: 'f'});
  h.post({action: 'submit', submission: submission({credit: '=IMPORTXML("x")', note: '+1 nice'})});
  const rows = h.sheets.Submissions.rows;
  const head = rows[0];
  assert.strictEqual(rows[1][head.indexOf('credit')], '\'=IMPORTXML("x")', 'stored as text');
  assert.strictEqual(rows[1][head.indexOf('note')], '\'+1 nice');
  const back = h.post({action: 'list', adminKey: 'a'}).items[0];
  assert.strictEqual(back.credit, '=IMPORTXML("x")', 'and read back as typed');
});

test('Studio: list, picture and status need the admin key', () => {
  const h = harness({ADMIN_KEY: 'admin', FOLDER_ID: 'f'});
  const a = h.post({action: 'submit', submission: submission()});
  const b = h.post({action: 'submit', submission: submission({targetId: '66'})});
  assert.strictEqual(h.post({action: 'list', adminKey: 'wrong'}).code, 'forbidden');
  assert.strictEqual(h.post({action: 'image', id: a.id}).code, 'forbidden');

  const list = h.post({action: 'list', adminKey: 'admin'});
  assert.deepStrictEqual(list.items.map((i) => i.id), [b.id, a.id], 'newest first');
  assert.strictEqual(list.items[0].fileId, undefined, 'Drive ids stay private');

  const pic = h.post({action: 'image', adminKey: 'admin', id: a.id});
  assert.strictEqual(pic.mimeType, 'image/jpeg');
  assert.strictEqual(pic.base64, JPEG, 'the same bytes come back');

  assert.ok(h.post({action: 'setStatus', adminKey: 'admin', id: a.id, status: 'applied', note: 'blades #65'}).ok);
  assert.strictEqual(h.post({action: 'setStatus', adminKey: 'admin', id: a.id, status: 'maybe'}).code, 'invalid');
  assert.strictEqual(h.post({action: 'setStatus', adminKey: 'admin', id: 'nope', status: 'applied'}).code,
      'not_found');
  assert.deepStrictEqual(h.post({action: 'list', adminKey: 'admin'}).items.map((i) => i.id), [b.id]);
  assert.strictEqual(h.post({action: 'list', adminKey: 'admin', status: 'applied'}).items[0].reviewNote,
      'blades #65');
});

test('a GET is a health check; junk is refused politely', () => {
  const h = harness();
  assert.deepStrictEqual(JSON.parse(h.ctx.doGet().text), {ok: true, service: 'clasher-submissions'});
  assert.strictEqual(JSON.parse(h.ctx.doPost({postData: {contents: 'not json'}}).text).code, 'bad_request');
  assert.strictEqual(h.post({action: 'drop tables'}).code, 'bad_request');
});

/**
 * Clasher submissions: pictures people send from the app (Settings -> Send pictures), kept in a Google Sheet.
 *
 * Deploy as a web app (Deploy -> New deployment -> Web app; Execute as: Me; Who has access: Anyone). Run setup()
 * once first: it creates the "Submissions" sheet, a Drive folder for the pictures and the keys. Opened from a
 * spreadsheet (Extensions -> Apps Script), it uses that spreadsheet; as a standalone script it creates a new
 * "Clasher submissions" spreadsheet (or uses SHEET_ID when you set it) and logs its link.
 *
 * Every request is a POST with a JSON body (sent as text/plain, so browsers don't need a CORS preflight):
 *   {action: "submit", submitKey?, submission: {...}}        the app: a picture and/or field values + who sent it
 *   {action: "list", adminKey, status?, limit?}             Clasher Studio: submissions to review (no pictures)
 *   {action: "image", adminKey, id}                         Clasher Studio: one picture as base64
 *   {action: "setStatus", adminKey, id, status, note?}      Clasher Studio: applied / rejected / new
 * A GET answers {ok: true} (health check).
 *
 * Pictures stay private in your Drive: nothing is shared publicly; Studio fetches them with the admin key.
 *
 * Script properties (Project settings -> Script properties), all set by setup():
 *   ADMIN_KEY    Studio's key (keep it private). Required for list / image / setStatus.
 *   SUBMIT_KEY   optional: when set, the app must send it (keeps random scripts out; it ships inside the app,
 *                so treat it as a speed bump, not a secret).
 *   FOLDER_ID    the Drive folder pictures go to.
 *   SHEET_ID     only for a standalone script: the spreadsheet's id or its whole link (setup() sets it when it
 *                creates the spreadsheet).
 *   MAX_PER_HOUR how many pictures one person can send per hour (default 20).
 */

var SHEET_NAME = 'Submissions';
var HEADERS = ['id', 'submittedAt', 'status', 'kind', 'targetType', 'targetId', 'targetName', 'field', 'value',
  'username', 'userId', 'credit', 'note', 'fileId', 'fileName', 'mimeType', 'bytes', 'appVersion', 'platform',
  'batch', 'reviewedAt', 'reviewNote'];
var STATUSES = ['new', 'applied', 'rejected'];
// a picture row: the main picture of a part / product / accessory / blader portrait, a blader's full-body
// picture, or anything else (described in the note). A value row ("value") holds one field's value.
var PICTURE_KINDS = ['image', 'fullBodyImage', 'other'];
// what it's of: the catalog sheet key the app uses (blades, burstLayers, products, bladers, tcgCards ...) or
// "other". Clasher Studio maps the key to the workbook tab.
var TARGET_TYPE = /^[A-Za-z][A-Za-z0-9]{1,40}$/;
var FIELD_NAME = /^[A-Za-z][A-Za-z0-9_]{0,40}$/;
// fields people never set from the app (ids, links, bookkeeping)
var NEVER_FIELDS = ['dataID', 'productID', 'setID', 'bladerID', 'stockComboID', 'parentPartId', 'parentProductId',
  'parentSetId', 'parentCardId', 'incompleteData', 'updated_at', 'deleted', 'credits', 'image', 'minifiedImage'];
var MAX_VALUES = 20;
var MIME_EXT = {'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp'};
var MAX_BYTES = 6 * 1024 * 1024;   // per picture, after base64 decoding (the app sends ~1600 px JPEGs)
var LIMITS = {username: 60, userId: 80, credit: 120, note: 500, targetId: 40, targetName: 120, appVersion: 40,
  platform: 20, value: 300};

function doGet() {
  return json_({ok: true, service: 'clasher-submissions'});
}

function doPost(e) {
  var body;
  try {
    body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (err) {
    return json_(fail_('bad_request', 'The request isn\'t JSON.'));
  }
  try {
    switch (body.action) {
      case 'submit': return json_(submit_(body));
      case 'list': requireAdmin_(body); return json_(list_(body));
      case 'image': requireAdmin_(body); return json_(image_(body));
      case 'setStatus': requireAdmin_(body); return json_(setStatus_(body));
      default: return json_(fail_('bad_request', 'Unknown action.'));
    }
  } catch (err) {
    if (err && err.code) return json_(fail_(err.code, err.message));
    console.error(err);
    return json_(fail_('server', 'Something went wrong. Try again later.'));
  }
}

// ── submit (the app) ────────────────────────────────────────────────────────────

function submit_(body) {
  var props = PropertiesService.getScriptProperties();
  var submitKey = props.getProperty('SUBMIT_KEY');
  if (submitKey && body.submitKey !== submitKey) throw error_('forbidden', 'This app version can\'t send pictures.');
  var s = body.submission || {};

  var username = clean_(s.username, LIMITS.username);
  if (!username) throw error_('invalid', 'Sign in to send pictures (no username).');
  var targetType = s.targetType === 'other' || TARGET_TYPE.test(String(s.targetType || '')) ? s.targetType : null;
  if (!targetType) throw error_('invalid', 'Unknown target.');
  var targetId = clean_(s.targetId, LIMITS.targetId);
  var note = clean_(s.note, LIMITS.note);
  if (targetType !== 'other' && !targetId) throw error_('invalid', 'Pick what the picture is of.');
  if (targetType === 'other' && !note) throw error_('invalid', 'Say what the picture is of.');
  if (s.consent !== true) throw error_('invalid', 'Confirm you may share this.');

  // field values: {field: value}, one row each
  var values = [];
  var raw = s.values && typeof s.values === 'object' ? s.values : {};
  Object.keys(raw).forEach(function (f) {
    var v = clean_(raw[f], LIMITS.value);
    if (!v) return;
    if (!FIELD_NAME.test(f) || NEVER_FIELDS.indexOf(f) >= 0) throw error_('invalid', 'Unknown field ' + f + '.');
    values.push([f, v]);
  });
  if (values.length > MAX_VALUES) throw error_('invalid', 'Too many fields at once.');
  if (values.length && targetType === 'other') throw error_('invalid', 'Values need a catalog entry.');

  // the picture (optional when there are values)
  var img = s.image && s.image.base64 ? s.image : null;
  var kind = null, ext = null, bytes = null;
  if (img) {
    kind = PICTURE_KINDS.indexOf(s.kind) >= 0 ? s.kind : null;
    if (!kind) throw error_('invalid', 'Unknown picture kind.');
    if (kind === 'fullBodyImage' && targetType !== 'bladers') throw error_('invalid', 'Full-body pictures are for bladers.');
    ext = MIME_EXT[img.mimeType];
    if (!ext) throw error_('invalid', 'Send a JPEG, PNG or WebP picture.');
    try {
      bytes = Utilities.base64Decode(String(img.base64 || ''));
    } catch (err) {
      throw error_('invalid', 'The picture couldn\'t be read.');
    }
    if (!bytes.length) throw error_('invalid', 'The picture is empty.');
    if (bytes.length > MAX_BYTES) throw error_('too_large', 'The picture is too big (max 6 MB).');
    if (!looksLike_(bytes, img.mimeType)) throw error_('invalid', 'The file isn\'t a ' + ext.toUpperCase() + ' picture.');
  }
  if (!img && !values.length) throw error_('invalid', 'Add a picture or fill in a field.');

  var who = clean_(s.userId, LIMITS.userId) || username.toLowerCase();
  rateLimit_(who, Number(props.getProperty('MAX_PER_HOUR')) || 20);

  var batch = Utilities.getUuid();
  var base = {
    submittedAt: new Date().toISOString(), status: 'new', targetType: targetType, targetId: targetId,
    targetName: clean_(s.targetName, LIMITS.targetName), username: username, userId: clean_(s.userId, LIMITS.userId),
    credit: clean_(s.credit, LIMITS.credit), note: note, appVersion: clean_(s.appVersion, LIMITS.appVersion),
    platform: clean_(s.platform, LIMITS.platform), batch: batch, reviewedAt: '', reviewNote: ''
  };
  var rows = [];
  if (img) {
    var id = Utilities.getUuid();
    var fileName = id + '_' + targetType + '-' + (targetId || 'other') + '.' + ext;
    var file = folder_().createFile(Utilities.newBlob(bytes, img.mimeType, fileName));
    rows.push(merge_(base, {id: id, kind: kind, fileId: file.getId(), fileName: fileName, mimeType: img.mimeType,
      bytes: bytes.length}));
  }
  values.forEach(function (fv) {
    rows.push(merge_(base, {id: Utilities.getUuid(), kind: 'value', field: fv[0], value: fv[1]}));
  });
  withLock_(function () {
    var sh = sheet_();
    var head = headers_(sh);
    rows.forEach(function (row) {
      sh.appendRow(head.map(function (h) { return safeCell_(row[h]); }));
    });
  });
  return {ok: true, id: rows[0].id, ids: rows.map(function (r) { return r.id; }), batch: batch};
}

// ── review (Clasher Studio) ─────────────────────────────────────────────────────

function list_(body) {
  var status = body.status ? String(body.status) : 'new';
  var limit = Math.min(Math.max(Number(body.limit) || 200, 1), 1000);
  var rows = readRows_();
  var items = rows.filter(function (r) { return status === 'all' || r.status === status; })
    .slice(-limit).reverse();          // newest first
  return {ok: true, items: items.map(function (r) {
    var out = {};
    HEADERS.forEach(function (h) { out[h] = r[h] === undefined ? '' : r[h]; });
    delete out.fileId;                 // Studio asks for the picture by submission id
    return out;
  })};
}

function image_(body) {
  var r = findRow_(String(body.id || ''));
  if (!r) throw error_('not_found', 'No submission ' + body.id + '.');
  if (!r.fileId) throw error_('not_found', 'Submission ' + body.id + ' has no picture.');
  var blob = DriveApp.getFileById(r.fileId).getBlob();
  return {ok: true, id: r.id, mimeType: blob.getContentType(), base64: Utilities.base64Encode(blob.getBytes())};
}

function setStatus_(body) {
  var status = String(body.status || '');
  if (STATUSES.indexOf(status) < 0) throw error_('invalid', 'Status must be ' + STATUSES.join(', ') + '.');
  var id = String(body.id || '');
  var updated = withLock_(function () {
    var r = findRow_(id);
    if (!r) return false;
    var sh = sheet_();
    var head = headers_(sh);
    var col = function (h) { return head.indexOf(h) + 1; };
    sh.getRange(r._row, col('status')).setValue(status);
    sh.getRange(r._row, col('reviewedAt')).setValue(new Date().toISOString());
    sh.getRange(r._row, col('reviewNote')).setValue(safeCell_(clean_(body.note, LIMITS.note)));
    return true;
  });
  if (!updated) throw error_('not_found', 'No submission ' + id + '.');
  return {ok: true, id: id, status: status};
}

// ── setup (run once from the editor) ────────────────────────────────────────────

function setup() {
  var props = PropertiesService.getScriptProperties();
  if (!spreadsheet_()) {
    // a standalone script with no SHEET_ID: make the spreadsheet and remember it
    var created = SpreadsheetApp.create('Clasher submissions');
    props.setProperty('SHEET_ID', created.getId());
  }
  var sh = sheet_();
  folder_();
  if (!props.getProperty('ADMIN_KEY')) props.setProperty('ADMIN_KEY', Utilities.getUuid().replace(/-/g, ''));
  if (!props.getProperty('SUBMIT_KEY')) props.setProperty('SUBMIT_KEY', Utilities.getUuid().replace(/-/g, '').slice(0, 16));
  console.log('ADMIN_KEY (Clasher Studio -> Settings -> Submissions): ' + props.getProperty('ADMIN_KEY'));
  console.log('SUBMIT_KEY (the app, CONTRIBUTIONS_KEY): ' + props.getProperty('SUBMIT_KEY'));
  console.log('Pictures folder: https://drive.google.com/drive/folders/' + props.getProperty('FOLDER_ID'));
  console.log('Submissions sheet: ' + sh.getParent().getUrl());
}

// ── helpers ─────────────────────────────────────────────────────────────────────

function requireAdmin_(body) {
  var key = PropertiesService.getScriptProperties().getProperty('ADMIN_KEY');
  if (!key || body.adminKey !== key) throw error_('forbidden', 'Wrong admin key.');
}

/** SHEET_ID's spreadsheet (an id or a whole link), else the one the script was opened from, else null. */
function spreadsheet_() {
  var raw = String(PropertiesService.getScriptProperties().getProperty('SHEET_ID') || '').trim();
  var m = raw.match(/\/d\/([A-Za-z0-9_-]+)/);
  var id = m ? m[1] : raw;
  if (id) return SpreadsheetApp.openById(id);
  try {
    return SpreadsheetApp.getActiveSpreadsheet();
  } catch (e) {
    return null;
  }
}

function sheet_() {
  var ss = spreadsheet_();
  if (!ss) throw error_('server', 'No spreadsheet yet: run setup() once from the Apps Script editor.');
  var sh = ss.getSheetByName(SHEET_NAME);
  if (!sh) {
    sh = ss.insertSheet(SHEET_NAME);
    sh.appendRow(HEADERS);
    sh.setFrozenRows(1);
  }
  return sh;
}

function folder_() {
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty('FOLDER_ID');
  if (id) return DriveApp.getFolderById(id);
  var folder = DriveApp.createFolder('Clasher submissions');
  props.setProperty('FOLDER_ID', folder.getId());
  return folder;
}

/** The sheet's header row, with any columns this script version added appended (older sheets keep working). */
function headers_(sh) {
  var values = sh.getDataRange().getValues();
  var head = (values[0] || []).map(String).filter(function (h) { return h; });
  var missing = HEADERS.filter(function (h) { return head.indexOf(h) < 0; });
  missing.forEach(function (h) {
    head.push(h);
    sh.getRange(1, head.length).setValue(h);
  });
  return head;
}

function merge_(a, b) {
  var out = {};
  Object.keys(a).forEach(function (k) { out[k] = a[k]; });
  Object.keys(b).forEach(function (k) { out[k] = b[k]; });
  return out;
}

function readRows_() {
  var values = sheet_().getDataRange().getValues();
  var head = values[0] || HEADERS;
  var out = [];
  for (var i = 1; i < values.length; i++) {
    var r = {_row: i + 1};
    head.forEach(function (h, j) {
      var v = values[i][j];
      r[h] = v instanceof Date ? v.toISOString() : v;
    });
    if (r.id) out.push(r);
  }
  return out;
}

function findRow_(id) {
  if (!id) return null;
  var rows = readRows_();
  for (var i = 0; i < rows.length; i++) if (String(rows[i].id) === id) return rows[i];
  return null;
}

function rateLimit_(who, perHour) {
  var cache = CacheService.getScriptCache();
  var key = 'rate:' + who;
  var n = Number(cache.get(key) || 0);
  if (n >= perHour) throw error_('rate_limited', 'You\'ve sent a lot of pictures - try again in an hour.');
  cache.put(key, String(n + 1), 3600);
}

function withLock_(fn) {
  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    return fn();
  } finally {
    lock.releaseLock();
  }
}

/** Text from the app: trimmed, one line for short fields, cut to max. Empty -> ''. */
function clean_(v, max) {
  if (v === null || v === undefined) return '';
  var s = String(v).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '').trim();
  if (max <= LIMITS.targetName) s = s.replace(/\s+/g, ' ');
  return s.slice(0, max);
}

/** A typed value starting with = + - @ would be run as a formula by Sheets: store it as text. */
function safeCell_(v) {
  if (typeof v === 'string' && /^[=+\-@\t\r]/.test(v)) return '\'' + v;
  return v === undefined || v === null ? '' : v;
}

/** The file's first bytes match its type (so a renamed file of another kind is refused). */
function looksLike_(bytes, mime) {
  var b = function (i) { return (bytes[i] + 256) % 256; };   // Apps Script bytes are signed
  if (mime === 'image/jpeg') return b(0) === 0xFF && b(1) === 0xD8 && b(2) === 0xFF;
  if (mime === 'image/png') return b(0) === 0x89 && b(1) === 0x50 && b(2) === 0x4E && b(3) === 0x47;
  if (mime === 'image/webp') {
    return b(0) === 0x52 && b(1) === 0x49 && b(2) === 0x46 && b(3) === 0x46 &&
      b(8) === 0x57 && b(9) === 0x45 && b(10) === 0x42 && b(11) === 0x50;
  }
  return false;
}

function error_(code, message) {
  var e = new Error(message);
  e.code = code;
  return e;
}

function fail_(code, message) {
  return {ok: false, code: code, error: message};
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

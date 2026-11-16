// In-memory stand-ins for the Apps Script services, running the real Code.gs (tests and the local server).
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SOURCE = fs.readFileSync(path.join(__dirname, '..', 'Code.gs'), 'utf8');

function harness(props = {}) {
  const store = {...props};
  const cache = {};
  const files = {};
  const sheets = {};
  let uuid = 0;

  class Range {
    constructor(sh, r, c) { this.sh = sh; this.r = r; this.c = c; }
    setValue(v) { this.sh.rows[this.r - 1][this.c - 1] = v; return this; }
  }
  class Sheet {
    constructor() { this.rows = []; }
    appendRow(r) { this.rows.push([...r]); }
    setFrozenRows() {}
    // like Sheets: a leading apostrophe only marks text and isn't part of the value read back
    getDataRange() {
      return {getValues: () => this.rows.map((r) => r.map((v) => (typeof v === 'string' && v.startsWith("'") ? v.slice(1) : v)))};
    }
    getRange(r, c) { return new Range(this, r, c); }
  }
  const ss = {
    getSheetByName: (n) => sheets[n] || null,
    insertSheet: (n) => (sheets[n] = new Sheet()),
  };
  const toBytes = (b64) => [...Buffer.from(b64, 'base64')].map((x) => (x > 127 ? x - 256 : x)); // signed like GAS
  const ctx = {
    console: {log() {}, error() {}},
    Date, JSON, Math, Number, String, Error,
    PropertiesService: {getScriptProperties: () => ({
      getProperty: (k) => (k in store ? store[k] : null),
      setProperty: (k, v) => { store[k] = v; },
    })},
    CacheService: {getScriptCache: () => ({
      get: (k) => (k in cache ? cache[k] : null),
      put: (k, v) => { cache[k] = v; },
    })},
    LockService: {getScriptLock: () => ({waitLock() {}, releaseLock() {}})},
    SpreadsheetApp: {getActiveSpreadsheet: () => ss, openById: () => ss},
    DriveApp: {
      createFolder: () => ({getId: () => 'folder1'}),
      getFolderById: () => ({createFile: (blob) => {
        const id = 'file' + Object.keys(files).length;
        files[id] = blob;
        return {getId: () => id};
      }}),
      getFileById: (id) => ({getBlob: () => ({
        getContentType: () => files[id].type,
        getBytes: () => files[id].bytes,
      })}),
    },
    Utilities: {
      getUuid: () => `00000000-0000-0000-0000-${String(++uuid).padStart(12, '0')}`,
      base64Decode: (s) => {
        if (!/^[A-Za-z0-9+/=]*$/.test(s)) throw new Error('bad base64');
        return toBytes(s);
      },
      base64Encode: (bytes) => Buffer.from(bytes.map((b) => (b + 256) % 256)).toString('base64'),
      newBlob: (bytes, type, name) => ({bytes, type, name}),
    },
    ContentService: {
      MimeType: {JSON: 'json'},
      createTextOutput: (text) => ({text, setMimeType() { return this; }}),
    },
  };
  vm.createContext(ctx);
  vm.runInContext(SOURCE, ctx);
  const post = (body) => JSON.parse(ctx.doPost({postData: {contents: JSON.stringify(body)}}).text);
  return {ctx, post, store, sheets, files, cache};
}


module.exports = {harness};

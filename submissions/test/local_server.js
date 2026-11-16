// A local stand-in for the deployed web app: runs Code.gs and answers like Apps Script does (a POST runs the
// script, then 302 -> a URL that returns the JSON). For trying the app and Clasher Studio without deploying.
//   node submissions/test/local_server.js [port]       (prints the URL; admin key "admin", submit key "sk")
const http = require('node:http');
const {harness} = require('./gas_harness');

const port = Number(process.argv[2] || 8765);
const h = harness({ADMIN_KEY: 'admin', SUBMIT_KEY: 'sk', FOLDER_ID: 'local'});
const answers = new Map();
let n = 0;

http.createServer((req, res) => {
  if (req.method === 'GET' && req.url.startsWith('/answer/')) {
    const body = answers.get(req.url.slice('/answer/'.length));
    res.writeHead(body ? 200 : 404, {'Content-Type': 'application/json'});
    return res.end(body || '{}');
  }
  if (req.method === 'GET') {
    res.writeHead(200, {'Content-Type': 'application/json'});
    return res.end(h.ctx.doGet().text);
  }
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const out = h.ctx.doPost({postData: {contents: Buffer.concat(chunks).toString('utf8')}}).text;
    const id = String(++n);
    answers.set(id, out);
    res.writeHead(302, {Location: `http://127.0.0.1:${port}/answer/${id}`});
    res.end();
  });
}).listen(port, '127.0.0.1', () => console.log(`http://127.0.0.1:${port}/exec`));

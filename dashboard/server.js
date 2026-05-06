const express = require('express');
const http = require('http');
const net = require('net');
const path = require('path');
const { Server } = require('socket.io');

const FLUME_HOST = process.env.FLUME_HOST || 'flume';
const FLUME_PORT = parseInt(process.env.FLUME_PORT || '44444', 10);
const HTTP_PORT = parseInt(process.env.HTTP_PORT || '5000', 10);
const TAP_PORT = parseInt(process.env.TAP_PORT || '5050', 10);

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

app.use(express.json({ limit: '256kb' }));
app.use(express.text({ limit: '256kb' }));
app.use(express.static(path.join(__dirname, 'public')));

const STATE = {
  total: 0, info: 0, warn: 0, error: 0,
  perSec: 0, start: Date.now(),
  logs: [],
  throughput: [],
  lastCount: 0,
};
const MAX_LOGS = 500;
const MAX_TP = 60;

function parseLevel(line) {
  if (line.includes('[INFO]')) return 'INFO';
  if (line.includes('[WARN]')) return 'WARN';
  if (line.includes('[ERROR]')) return 'ERROR';
  return 'INFO';
}

function processLine(line) {
  const trimmed = (line || '').trim();
  if (!trimmed) return;
  const level = parseLevel(trimmed);
  STATE.total += 1;
  if (level === 'INFO') STATE.info += 1;
  else if (level === 'WARN') STATE.warn += 1;
  else if (level === 'ERROR') STATE.error += 1;
  const entry = { ts: new Date().toISOString().slice(0, 19), level, msg: trimmed };
  STATE.logs.push(entry);
  if (STATE.logs.length > MAX_LOGS) STATE.logs.shift();
  io.emit('log', entry);
}

function sendToFlume(line) {
  return new Promise((resolve) => {
    const sock = net.createConnection({ host: FLUME_HOST, port: FLUME_PORT, timeout: 5000 });
    sock.on('connect', () => {
      sock.write(line.endsWith('\n') ? line : line + '\n', () => sock.end());
    });
    sock.on('close', () => resolve({ ok: true }));
    sock.on('error', (err) => resolve({ ok: false, error: err.message }));
    sock.on('timeout', () => { sock.destroy(); resolve({ ok: false, error: 'timeout' }); });
  });
}

function tapServer() {
  net.createServer((conn) => {
    let buf = '';
    conn.on('data', (chunk) => {
      buf += chunk.toString('utf8');
      let idx;
      while ((idx = buf.indexOf('\n')) !== -1) {
        const line = buf.slice(0, idx);
        buf = buf.slice(idx + 1);
        processLine(line);
      }
    });
    conn.on('error', () => {});
  }).listen(TAP_PORT, '0.0.0.0', () => {
    console.log(`[dashboard] TCP tap listening :${TAP_PORT}`);
  });
}

setInterval(() => {
  const delta = STATE.total - STATE.lastCount;
  STATE.perSec = delta / 2;
  STATE.lastCount = STATE.total;
  STATE.throughput.push({ t: new Date().toISOString().slice(0, 19), v: delta });
  if (STATE.throughput.length > MAX_TP) STATE.throughput.shift();
  io.emit('metrics', metrics());
}, 2000);

function metrics() {
  return {
    total: STATE.total,
    info: STATE.info,
    warn: STATE.warn,
    error: STATE.error,
    per_sec: STATE.perSec,
    uptime: Math.floor((Date.now() - STATE.start) / 1000),
  };
}

app.get('/api/metrics', (req, res) => res.json(metrics()));
app.get('/api/logs', (req, res) => res.json(STATE.logs));
app.get('/api/throughput', (req, res) => res.json(STATE.throughput));

app.post('/ingest', (req, res) => {
  const raw = typeof req.body === 'string' ? req.body : '';
  raw.split('\n').forEach(processLine);
  res.status(204).end();
});

app.post('/submit', async (req, res) => {
  const { level = 'INFO', msg = '' } = req.body || {};
  const lvl = String(level).toUpperCase();
  const text = String(msg).trim();
  if (!['INFO', 'WARN', 'ERROR'].includes(lvl)) {
    return res.status(400).json({ ok: false, error: 'niveau invalide' });
  }
  if (!text) return res.status(400).json({ ok: false, error: 'message vide' });
  const ts = new Date().toISOString().slice(0, 19).replace('T', ' ');
  const line = `[${lvl}] ${ts} - ${text}`;
  const r = await sendToFlume(line);
  processLine(line);
  res.json({ ok: r.ok, line, error: r.error || '' });
});

const ACTIONS = {
  login:  { level: 'INFO',  tpl: (u) => `User ${u} logged in successfully` },
  logout: { level: 'INFO',  tpl: (u) => `User ${u} logged out` },
  view:   { level: 'INFO',  tpl: (u, p) => `User ${u} viewed page ${p}` },
  click:  { level: 'INFO',  tpl: (u, p) => `User ${u} clicked button '${p}'` },
  submit: { level: 'INFO',  tpl: (u, p) => `User ${u} submitted form '${p}'` },
  upload: { level: 'INFO',  tpl: (u, p) => `User ${u} uploaded file ${p}` },
  search: { level: 'INFO',  tpl: (u, p) => `User ${u} searched '${p}'` },
  delete: { level: 'WARN',  tpl: (u, p) => `User ${u} deleted resource '${p}'` },
  fail:   { level: 'WARN',  tpl: (u) => `Login failed for user ${u}` },
  perms:  { level: 'WARN',  tpl: (u, p) => `Permission denied: ${u} on ${p}` },
  crash:  { level: 'ERROR', tpl: (u) => `Unhandled exception in session ${u}` },
  db:     { level: 'ERROR', tpl: () => `Database connection lost` },
  timeout:{ level: 'ERROR', tpl: (u, p) => `Timeout for ${u} on ${p}` },
};

app.post('/action', async (req, res) => {
  const { type, user = 'anonymous', target = '' } = req.body || {};
  const def = ACTIONS[type];
  if (!def) return res.status(400).json({ ok: false, error: `type inconnu: ${type}` });
  const ts = new Date().toISOString().slice(0, 19).replace('T', ' ');
  const line = `[${def.level}] ${ts} - ${def.tpl(user, target)}`;
  const r = await sendToFlume(line);
  processLine(line);
  res.json({ ok: r.ok, line, error: r.error || '' });
});

app.get('/api/actions', (req, res) => {
  res.json(Object.keys(ACTIONS).map((k) => ({ type: k, level: ACTIONS[k].level })));
});

io.on('connection', (sock) => {
  sock.emit('metrics', metrics());
  sock.emit('logs:init', STATE.logs.slice(-50));
});

tapServer();
server.listen(HTTP_PORT, '0.0.0.0', () => {
  console.log(`[dashboard] HTTP listening :${HTTP_PORT} → Flume ${FLUME_HOST}:${FLUME_PORT}`);
});

const express = require('express');
const net = require('net');
const path = require('path');
const crypto = require('crypto');

const FLUME_HOST = process.env.FLUME_HOST || 'flume';
const FLUME_PORT = parseInt(process.env.FLUME_PORT || '44444', 10);
const HTTP_PORT = parseInt(process.env.HTTP_PORT || '4000', 10);
const DASHBOARD_HOST = process.env.DASHBOARD_HOST || 'flume-dashboard';
const DASHBOARD_PORT = parseInt(process.env.DASHBOARD_PORT || '5050', 10);
const TOKEN_TTL_MS = 24 * 60 * 60 * 1000;

const app = express();
app.use(express.json({ limit: '128kb' }));
app.use(express.static(path.join(__dirname, 'public')));

// ─── State (in-memory) ─────────────────────────────────────────────────────
let SEQ = { user: 1, product: 1, category: 1, supplier: 1, movement: 1 };

const USERS = new Map();      // id → user
const USERS_BY_NAME = new Map();
const PRODUCTS = new Map();
const CATEGORIES = new Map();
const SUPPLIERS = new Map();
const MOVEMENTS = new Map();
const TOKENS = new Map();     // token → {userId, expires}

function addUser(u) {
  const id = SEQ.user++;
  const rec = { id, ...u, createdAt: new Date().toISOString() };
  USERS.set(id, rec);
  USERS_BY_NAME.set(u.username.toLowerCase(), rec);
  return rec;
}
function addCategory(name) { const id = SEQ.category++; const r = { id, name }; CATEGORIES.set(id, r); return r; }
function addSupplier(s) { const id = SEQ.supplier++; const r = { id, ...s }; SUPPLIERS.set(id, r); return r; }
function addProduct(p) {
  const id = SEQ.product++;
  const r = { id, ...p, createdAt: new Date().toISOString() };
  PRODUCTS.set(id, r);
  return r;
}

// Seed
addUser({ username: 'admin',    password: 'admin123',    role: 'admin',    name: 'Administrateur' });
addUser({ username: 'manager',  password: 'manager123',  role: 'manager',  name: 'Chef de stock' });
addUser({ username: 'employee', password: 'employee123', role: 'employee', name: 'Employé magasin' });

const catE = addCategory('Électronique');
const catA = addCategory('Alimentation');
const catB = addCategory('Bureautique');

const supA = addSupplier({ name: 'TogoTech SARL', contact: 'contact@togotech.tg' });
const supB = addSupplier({ name: 'CFAO Lomé',     contact: 'sales@cfao.tg' });

addProduct({ name: 'Ordinateur portable HP', sku: 'PC-HP-001', categoryId: catE.id, price: 450000, quantity: 12, supplierId: supA.id });
addProduct({ name: 'Souris Logitech',         sku: 'SR-LG-002', categoryId: catE.id, price: 8500,   quantity: 50, supplierId: supA.id });
addProduct({ name: 'Ramette papier A4',       sku: 'BR-PA-001', categoryId: catB.id, price: 4500,   quantity: 100, supplierId: supB.id });
addProduct({ name: 'Café 250g',               sku: 'AL-CA-001', categoryId: catA.id, price: 3500,   quantity: 30, supplierId: supB.id });

// ─── Logging vers Flume + Dashboard ───────────────────────────────────────
function nowTs() { return new Date().toISOString().slice(0, 19).replace('T', ' '); }
function sendTcp(host, port, line) {
  return new Promise((resolve) => {
    const sock = net.createConnection({ host, port, timeout: 5000 });
    sock.on('connect', () => sock.write(line.endsWith('\n') ? line : line + '\n', () => sock.end()));
    sock.on('close', () => resolve({ ok: true }));
    sock.on('error', () => resolve({ ok: false }));
    sock.on('timeout', () => { sock.destroy(); resolve({ ok: false }); });
  });
}
function logEvent(level, action, detail) {
  const line = `[${level}] ${nowTs()} - STOCK ${action} ${detail}`;
  sendTcp(FLUME_HOST, FLUME_PORT, line);
  sendTcp(DASHBOARD_HOST, DASHBOARD_PORT, line);
  console.log(line);
}

// ─── Auth middleware ──────────────────────────────────────────────────────
function getClientIp(req) {
  return (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
}

function authenticate(req, res, next) {
  const auth = req.headers.authorization || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'token requis' });
  const entry = TOKENS.get(token);
  if (!entry || entry.expires < Date.now()) {
    TOKENS.delete(token);
    return res.status(401).json({ error: 'token invalide ou expiré' });
  }
  req.user = USERS.get(entry.userId);
  if (!req.user) return res.status(401).json({ error: 'utilisateur introuvable' });
  next();
}

function requireRole(...allowed) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'non authentifié' });
    if (!allowed.includes(req.user.role)) {
      logEvent('WARN', 'PERM_DENIED', `user=${req.user.username} role=${req.user.role} required=[${allowed.join(',')}] path=${req.path} method=${req.method}`);
      return res.status(403).json({ error: 'permission refusée' });
    }
    next();
  };
}

// ─── Auth endpoints ───────────────────────────────────────────────────────
app.post('/api/auth/login', (req, res) => {
  const { username = '', password = '' } = req.body || {};
  const ip = getClientIp(req);
  const u = USERS_BY_NAME.get(String(username).toLowerCase());
  if (!u || u.password !== password) {
    logEvent('WARN', 'LOGIN_FAIL', `username=${username} ip=${ip} reason=${u ? 'wrong_password' : 'unknown_user'}`);
    return res.status(401).json({ error: 'identifiants invalides' });
  }
  const token = crypto.randomBytes(24).toString('hex');
  TOKENS.set(token, { userId: u.id, expires: Date.now() + TOKEN_TTL_MS });
  logEvent('INFO', 'LOGIN_OK', `user=${u.username} role=${u.role} ip=${ip}`);
  const { password: _, ...safe } = u;
  res.json({ token, user: safe });
});

app.post('/api/auth/logout', authenticate, (req, res) => {
  const auth = req.headers.authorization.slice(7);
  TOKENS.delete(auth);
  logEvent('INFO', 'LOGOUT', `user=${req.user.username}`);
  res.status(204).end();
});

app.get('/api/auth/me', authenticate, (req, res) => {
  const { password: _, ...safe } = req.user;
  res.json(safe);
});

// ─── Users (admin only) ───────────────────────────────────────────────────
app.get('/api/users', authenticate, requireRole('admin'), (req, res) => {
  const list = Array.from(USERS.values()).map(({ password, ...u }) => u);
  logEvent('INFO', 'LIST_USERS', `actor=${req.user.username} count=${list.length}`);
  res.json(list);
});

app.post('/api/users', authenticate, requireRole('admin'), (req, res) => {
  const { username, password, role, name } = req.body || {};
  if (!username || !password || !['admin', 'manager', 'employee'].includes(role)) {
    logEvent('WARN', 'CREATE_USER', `actor=${req.user.username} status=invalid_input`);
    return res.status(400).json({ error: 'champs invalides (username, password, role admin|manager|employee)' });
  }
  if (USERS_BY_NAME.has(username.toLowerCase())) {
    logEvent('WARN', 'CREATE_USER', `actor=${req.user.username} username=${username} status=duplicate`);
    return res.status(409).json({ error: 'utilisateur existant' });
  }
  const u = addUser({ username, password, role, name: name || username });
  logEvent('INFO', 'CREATE_USER', `actor=${req.user.username} new_user=${u.username} role=${u.role}`);
  const { password: _, ...safe } = u;
  res.status(201).json(safe);
});

app.delete('/api/users/:id', authenticate, requireRole('admin'), (req, res) => {
  const id = parseInt(req.params.id, 10);
  const u = USERS.get(id);
  if (!u) return res.status(404).json({ error: 'introuvable' });
  if (u.id === req.user.id) {
    logEvent('WARN', 'DELETE_USER', `actor=${req.user.username} status=self_delete_blocked`);
    return res.status(400).json({ error: 'impossible de se supprimer soi-même' });
  }
  USERS.delete(id);
  USERS_BY_NAME.delete(u.username.toLowerCase());
  logEvent('WARN', 'DELETE_USER', `actor=${req.user.username} target=${u.username}`);
  res.status(204).end();
});

// ─── Categories ───────────────────────────────────────────────────────────
app.get('/api/categories', authenticate, (req, res) => {
  res.json(Array.from(CATEGORIES.values()));
});
app.post('/api/categories', authenticate, requireRole('admin', 'manager'), (req, res) => {
  const { name } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name requis' });
  const c = addCategory(name);
  logEvent('INFO', 'CREATE_CATEGORY', `actor=${req.user.username} name=${name}`);
  res.status(201).json(c);
});

// ─── Suppliers ────────────────────────────────────────────────────────────
app.get('/api/suppliers', authenticate, requireRole('admin', 'manager'), (req, res) => {
  res.json(Array.from(SUPPLIERS.values()));
});
app.post('/api/suppliers', authenticate, requireRole('admin', 'manager'), (req, res) => {
  const { name, contact } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name requis' });
  const s = addSupplier({ name, contact: contact || '' });
  logEvent('INFO', 'CREATE_SUPPLIER', `actor=${req.user.username} name=${name}`);
  res.status(201).json(s);
});

// ─── Products ─────────────────────────────────────────────────────────────
app.get('/api/products', authenticate, (req, res) => {
  const list = Array.from(PRODUCTS.values()).map((p) => ({
    ...p,
    category: CATEGORIES.get(p.categoryId)?.name || '',
    supplier: SUPPLIERS.get(p.supplierId)?.name || '',
  }));
  logEvent('INFO', 'LIST_PRODUCTS', `actor=${req.user.username} count=${list.length}`);
  res.json(list);
});

app.post('/api/products', authenticate, requireRole('admin', 'manager'), (req, res) => {
  const { name, sku, categoryId, price, quantity, supplierId } = req.body || {};
  const errs = [];
  if (!name) errs.push('name');
  if (!sku) errs.push('sku');
  if (!CATEGORIES.has(Number(categoryId))) errs.push('categoryId');
  if (!SUPPLIERS.has(Number(supplierId))) errs.push('supplierId');
  if (Number(price) < 0) errs.push('price');
  if (Number(quantity) < 0) errs.push('quantity');
  if (errs.length) {
    logEvent('WARN', 'CREATE_PRODUCT', `actor=${req.user.username} status=invalid fields=[${errs.join(',')}]`);
    return res.status(400).json({ errors: errs });
  }
  const p = addProduct({
    name, sku,
    categoryId: Number(categoryId),
    supplierId: Number(supplierId),
    price: Number(price),
    quantity: Number(quantity),
  });
  logEvent('INFO', 'CREATE_PRODUCT', `actor=${req.user.username} sku=${sku} qty=${p.quantity}`);
  res.status(201).json(p);
});

app.put('/api/products/:id', authenticate, requireRole('admin', 'manager'), (req, res) => {
  const id = parseInt(req.params.id, 10);
  const p = PRODUCTS.get(id);
  if (!p) return res.status(404).json({ error: 'introuvable' });
  const { name, sku, categoryId, price, quantity, supplierId } = req.body || {};
  if (name) p.name = name;
  if (sku) p.sku = sku;
  if (categoryId && CATEGORIES.has(Number(categoryId))) p.categoryId = Number(categoryId);
  if (supplierId && SUPPLIERS.has(Number(supplierId))) p.supplierId = Number(supplierId);
  if (price !== undefined) p.price = Number(price);
  if (quantity !== undefined) p.quantity = Number(quantity);
  p.updatedAt = new Date().toISOString();
  logEvent('INFO', 'UPDATE_PRODUCT', `actor=${req.user.username} id=${id} sku=${p.sku}`);
  res.json(p);
});

app.delete('/api/products/:id', authenticate, requireRole('admin'), (req, res) => {
  const id = parseInt(req.params.id, 10);
  const p = PRODUCTS.get(id);
  if (!p) return res.status(404).json({ error: 'introuvable' });
  PRODUCTS.delete(id);
  logEvent('WARN', 'DELETE_PRODUCT', `actor=${req.user.username} id=${id} sku=${p.sku}`);
  res.status(204).end();
});

// ─── Stock movements ──────────────────────────────────────────────────────
app.get('/api/movements', authenticate, (req, res) => {
  const list = Array.from(MOVEMENTS.values()).sort((a, b) => b.id - a.id).map((m) => ({
    ...m,
    product: PRODUCTS.get(m.productId)?.sku || `#${m.productId}`,
    user: USERS.get(m.userId)?.username || '?',
  }));
  res.json(list);
});

app.post('/api/movements', authenticate, requireRole('admin', 'manager', 'employee'), (req, res) => {
  const { productId, qty, type, reason } = req.body || {};
  const p = PRODUCTS.get(Number(productId));
  if (!p) return res.status(404).json({ error: 'produit introuvable' });
  if (!['IN', 'OUT'].includes(type)) return res.status(400).json({ error: 'type doit être IN ou OUT' });
  const q = parseInt(qty, 10);
  if (!Number.isInteger(q) || q <= 0) return res.status(400).json({ error: 'qty entier positif' });

  if (type === 'OUT' && p.quantity < q) {
    logEvent('ERROR', 'STOCK_OUT', `actor=${req.user.username} sku=${p.sku} requested=${q} available=${p.quantity}`);
    return res.status(400).json({ error: `stock insuffisant (disponible: ${p.quantity})` });
  }

  p.quantity = type === 'IN' ? p.quantity + q : p.quantity - q;
  const id = SEQ.movement++;
  const m = {
    id, productId: p.id, qty: q, type,
    reason: reason || '',
    userId: req.user.id,
    createdAt: new Date().toISOString(),
  };
  MOVEMENTS.set(id, m);

  const lvl = type === 'IN' ? 'INFO' : 'WARN';
  logEvent(lvl, `MOVEMENT_${type}`, `actor=${req.user.username} sku=${p.sku} qty=${q} new_stock=${p.quantity} reason="${m.reason}"`);

  if (p.quantity < 5) {
    logEvent('WARN', 'LOW_STOCK', `sku=${p.sku} remaining=${p.quantity}`);
  }
  res.status(201).json(m);
});

// ─── Misc ─────────────────────────────────────────────────────────────────
app.get('/api/dashboard', authenticate, (req, res) => {
  const products = Array.from(PRODUCTS.values());
  res.json({
    products: products.length,
    totalQuantity: products.reduce((s, p) => s + p.quantity, 0),
    totalValue: products.reduce((s, p) => s + p.quantity * p.price, 0),
    lowStock: products.filter((p) => p.quantity < 5).length,
    movements: MOVEMENTS.size,
    users: USERS.size,
  });
});

app.get('/api/health', (req, res) => res.json({ ok: true }));

app.listen(HTTP_PORT, '0.0.0.0', () => {
  console.log(`[stock-app] HTTP listening :${HTTP_PORT} → Flume ${FLUME_HOST}:${FLUME_PORT}`);
  console.log(`[stock-app] Comptes seed : admin/admin123 · manager/manager123 · employee/employee123`);
});

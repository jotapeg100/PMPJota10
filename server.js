const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

let Pool;
try {
  ({ Pool } = require("pg"));
} catch {
  console.error("Falta instalar la dependencia PostgreSQL. Ejecuta: npm.cmd install");
  process.exit(1);
}

const PORT = Number(process.env.PORT || 3000);
const PUBLIC_DIR = path.join(__dirname, "public");
const sessions = new Map();
const databaseUrl = process.env.DATABASE_URL || "postgres://postgres:postgres@localhost:5432/pmp_control";

const pool = new Pool({
  connectionString: databaseUrl,
  ssl: process.env.PGSSL === "true" ? { rejectUnauthorized: false } : undefined
});

const tableConfig = {
  areas: {
    table: "areas",
    fields: ["name"]
  },
  initiatives: {
    table: "initiatives",
    fields: ["name", "sponsor", "areaId", "objective", "priority", "rag", "ragReasonInternal", "ragReasonExternal", "status", "budget", "benefit"]
  },
  projects: {
    table: "projects",
    fields: ["initiativeId", "parentProjectId", "type", "name", "owner", "scope", "status", "rag", "startDate", "endDate", "estimatedEffort", "actualEffort", "progress", "visibleToExternal"]
  },
  risks: {
    table: "risks",
    fields: ["entityType", "entityId", "title", "description", "cause", "consequence", "probability", "impact", "strategy", "mitigation", "owner", "dueDate", "status", "visibility"]
  },
  deliverables: {
    table: "deliverables",
    fields: ["projectId", "name", "description", "status", "evidenceUrl", "publishedAt"]
  },
  conformities: {
    table: "conformities",
    fields: ["deliverableId", "projectId", "userId", "status", "comment", "requestedAt", "respondedAt"]
  },
  phases: {
    table: "phases",
    fields: ["projectId", "name", "status", "closedAt", "closureNote"]
  },
  milestones: {
    table: "milestones",
    fields: ["projectId", "name", "dueDate", "status"]
  }
};

const seed = {
  areas: [
    { id: "area-comercial", name: "Comercial" },
    { id: "area-operaciones", name: "Operaciones" },
    { id: "area-tecnologia", name: "Tecnologia" }
  ],
  users: [
    { id: "u-pmp", name: "PMP Gestor", email: "pmp@local", role: "pmp", password: "pmp123" },
    { id: "u-cliente", name: "Cliente Externo", email: "cliente@local", role: "external", password: "cliente123" },
    { id: "u-gerente", name: "Gerente Comercial", email: "gerente@local", role: "external", password: "gerente123" }
  ],
  initiatives: [
    {
      id: "ini-transformacion",
      name: "Transformacion Digital Comercial",
      sponsor: "Direccion Comercial",
      areaId: "area-comercial",
      objective: "Ordenar el ciclo comercial y mejorar trazabilidad ejecutiva.",
      priority: "Alta",
      rag: "amber",
      ragReasonInternal: "Integracion CRM/ERP aun no cerrada.",
      ragReasonExternal: "Plan en curso con dependencias bajo seguimiento.",
      status: "En evaluacion",
      budget: 120000,
      benefit: "Mayor visibilidad del pipeline y menor reproceso."
    }
  ],
  projects: [
    {
      id: "pro-crm",
      initiativeId: "ini-transformacion",
      parentProjectId: null,
      type: "proyecto",
      name: "Implementacion CRM",
      owner: "PMP Gestor",
      scope: "Implementar flujo de oportunidades, contactos, pipeline y reportes.",
      status: "En ejecucion",
      rag: "amber",
      startDate: "2026-06-01",
      endDate: "2026-09-30",
      estimatedEffort: 720,
      actualEffort: 260,
      progress: 38,
      visibleToExternal: true
    },
    {
      id: "sub-migracion",
      initiativeId: "ini-transformacion",
      parentProjectId: "pro-crm",
      type: "subproyecto",
      name: "Migracion de datos",
      owner: "Operaciones",
      scope: "Depurar y migrar cuentas, contactos y oportunidades historicas.",
      status: "Plan aprobado",
      rag: "green",
      startDate: "2026-06-10",
      endDate: "2026-07-31",
      estimatedEffort: 180,
      actualEffort: 58,
      progress: 42,
      visibleToExternal: true
    },
    {
      id: "fea-dashboard",
      initiativeId: "ini-transformacion",
      parentProjectId: "pro-crm",
      type: "feature",
      name: "Dashboard comercial",
      owner: "Tecnologia",
      scope: "Tablero de pipeline, conversion y oportunidades por etapa.",
      status: "En definicion",
      rag: "green",
      startDate: "2026-07-01",
      endDate: "2026-08-15",
      estimatedEffort: 96,
      actualEffort: 12,
      progress: 15,
      visibleToExternal: true
    }
  ],
  phases: [
    { id: "ph-crm-1", projectId: "pro-crm", name: "Definicion", status: "Cerrada", closedAt: "2026-06-15", closureNote: "Alcance inicial aprobado." },
    { id: "ph-crm-2", projectId: "pro-crm", name: "Ejecucion", status: "En curso", closedAt: null, closureNote: "" }
  ],
  milestones: [
    { id: "ms-1", projectId: "pro-crm", name: "Plan de trabajo aprobado", dueDate: "2026-06-20", status: "Cumplido" },
    { id: "ms-2", projectId: "pro-crm", name: "Primer entregable funcional", dueDate: "2026-07-18", status: "En riesgo" }
  ],
  deliverables: [
    { id: "del-1", projectId: "pro-crm", name: "Documento de alcance CRM", description: "Alcance, exclusiones, supuestos y criterios de aceptacion.", status: "Conforme", evidenceUrl: "", publishedAt: "2026-06-14" },
    { id: "del-2", projectId: "pro-crm", name: "Prototipo dashboard comercial", description: "Vista inicial de indicadores comerciales.", status: "Publicado para conformidad", evidenceUrl: "", publishedAt: "2026-06-18" }
  ],
  conformities: [
    { id: "conf-1", deliverableId: "del-1", projectId: "pro-crm", userId: "u-cliente", status: "conforme", comment: "Aceptado para avanzar.", requestedAt: "2026-06-14", respondedAt: "2026-06-15" }
  ],
  risks: [
    { id: "risk-1", entityType: "project", entityId: "pro-crm", title: "Demora en integracion con ERP", description: "La disponibilidad del equipo ERP puede retrasar la integracion.", cause: "Capacidad limitada del proveedor interno.", consequence: "Retraso en hito de pruebas integrales.", probability: 3, impact: 3, strategy: "Mitigar", mitigation: "Reservar agenda tecnica y definir alternativa manual temporal.", owner: "Tecnologia", dueDate: "2026-07-05", status: "En seguimiento", visibility: "interno" },
    { id: "risk-2", entityType: "initiative", entityId: "ini-transformacion", title: "Demora en validacion de entregables", description: "Las aprobaciones externas pueden demorar el cierre de etapas.", cause: "Agenda de referentes comerciales.", consequence: "Reprogramacion de hitos.", probability: 2, impact: 3, strategy: "Mitigar", mitigation: "Acordar calendario fijo de revision.", owner: "PMP Gestor", dueDate: "2026-06-28", status: "Mitigacion definida", visibility: "externo" }
  ],
  access: [
    ["u-cliente", "pro-crm"],
    ["u-cliente", "sub-migracion"],
    ["u-cliente", "fea-dashboard"],
    ["u-gerente", "pro-crm"],
    ["u-gerente", "sub-migracion"],
    ["u-gerente", "fea-dashboard"]
  ]
};

function camelToSnake(value) {
  return value.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
}

function mapRow(row) {
  const item = {};
  for (const [key, value] of Object.entries(row)) {
    const cleanValue = value instanceof Date ? value.toISOString().slice(0, 10) : value;
    item[key.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase())] = cleanValue;
  }
  return item;
}

function id(prefix) {
  return `${prefix}-${crypto.randomBytes(5).toString("hex")}`;
}

function hashPassword(password, salt = crypto.randomBytes(16).toString("hex")) {
  const hash = crypto.scryptSync(password, salt, 64).toString("hex");
  return { salt, hash };
}

function verifyPassword(password, salt, expectedHash) {
  const actual = Buffer.from(hashPassword(password, salt).hash, "hex");
  const expected = Buffer.from(expectedHash, "hex");
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

function parseCookies(req) {
  return Object.fromEntries((req.headers.cookie || "").split(";").filter(Boolean).map((cookie) => {
    const index = cookie.indexOf("=");
    return [cookie.slice(0, index).trim(), decodeURIComponent(cookie.slice(index + 1))];
  }));
}

function sessionCookie(token) {
  return `sid=${encodeURIComponent(token)}; HttpOnly; SameSite=Lax; Path=/; Max-Age=28800`;
}

function clearSessionCookie() {
  return "sid=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0";
}

function sendJson(res, status, body, headers = {}) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    ...headers
  });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > 1_000_000) reject(new Error("Payload demasiado grande"));
    });
    req.on("end", () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        reject(new Error("JSON invalido"));
      }
    });
  });
}

async function initDatabase() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT UNIQUE NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('pmp', 'external')),
      password_hash TEXT NOT NULL,
      password_salt TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS areas (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS initiatives (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      sponsor TEXT,
      area_id TEXT REFERENCES areas(id),
      objective TEXT,
      priority TEXT,
      rag TEXT,
      rag_reason_internal TEXT,
      rag_reason_external TEXT,
      status TEXT,
      budget NUMERIC,
      benefit TEXT
    );
    CREATE TABLE IF NOT EXISTS projects (
      id TEXT PRIMARY KEY,
      initiative_id TEXT REFERENCES initiatives(id) ON DELETE CASCADE,
      parent_project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
      type TEXT NOT NULL,
      name TEXT NOT NULL,
      owner TEXT,
      scope TEXT,
      status TEXT,
      rag TEXT,
      start_date DATE,
      end_date DATE,
      estimated_effort NUMERIC DEFAULT 0,
      actual_effort NUMERIC DEFAULT 0,
      progress NUMERIC DEFAULT 0,
      visible_to_external BOOLEAN DEFAULT true
    );
    CREATE TABLE IF NOT EXISTS user_project_access (
      user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
      PRIMARY KEY (user_id, project_id)
    );
    CREATE TABLE IF NOT EXISTS phases (
      id TEXT PRIMARY KEY,
      project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      status TEXT,
      closed_at DATE,
      closure_note TEXT
    );
    CREATE TABLE IF NOT EXISTS milestones (
      id TEXT PRIMARY KEY,
      project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      due_date DATE,
      status TEXT
    );
    CREATE TABLE IF NOT EXISTS deliverables (
      id TEXT PRIMARY KEY,
      project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      description TEXT,
      status TEXT,
      evidence_url TEXT,
      published_at DATE
    );
    CREATE TABLE IF NOT EXISTS conformities (
      id TEXT PRIMARY KEY,
      deliverable_id TEXT REFERENCES deliverables(id) ON DELETE CASCADE,
      project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
      user_id TEXT REFERENCES users(id),
      status TEXT,
      comment TEXT,
      requested_at DATE,
      responded_at DATE
    );
    CREATE TABLE IF NOT EXISTS risks (
      id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      cause TEXT,
      consequence TEXT,
      probability INTEGER NOT NULL DEFAULT 1,
      impact INTEGER NOT NULL DEFAULT 1,
      strategy TEXT,
      mitigation TEXT,
      owner TEXT,
      due_date DATE,
      status TEXT,
      visibility TEXT NOT NULL DEFAULT 'interno'
    );
  `);

  const { rows } = await pool.query("SELECT COUNT(*)::int AS count FROM users");
  if (rows[0].count > 0) return;

  for (const area of seed.areas) {
    await pool.query("INSERT INTO areas (id, name) VALUES ($1, $2)", [area.id, area.name]);
  }
  for (const user of seed.users) {
    const password = hashPassword(user.password);
    await pool.query(
      "INSERT INTO users (id, name, email, role, password_hash, password_salt) VALUES ($1, $2, $3, $4, $5, $6)",
      [user.id, user.name, user.email, user.role, password.hash, password.salt]
    );
  }
  for (const initiative of seed.initiatives) await insertRecord("initiatives", initiative);
  for (const project of seed.projects) await insertRecord("projects", project);
  for (const phase of seed.phases) await insertRecord("phases", phase);
  for (const milestone of seed.milestones) await insertRecord("milestones", milestone);
  for (const deliverable of seed.deliverables) await insertRecord("deliverables", deliverable);
  for (const conformity of seed.conformities) await insertRecord("conformities", conformity);
  for (const risk of seed.risks) await insertRecord("risks", risk);
  for (const [userId, projectId] of seed.access) {
    await pool.query("INSERT INTO user_project_access (user_id, project_id) VALUES ($1, $2)", [userId, projectId]);
  }
}

async function insertRecord(collection, body) {
  const config = tableConfig[collection];
  const item = { ...body, id: body.id || id(collection.slice(0, 4)) };
  const fields = config.fields.filter((field) => Object.prototype.hasOwnProperty.call(item, field));
  const columns = ["id", ...fields.map(camelToSnake)];
  const values = [item.id, ...fields.map((field) => item[field] === "" ? null : item[field])];
  const placeholders = values.map((_, index) => `$${index + 1}`);
  await pool.query(`INSERT INTO ${config.table} (${columns.join(", ")}) VALUES (${placeholders.join(", ")})`, values);
  return item;
}

async function updateRecord(collection, recordId, body) {
  const config = tableConfig[collection];
  const fields = config.fields.filter((field) => Object.prototype.hasOwnProperty.call(body, field));
  if (fields.length === 0) return getRecordById(collection, recordId);
  const sets = fields.map((field, index) => `${camelToSnake(field)} = $${index + 1}`);
  const values = fields.map((field) => body[field] === "" ? null : body[field]);
  values.push(recordId);
  await pool.query(`UPDATE ${config.table} SET ${sets.join(", ")} WHERE id = $${values.length}`, values);
  return getRecordById(collection, recordId);
}

async function getRecordById(collection, recordId) {
  const config = tableConfig[collection];
  const { rows } = await pool.query(`SELECT * FROM ${config.table} WHERE id = $1`, [recordId]);
  return rows[0] ? mapRow(rows[0]) : null;
}

async function getUserFromRequest(req) {
  const token = parseCookies(req).sid;
  const userId = token ? sessions.get(token) : null;
  if (!userId) return null;
  const { rows } = await pool.query("SELECT id, name, email, role FROM users WHERE id = $1", [userId]);
  return rows[0] ? mapRow(rows[0]) : null;
}

function requirePmp(user) {
  if (!user || user.role !== "pmp") {
    const error = new Error("No tenes permisos para esta accion");
    error.status = 403;
    throw error;
  }
}

async function canAccessProject(user, projectId) {
  if (user.role === "pmp") return true;
  const { rows } = await pool.query(
    "SELECT 1 FROM user_project_access a JOIN projects p ON p.id = a.project_id WHERE a.user_id = $1 AND a.project_id = $2 AND p.visible_to_external = true",
    [user.id, projectId]
  );
  return rows.length > 0;
}

async function bootstrap(user) {
  const db = {};
  db.users = user.role === "pmp" ? (await pool.query("SELECT id, name, email, role FROM users ORDER BY name")).rows.map(mapRow) : [user];
  db.areas = (await pool.query("SELECT * FROM areas ORDER BY name")).rows.map(mapRow);

  if (user.role === "pmp") {
    for (const [collection, config] of Object.entries(tableConfig)) {
      if (collection === "areas") continue;
      db[collection] = (await pool.query(`SELECT * FROM ${config.table} ORDER BY id`)).rows.map(mapRow);
    }
    return db;
  }

  const projectRows = await pool.query(`
    SELECT p.* FROM projects p
    JOIN user_project_access a ON a.project_id = p.id
    WHERE a.user_id = $1 AND p.visible_to_external = true
    ORDER BY p.id
  `, [user.id]);
  db.projects = projectRows.rows.map(mapRow);
  const projectIds = db.projects.map((project) => project.id);
  const initiativeIds = [...new Set(db.projects.map((project) => project.initiativeId))];

  db.initiatives = initiativeIds.length
    ? (await pool.query("SELECT * FROM initiatives WHERE id = ANY($1) ORDER BY id", [initiativeIds])).rows.map((row) => {
        const initiative = mapRow(row);
        initiative.ragReasonInternal = "";
        return initiative;
      })
    : [];
  db.phases = projectIds.length ? (await pool.query("SELECT * FROM phases WHERE project_id = ANY($1) ORDER BY id", [projectIds])).rows.map(mapRow) : [];
  db.milestones = projectIds.length ? (await pool.query("SELECT * FROM milestones WHERE project_id = ANY($1) ORDER BY id", [projectIds])).rows.map(mapRow) : [];
  db.deliverables = projectIds.length ? (await pool.query("SELECT * FROM deliverables WHERE project_id = ANY($1) ORDER BY id", [projectIds])).rows.map(mapRow) : [];
  db.conformities = projectIds.length ? (await pool.query("SELECT * FROM conformities WHERE project_id = ANY($1) AND user_id = $2 ORDER BY id", [projectIds, user.id])).rows.map(mapRow) : [];
  db.risks = projectIds.length || initiativeIds.length
    ? (await pool.query(`
        SELECT * FROM risks
        WHERE visibility = 'externo'
        AND (
          (entity_type = 'project' AND entity_id = ANY($1))
          OR (entity_type = 'initiative' AND entity_id = ANY($2))
        )
        ORDER BY id
      `, [projectIds, initiativeIds])).rows.map(mapRow)
    : [];
  return db;
}

function serveStatic(req, res) {
  const reqPath = decodeURIComponent(new URL(req.url, `http://${req.headers.host}`).pathname);
  const safePath = reqPath === "/" ? "/index.html" : reqPath;
  const filePath = path.normalize(path.join(PUBLIC_DIR, safePath));
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    const contentType = {
      ".html": "text/html; charset=utf-8",
      ".css": "text/css; charset=utf-8",
      ".js": "text/javascript; charset=utf-8",
      ".png": "image/png"
    }[path.extname(filePath)] || "application/octet-stream";
    res.writeHead(200, { "content-type": contentType });
    res.end(data);
  });
}

async function handleApi(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const parts = url.pathname.replace("/api/", "").split("/").filter(Boolean);

  if (req.method === "POST" && parts[0] === "login") {
    const body = await readBody(req);
    const { rows } = await pool.query("SELECT * FROM users WHERE lower(email) = lower($1)", [body.email || ""]);
    const dbUser = rows[0];
    if (!dbUser || !verifyPassword(body.password || "", dbUser.password_salt, dbUser.password_hash)) {
      sendJson(res, 401, { error: "Email o clave incorrectos" });
      return;
    }
    const token = crypto.randomBytes(32).toString("hex");
    sessions.set(token, dbUser.id);
    sendJson(res, 200, { user: mapRow({ id: dbUser.id, name: dbUser.name, email: dbUser.email, role: dbUser.role }) }, { "set-cookie": sessionCookie(token) });
    return;
  }

  const user = await getUserFromRequest(req);
  if (!user) {
    sendJson(res, 401, { error: "Necesitas iniciar sesion" });
    return;
  }

  if (req.method === "POST" && parts[0] === "logout") {
    const token = parseCookies(req).sid;
    if (token) sessions.delete(token);
    sendJson(res, 200, { ok: true }, { "set-cookie": clearSessionCookie() });
    return;
  }

  if (req.method === "GET" && parts[0] === "me") {
    sendJson(res, 200, { user });
    return;
  }

  if (req.method === "GET" && parts[0] === "bootstrap") {
    sendJson(res, 200, await bootstrap(user));
    return;
  }

  const collection = parts[0];
  if (!tableConfig[collection]) {
    sendJson(res, 404, { error: "Ruta no encontrada" });
    return;
  }

  if (req.method === "POST" && parts.length === 1) {
    const body = await readBody(req);
    if (collection === "conformities" && user.role === "external") {
      if (!(await canAccessProject(user, body.projectId))) {
        sendJson(res, 403, { error: "No tenes acceso a este proyecto" });
        return;
      }
      body.userId = user.id;
      const created = await insertRecord(collection, body);
      const newStatus = body.status === "conforme" ? "Conforme" : "Observado";
      await pool.query("UPDATE deliverables SET status = $1 WHERE id = $2", [newStatus, body.deliverableId]);
      sendJson(res, 201, created);
      return;
    } else {
      requirePmp(user);
    }
    sendJson(res, 201, await insertRecord(collection, body));
    return;
  }

  if (req.method === "PUT" && parts.length === 2) {
    requirePmp(user);
    const updated = await updateRecord(collection, parts[1], await readBody(req));
    sendJson(res, updated ? 200 : 404, updated || { error: "Registro no encontrado" });
    return;
  }

  if (req.method === "DELETE" && parts.length === 2) {
    requirePmp(user);
    const { rowCount } = await pool.query(`DELETE FROM ${tableConfig[collection].table} WHERE id = $1`, [parts[1]]);
    sendJson(res, rowCount ? 200 : 404, { ok: rowCount > 0 });
    return;
  }

  sendJson(res, 405, { error: "Metodo no soportado" });
}

const server = http.createServer(async (req, res) => {
  if (!req.url.startsWith("/api/")) return serveStatic(req, res);
  try {
    await handleApi(req, res);
  } catch (error) {
    sendJson(res, error.status || 400, { error: error.message });
  }
});

initDatabase()
  .then(() => {
    server.listen(PORT, () => {
      console.log(`PMP Control MVP disponible en http://localhost:${PORT}`);
    });
  })
  .catch((error) => {
    console.error("No se pudo inicializar PostgreSQL:", error.message);
    process.exit(1);
  });

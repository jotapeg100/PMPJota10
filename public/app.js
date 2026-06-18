const state = {
  db: null,
  user: null,
  view: "dashboard",
  modal: null,
  authError: ""
};

const labels = {
  green: "Verde",
  amber: "Ambar",
  red: "Rojo",
  proyecto: "Proyecto",
  subproyecto: "Subproyecto",
  feature: "Feature"
};

const app = document.querySelector("#app");

async function api(path, options = {}) {
  const response = await fetch(path, {
    credentials: "same-origin",
    headers: { "content-type": "application/json" },
    ...options,
    body: options.body ? JSON.stringify(options.body) : undefined
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || "Error de API");
  return data;
}

async function load() {
  try {
    const me = await api("/api/me");
    state.user = me.user;
    state.db = await api("/api/bootstrap");
    if (state.user.role === "external" && !["external", "deliverables", "risks"].includes(state.view)) {
      state.view = "external";
    }
    render();
  } catch {
    state.user = null;
    state.db = null;
    renderLogin();
  }
}

function isPmp() {
  return state.user?.role === "pmp";
}

function escapeHtml(value = "") {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function rag(value) {
  return `<span class="rag ${value}">&bull; ${labels[value] || value}</span>`;
}

function riskLevel(probability, impact) {
  const score = Number(probability) * Number(impact);
  if (score <= 2) return { text: "Bajo", cls: "low", score };
  if (score <= 4) return { text: "Medio", cls: "mid", score };
  if (score <= 6) return { text: "Alto", cls: "high", score };
  return { text: "Critico", cls: "high", score };
}

function visibleProjects() {
  return state.db.projects;
}

function visibleRisks() {
  return state.db.risks;
}

function initials(name) {
  return String(name || "U").split(" ").filter(Boolean).slice(0, 2).map((part) => part[0]).join("").toUpperCase();
}

function setView(view) {
  state.view = view;
  state.modal = null;
  render();
}

async function logout() {
  await api("/api/logout", { method: "POST" });
  state.user = null;
  state.db = null;
  renderLogin();
}

function renderLogin() {
  app.innerHTML = `
    <main class="login-page">
      <section class="login-panel">
        <img class="login-logo" src="/assets/logo.png" alt="Logo" />
        <h1>PMP Control</h1>
        <p class="muted">Ingresar a la plataforma de gestion de iniciativas y proyectos.</p>
        ${state.authError ? `<div class="auth-error">${escapeHtml(state.authError)}</div>` : ""}
        <form class="login-form" id="loginForm">
          <label>Email<input name="email" type="email" autocomplete="username" value="pmp@local" required></label>
          <label>Clave<input name="password" type="password" autocomplete="current-password" value="pmp123" required></label>
          <button class="primary" type="submit">Ingresar</button>
        </form>
        <div class="demo-users">
          <strong>Usuarios demo</strong>
          <span>PMP: pmp@local / pmp123</span>
          <span>Cliente: cliente@local / cliente123</span>
          <span>Gerente: gerente@local / gerente123</span>
        </div>
      </section>
    </main>
  `;
  document.querySelector("#loginForm").onsubmit = async (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.target).entries());
    try {
      state.authError = "";
      await api("/api/login", { method: "POST", body: data });
      await load();
    } catch (error) {
      state.authError = error.message;
      renderLogin();
    }
  };
}

function layout(content) {
  const nav = isPmp()
    ? [
        ["dashboard", "Panel de control"],
        ["portfolio", "Iniciativas y proyectos"],
        ["risks", "Riesgos"],
        ["deliverables", "Entregables"],
        ["admin", "ABM areas"]
      ]
    : [["external", "Vista externa"], ["deliverables", "Conformidades"], ["risks", "Riesgos visibles"]];

  return `
    <div class="app-shell">
      <header class="global-topbar">
        <div class="topbar-brand">
          <button class="icon-button" title="Menu">‹</button>
          <img src="/assets/logo.png" alt="Logo de empresa" />
          <strong>PMP Control</strong>
        </div>
        <div class="user-menu">
          <span>${escapeHtml(state.user.name)}</span>
          <span class="user-badge">${initials(state.user.name)}</span>
          <button onclick="logout()">Salir</button>
        </div>
      </header>
      <div class="layout">
        <aside class="sidebar">
          <div class="role-label">${isPmp() ? "PMP / Gestor" : "Usuario externo"}</div>
          <nav class="nav">
            ${nav.map(([view, label]) => `<button class="${state.view === view ? "active" : ""}" onclick="setView('${view}')">${label}</button>`).join("")}
          </nav>
        </aside>
        <main class="main">${content}</main>
        ${state.modal || ""}
      </div>
    </div>
  `;
}

function dashboard() {
  const projects = state.db.projects;
  const risks = state.db.risks;
  const deliverables = state.db.deliverables;
  const effortEstimated = projects.reduce((sum, p) => sum + Number(p.estimatedEffort || 0), 0);
  const effortActual = projects.reduce((sum, p) => sum + Number(p.actualEffort || 0), 0);
  const pendingConformities = deliverables.filter((d) => d.status === "Publicado para conformidad").length;
  const criticalRisks = risks.filter((r) => riskLevel(r.probability, r.impact).score >= 6 && r.status !== "Cerrado").length;

  return `
    <div class="topbar">
      <div>
        <h1>Panel de control</h1>
        <p class="muted">Vision ejecutiva de iniciativas, proyectos, RAG, riesgos y conformidades.</p>
      </div>
      <button class="primary" onclick="openProjectForm()">Nuevo proyecto</button>
    </div>
    <section class="grid cols-4">
      ${metric("Iniciativas", state.db.initiatives.length)}
      ${metric("Proyectos activos", projects.length)}
      ${metric("Riesgos altos", criticalRisks)}
      ${metric("Conformidades pendientes", pendingConformities)}
    </section>
    <section class="grid cols-2" style="margin-top:14px">
      <div class="panel">
        <h2>Estado RAG</h2>
        <table class="table" style="margin-top:12px">
          <thead><tr><th>Proyecto</th><th>Tipo</th><th>RAG</th><th>Avance</th></tr></thead>
          <tbody>${projects.map(projectRow).join("")}</tbody>
        </table>
      </div>
      <div class="panel">
        <h2>Esfuerzo</h2>
        <p class="muted">Planificado vs real registrado.</p>
        <div class="grid cols-2">
          ${metric("Estimado", `${effortEstimated} h`)}
          ${metric("Real", `${effortActual} h`)}
        </div>
        <div style="margin-top:14px">
          <div class="progress"><span style="width:${Math.min(100, Math.round((effortActual / Math.max(effortEstimated, 1)) * 100))}%"></span></div>
        </div>
      </div>
    </section>
  `;
}

function metric(label, value) {
  return `<div class="card metric"><span class="muted">${label}</span><strong>${value}</strong></div>`;
}

function projectRow(project) {
  return `
    <tr>
      <td><strong>${escapeHtml(project.name)}</strong><br><span class="muted">${escapeHtml(project.owner || "")}</span></td>
      <td><span class="tag">${labels[project.type]}</span></td>
      <td>${rag(project.rag)}</td>
      <td><div class="progress"><span style="width:${Number(project.progress || 0)}%"></span></div><span class="muted">${project.progress || 0}%</span></td>
    </tr>
  `;
}

function portfolio() {
  return `
    <div class="topbar">
      <div>
        <h1>Iniciativas y proyectos</h1>
        <p class="muted">Estructura padre-hijo: iniciativa, proyectos, subproyectos y features.</p>
      </div>
      <div class="toolbar">
        <button class="primary" onclick="openInitiativeForm()">Nueva iniciativa</button>
        <button onclick="openProjectForm()">Nuevo proyecto</button>
      </div>
    </div>
    <div class="tree">${state.db.initiatives.map((initiative) => initiativeTree(initiative)).join("")}</div>
  `;
}

function initiativeTree(initiative) {
  const projects = state.db.projects.filter((project) => project.initiativeId === initiative.id && !project.parentProjectId);
  return `
    <div class="panel">
      <div class="tree-node">
        <strong>${escapeHtml(initiative.name)}</strong> ${rag(initiative.rag)}
        <div class="muted">${escapeHtml(initiative.objective)}</div>
      </div>
      ${projects.map((project) => projectTree(project)).join("") || `<div class="empty">Sin proyectos asociados.</div>`}
    </div>
  `;
}

function projectTree(project) {
  const children = state.db.projects.filter((child) => child.parentProjectId === project.id);
  const cls = project.type === "feature" ? "feature" : "child";
  return `
    <div class="tree-node ${project.parentProjectId ? cls : ""}">
      <div style="display:flex;justify-content:space-between;gap:10px;align-items:start">
        <div>
          <strong>${escapeHtml(project.name)}</strong> ${rag(project.rag)}
          <div class="muted">${labels[project.type]} &middot; ${escapeHtml(project.status)} &middot; ${project.progress || 0}% avance</div>
        </div>
        ${isPmp() ? `<button onclick="openProjectForm('${project.id}')">Editar</button>` : ""}
      </div>
    </div>
    ${children.map((child) => projectTree(child)).join("")}
  `;
}

function risksView() {
  const risks = visibleRisks();
  return `
    <div class="topbar">
      <div>
        <h1>Gestion de riesgos</h1>
        <p class="muted">Matriz basica de probabilidad e impacto para iniciativas y proyectos.</p>
      </div>
      ${isPmp() ? `<button class="primary" onclick="openRiskForm()">Nuevo riesgo</button>` : ""}
    </div>
    <section class="grid cols-2">
      <div class="panel">
        <h2>Matriz 3 x 3</h2>
        ${riskMatrix(risks)}
      </div>
      <div class="panel">
        <h2>Riesgos abiertos</h2>
        <table class="table" style="margin-top:12px">
          <thead><tr><th>Riesgo</th><th>Nivel</th><th>Estado</th><th>Visible</th></tr></thead>
          <tbody>${risks.map(riskRow).join("")}</tbody>
        </table>
      </div>
    </section>
  `;
}

function riskMatrix(risks) {
  const cells = [];
  for (let p = 3; p >= 1; p--) {
    cells.push(`<div class="risk-head">P ${p}</div>`);
    for (let i = 1; i <= 3; i++) {
      const level = riskLevel(p, i);
      const count = risks.filter((risk) => Number(risk.probability) === p && Number(risk.impact) === i).length;
      cells.push(`<div class="risk-cell ${level.cls}"><strong>${level.text}</strong><br><span class="muted">${count} riesgo(s)</span></div>`);
    }
  }
  return `
    <div class="risk-matrix" style="margin-top:12px">
      <div></div><div class="risk-head">Impacto 1</div><div class="risk-head">Impacto 2</div><div class="risk-head">Impacto 3</div>
      ${cells.join("")}
    </div>
  `;
}

function riskRow(risk) {
  const level = riskLevel(risk.probability, risk.impact);
  return `
    <tr>
      <td><strong>${escapeHtml(risk.title)}</strong><br><span class="muted">${escapeHtml(risk.mitigation || "")}</span></td>
      <td><span class="tag">${level.text} ${level.score}</span></td>
      <td>${escapeHtml(risk.status)}</td>
      <td>${escapeHtml(risk.visibility)}</td>
    </tr>
  `;
}

function deliverablesView() {
  const deliverables = state.db.deliverables;
  return `
    <div class="topbar">
      <div>
        <h1>${isPmp() ? "Entregables" : "Conformidades"}</h1>
        <p class="muted">Publicacion, revision y conformidad formal de entregas.</p>
      </div>
      ${isPmp() ? `<button class="primary" onclick="openDeliverableForm()">Nuevo entregable</button>` : ""}
    </div>
    <table class="table">
      <thead><tr><th>Entregable</th><th>Proyecto</th><th>Estado</th><th>Accion</th></tr></thead>
      <tbody>${deliverables.map(deliverableRow).join("")}</tbody>
    </table>
  `;
}

function deliverableRow(deliverable) {
  const project = state.db.projects.find((item) => item.id === deliverable.projectId);
  const externalAction = !isPmp() && deliverable.status === "Publicado para conformidad"
    ? `<button class="primary" onclick="conform('${deliverable.id}', 'conforme')">Dar conforme</button> <button onclick="conform('${deliverable.id}', 'observado')">Observar</button>`
    : "";
  return `
    <tr>
      <td><strong>${escapeHtml(deliverable.name)}</strong><br><span class="muted">${escapeHtml(deliverable.description)}</span></td>
      <td>${escapeHtml(project?.name || "")}</td>
      <td><span class="tag">${escapeHtml(deliverable.status)}</span></td>
      <td>${externalAction || (isPmp() ? `<button onclick="openDeliverableForm('${deliverable.id}')">Editar</button>` : "-")}</td>
    </tr>
  `;
}

function externalView() {
  return `
    <div class="topbar">
      <div>
        <h1>Vista externa</h1>
        <p class="muted">Status ejecutivo, hitos publicados y conformidades pendientes.</p>
      </div>
    </div>
    <section class="grid cols-3">
      ${visibleProjects().map((project) => `
        <div class="card">
          <h2>${escapeHtml(project.name)}</h2>
          <p>${rag(project.rag)} <span class="tag">${escapeHtml(project.status)}</span></p>
          <p class="muted">${escapeHtml(project.scope)}</p>
          <div class="progress"><span style="width:${Number(project.progress || 0)}%"></span></div>
          <p class="muted">${project.progress || 0}% avance &middot; cierre previsto ${escapeHtml(project.endDate || "")}</p>
        </div>
      `).join("")}
    </section>
  `;
}

function adminView() {
  return `
    <div class="topbar">
      <div>
        <h1>ABM areas</h1>
        <p class="muted">Administracion basica de areas para clasificar iniciativas.</p>
      </div>
      <button class="primary" onclick="openAreaForm()">Nueva area</button>
    </div>
    <table class="table">
      <thead><tr><th>Area</th><th>Accion</th></tr></thead>
      <tbody>${state.db.areas.map((area) => `<tr><td>${escapeHtml(area.name)}</td><td><button onclick="openAreaForm('${area.id}')">Editar</button></td></tr>`).join("")}</tbody>
    </table>
  `;
}

function render() {
  if (!state.db || !state.user) return renderLogin();
  const views = {
    dashboard,
    portfolio,
    risks: risksView,
    deliverables: deliverablesView,
    external: externalView,
    admin: adminView
  };
  app.innerHTML = layout((views[state.view] || dashboard)());
}

function field(name, label, value = "", type = "text", options = null, full = false) {
  if (options) {
    return `<label class="${full ? "full" : ""}">${label}<select name="${name}">${options.map(([v, t]) => `<option value="${v}" ${String(value) === String(v) ? "selected" : ""}>${t}</option>`).join("")}</select></label>`;
  }
  if (type === "textarea") {
    return `<label class="${full ? "full" : ""}">${label}<textarea name="${name}">${escapeHtml(value)}</textarea></label>`;
  }
  return `<label class="${full ? "full" : ""}">${label}<input name="${name}" type="${type}" value="${escapeHtml(value)}"></label>`;
}

function openModal(title, formHtml, submitName, onSubmit) {
  state.modal = `
    <div class="modal">
      <div class="modal-body">
        <div class="topbar">
          <h2>${title}</h2>
          <button onclick="closeModal()">Cerrar</button>
        </div>
        <form class="form" id="modalForm">
          ${formHtml}
          <div class="full toolbar">
            <button class="primary" type="submit">${submitName}</button>
            <button type="button" onclick="closeModal()">Cancelar</button>
          </div>
        </form>
      </div>
    </div>
  `;
  render();
  document.querySelector("#modalForm").onsubmit = async (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.target).entries());
    await onSubmit(data);
    state.modal = null;
    await load();
  };
}

function closeModal() {
  state.modal = null;
  render();
}

function openInitiativeForm(id = null) {
  const item = state.db.initiatives.find((initiative) => initiative.id === id) || {};
  openModal("Iniciativa", `
    ${field("name", "Nombre", item.name)}
    ${field("sponsor", "Sponsor", item.sponsor)}
    ${field("areaId", "Area", item.areaId, "text", state.db.areas.map((a) => [a.id, a.name]))}
    ${field("priority", "Prioridad", item.priority, "text", [["Alta", "Alta"], ["Media", "Media"], ["Baja", "Baja"]])}
    ${field("status", "Estado", item.status)}
    ${field("rag", "RAG", item.rag || "green", "text", [["green", "Verde"], ["amber", "Ambar"], ["red", "Rojo"]])}
    ${field("objective", "Objetivo", item.objective, "textarea", null, true)}
    ${field("benefit", "Beneficio esperado", item.benefit, "textarea", null, true)}
    ${field("ragReasonInternal", "Motivo RAG interno", item.ragReasonInternal, "textarea", null, true)}
    ${field("ragReasonExternal", "Motivo RAG externo", item.ragReasonExternal, "textarea", null, true)}
  `, "Guardar", (data) => id ? api(`/api/initiatives/${id}`, { method: "PUT", body: data }) : api("/api/initiatives", { method: "POST", body: data }));
}

function openProjectForm(id = null) {
  const item = state.db.projects.find((project) => project.id === id) || {};
  const parentOptions = [["", "Sin padre"], ...state.db.projects.filter((p) => p.id !== id).map((p) => [p.id, p.name])];
  openModal("Proyecto / subproyecto / feature", `
    ${field("name", "Nombre", item.name)}
    ${field("type", "Tipo", item.type || "proyecto", "text", [["proyecto", "Proyecto"], ["subproyecto", "Subproyecto"], ["feature", "Feature"]])}
    ${field("initiativeId", "Iniciativa", item.initiativeId, "text", state.db.initiatives.map((i) => [i.id, i.name]))}
    ${field("parentProjectId", "Proyecto padre", item.parentProjectId || "", "text", parentOptions)}
    ${field("owner", "Responsable", item.owner)}
    ${field("status", "Estado", item.status || "En definicion")}
    ${field("rag", "RAG", item.rag || "green", "text", [["green", "Verde"], ["amber", "Ambar"], ["red", "Rojo"]])}
    ${field("progress", "Avance %", item.progress || 0, "number")}
    ${field("startDate", "Inicio", item.startDate, "date")}
    ${field("endDate", "Fin previsto", item.endDate, "date")}
    ${field("estimatedEffort", "Esfuerzo estimado", item.estimatedEffort || 0, "number")}
    ${field("actualEffort", "Esfuerzo real", item.actualEffort || 0, "number")}
    ${field("visibleToExternal", "Visible externo", String(item.visibleToExternal ?? true), "text", [["true", "Si"], ["false", "No"]])}
    ${field("scope", "Alcance", item.scope, "textarea", null, true)}
  `, "Guardar", (data) => {
    data.parentProjectId = data.parentProjectId || null;
    data.visibleToExternal = data.visibleToExternal === "true";
    data.progress = Number(data.progress || 0);
    data.estimatedEffort = Number(data.estimatedEffort || 0);
    data.actualEffort = Number(data.actualEffort || 0);
    return id ? api(`/api/projects/${id}`, { method: "PUT", body: data }) : api("/api/projects", { method: "POST", body: data });
  });
}

function openRiskForm() {
  const targets = [
    ...state.db.initiatives.map((i) => [`initiative:${i.id}`, `Iniciativa - ${i.name}`]),
    ...state.db.projects.map((p) => [`project:${p.id}`, `${labels[p.type]} - ${p.name}`])
  ];
  openModal("Riesgo", `
    ${field("target", "Asociado a", "", "text", targets)}
    ${field("title", "Titulo")}
    ${field("probability", "Probabilidad", 2, "text", [[1, "Baja"], [2, "Media"], [3, "Alta"]])}
    ${field("impact", "Impacto", 2, "text", [[1, "Bajo"], [2, "Medio"], [3, "Alto"]])}
    ${field("strategy", "Estrategia", "Mitigar", "text", [["Aceptar", "Aceptar"], ["Mitigar", "Mitigar"], ["Transferir", "Transferir"], ["Evitar", "Evitar"], ["Escalar", "Escalar"]])}
    ${field("visibility", "Visibilidad", "interno", "text", [["interno", "Interno"], ["externo", "Externo"]])}
    ${field("owner", "Responsable")}
    ${field("dueDate", "Fecha objetivo", today(), "date")}
    ${field("status", "Estado", "Identificado")}
    ${field("description", "Descripcion", "", "textarea", null, true)}
    ${field("mitigation", "Plan de mitigacion", "", "textarea", null, true)}
  `, "Guardar", (data) => {
    const [entityType, entityId] = data.target.split(":");
    delete data.target;
    return api("/api/risks", { method: "POST", body: { ...data, entityType, entityId, probability: Number(data.probability), impact: Number(data.impact) } });
  });
}

function openDeliverableForm(id = null) {
  const item = state.db.deliverables.find((deliverable) => deliverable.id === id) || {};
  openModal("Entregable", `
    ${field("name", "Nombre", item.name)}
    ${field("projectId", "Proyecto", item.projectId, "text", state.db.projects.map((p) => [p.id, p.name]))}
    ${field("status", "Estado", item.status || "Borrador", "text", [["Borrador", "Borrador"], ["Publicado para conformidad", "Publicado para conformidad"], ["Conforme", "Conforme"], ["Observado", "Observado"], ["Rechazado", "Rechazado"], ["Cerrado", "Cerrado"]])}
    ${field("publishedAt", "Fecha publicacion", item.publishedAt || today(), "date")}
    ${field("description", "Descripcion", item.description, "textarea", null, true)}
    ${field("evidenceUrl", "URL evidencia", item.evidenceUrl, "text", null, true)}
  `, "Guardar", (data) => id ? api(`/api/deliverables/${id}`, { method: "PUT", body: data }) : api("/api/deliverables", { method: "POST", body: data }));
}

function openAreaForm(id = null) {
  const item = state.db.areas.find((area) => area.id === id) || {};
  openModal("Area", field("name", "Nombre", item.name, "text", null, true), "Guardar", (data) => id ? api(`/api/areas/${id}`, { method: "PUT", body: data }) : api("/api/areas", { method: "POST", body: data }));
}

async function conform(deliverableId, status) {
  const deliverable = state.db.deliverables.find((item) => item.id === deliverableId);
  await api("/api/conformities", {
    method: "POST",
    body: {
      deliverableId,
      projectId: deliverable.projectId,
      status,
      comment: status === "conforme" ? "Conforme registrado desde vista externa." : "Observado desde vista externa.",
      requestedAt: deliverable.publishedAt || today(),
      respondedAt: today()
    }
  });
  await load();
}

window.setView = setView;
window.logout = logout;
window.openInitiativeForm = openInitiativeForm;
window.openProjectForm = openProjectForm;
window.openRiskForm = openRiskForm;
window.openDeliverableForm = openDeliverableForm;
window.openAreaForm = openAreaForm;
window.closeModal = closeModal;
window.conform = conform;

load();

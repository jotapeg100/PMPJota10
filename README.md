# PMP Control MVP

MVP de una plataforma de gestion de iniciativas y proyectos orientada a control PMP.

## Incluye

- Login real con usuarios, password hasheada y sesion por cookie.
- Permisos por rol: PMP/Gestor y Usuario externo.
- Persistencia en PostgreSQL.
- Panel de control ejecutivo.
- Iniciativas como padres de multiples proyectos.
- Proyectos con subproyectos o features debajo.
- RAG para iniciativas y proyectos.
- Gestion de riesgos con matriz probabilidad x impacto 3x3.
- Entregables y conformidad de entrega para usuarios externos.
- ABM simple de areas.
- Top nav bar con logo institucional y badge de usuario.

## Requisitos

- Node.js 20 o superior.
- PostgreSQL local o remoto.

## Instalar dependencias

```powershell
npm.cmd install --cache .\.npm-cache
```

## Configurar PostgreSQL

Crear una base local, por ejemplo:

```sql
CREATE DATABASE pmp_control;
```

Luego definir la variable de conexion en PowerShell:

```powershell
$env:DATABASE_URL="postgres://postgres:postgres@localhost:5432/pmp_control"
```

Si usas una base administrada que requiere SSL:

```powershell
$env:PGSSL="true"
```

## Ejecutar localmente

```powershell
node server.js
```

Luego abrir:

```text
http://localhost:3000
```

La primera vez que arranca, la app crea las tablas y carga datos demo.

## Usuarios demo

```text
PMP/Gestor:      pmp@local / pmp123
Cliente externo: cliente@local / cliente123
Gerente externo: gerente@local / gerente123
```

## Estructura

```text
server.js               Backend HTTP, API, auth, permisos y PostgreSQL
public/index.html       Entrada del frontend
public/app.js           Interfaz y comportamiento
public/styles.css       Estilos visuales
public/assets/logo.png  Logo de la barra superior
.env.example            Variables de entorno sugeridas
```

## API base

```text
POST   /api/login
POST   /api/logout
GET    /api/me
GET    /api/bootstrap
POST   /api/initiatives
PUT    /api/initiatives/:id
POST   /api/projects
PUT    /api/projects/:id
POST   /api/risks
POST   /api/deliverables
PUT    /api/deliverables/:id
POST   /api/conformities
POST   /api/areas
PUT    /api/areas/:id
```

## Permisos

El rol PMP/Gestor puede crear y editar iniciativas, proyectos, riesgos, entregables y areas.

El Usuario externo solo ve proyectos asignados y visibles, riesgos externos, entregables publicados y puede registrar conformidades.

## Despliegue recomendado

Para DigitalOcean App Platform:

1. Crear una base PostgreSQL administrada.
2. Subir este proyecto a GitHub.
3. Crear una App Platform Node.js.
4. Configurar `DATABASE_URL`, `PORT` y `PGSSL=true` si corresponde.
5. Usar `node server.js` como comando de inicio.
6. Asociar el dominio propio desde la app.

Para Vercel:

1. Separar el frontend del backend o adaptar el backend a funciones serverless.
2. Usar PostgreSQL externo, por ejemplo Neon, Supabase o DigitalOcean Managed Database.
3. Configurar `DATABASE_URL` en las variables de entorno del proyecto.

## Notas de MVP

Las sesiones viven en memoria del servidor. Para produccion conviene moverlas a PostgreSQL o Redis antes de usar multiples instancias.

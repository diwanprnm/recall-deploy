# ──────────────────────────────────────────────────────────────────
# Recall — Your Second Brain for Social Media
# ──────────────────────────────────────────────────────────────────

A knowledge manager that saves content from Twitter/X, Reddit, YouTube, Instagram, and LinkedIn. Auto-classifies, summarises, and tags content with AI (GPT-4o-mini via 9router) and enables semantic (vector) search via Supabase.

This is a **monorepo** with two services:

| Service     | Source                  | Stack                                                  |
| ----------- | ----------------------- | ------------------------------------------------------ |
| `recall-web`    | `./recall-web`      | Next.js 16 (App Router) + Turbopack, Tailwind         |
| `recall-api`    | `./recall-api`      | FastAPI + instructor + Supabase + Pydantic v2          |

---

## 🚀 Quick Start (local development)

Prerequisites:
- Docker + Docker Compose v2
- A Supabase project (free tier is fine)
- A 9router API key (or any OpenAI-compatible endpoint)

```bash
git clone https://github.com/diwanprnm/recall-deploy.git
cd recall-deploy

# 1. Copy both sub-repos into this folder
#    (they live in separate repos for surgical CI/CD)
git clone https://github.com/diwanprnm/recall-web.git  ./recall-web
git clone https://github.com/diwanprnm/recall-api.git  ./recall-api

# 2. Spin it up
./setup.sh
```

The setup script will:
- Copy `.env.example → .env` **once** and ask you to fill in your Supabase keys.
- Auto-create `recall-api/.env` and `recall-web/.env.local` from the root `.env`.
- Build and start all containers.
- Wait for the backend `/health` endpoint to return 200.
- Print the URLs.

### Useful commands

```text
./setup.sh          # bring the stack up (interactive on first run)
./setup.sh down     # stop containers, keep volumes
./setup.sh reset    # nuke node_modules + env files and start clean

docker compose logs -f              # tail all logs
docker compose logs -f backend      # tail only backend
docker compose logs -f frontend     # tail only frontend
```

After it's up:
- **App**: http://localhost:3000
- **API**: http://localhost:8000
- **API docs** (dev only): http://localhost:8000/docs

---

## 📦 Architecture

```
┌─────────────────────────────────────┐
│   Browser (PWA)                     │  ← recall-theonezone.my.id
└────────────────┬────────────────────┘
                 │
        ┌────────▼──────────┐
        │   nginx / Caddy   │  (SSL termination, host-level reverse proxy)
        └────────┬──────────┘
                 │
       ┌─────────┴─────────────┐
       │                       │
       ▼                       ▼
┌───────────────┐       ┌────────────────┐
│  recall-web   │       │   recall-api   │
│   :3000       │       │     :8000      │
│  Next.js 16   │       │   FastAPI      │
│  Turbopack    │       │  + instructor  │
└───────────────┘       └───────┬────────┘
                                │
                                ▼
                  ┌──────────────────────────┐
                  │ Supabase (Postgres +     │
                  │   pgvector + Storage +   │
                  │     Realtime + Auth)     │
                  └──────────────────────────┘

                  + 9router (OpenAI-compatible
                    LLM API for embeddings
                    & chat completions)
```

The frontend talks to Supabase directly for auth and authoritative reads, and goes through the FastAPI backend for AI features and cross-table writes.

---

## 🛠 Production deployment

This repo is configured for **single-host Docker deployment behind a reverse proxy** (nginx or Caddy on the host).

See [DEPLOY.md](./DEPLOY.md) for the full production checklist.

Key points:
- `ENVIRONMENT=production` in `.env`
- Run migrations against Supabase: `cd recall-api && alembic upgrade head`
- Run `docker compose up -d`
- Set up Cloudflare in front of the host for SSL termination.

---

## 🔧 Per-service development

Each sub-repo is independent and has its own AGENTS.md / CLAUDE.md for agent tooling.

```bash
# Work on backend alone
cd recall-api
uv venv && uv sync
uvicorn app.main:app --reload --port 8000

# Work on frontend alone
cd recall-web
npm install
npm run dev      # http://localhost:3000
```

When running services separately, point the frontend at your locally-running API:

```bash
echo 'NEXT_PUBLIC_API_URL=http://localhost:8000' > recall-web/.env.local
```

---

## 📚 Tech stack

- **Frontend**: Next.js 16 (App Router), Turbopack, Tailwind, shadcn/ui, Workbox PWA
- **Backend**: FastAPI, Pydantic v2, instructor (structured outputs), Supabase Python SDK
- **DB**: Supabase Postgres + pgvector for embeddings
- **AI**: 9router (OpenAI-compatible) — `gpt-4o-mini` + `text-embedding-3-small`
- **Auth**: Supabase Auth (JWT bearer tokens)
- **Infra**: Docker Compose, nginx/Caddy for reverse proxy

---

## 📄 License

MIT

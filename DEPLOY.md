# ────────────────────────────────────────────
# Recall — Production deployment checklist
# ────────────────────────────────────────────

This document covers the **single-host Docker deployment**. The setup assumes:

- A VPS / bare-metal host running Docker
- Cloudflare in front (terminates SSL, forwards 80/443 to host)
- Public DNS records for `recall.example.com` → VPS IP, `api.recall.example.com` → VPS IP
- Or use a wildcard `*.recall.example.com`

## 1. DNS

| Type | Name                | Value             |
| ---- | ------------------- | ----------------- |
| A    | `recall`            | `<VPS-IP>`        |
| A    | `api.recall`        | `<VPS-IP>`        |

Both records can be **proxied** through Cloudflare (orange cloud).

## 2. Clone and copy

```bash
git clone https://github.com/diwanprnm/recall-deploy.git /opt/recall
cd /opt/recall
git clone https://github.com/diwanprnm/recall-web.git ./recall-web
git clone https://github.com/diwanprnm/recall-api.git ./recall-api
```

## 3. Configure env

```bash
cp .env.example .env
nano .env   # fill in everything
```

For **production**, make sure to set:

```env
ENVIRONMENT=production
DEBUG=false
ALLOWED_ORIGINS=https://recall.example.com,https://api.recall.example.com
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<from supabase dashboard>
OPENAI_API_KEY=<9router key>
```

## 4. Run migrations

```bash
cd recall-api
uv venv && uv sync
source .venv/bin/activate
alembic upgrade head
cd ..
```

Or run the migrations directly against Supabase via the Supabase dashboard SQL editor.

## 5. Start the stack

```bash
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml logs -f
```

## 6. Reverse proxy (host-level)

We use the **host's own nginx** for SSL termination when Cloudflare is forwarding plain HTTP. Cloudflare re-encrypts between edge and origin if configured; with the "Full" SSL mode Cloudflare terminates at origin too.

The easiest path: just rely on Cloudflare's SSL and let docker bind to `127.0.0.1` like the `docker-compose.yml` in this repo:

```yaml
frontend:
  ports: ["127.0.0.1:3001:3000"]
backend:
  ports: ["127.0.0.1:8001:8000"]
```

Then the host nginx serves as a reverse proxy with CORS handling.

See `nginx/nginx.conf` for the working config.

## 7. Verify

```bash
curl -fsS https://recall.example.com/manifest.webmanifest | jq .   # PWA manifest
curl -fsS -I -H "Origin: https://recall.example.com" \
  -X OPTIONS https://api.recall.example.com/api/items | head -20   # CORS preflight
```

You should see:

- 200 on the manifest with `"start_url": "/dashboard"` and `"scope": "/dashboard"` (aligned)
- 204 on CORS preflight with `access-control-allow-origin: https://recall.example.com`

---

## 8. Backups

- Rely on **Supabase automatic backups** for the DB (enabled in paid plan, or via `pg_dump` cron).
- Back up the env and env.example files (excluding secrets) via Git.
- No user uploads stored locally — everything is in Supabase Storage or content URLs.

---

## Troubleshooting

| Symptom                                                   | Cause                                                          | Fix                                                                                       |
| --------------------------------------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `CORS policy: No 'Access-Control-Allow-Origin' header`    | nginx reverses to wrong port or doesn't set CORS               | Confirm `proxy_pass` points to host port that maps to the container (8001 in compose).    |
| `Manifest: property 'scope' ignored`                      | `start_url` outside `scope`                                    | Make them equal (both `/` or both `/dashboard`).                                         |
| `Failed to load resource: 404` on manifest.webmanifest    | `layout.tsx` references `/api/manifest.webmanifest`            | App Router generates it at `/manifest.webmanifest`. Change `manifest:` reference.         |
| `Cannot connect to backend`                               | Container name vs host port mismatch                           | Use `127.0.0.1:<host-port>` (compose's external mapping), not the in-network name.       |

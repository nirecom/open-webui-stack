# Open WebUI Stack

Docker Compose setup for [Open WebUI](https://github.com/open-webui/open-webui) with SearXNG, Cloudflare Tunnel, and Watchtower.

LLM inference runs on a separate host via [llama.cpp](https://github.com/ggml-org/llama.cpp) (llama-server), either directly or through [LiteLLM](https://github.com/BerriAI/litellm) proxy.

## Architecture

```
Browser ──→ Open WebUI (:3000) ──→ LiteLLM Proxy ──→ llama-server (HTTPS)
                │                       │
                │                       └──→ Cloud LLM APIs (fallback)
                │
                ├── SearXNG (:8888) ── Google / Wikipedia
                │
Cloudflare ──→ cloudflared ──→ Open WebUI

Watchtower ──→ Auto-updates open-webui container
```

## Quick Start

```bash
git clone <this-repo> && cd open-webui-stack
cp .env.example .env
vi .env  # Fill in all values
docker compose up -d
```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `OPENAI_API_BASE_URLS` | LLM backend endpoint (see below) | `http://litellm-proxy:4000/v1` |
| `OPENAI_API_KEYS` | API key for the backend | LiteLLM master key or `dummy` |
| `OPEN_WEBUI_DATA_DIR` | Absolute path to Open WebUI data directory | `/share/data/open-webui` |
| `CA_CERT_PATH` | CA certificate for self-signed certs (mkcert etc.) | `/share/certs/rootCA.pem` |
| `SEARXNG_SECRET` | SearXNG secret key | Generate with `openssl rand -hex 32` |
| `CLOUDFLARE_TUNNEL_TOKEN` | Cloudflare Tunnel token | Obtain from Dashboard |
| `OPEN_WEBUI_PORT` | Open WebUI port (optional, default: 3000) | `3000` |
| `SEARXNG_PORT` | SearXNG port (optional, default: 8888) | `8888` |

### Connecting to LiteLLM (recommended)

If [litellm-stack](https://github.com/nirecom/litellm-stack) runs on the **same Docker host**, Open WebUI can reach it by Docker container name. Both stacks share the `shared-llm-net` Docker network, which is owned by litellm-stack. Start litellm-stack first (or run `docker network create shared-llm-net` manually).

```env
OPENAI_API_BASE_URLS=http://litellm-proxy:4000/v1
OPENAI_API_KEYS=<your-litellm-master-key>
```

> `litellm-proxy` is the container name defined in litellm-stack's `docker-compose.yml`. This works because both stacks join a shared Docker network, enabling cross-stack container name resolution.

### Connecting directly to llama-server

If not using LiteLLM, point directly to the llama-server host:

```env
OPENAI_API_BASE_URLS=https://<your-llm-server>/v1
OPENAI_API_KEYS=dummy
```

## SearXNG First Run

If `uwsgi.ini` generation fails on the first run:

1. Temporarily comment out `cap_drop: ALL` in `docker-compose.yml` under the searxng service
2. Run `docker compose up -d searxng`, wait 10 seconds, then `docker compose down`
3. Restore `cap_drop: ALL` and run `docker compose up -d`

## Daily Operations

```bash
docker compose ps                                # Check status
docker compose logs -f [service]                 # Follow logs
docker compose restart [service]                 # Restart a service
docker compose pull && docker compose up -d      # Update all images
```

Watchtower automatically updates the `open-webui` container every 5 minutes. Other containers require manual `docker compose pull`.

## Open WebUI Post-Setup

Some settings cannot be configured via environment variables and must be set through Admin Panel:

- **Settings → Web Search**: Enable and set engine to `searxng`
- **SearXNG Query URL**: `http://searxng:8080/search?q=<query>`
- Recommended: Enable **Bypass Web Loader** and **Bypass Embedding and Retrieval** for faster search

These settings are persisted in the database (webui.db) and survive container recreation.

## ⚠ Caution

- **Never** run `docker compose down -v` unless you intend to delete all data volumes
- `.env` contains secrets — it is excluded from Git via `.gitignore`

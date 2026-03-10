# CLAUDE.md

## Project Overview

Docker Compose deployment stack for **Open WebUI** (LLM web frontend) with supporting services: LiteLLM Proxy (model routing/fallback), SearXNG (meta-search), Cloudflare Tunnel (external access), and Watchtower (auto-updates). There is no application source code — this repo is purely infrastructure configuration.

LLM inference runs on a separate host via llama-server (llama.cpp), either directly or through the LiteLLM proxy included in this stack (`litellm/config.yaml`).

## Architecture

```
Browser → Open WebUI (:3000) → LiteLLM Proxy → llama-server (HTTPS)
               │                     └→ Cloud LLM APIs (fallback)
               ├── SearXNG (:8888) → Google / Wikipedia
Cloudflare → cloudflared → Open WebUI
Watchtower → auto-updates open-webui only (every 5 min)
```

All services communicate over the Compose default bridge network using Docker DNS (container names as hostnames).

## Services (docker-compose.yml)

| Service | Container | Ports | Key Detail |
|---------|-----------|-------|------------|
| open-webui | `open-webui` | `${OPEN_WEBUI_PORT:-3000}:8080` | Runs `update-ca-certificates` before start for self-signed cert support |
| litellm-proxy | `litellm-proxy` | `${LITELLM_PORT:-4000}:4000` | LLM gateway with model routing, fallback, load balancing; config in `./litellm/` |
| searxng | `searxng` | `${SEARXNG_PORT:-8888}:8080` | Capabilities dropped (minimal cap_add); config in `./searxng/` |
| cloudflared | `cloudflared` | none | Tunnel token from env |
| watchtower | `watchtower` | none | Monitors only `open-webui`, not other containers |

## Configuration

- **All secrets and host-specific paths** live in `.env` (gitignored). Template: `.env.example`.
- **LiteLLM config**: `litellm/config.yaml` — model routing uses `os.environ/` references; no manual editing needed.
- **SearXNG config**: `searxng/settings.yml` — engines limited to Google + Wikipedia, JSON output enabled (required for Open WebUI), default language `ja-JP`.
- **Open WebUI data**: persisted at `${OPEN_WEBUI_DATA_DIR}` (mapped to `/app/backend/data` inside container). Settings stored in `webui.db` survive container recreation.
- **CA certificate**: `${CA_CERT_PATH}` mounted read-only for mkcert / self-signed cert trust.

## SearXNG First-Run Workaround

If `uwsgi.ini` fails to generate on first run: temporarily comment out `cap_drop: ALL`, start the container once, then restore it. Details in README.md.

## Related Resources

- Sibling directory `../ai-specs` is configured as an additional Claude Code directory (`.claude/settings.json`) and contains architecture design documents.

## LangChain Project: Phase Workflow

This repo participates in the LangChain phased implementation.
Canonical rules: `../ai-specs/CLAUDE.md` § "LangChain Project: Phase Workflow"

Phase handoffs and completion reports are stored in `.context-private/`.

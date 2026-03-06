# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker Compose deployment stack for **Open WebUI** (LLM web frontend) with supporting services: SearXNG (meta-search), Cloudflare Tunnel (external access), and Watchtower (auto-updates). There is no application source code — this repo is purely infrastructure configuration.

LLM inference runs on a separate host via llama-server (llama.cpp), either directly or through a LiteLLM proxy defined in the sibling [litellm-stack](https://github.com/nirecom/litellm-stack) repository.

## Common Commands

```bash
# Start / stop
docker compose up -d
docker compose down              # NEVER use -v unless intentionally deleting all data

# Status and logs
docker compose ps
docker compose logs -f [service]

# Update all images
docker compose pull && docker compose up -d
```

## Architecture

```
Browser → Open WebUI (:3000) → LiteLLM Proxy → llama-server (HTTPS)
               │                     └→ Cloud LLM APIs (fallback)
               ├── SearXNG (:8888) → Google / Wikipedia
Cloudflare → cloudflared → Open WebUI
Watchtower → auto-updates open-webui only (every 5 min)
```

All services communicate over the `app-net` network (backed by the external `shared-llm-net` Docker network) using Docker DNS (container names as hostnames).

## Services (docker-compose.yml)

| Service | Container | Ports | Key Detail |
|---------|-----------|-------|------------|
| open-webui | `open-webui` | `${OPEN_WEBUI_PORT:-3000}:8080` | Runs `update-ca-certificates` before start for self-signed cert support |
| searxng | `searxng` | `${SEARXNG_PORT:-8888}:8080` | Capabilities dropped (minimal cap_add); config in `./searxng/` |
| cloudflared | `cloudflared` | none | Tunnel token from env |
| watchtower | `watchtower` | none | Monitors only `open-webui`, not other containers |

## Configuration

- **All secrets and host-specific paths** live in `.env` (gitignored). Template: `.env.example`.
- **SearXNG config**: `searxng/settings.yml` — engines limited to Google + Wikipedia, JSON output enabled (required for Open WebUI), default language `ja-JP`.
- **Open WebUI data**: persisted at `${OPEN_WEBUI_DATA_DIR}` (mapped to `/app/backend/data` inside container). Settings stored in `webui.db` survive container recreation.
- **CA certificate**: `${CA_CERT_PATH}` mounted read-only for mkcert / self-signed cert trust.

## Cross-Stack Networking

Both stacks share a Docker network named `shared-llm-net`. **litellm-stack owns this network** (defined in its `docker-compose.override.yml`); open-webui-stack references it as `external`. This means litellm-stack must be started first (or the network must be created manually via `docker network create shared-llm-net`).

## SearXNG First-Run Workaround

If `uwsgi.ini` fails to generate on first run: temporarily comment out `cap_drop: ALL`, start the container once, then restore it. Details in README.md.

## Related Resources

- Sibling directory `../ai-specs` is configured as an additional Claude Code directory (`.claude/settings.json`) and contains architecture design documents.

## LangChain Project: Phase Workflow

This repo participates in the LangChain phased implementation.
Canonical rules: `../ai-specs/CLAUDE.md` § "LangChain Project: Phase Workflow"

Phase handoffs and completion reports are stored in `.context-private/`.

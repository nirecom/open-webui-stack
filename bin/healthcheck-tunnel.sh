#!/bin/sh
# healthcheck-tunnel.sh — Detect cloudflared → open-webui connectivity failure and auto-recover
# Intended for QNAP cron (root). Checks last 5 minutes of cloudflared logs for "no route to host".

COMPOSE_DIR="/share/Container/open-webui-stack"
LOG_FILE="/share/Container/open-webui-stack/bin/healthcheck-tunnel.log"
SINCE="5m"

# Check cloudflared logs for recent connectivity errors
if docker logs --since "$SINCE" cloudflared 2>&1 | grep -q "no route to host"; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] Detected 'no route to host' — force-recreating containers" >> "$LOG_FILE"
    cd "$COMPOSE_DIR" && docker compose up -d --force-recreate >> "$LOG_FILE" 2>&1
    echo "[$TIMESTAMP] Recovery complete" >> "$LOG_FILE"
fi

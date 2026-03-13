#!/bin/sh
# Show compact Caddy access logs (method, URI, status, upstream, duration)
# Usage: ./bin/caddy-log.sh         (follow mode)
#        ./bin/caddy-log.sh --tail   (last 50 lines)

if command -v jq >/dev/null 2>&1; then
  JQ_FILTER='select(.msg == "handled request") | "\(.request.method) \(.status) \(.request.uri) dur=\(.duration)s"'
  if [ "$1" = "--tail" ]; then
    docker compose logs --tail 50 caddy 2>&1 | grep '"handled request"' | sed 's/^caddy  | //' | jq -r "$JQ_FILTER"
  else
    docker compose logs -f caddy 2>&1 | grep --line-buffered '"handled request"' | sed 's/^caddy  | //' | jq -r --unbuffered "$JQ_FILTER"
  fi
else
  # Fallback without jq: extract key fields with grep/sed
  if [ "$1" = "--tail" ]; then
    docker compose logs --tail 50 caddy 2>&1 | grep '"handled request"' | sed 's/.*"method":"\([^"]*\)".*"uri":"\([^"]*\)".*"status":\([0-9]*\).*"duration":\([0-9.]*\).*/\1 \3 \2 dur=\4s/'
  else
    docker compose logs -f caddy 2>&1 | grep --line-buffered '"handled request"' | sed 's/.*"method":"\([^"]*\)".*"uri":"\([^"]*\)".*"status":\([0-9]*\).*"duration":\([0-9.]*\).*/\1 \3 \2 dur=\4s/'
  fi
fi

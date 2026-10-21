#!/usr/bin/env bash
set -euo pipefail

# Sets up / refreshes .env.local for the current worktree.
# Injects environment variables from running services (Supabase, etc.).
# Usage: dev worktree env

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/dev.helpers.sh"

WORKTREE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$WORKTREE_DIR/.env.local"

# Classify a Supabase-related env var name by suffix, echoing the matching
# `supabase status --output json` field (or empty if unmapped).
# Order matters: longer/more-specific suffixes first.
classify_supabase_var() {
  local name="$1"
  case "$name" in
    DATABASE_URL|*_DATABASE_URL)           echo "DB_URL" ;;
    JWT_SECRET)                            echo "JWT_SECRET" ;;
    *SUPABASE*_SERVICE_ROLE_KEY)           echo "SERVICE_ROLE_KEY" ;;
    *SUPABASE*_PUBLISHABLE_KEY)            echo "PUBLISHABLE_KEY" ;;
    *SUPABASE*_SECRET_KEY)                 echo "SECRET_KEY" ;;
    *SUPABASE*_ANON_KEY)                   echo "ANON_KEY" ;;
    *SUPABASE*_URL)                        echo "API_URL" ;;
    *)                                     echo "" ;;
  esac
}

# Discover Supabase-related env var names by scanning source code and the
# existing .env.local. Outputs one unique name per line.
discover_supabase_vars() {
  local worktree="$1" env_file="$2"
  # `|| true` on each branch keeps pipefail from aborting the function
  # when a scanned directory is missing or a grep finds zero matches.
  {
    for dir in "$worktree/src" "$worktree/app" "$worktree/supabase" "$worktree/infra"; do
      if [ -d "$dir" ]; then
        grep -rEoh 'process\.env\.[A-Z_]+' "$dir" 2>/dev/null \
          | sed 's/^process\.env\.//' || true
      fi
    done
    if [ -f "$env_file" ]; then
      grep -oE '^[A-Z_][A-Z0-9_]*=' "$env_file" | tr -d '=' || true
    fi
  } \
    | awk '/SUPABASE/ || $0 == "DATABASE_URL" || $0 == "JWT_SECRET"' \
    | sort -u
}

touch "$ENV_FILE"

# Choose how to rewrite the host portion of service URLs before writing them
# into .env.local. `supabase status` returns 127.0.0.1-based URLs; those are
# host-reachable from the shell but not from inside a Docker container.
#
# Docker worktrees use `host.docker.internal` — install.sh ensures it maps
# to 127.0.0.1 in /etc/hosts so the same URL also resolves from the host
# browser. Non-Docker worktrees keep the friendlier `localhost` form.
if [ -f "$WORKTREE_DIR/Dockerfile" ]; then
  URL_HOST="host.docker.internal"
else
  URL_HOST="localhost"
fi

# --- Supabase ---
# SUPABASE_STATUS_DIR overrides where `supabase status` runs.
# Needed when the current worktree's config.toml has different ports
# than the shared running Supabase instance.
STATUS_DIR="${SUPABASE_STATUS_DIR:-$WORKTREE_DIR}"
if [ -f "$WORKTREE_DIR/supabase/config.toml" ] && command -v supabase &>/dev/null; then
  if (cd "$STATUS_DIR" && supabase status --output json) >/dev/null 2>&1; then
    echo "Injecting Supabase env vars..."
    STATUS_JSON="$(cd "$STATUS_DIR" && supabase status --output json 2>/dev/null | sed -n '/^{/,/^}/p')"

    # Discover every Supabase-related env var referenced by the app or already
    # declared in .env.local, classify each by name, and populate from the
    # running local Supabase. Every worktree on this machine connects to the
    # same shared local instance, so we always overwrite — remote values are
    # never desired in local dev. URLs have 127.0.0.1 rewritten to the host
    # chosen above so they resolve from whichever context reads them.
    while IFS= read -r var_name; do
      [ -z "$var_name" ] && continue
      status_key="$(classify_supabase_var "$var_name")"
      if [ -z "$status_key" ]; then
        echo "  - skipping $var_name (no mapping)"
        continue
      fi

      raw="$(echo "$STATUS_JSON" | jq -r ".${status_key} // empty")"
      if [ -z "$raw" ]; then
        echo "  - skipping $var_name (supabase status missing .${status_key})"
        continue
      fi

      case "$status_key" in
        *_URL) value="$(echo "$raw" | sed "s/127\\.0\\.0\\.1/$URL_HOST/")" ;;
        *)     value="$raw" ;;
      esac

      upsert_env "$ENV_FILE" "$var_name" "$value"
      echo "  + $var_name <- .${status_key}"
    done < <(discover_supabase_vars "$WORKTREE_DIR" "$ENV_FILE")

    echo "Updated $ENV_FILE with Supabase connection details (host: $URL_HOST)."
  else
    echo "Warning: Supabase project detected but not running. Skipping env injection." >&2
    echo "  To start: dev supabase up" >&2
  fi
else
  echo "No Supabase project detected, skipping."
fi

echo "Done: $ENV_FILE"

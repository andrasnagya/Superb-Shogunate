#!/usr/bin/env bash
# ntfy_auth.sh — ntfy authentication helper library
# FR-066: ntfy authentication support
#
# Exported functions:
#   ntfy_get_auth_args [auth_env_file]  → outputs curl authentication flags
#   ntfy_validate_topic [topic]         → 0=OK, 1=weak topic name
#
# Authentication methods:
#   - token: Bearer token (for self-hosted ntfy)
#   - basic: username + password (for self-hosted ntfy)
#   - none: no authentication (public ntfy.sh, backward compatible)
#
# Config file: config/ntfy_auth.env (not tracked by git)

# --- ntfy_get_auth_args ---
# Returns curl authentication arguments to stdout
# Args: [auth_env_file] — path to auth config file (defaults to config/ntfy_auth.env)
# Output: curl argument string (e.g.: "-H" "Authorization: Bearer tk_xxx")
#         Empty string if no auth configured (backward compatible)
ntfy_get_auth_args() {
    local auth_file="${1:-}"

    # If auth_file is not specified, resolve via relative path from script location
    if [ -z "$auth_file" ]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || true
        auth_file="${script_dir}/config/ntfy_auth.env"
    fi

    # Load environment variables (only if file exists)
    if [ -f "$auth_file" ]; then
        # shellcheck disable=SC1090
        source "$auth_file"
    fi

    # Bearer token authentication (preferred)
    if [ -n "${NTFY_TOKEN:-}" ]; then
        printf '%s\n' "-H" "Authorization: Bearer ${NTFY_TOKEN}"
        return 0
    fi

    # Basic authentication (fallback)
    if [ -n "${NTFY_USER:-}" ] && [ -n "${NTFY_PASS:-}" ]; then
        printf '%s\n' "-u" "${NTFY_USER}:${NTFY_PASS}"
        return 0
    fi

    # No authentication (backward compatible: used for public ntfy.sh)
    return 0
}

# --- ntfy_validate_topic ---
# Validates the security strength of a topic name
# Args: topic — topic name
# Returns: 0=OK (sufficient length + randomness), 1=weak (too short or guessable)
# Stderr: warning messages
ntfy_validate_topic() {
    local topic="${1:-}"

    # Empty check
    if [ -z "$topic" ]; then
        echo "ERROR: ntfy topic is empty" >&2
        return 1
    fi

    # Length check (less than 8 chars is dangerous)
    if [ "${#topic}" -lt 8 ]; then
        echo "WARNING: ntfy topic '$topic' is too short (${#topic} chars). Recommend 12+ chars for security." >&2
        return 1
    fi

    # Check for commonly used weak topic names
    local weak_topics="test mytopic notifications alerts messages my-topic default ntfy"
    local lower_topic
    lower_topic=$(echo "$topic" | tr '[:upper:]' '[:lower:]')
    for weak in $weak_topics; do
        if [ "$lower_topic" = "$weak" ]; then
            echo "WARNING: ntfy topic '$topic' is a commonly used name. Use a random string." >&2
            return 1
        fi
    done

    return 0
}

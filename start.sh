#!/bin/bash
# Pi Web on Railway: prepare the /data volume, set up the LLM provider from
# Railway variables, then run Pi Web's two processes (session daemon + web/API,
# as upstream's compose file does) and Caddy (login + /healthz on $PORT).
# Exits non-zero as soon as any of the three stops unexpectedly, so Railway's
# ON_FAILURE restart policy brings the service back.
set -euo pipefail

log() { echo "pi-web-railway: $*"; }

export PI_WEB_USERNAME="${PI_WEB_USERNAME:-admin}"
if [ -z "${PI_WEB_PASSWORD:-}" ] || [ "${#PI_WEB_PASSWORD}" -lt 12 ]; then
	echo "pi-web-railway: PI_WEB_PASSWORD must be set (12+ characters). Refusing to start an open coding agent with a shell." >&2
	exit 1
fi
export PORT="${PORT:-8080}"
if [ "$PORT" = "8504" ]; then
	echo "pi-web-railway: PORT 8504 is used internally by Pi Web; use another port (default 8080)." >&2
	exit 1
fi

run_as() { setpriv --reuid=pi-web --regid="$(id -g pi-web)" --init-groups -- "$@"; }

# --- Persistent layout: everything lives on the /data volume -------------------
# HOME, XDG config, Pi Web state, the Pi agent profile (providers, sessions) and
# the default workspace folder. Fix ownership only where it is wrong, so a
# large workspace isn't walked on every start.
for d in /data /data/home /data/config /data/pi-web /data/pi-agent /data/workspace; do
	mkdir -p "$d"
	if [ "$(stat -c %U "$d")" != "pi-web" ]; then chown -R pi-web: "$d"; fi
done
# A crashed daemon can leave its socket behind; Pi Web recovers stale owner
# markers itself, but a stale socket file blocks the bind.
rm -f -- "$PI_WEB_SESSIOND_SOCKET" 2>/dev/null || true

# --- Sizes from the service's memory limit -------------------------------------
limit_mb=0
if [ -r /sys/fs/cgroup/memory.max ]; then
	raw=$(cat /sys/fs/cgroup/memory.max)
	[ "$raw" != "max" ] && limit_mb=$((raw / 1048576))
fi
web_heap=""; sessiond_heap=""
if [ "$limit_mb" -gt 0 ] && [ "$limit_mb" -le 2048 ]; then
	web_heap=$((limit_mb / 5)); [ "$web_heap" -lt 96 ] && web_heap=96
	sessiond_heap=$((limit_mb * 2 / 5)); [ "$sessiond_heap" -lt 160 ] && sessiond_heap=160
fi
if [ -z "${PI_WEB_MAX_UPLOAD_BYTES:-}" ]; then
	up=67108864
	if [ "$limit_mb" -gt 0 ]; then
		cap=$((limit_mb * 1048576 / 8)); [ "$cap" -lt "$up" ] && up=$cap
	fi
	export PI_WEB_MAX_UPLOAD_BYTES="$up"
fi
# Railway shows the host's CPUs inside the container: keep libuv's pool small.
export UV_THREADPOOL_SIZE="${UV_THREADPOOL_SIZE:-4}"

# Behind the login every public hostname is fine (custom domains included);
# an explicit policy also clears Pi Web's "choose allowed hostnames" notice.
if [ -z "${PI_WEB_HOST_ACCESS:-}" ]; then PI_WEB_HOST_ACCESS='{"mode":"any"}'; fi
export PI_WEB_HOST_ACCESS

# --- LLM provider (OpenAI-compatible) from Railway variables -------------------
# models.json refers to $LLM_API_KEY, so the key itself never touches the disk.
# The entry is ours while its apiKey is still that reference; if you replace
# the provider (or log in to another one in the UI), this script leaves it alone.
AGENT_DIR="$PI_CODING_AGENT_DIR"
MODELS="$AGENT_DIR/models.json"
SETTINGS="$AGENT_DIR/settings.json"
PROVIDER=openai-compatible
LLM_BASE_URL="${LLM_BASE_URL:-https://api.openai.com/v1}"
LLM_MODEL="${LLM_MODEL:-gpt-5.4-mini}"
LLM_CONTEXT_WINDOW="${LLM_CONTEXT_WINDOW:-128000}"
[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
# No install telemetry from this server (PI_TELEMETRY=0 also covers child processes).
jq '.enableInstallTelemetry = false' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
if [ -n "${LLM_API_KEY:-}" ]; then
	[ -s "$MODELS" ] || echo '{}' > "$MODELS"
	if jq -e --arg p "$PROVIDER" '(.providers[$p] // null) == null or .providers[$p].apiKey == "$LLM_API_KEY"' "$MODELS" >/dev/null 2>&1; then
		model_ids=$(printf '%s' "$LLM_MODEL${LLM_EXTRA_MODELS:+,$LLM_EXTRA_MODELS}" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | jq -R . | jq -s .)
		jq --arg p "$PROVIDER" --arg url "$LLM_BASE_URL" --argjson ids "$model_ids" --argjson ctx "$LLM_CONTEXT_WINDOW" \
			'.providers = (.providers // {}) | .providers[$p] = {name: "OpenAI-compatible (Railway variables)", baseUrl: $url, api: "openai-completions", apiKey: "$LLM_API_KEY",
			  models: [$ids[] | {id: ., name: ., contextWindow: $ctx}]}' "$MODELS" > "$MODELS.tmp" && mv "$MODELS.tmp" "$MODELS"
		jq --arg p "$PROVIDER" --arg m "$LLM_MODEL" \
			'if (.defaultProvider // $p) == $p then .defaultProvider = $p | .defaultModel = $m else . end' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
		log "LLM provider '$PROVIDER' set to $LLM_BASE_URL, default model $LLM_MODEL"
	else
		log "LLM provider '$PROVIDER' was changed in the UI or by hand; leaving it unchanged"
	fi
	chmod 600 "$MODELS"
else
	log "LLM_API_KEY is empty: set it in Railway, or log in to a provider from Pi Web's settings"
fi
chown pi-web: "$SETTINGS" "$MODELS" 2>/dev/null || chown pi-web: "$SETTINGS"

PKG=/usr/local/lib/node_modules/@jmfederico/pi-web
log "Pi Web $(jq -r .version "$PKG/package.json") with Pi Coding Agent $(jq -r .version /usr/local/lib/node_modules/@earendil-works/pi-coding-agent/package.json) (memory limit ${limit_mb} MB)"

# --- Caddy (login + /healthz) --------------------------------------------------
PI_WEB_PASSWORD_HASH=$(caddy hash-password --algorithm bcrypt --bcrypt-cost 10 --plaintext "$PI_WEB_PASSWORD")
export PI_WEB_PASSWORD_HASH
unset PI_WEB_PASSWORD
mkdir -p /tmp/caddy && chown pi-web: /tmp/caddy
(cd /tmp && HOME=/tmp/caddy XDG_CONFIG_HOME=/tmp/caddy XDG_DATA_HOME=/tmp/caddy GOMEMLIMIT="${GOMEMLIMIT:-48MiB}" GOMAXPROCS="${CADDY_GOMAXPROCS:-2}" \
	exec setpriv --reuid=pi-web --regid="$(id -g pi-web)" --init-groups -- caddy run --adapter caddyfile --config /etc/pi-web-railway/Caddyfile) &
proxy=$!
unset PI_WEB_PASSWORD_HASH

# --- Pi Web: session daemon first, then the web/API server ---------------------
cd /data/workspace
run_as pi-web-service ${sessiond_heap:+--max-old-space-size=$sessiond_heap} "$PKG/dist/server/sessiond.js" &
sessiond=$!
for _ in $(seq 1 120); do
	[ -S "$PI_WEB_SESSIOND_SOCKET" ] && break
	kill -0 "$sessiond" 2>/dev/null || break
	sleep 0.5
done
if ! [ -S "$PI_WEB_SESSIOND_SOCKET" ]; then
	echo "pi-web-railway: the session daemon did not open its socket; exiting 1" >&2
	kill -TERM "$sessiond" "$proxy" 2>/dev/null || true
	exit 1
fi
run_as pi-web-service ${web_heap:+--max-old-space-size=$web_heap} "$PKG/dist/server/index.js" &
web=$!

stopping=0
term() {
	stopping=1
	kill -TERM "$web" "$sessiond" "$proxy" 2>/dev/null || true
}
trap term TERM INT

# BusyBox/bash `wait -n` races with traps; poll instead.
reason=""
while :; do
	sleep 3 &
	wait $! || true
	[ "$stopping" = 1 ] && break
	if ! kill -0 "$proxy" 2>/dev/null; then reason="Caddy stopped"; break; fi
	if ! kill -0 "$sessiond" 2>/dev/null; then reason="the Pi Web session daemon stopped"; break; fi
	if ! kill -0 "$web" 2>/dev/null; then reason="the Pi Web web/API server stopped"; break; fi
done

kill -TERM "$web" "$sessiond" "$proxy" 2>/dev/null || true
wait "$web" 2>/dev/null || true
wait "$sessiond" 2>/dev/null || true
wait "$proxy" 2>/dev/null || true
if [ "$stopping" = 1 ]; then
	exit 0
fi
echo "pi-web-railway: $reason; exiting 1 so Railway restarts the service" >&2
exit 1

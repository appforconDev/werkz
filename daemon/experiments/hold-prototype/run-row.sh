#!/bin/bash
# Run one matrix row: run-row.sh <row> <port> <holdSeconds> <allow|deny> <hookTimeoutSeconds|default> [kill-mid-hold]
# Creates a sacrificial project, installs the http PermissionRequest hook,
# spawns a real `claude -p` session that needs Bash permission, releases the
# hold after <holdSeconds>, and records everything.
set -u
ROW=$1; PORT=$2; HOLD=$3; DECISION=$4; HOOK_TIMEOUT=$5; KILL_MODE=${6:-}

BASE="$(cd "$(dirname "$0")" && pwd)"
WORK="$BASE/runs/row-$ROW"
LOG="$WORK/server.jsonl"
rm -rf "$WORK" && mkdir -p "$WORK/project/.claude"

if [ "$HOOK_TIMEOUT" = "default" ]; then TIMEOUT_JSON=""; else TIMEOUT_JSON=", \"timeout\": $HOOK_TIMEOUT"; fi
cat > "$WORK/project/.claude/settings.json" <<EOF
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "http", "url": "http://127.0.0.1:$PORT/hook"$TIMEOUT_JSON }
        ]
      }
    ]
  }
}
EOF

node "$BASE/hold-server.mjs" --port "$PORT" --log "$LOG" >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1

echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"evt\":\"claude-start\",\"row\":\"$ROW\"}" >> "$LOG"
( cd "$WORK/project" && claude -p \
    "Run exactly this bash command and nothing else: echo werkz-hold-$ROW > proof.txt" \
    --model haiku --output-format json > "$WORK/claude-out.json" 2> "$WORK/claude-err.txt"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"evt\":\"claude-exit\",\"code\":$?}" >> "$LOG" ) &
CLAUDE_PID=$!

if [ "$KILL_MODE" = "kill-mid-hold" ]; then
  sleep "$HOLD"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"evt\":\"server-killed-mid-hold\"}" >> "$LOG"
  kill -9 "$SERVER_PID" 2>/dev/null
else
  sleep "$HOLD"
  curl -s "http://127.0.0.1:$PORT/release?decision=$DECISION" >> "$WORK/release-response.json" 2>&1
  echo >> "$WORK/release-response.json"
fi

wait "$CLAUDE_PID" 2>/dev/null
kill "$SERVER_PID" 2>/dev/null

[ -f "$WORK/project/proof.txt" ] && PROOF=yes || PROOF=no
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"evt\":\"row-done\",\"row\":\"$ROW\",\"proof\":\"$PROOF\"}" >> "$LOG"
echo "ROW $ROW DONE proof=$PROOF"

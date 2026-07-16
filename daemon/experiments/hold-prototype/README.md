# Hold prototype (task 4, throwaway)
See docs/experiments/hold-prototype-results.md for findings.
run-row.sh <row> <port> <holdSeconds> <allow|deny> <hookTimeout|default> [kill-mid-hold]
hold-server.mjs holds a PreToolUse/PermissionRequest http hook until GET /release?decision=allow|deny

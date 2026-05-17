#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_DIR="$HERE/LOCKS"
mkdir -p "$LOCK_DIR"

date

display=$(tmux list-sessions -F '#{session_created} #{session_name}: #{session_windows} windows (created #{t:session_created})#{?session_attached, (attached),}' 2>/dev/null \
    | sort -rn -k1,1 \
    | cut -d' ' -f2-)

if [ -z "$display" ]; then
    echo "no tmux sessions"
    sleep 3
    exit 0
fi

echo "$display"

names=$(tmux list-sessions -F '#{session_created} #{session_name}' 2>/dev/null \
    | sort -rn -k1,1 \
    | cut -d' ' -f2)

exec 3<&0

while IFS= read -r session; do
    lock_key=$(printf '%s' "$session" | tr -c 'a-zA-Z0-9._-' '_')
    exec 9>"$LOCK_DIR/$lock_key"
    if flock -n -E 75 9; then
        echo "attaching to: $session"
        tmux attach -t "$session" <&3
        exec 9>&-
        exec 3<&-
        # detached: short random jitter (0-199ms) before next acquisition attempt
        sleep "$(printf '0.%03d' $((RANDOM % 200)))"
        exit 0
    fi
    exec 9>&-
done <<< "$names"

exec 3<&-

# no session was free: wait longer before retrying
sleep 3

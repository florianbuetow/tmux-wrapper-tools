# =============================================================================
# Justfile Rules (follow these when editing justfile):
#
# 1. Use printf (not echo) to print colors — some terminals won't render
#    colors with echo.
#
# 2. Always add an empty `@echo ""` line before and after each target's
#    command block.
#
# 3. Always add new targets to the help section and update it when targets
#    are added, modified or removed.
#
# 4. Target ordering in help (and in this file) matters:
#    - Setup targets first (init, setup, install, etc.)
#    - Start/stop/run targets next
#    - Code generation / data tooling targets next
#    - Checks, linting, and tests next (ordered fastest to slowest)
#    Group related targets together and separate groups with an empty
#    `@echo ""` line in the help output.
#
# 5. Composite targets (e.g. ci) that call multiple sub-targets must fail
#    fast: exit 1 on the first error. Never skip over errors or warnings.
#    Use `set -e` or `&&` chaining to ensure immediate abort with the
#    appropriate error message.
#
# 6. Every target must end with a clear short status message:
#    - On success: green (\033[32m) message confirming completion.
#      E.g. printf "\033[32m✓ init completed successfully\033[0m\n"
#    - On failure: red (\033[31m) message indicating what failed, then exit 1.
#      E.g. printf "\033[31m✗ ci failed: tests exited with errors\033[0m\n"
# 7. Targets must be shown in groups separated by empty newlines in the help section.
#    - init/destroy/clean/help on top, ci and other tests on the bottom, between other groups
# =============================================================================

# Default recipe: show available commands
_default:
    @just help

# Show help information
help:
    @clear
    @echo ""
    @printf "\033[0;34m=== tmux-watcher ===\033[0m\n"
    @echo ""
    @printf "\033[0;33mSetup & Lifecycle:\033[0m\n"
    @printf "  %-40s %s\n" "init" "Check prerequisites and create the lock folder"
    @printf "  %-40s %s\n" "cleanup" "Remove lockfiles whose tmux session no longer exists"
    @printf "  %-40s %s\n" "help" "Show this help message"
    @echo ""
    @printf "\033[0;33mRun & Status:\033[0m\n"
    @printf "  %-40s %s\n" "attach" "Run the auto-attach loop"
    @printf "  %-40s %s\n" "status [N|once]" "Show session watch status (N=refresh secs, default 10)"
    @echo ""

# Check prerequisites and create the lock folder
init:
    #!/usr/bin/env bash
    set -e
    echo ""
    printf "\033[0;34m=== Initialising tmux-watcher ===\033[0m\n"
    echo ""

    if ! command -v flock >/dev/null 2>&1; then
        printf "\033[0;31m✗ init failed: flock not found. install it with: brew install flock\033[0m\n"
        exit 1
    fi
    printf "  %-40s %s\n" "flock" "found ($(command -v flock))"

    mkdir -p "$(pwd)/LOCKS"
    printf "  %-40s %s\n" "lock folder" "$(pwd)/LOCKS"

    echo ""
    printf "\033[0;32m✓ init completed successfully\033[0m\n"
    echo ""

# Remove lockfiles whose tmux session no longer exists
cleanup:
    @echo ""
    @printf "\033[0;34m=== Cleaning up stale lockfiles ===\033[0m\n"
    @echo ""
    @./cleanup.sh
    @echo ""
    @printf "\033[0;32m✓ cleanup completed successfully\033[0m\n"
    @echo ""

# Run the auto-attach loop
attach:
    @echo ""
    @printf "\033[0;34m=== Starting tmux watcher ===\033[0m\n"
    @echo ""
    @./loop.sh
    @echo ""
    @printf "\033[0;32m✓ attach completed successfully\033[0m\n"
    @echo ""

# Show tmux sessions and which are under watch (locked via flock), refreshing every N seconds (default 10). Pass "once" to render once and exit.
status interval="10":
    #!/usr/bin/env bash
    set -e
    once=""
    secs="{{interval}}"
    if [ "$secs" = "once" ]; then
        once=yes
    elif ! [[ "$secs" =~ ^[0-9]+$ ]] || [ "$secs" -lt 1 ]; then
        printf "\033[0;31m✗ status failed: interval must be a positive integer or \"once\" (got: %s)\033[0m\n" "$secs"
        exit 1
    fi
    while true; do
        rendered=$(just _status-render)
        [ -z "$once" ] && clear
        echo ""
        printf "\033[0;34m=== tmux session status ===\033[0m\n"
        echo ""
        printf '%s\n' "$rendered"
        echo ""
        if [ -n "$once" ]; then
            printf "\033[0;32m✓ status completed successfully\033[0m\n"
            echo ""
            break
        fi
        printf "\033[0;90m[%s] refreshing every %ss — Ctrl-C to stop\033[0m\n" "$(date +%H:%M:%S)" "$secs"
        echo ""
        sleep "$secs"
    done

# Private: render the status table once (no loop, no header)
_status-render:
    #!/usr/bin/env bash
    set -e
    LOCK_DIR="$(pwd)/LOCKS"

    sessions=$(tmux list-sessions -F '#{session_created}|#{session_name}|#{t:session_created}' 2>/dev/null | sort -rn -t'|' -k1,1)

    active_keys=""
    if [ -n "$sessions" ]; then
        active_keys=$(printf '%s\n' "$sessions" | awk -F'|' '{print $2}' | while IFS= read -r n; do
            printf '%s\n' "$(printf '%s' "$n" | tr -c 'a-zA-Z0-9._-' '_')"
        done)
    fi

    stale=""
    if [ -d "$LOCK_DIR" ]; then
        shopt -s nullglob
        for lockfile in "$LOCK_DIR"/*; do
            [ -f "$lockfile" ] || continue
            key=$(basename "$lockfile")
            if [ -z "$active_keys" ] || ! printf '%s\n' "$active_keys" | grep -Fxq "$key"; then
                created=$(date -r "$lockfile" 2>/dev/null || echo "")
                if [ -z "$stale" ]; then
                    stale="$key|$created"
                else
                    stale="$stale"$'\n'"$key|$created"
                fi
            fi
        done
        shopt -u nullglob
    fi

    if [ -z "$sessions" ] && [ -z "$stale" ]; then
        printf "\033[0;33mNo tmux sessions\033[0m\n"
        exit 0
    fi

    header_att="Attached"
    header_name="Session Name"
    header_created="Created"

    att_w=${#header_att}
    name_w=${#header_name}
    created_w=${#header_created}

    if [ -n "$sessions" ]; then
        while IFS='|' read -r _ name created; do
            [ ${#name} -gt $name_w ] && name_w=${#name}
            [ ${#created} -gt $created_w ] && created_w=${#created}
        done <<< "$sessions"
    fi

    if [ -n "$stale" ]; then
        while IFS='|' read -r name created; do
            [ ${#name} -gt $name_w ] && name_w=${#name}
            [ ${#created} -gt $created_w ] && created_w=${#created}
        done <<< "$stale"
    fi

    h_att=$(printf '─%.0s' $(seq 1 $((att_w + 2))))
    h_name=$(printf '─%.0s' $(seq 1 $((name_w + 2))))
    h_created=$(printf '─%.0s' $(seq 1 $((created_w + 2))))

    printf "┌%s┬%s┬%s┐\n" "$h_att" "$h_name" "$h_created"
    printf "│ %-*s │ %-*s │ %-*s │\n" "$att_w" "$header_att" "$name_w" "$header_name" "$created_w" "$header_created"
    printf "├%s┼%s┼%s┤\n" "$h_att" "$h_name" "$h_created"

    render_row() {
        local name="$1" created="$2" grey="$3"
        local lock_key=$(printf '%s' "$name" | tr -c 'a-zA-Z0-9._-' '_')
        local lockfile="$LOCK_DIR/$lock_key"
        local locked=no
        if [ -e "$lockfile" ]; then
            flock -n "$lockfile" true 2>/dev/null || locked=yes
        fi
        local sym sym_w
        if [ "$locked" = yes ]; then
            sym="✅"; sym_w=2
        else
            sym="-"; sym_w=1
        fi
        local lpad=$(( (att_w - sym_w) / 2 ))
        local rpad=$(( att_w - sym_w - lpad ))
        local mark=$(printf '%*s%s%*s' "$lpad" '' "$sym" "$rpad" '')
        local name_padded=$(printf '%-*s' "$name_w" "$name")
        if [ "$grey" = yes ]; then
            name_padded=$(printf '\033[0;90m%s\033[0m' "$name_padded")
        fi
        printf "│ %s │ %s │ %-*s │\n" "$mark" "$name_padded" "$created_w" "$created"
    }

    if [ -n "$sessions" ]; then
        while IFS='|' read -r _ name created; do
            render_row "$name" "$created" no
        done <<< "$sessions"
    fi

    if [ -n "$stale" ]; then
        while IFS='|' read -r name created; do
            render_row "$name" "$created" yes
        done <<< "$stale"
    fi

    printf "└%s┴%s┴%s┘\n" "$h_att" "$h_name" "$h_created"

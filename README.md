# tmux-watcher

Auto-attach helper for tmux. Each terminal running the watcher locks onto a
different existing session, newest first, so opening N terminals attaches to
the N most-recently-created sessions. Watchers coordinate via `flock`-held
files in `./LOCKS/`; see [How the locking works](#how-the-locking-works) for
the exact guarantees and the lossy-sanitization caveat on session names.

The repo also ships [`wrapfunc.sh`](#wrap-per-directory-tmux-sessions), a zsh
helper that creates tmux sessions whose names start with `WRAP-` so external
automation (e.g. agents) can find and remote-control them with
`tmux ls | grep '^WRAP-'`.

## Requirements

- `tmux`
- `flock` (on macOS: `brew install flock`)
- `just` (optional, for the `just` interface — on macOS: `brew install just`)

## Usage

Initialize once (verifies `flock` and creates `./LOCKS/`):

```sh
just init
```

Run the watcher in a terminal:

```sh
just attach
```

Open additional terminals and run the same command — each one attaches to the
next-newest session.

Check which sessions are under watch:

```sh
just status        # refresh every 10s (default)
just status 5      # refresh every 5s
just status once   # render once and exit
```

Remove lockfiles whose tmux session no longer exists:

```sh
just cleanup
```

## Scripts

The `just` targets wrap three scripts you can also invoke directly:

- `auto-attach.sh` — one-shot. Lists tmux sessions sorted by creation time
  (newest first) and attaches to the first one no other watcher has locked.
  Uses `flock` files under `./LOCKS/` for mutual exclusion. Sleeps a random
  0–199 ms after detaching from a session (so multiple watchers racing for
  the next free slot don't collide), and 3 s when no session was available.
- `loop.sh` — checks that `flock` is installed, then repeatedly clears the
  screen and re-runs `auto-attach.sh`. All inter-attempt pacing lives in
  `auto-attach.sh`; the loop itself doesn't sleep.
- `cleanup.sh` — removes every lockfile in `./LOCKS/` whose name no longer
  matches an active tmux session (after the same sanitization the watcher
  applies). Prints one line per file (`kept` / `removed` / `held`) and a
  count summary. Two safety layers run before any deletion: the lockfile's
  key must not match an active session, and `flock -n` must succeed against
  the file (no other process holds it). If `tmux list-sessions` fails for
  any reason other than "no server running", cleanup exits non-zero without
  deleting anything — earlier behavior treated that case as "every lock is
  orphaned" and could destroy live locks.

## How the locking works

For each session name, the watcher opens `LOCKS/<sanitized-name>` and tries
`flock -n` on it. The lock is held only while that terminal is attached, so
when a session is detached or killed, the slot frees up for the next watcher.

The sanitization is `tr -c 'a-zA-Z0-9._-' '_'` — anything outside that
character class becomes `_`. This is **lossy**: distinct session names that
differ only in those characters (e.g. `my session` and `my_session`, or
`a/b` and `a_b`) collapse to the same lock key and therefore share a single
lock. Two watchers can never attach to such a pair concurrently. If you
need them to be watched in parallel, name them so they differ in
`[A-Za-z0-9._-]` characters.

`just status` reflects the lock state directly: the ✅ column is a live
`flock -n` probe against the lockfile. Sessions in normal color come from
`tmux list-sessions`; greyed rows are stale lockfiles whose tmux session no
longer exists (and which `just cleanup` will remove on its next run,
provided no process still holds the flock).

## Wrap (per-directory tmux sessions)

`wrapfunc.sh` defines a zsh function `wrap` that spawns and manages tmux
sessions named `WRAP-[N]-<dir>`, where `<dir>` is the current working
directory (with `$HOME` rewritten to `~` and `.` characters replaced by `_`
to match tmux's own session-name normalization). The numeric index `N`
auto-increments across all wrap sessions globally, so every new wrap
session gets a unique name regardless of directory.

The `WRAP-` prefix is the point: it makes these sessions trivially
discoverable from outside the terminal. An agent or any external
automation can find them with:

```sh
tmux ls | grep '^WRAP-'
```

and then attach, send keys, or otherwise remote-control them by name. The
auto-attach watcher above doesn't care about session names; `wrap` just
gives you a naming convention so external tooling can locate sessions by
`grep`.

### Install

`wrapfunc.sh` is a sourced library, not a runnable script. Add this line
to your `~/.zshrc`:

```sh
[ -f "$HOME/path/to/tmux-wrapper-tools/wrapfunc.sh" ] && \
    source "$HOME/path/to/tmux-wrapper-tools/wrapfunc.sh"
```

Adjust the path to wherever you cloned the repo. Reopen your shell or run
`source ~/.zshrc` to load the function.

### Requirements

- `zsh` — the function uses zsh-specific syntax (`${match[N]}` regex
  captures, `local -A` associative arrays, `read "var?prompt"`). It will
  not work in bash without modification.
- `tmux`.

### Usage

```sh
wrap            # list all wrap sessions, show usage
wrap new        # create a new wrap session for $PWD (refuses inside tmux)
wrap -r        # reattach to (or `switch-client` to) a wrap session for $PWD
wrap -d        # kill a wrap session for $PWD
```

`wrap -r` and `wrap -d` filter the candidate list by the current working
directory: only sessions whose embedded `<dir>` matches `$PWD` are offered.
If exactly one match exists, `wrap -r` attaches directly; otherwise it
prompts for the session number. `wrap new` refuses to run from inside an
existing tmux session — detach first, or use `wrap -r` to switch between
wrap sessions while attached.

#!/usr/bin/env bash
set -u

TARGET="8.8.8.8"
LOG_DIR="/root/logs/mtr"
REMOTE_URL="https://github.com/LisArtist/V...A-logs.git"
BRANCH="main"
TZ_NAME="Europe/Moscow"

LOG_FILE="${LOG_DIR}/mtr_${TARGET}_$(TZ="$TZ_NAME" date '+%F').log"
LOCK_FILE="/tmp/run_mtr_${TARGET//./_}.lock"

timestamp() {
  TZ="$TZ_NAME" date '+%Y-%m-%d %H:%M:%S %Z'
}

log_msg() {
  printf '[%s] %s\n' "$(timestamp)" "$*" >&2
}

run_mtr() {
  mkdir -p "$LOG_DIR"

  {
    printf '===== %s =====\n' "$(timestamp)"
    mtr -rwzc 500 "$TARGET"
    printf '\n'
  } >> "$LOG_FILE" 2>&1
}

ensure_git_repo() {
  cd "$LOG_DIR" || return 1

  if [ ! -d .git ]; then
    git init -b "$BRANCH" || return 1
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$REMOTE_URL" || return 1
  else
    git remote add origin "$REMOTE_URL" || return 1
  fi

  git config user.name "mtr log bot" || return 1
  git config user.email "root@$(hostname -f 2>/dev/null || hostname)" || return 1
}

commit_and_push() {
  cd "$LOG_DIR" || return 1

  git add -- .gitignore run_mtr_8.8.8.8.sh mtr_*.log || return 1

  if git diff --cached --quiet; then
    log_msg "No git changes to commit."
    return 0
  fi

  git commit -m "Update mtr logs $(timestamp)" || return 1

  if ! git push -u origin "$BRANCH"; then
    log_msg "git push failed. Configure GitHub credentials for ${REMOTE_URL} and retry."
    return 1
  fi
}

main() {
  if ! command -v flock >/dev/null 2>&1; then
    log_msg "flock is not installed."
    return 1
  fi

  (
    if ! flock -n 9; then
      log_msg "Previous mtr run is still active; skipping this interval."
      return 0
    fi

    run_mtr
    ensure_git_repo || log_msg "git repository setup failed."
    commit_and_push || log_msg "git commit or push failed."
  ) 9>"$LOCK_FILE"
}

main "$@"

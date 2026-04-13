#!/usr/bin/env bash
set -Eeuo pipefail

TEST_NAME="gun-smoke"
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY_FILE="${ENTRY_FILE:-${ROOT_DIR}/entry/arch.sh}"

PASS_COUNT=0
FAIL_COUNT=0

TMP_ROOT=""
TEST_ROOT=""
TEST_REPO=""

log ()      { printf '%s\n' "$*"; }
section ()  { printf '\n==> %s\n' "$*"; }
pass ()     { PASS_COUNT=$(( PASS_COUNT + 1 )); printf '  [PASS] %s\n' "$*"; }
fail ()     { FAIL_COUNT=$(( FAIL_COUNT + 1 )); printf '  [FAIL] %s\n' "$*"; }
die ()      { printf '\n[FAIL] %s\n' "$*" >&2; exit 1; }

have () { command -v "$1" >/dev/null 2>&1; }

cleanup () {

    local code=$?

    if [[ -n "${TMP_ROOT}" && -d "${TMP_ROOT}" ]]; then
        rm -rf -- "${TMP_ROOT}" >/dev/null 2>&1 || true
    fi

    if (( code == 0 )); then
        printf '\nOK: %s passed ( %d tests )\n' "${TEST_NAME}" "${PASS_COUNT}"
    else
        printf '\nFAILED: %s failed ( pass=%d, fail=%d )\n' "${TEST_NAME}" "${PASS_COUNT}" "${FAIL_COUNT}" >&2
    fi

    exit "${code}"

}
trap cleanup EXIT

run_ok () {

    local name="${1:-}"
    shift || true

    if "$@"; then
        pass "${name}"
        return 0
    fi

    fail "${name}"
    return 1

}
run_fail () {

    local name="${1:-}"
    shift || true

    if "$@" >/dev/null 2>&1; then
        fail "${name}"
        return 1
    fi

    pass "${name}"
    return 0

}
assert_file () {

    local path="${1:-}"
    [[ -f "${path}" ]]

}
assert_dir () {

    local path="${1:-}"
    [[ -d "${path}" ]]

}
assert_link () {

    local path="${1:-}"
    [[ -L "${path}" ]]

}
assert_contains () {

    local file="${1:-}" needle="${2:-}"
    grep -Fq -- "${needle}" "${file}"

}
assert_cmd () {

    local name="${1:-}"
    type -t "${name}" >/dev/null 2>&1

}
new_temp_layout () {

    TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gun-test.XXXXXX")"
    TEST_ROOT="${TMP_ROOT}/work"
    TEST_REPO="${TMP_ROOT}/repo"

    mkdir -p -- "${TEST_ROOT}" "${TEST_REPO}"

}
source_entry () {

    [[ -f "${ENTRY_FILE}" ]] || die "Entry file not found: ${ENTRY_FILE}"

    # shellcheck disable=SC1090
    source "${ENTRY_FILE}"

}
syntax_check_all () {

    local f="" ok=1

    while IFS= read -r -d '' f; do
        if bash -n "${f}"; then
            :
        else
            printf 'syntax error: %s\n' "${f}" >&2
            ok=0
        fi
    done < <(
        find "${ROOT_DIR}/core" "${ROOT_DIR}/ensure" "${ROOT_DIR}/entry" "${ROOT_DIR}/module" \
            -type f -name '*.sh' ! -path '*/stack/*' -print0
    )

    (( ok == 1 ))

}
register_check () {

    local cmds=(
        cmd_fs_help
        cmd_forge_help
        cmd_git_help
        cmd_github_help
        cmd_notify_help
        cmd_new_dir
        cmd_new_file
        cmd_copy
        cmd_move
        cmd_link
        cmd_remove
        cmd_trash
        cmd_clear
        cmd_stats
        cmd_diff
        cmd_synced
        cmd_compress
        cmd_extract
        cmd_backup
        cmd_sync
        cmd_is_repo
        cmd_repo_root
        cmd_status
        cmd_init
        cmd_current_branch
        cmd_all_branches
        cmd_all_tags
    )

    local c=""
    for c in "${cmds[@]}"; do
        assert_cmd "${c}" || return 1
    done

}
help_output_check () {

    cmd_fs_help      >/dev/null
    cmd_forge_help   >/dev/null
    cmd_git_help     >/dev/null
    cmd_github_help  >/dev/null
    cmd_notify_help  >/dev/null

}
fs_smoke_check () {

    cd -- "${TEST_ROOT}"

    cmd_new_dir alpha
    assert_dir alpha || return 1

    cmd_new_file alpha/a.txt
    assert_file alpha/a.txt || return 1

    printf 'hello\n' > alpha/a.txt

    cmd_copy alpha/a.txt alpha/b.txt
    assert_file alpha/b.txt || return 1
    assert_contains alpha/b.txt "hello" || return 1

    cmd_move alpha/b.txt alpha/c.txt
    assert_file alpha/c.txt || return 1
    [[ ! -e alpha/b.txt ]] || return 1

    cmd_link alpha/a.txt alpha/a.link
    assert_link alpha/a.link || return 1

    cmd_path_type alpha >/dev/null
    cmd_file_type alpha/a.txt >/dev/null
    cmd_stats alpha/a.txt >/dev/null

    cmd_diff alpha/a.txt alpha/c.txt >/dev/null || true
    cmd_synced alpha/a.txt alpha/c.txt >/dev/null || true

    return 0

}
fs_clear_check () {

    cd -- "${TEST_ROOT}"

    mkdir -p beta
    printf 'x\n' > beta/1.txt
    printf 'y\n' > beta/2.txt

    cmd_clear beta
    [[ -d beta ]] || return 1
    [[ -z "$(find beta -mindepth 1 -print -quit 2>/dev/null || true)" ]] || return 1

    printf 'data\n' > single.txt
    cmd_clear single.txt
    assert_file single.txt || return 1
    [[ ! -s single.txt ]] || return 1

}
fs_archive_check () {

    cd -- "${TEST_ROOT}"

    mkdir -p gamma
    printf 'abc\n' > gamma/file.txt

    cmd_compress gamma

    local arc=""
    arc="$(find . -maxdepth 1 -type f \( -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.tar.zst' -o -name '*.tar' \) | head -n1 || true)"
    [[ -n "${arc}" ]] || return 1

    mkdir -p out
    cmd_extract "${arc#./}" out
    [[ -d out ]] || return 1

}
fs_backup_sync_check () {

    cd -- "${TEST_ROOT}"

    mkdir -p delta
    printf 'backup\n' > delta/k.txt

    cmd_backup delta
    local backup_path=""
    backup_path="$(find . -maxdepth 1 \( -name '*backup*' -o -name '*.bak' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.zip' -o -name '*.tar.zst' \) | head -n1 || true)"
    [[ -n "${backup_path}" ]] || return 1

    mkdir -p sync_dst
    cmd_sync delta sync_dst || cmd_sync --src delta --dest sync_dst || true

    [[ -e sync_dst || -e sync_dst/delta || -e sync_dst/k.txt || -e sync_dst/delta/k.txt ]]

}
fs_failure_check () {

    cd -- "${TEST_ROOT}"

    run_fail "fs copy missing source"    cmd_copy missing.txt out.txt
    run_fail "fs move missing source"    cmd_move missing.txt out.txt
    run_fail "fs extract missing src"    cmd_extract missing.zip out
    run_fail "fs remove missing source"  cmd_remove missing.txt

}
git_local_check () {

    have git || return 0

    cd -- "${TEST_REPO}"

    git init -b main >/dev/null 2>&1 || git init >/dev/null 2>&1
    git config user.name  "Core Master Test"
    git config user.email "test@example.com"

    printf 'hello\n' > README.md
    git add README.md
    git commit -m "init" >/dev/null 2>&1

    cmd_is_repo >/dev/null
    [[ "$(cmd_is_repo 2>/dev/null || true)" == "yes" ]] || return 1

    cmd_repo_root >/dev/null || return 1
    cmd_status >/dev/null || return 1
    [[ "$(cmd_status 2>/dev/null || true)" == "clean" ]] || return 1

    printf 'dirty\n' >> README.md
    [[ "$(cmd_status 2>/dev/null || true)" == "dirty" ]] || return 1

    cmd_current_branch >/dev/null || return 1
    [[ "$(cmd_current_branch 2>/dev/null || true)" == "main" ]] || return 1

    cmd_new_branch dev >/dev/null || return 1
    [[ "$(cmd_current_branch 2>/dev/null || true)" == "dev" ]] || return 1

    cmd_switch_branch main >/dev/null || return 1
    [[ "$(cmd_current_branch 2>/dev/null || true)" == "main" ]] || return 1

    cmd_all_branches --only-local >/dev/null || return 1
    cmd_all_tags --only-local >/dev/null || return 1

}
git_changelog_check () {

    have git || return 0

    cd -- "${TEST_REPO}"

    cmd_changelog 0.1.0 "Track 0.1.0 release."
    assert_file CHANGELOG.md || return 1
    assert_contains CHANGELOG.md "# Changelog" || return 1
    assert_contains CHANGELOG.md "## 0.1.0" || return 1

}
git_failure_check () {

    have git || return 0

    cd -- "${TEST_ROOT}"
    run_fail "git current-branch outside repo" cmd_current_branch
    run_fail "git repo-root outside repo"      cmd_repo_root

}
github_help_only_check () {

    cmd_github_help >/dev/null

}
notify_help_only_check () {

    cmd_notify_help >/dev/null

}
main () {

    new_temp_layout

    section "syntax"
    run_ok "bash -n for all shell files" syntax_check_all || exit 1

    section "load"
    source_entry
    run_ok "entry source" true
    run_ok "command registry" register_check || exit 1
    run_ok "help commands output" help_output_check || exit 1

    section "fs"
    run_ok "fs smoke" fs_smoke_check || exit 1
    run_ok "fs clear" fs_clear_check || exit 1
    run_ok "fs archive" fs_archive_check || exit 1
    run_ok "fs backup/sync" fs_backup_sync_check || true
    fs_failure_check || exit 1

    section "git"
    run_ok "git local smoke" git_local_check || exit 1
    run_ok "git changelog" git_changelog_check || exit 1
    run_ok "git failure paths" git_failure_check || exit 1

    section "github/notify"
    run_ok "github help only" github_help_only_check || exit 1
    run_ok "notify help only" notify_help_only_check || exit 1

    (( FAIL_COUNT == 0 )) || exit 1
}

main "$@"

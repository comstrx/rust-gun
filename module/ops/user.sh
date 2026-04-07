
WORKSPACE_DIR="${WORKSPACE_DIR:-/var/www}"
PROJECTS_DIR="${PROJECTS_DIR:-/var/www/projects}"

SYNC_DIR="${SYNC_DIR:-/mnt/d}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/mnt/d/Archive}"

OUT_DIR="${OUT_DIR:-out}"

GIT_HTTP_USER="${GIT_HTTP_USER:-x-access-token}"
GIT_HOST="${GIT_HOST:-github.com}"
GIT_AUTH="${GIT_AUTH:-ssh}"
GIT_TOKEN="${GIT_TOKEN:-}"
GIT_SSH_KEY="${GIT_SSH_KEY:-}"

GH_HOST="${GH_HOST:-}"
GH_PROFILE="${GH_PROFILE:-}"

cmd_new () {

    cmd_new_project "$@"

}
cmd_done () {

    source <(parse "$@" -- tag release:bool sync:bool=true backup:bool=false)

    cmd_format_fix
    cmd_format_check

    cmd_lint_fix
    cmd_lint_check

    cmd_audit_fix
    cmd_audit_check

    cmd_syft
    cmd_trivy
    cmd_leaks

    cmd_typos_fix
    cmd_typos_check

    cmd_taplo_fix
    cmd_taplo_check

    cmd_prettier_fix
    cmd_prettier_check

    cmd_tree_fix

    cmd_coverage
    cmd_semver

    (( release )) && [[ -z "${tag}" ]] && tag="$(cmd_guess_tag)"

    cmd_push --tag "${tag}" --release "${release}" "${kwargs[@]}"

    (( sync )) && cmd_sync "${kwargs[@]}"

    (( backup )) && cmd_backup --name "${tag}" "${kwargs[@]}"

}

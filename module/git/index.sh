
cmd_repo_root () {

    git_repo_root

}
cmd_is_repo () {

    ensure_pkg git

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        print yes
        return 0
    fi

    print no
    return 1

}
cmd_clone () {

    ensure_pkg git
    run git clone "$@"

}
cmd_pull () {

    ensure_pkg git
    run git pull --rebase "$@"

}
cmd_status () {

    ensure_pkg git
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { print no-repo; return 1; }

    if [[ -z "$(git status --porcelain 2>/dev/null || true)" ]]; then
        print clean
        return 0
    fi

    print dirty
    return 1

}
cmd_guess_tag () {

    printf '%s\n' "$(git_norm_tag "v$(git_root_version)")"

}
cmd_remote_info () {

    git_repo_guard
    source <(parse "$@" -- remote=origin)

    local url="$(git_remote_url "${remote}")"
    [[ -n "${url}" ]] || die "Remote not found: ${remote}"

    info "${remote}: $(git_redact_url "${url}")"

    if [[ "${url}" == https://* || "${url}" == http://* ]]; then
        info "Protocol: HTTPS"
        return 0
    fi
    if [[ "${url}" == git@*:* || "${url}" == ssh://* ]]; then
        info "Protocol: SSH"
        return 0
    fi

    warn "Protocol: unknown"

}

cmd_init () {

    ensure_pkg git
    source <(parse "$@" -- :repo branch=main remote=origin auth key host create:bool=true)

    local path="" url="" parsed=0 explicit=0 before_url="" after_url="" cur=""

    auth="${auth:-${GIT_AUTH:-ssh}}"
    host="${host:-${GIT_HOST:-github.com}}"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

        if git_init_supports_initial_branch; then
            run git init -b "${branch}"
        else
            run git init
            git_set_default_branch "${branch}"
        fi

    fi
    if [[ "${repo}" == *"://"* || "${repo}" == git@*:* || "${repo}" == ssh://* ]]; then
        explicit=1
    fi
    if [[ -n "${key}" && "${auth}" == "ssh" ]]; then

        local key_path="$(git_resolve_ssh_key "${key}")"
        [[ -f "${key_path}" ]] && git_keymap_set "${key_path}" >/dev/null 2>&1 || true
        [[ -f "${key_path}" ]] || cmd_add_ssh "${key}" "${host}" --upload

    fi

    before_url="$(git_remote_url "${remote}")"
    (( create )) && (( explicit == 0 )) && cmd_new_repo --repo "${repo}" "${kwargs[@]}"
    after_url="$(git_remote_url "${remote}")"

    if (( explicit == 0 )) && (( create )) && [[ -n "${after_url}" && "${after_url}" != "${before_url}" ]]; then

        url="${after_url}"

    else

        cur="${after_url:-${before_url}}"

        if [[ -n "${cur}" ]]; then
            local h="" p=""

            if read -r h p < <(git_parse_remote "${cur}"); then
                host="${h}"
            fi
        fi

        if [[ "${repo}" != *"://"* && "${repo}" != git@*:* && "${repo}" != ssh://* && "${repo}" == */* ]]; then
            path="${repo}"
            parsed=1
        else
            if read -r host path < <(git_parse_remote "${repo}"); then
                parsed=1
            fi
        fi

        if (( parsed )); then
            path="$(git_norm_path_git "${path}")"

            if [[ "${auth}" == "ssh" ]]; then url="$(git_build_ssh_url "${host}" "${path}")" || die "Can't build ssh url"
            else url="$(git_build_https_url "${host}" "${path}")" || die "Can't build https url"
            fi
        else
            url="${repo}"
        fi

    fi

    if git remote get-url "${remote}" >/dev/null 2>&1; then run git remote set-url "${remote}" "${url}"
    else run git remote add "${remote}" "${url}"
    fi

    git_set_default_branch "${branch}"
    success "OK: branch='${branch}', remote='${remote}' -> $(git_redact_url "${url}")"

}
cmd_push () {

    git_repo_guard
    source <(parse "$@" -- remote=origin auth key token token_env branch message tag t force:bool f:bool changelog:bool log:bool release:bool)

    git_require_remote "${remote}"
    local kind="" target="" safe="" ssh_cmd=""

    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")
    [[ -n "${kind}" && -n "${target}" ]] || die "Failed to resolve git auth for remote '${remote}'."

    (( f )) && force=1
    (( log )) && changelog=1

    [[ -z "${tag}" ]] && tag="${t}"
    (( release )) && [[ -z "${tag}" ]] && tag="auto"

    if [[ -n "${tag}" ]]; then

        [[ "${tag}" == "auto" ]] && tag="$(cmd_guess_tag)"
        tag="$(git_norm_tag "${tag}")"
        [[ -z "${message}" ]] && message="Track ${tag} release."

    fi
    if [[ -z "${branch}" ]]; then
        branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        [[ -n "${branch}" ]] || branch="main"
    fi
    if [[ -z "$message" ]]; then
        [[ -n "${tag}" ]] && message="Track ${tag} release." || message="new commit"
    fi

    local root="$(git_repo_root)"
    git_guard_no_unborn_nested_repos "${root}"

    run_git "${kind}" "${ssh_cmd}" add -A || die "git add failed."

    if run_git "${kind}" "${ssh_cmd}" diff --cached --quiet >/dev/null 2>&1; then
        git_has_commit || die "Nothing to push: no commits yet. Make changes then run: push"
    else
        git_require_identity
        run_git "${kind}" "${ssh_cmd}" commit -m "${message}" || die "git commit failed."
    fi

    if [[ -n "${tag}" ]]; then

        if git_remote_has_tag "${kind}" "${ssh_cmd}" "${target}" "${tag}" && (( force == 0 )); then

            log "Tag exists on remote (${remote}/${tag}). Use --force to overwrite."
            tag=""; changelog=0

        else

            if (( changelog )); then

                cmd_changelog "${tag}" "${message}"
                run_git "${kind}" "${ssh_cmd}" add -A

                if ! run_git "${kind}" "${ssh_cmd}" diff --cached --quiet >/dev/null 2>&1; then

                    git_require_identity
                    run_git "${kind}" "${ssh_cmd}" commit -m "Track ${tag} release." || die "git commit failed."

                fi

            fi

        fi

    fi

    local target_is_url=0
    [[ "${target}" == http://* || "${target}" == https://* ]] && target_is_url=1

    if (( force )); then

        run_git "${kind}" "${ssh_cmd}" fetch "${target}" "${branch}" >/dev/null 2>&1 || true
        run_git "${kind}" "${ssh_cmd}" push --force-with-lease "${target}" "${branch}" || die "push rejected. fetch/pull first."

    else

        if (( target_is_url )); then
            run_git "${kind}" "${ssh_cmd}" push "${target}" "${branch}" || die "push rejected. Run: git pull --rebase ${remote} ${branch}"
        else
            if git_upstream_exists_for "${branch}"; then
                run_git "${kind}" "${ssh_cmd}" push "${target}" "${branch}" || die "push rejected. Run: git pull --rebase ${remote} ${branch}"
            else
                run_git "${kind}" "${ssh_cmd}" push -u "${target}" "${branch}" || die "push rejected. Run: git pull --rebase ${remote} ${branch}"
            fi
        fi

    fi

    if [[ -n "${tag}" ]]; then

        run_git "${kind}" "${ssh_cmd}" tag -d "${tag}" >/dev/null 2>&1 || true

        if (( force )); then
            run_git "${kind}" "${ssh_cmd}" push "${target}" --delete "${tag}" >/dev/null 2>&1 || true
        fi

        run_git "${kind}" "${ssh_cmd}" tag -a "${tag}" -m "${message}" || die "tag create failed."

        if (( force )); then run_git "${kind}" "${ssh_cmd}" push --force "${target}" "${tag}" || die "tag push failed."
        else run_git "${kind}" "${ssh_cmd}" push "${target}" "${tag}" || die "tag push failed."
        fi

    fi
    if [[ -n "${key}" ]]; then

        local key_path="$(git_resolve_ssh_key "${key}")"
        [[ -f "${key_path}" ]] && git_keymap_set "${key_path}" >/dev/null 2>&1 || true

    fi

    success "OK: pushed via ${kind} -> ${safe}"

}
cmd_add_ssh () {

    source <(parse "$@" -- name host alias title upload:bool)

    [[ -n "${host}" ]] || host="${GIT_HOST:-github.com}"
    [[ -n "${name}" ]] || name="$(git_guess_ssh_key 2>/dev/null || true)"
    [[ -n "${name}" ]] || die "ssh: cannot guess key name. Use --name <key>"

    local base="$(git_new_ssh_key "${name}" "${host}" "${alias}" "${kwargs[@]}")"
    local pub="${base}.pub"

    if (( upload )) && [[ "${host}" == *github* ]]; then

        ensure_pkg gh
        gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated. Run 'gh auth login'"

        [[ -n "${title}" ]] || { local os="$(os_name)"; is_wsl && os="wsl"; title="${os}${name:+-${name}}"; }
        title="${title^^}"

        run gh ssh-key add "${pub}" --title "${title}" --type authentication
        success "Key uploaded to GitHub -> ${title}"

    fi

    git rev-parse --show-toplevel >/dev/null 2>&1 && git_keymap_set "${base}" >/dev/null 2>&1 || true

    success "OK: key created -> ${base}"
    success "Public key -> $(cat "${pub}")"

}
cmd_changelog () {

    ensure_pkg grep mktemp mv date tail git

    local tag="${1:-unreleased}" msg="${2:-}"

    [[ "${tag}" =~ ^v[0-9] ]] && tag="${tag#v}"
    [[ -n "${msg}" ]] || msg="Track ${tag} release."
    msg="${msg//$'\r'/ }"; msg="${msg//$'\n'/ }"

    local root="$(git_repo_root)"
    local file="${root}/CHANGELOG.md"
    local day="$(date -u +%Y-%m-%d)"
    local header="## ${tag} ( ${day} )"
    local block="${header}"$'\n\n'"- ${msg}"
    local tmp="$(mktemp "${TMPDIR:-/tmp}/git.XXXXXX")"

    if [[ -f "${file}" ]]; then

        local top=""
        IFS= read -r top < "${file}" 2>/dev/null || true

        if [[ "${top}" != "# Changelog" ]]; then

            { printf '%s\n\n' "# Changelog"; cat "${file}"; } > "${tmp}"
            mv -f "${tmp}" "${file}"
            tmp="$(mktemp)" || die "changelog: mktemp failed"

        fi

        local first="$(tail -n +2 "${file}" 2>/dev/null | grep -m1 -E '^[[:space:]]*## ' || true)"

        if [[ "${first}" == "${header}" ]]; then
            log "changelog: already written -> skip"
            return 0
        fi

        {
            printf '%s\n\n' "# Changelog"
            printf '%s\n' "${block}"
            tail -n +2 "${file}"
        } > "${tmp}"

    else

        {
            printf '%s\n\n' "# Changelog"
            printf '%s\n' "${block}"
        } > "${tmp}"

    fi

    mv -f "${tmp}" "${file}"
    success "changelog: updated ${file}"

}

cmd_new_tag () {

    git_repo_guard
    source <(parse "$@" -- :tag)
    cmd_push --tag "${tag}" "${kwargs[@]}"

}
cmd_remove_tag () {

    git_repo_guard
    source <(parse "$@" -- :tag remote=origin auth key token token_env)

    tag="$(git_norm_tag "${tag}")"
    confirm "Delete tag '${tag}' locally and on '${remote}'?" || return 0

    run git tag -d "${tag}" >/dev/null 2>&1 || true

    local have_remote=0
    git remote get-url "${remote}" >/dev/null 2>&1 && have_remote=1
    (( have_remote )) || return 0

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    run_git "${kind}" "${ssh_cmd}" push "${target}" --delete "${tag}" >/dev/null 2>&1 || true

}
cmd_new_branch () {

    git_repo_guard
    source <(parse "$@" -- :branch remote=origin auth key token token_env)

    if git show-ref --verify --quiet "refs/heads/${branch}"; then
        git_switch "${branch}"
        return 0
    fi

    local have_remote=0
    git remote get-url "${remote}" >/dev/null 2>&1 && have_remote=1

    if (( have_remote )); then

        local kind="" target="" safe="" ssh_cmd=""
        IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

        if git_remote_has_branch "${kind}" "${ssh_cmd}" "${target}" "${branch}"; then

            run_git "${kind}" "${ssh_cmd}" fetch "${target}" "refs/heads/${branch}:refs/remotes/${remote}/${branch}" >/dev/null 2>&1 || true
            git_switch -c "${branch}" --track "${remote}/${branch}"
            return 0

        fi

    fi

    git_switch -c "${branch}"

}
cmd_remove_branch () {

    git_repo_guard
    source <(parse "$@" -- :branch remote=origin auth key token token_env)

    local cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ "${cur}" != "${branch}" ]] || die "Can't delete current branch: ${branch}"

    confirm "Delete branch '${branch}' locally and on '${remote}'?" || return 0
    run git branch -D "${branch}" >/dev/null 2>&1 || true

    local have_remote=0
    git remote get-url "${remote}" >/dev/null 2>&1 && have_remote=1
    (( have_remote )) || return 0

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    run_git "${kind}" "${ssh_cmd}" push "${target}" --delete "${branch}" >/dev/null 2>&1 || true

}

cmd_default_branch () {

    git_repo_guard

    local b="$(git_default_branch "origin")" || die "Can't detect default branch."
    [[ -n "${b}" ]] || die "No branch checked out."

    info "${b}"

}
cmd_current_branch () {

    git_repo_guard

    local b="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "${b}" ]] || die "No branch checked out."

    info "${b}"

}
cmd_switch_branch () {

    git_repo_guard
    source <(parse "$@" -- :branch remote=origin auth key token token_env create:bool track:bool=true)

    if git show-ref --verify --quiet "refs/heads/${branch}"; then
        git_switch "${branch}"
        return 0
    fi

    local have_remote=0
    git remote get-url "${remote}" >/dev/null 2>&1 && have_remote=1

    if (( track )) && (( have_remote )); then

        local kind="" target="" safe="" ssh_cmd=""

        IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")
        [[ -n "${kind}" && -n "${target}" ]] || die "Failed to resolve git auth for remote '${remote}'."

        if git_remote_has_branch "${kind}" "${ssh_cmd}" "${target}" "${branch}"; then

            run_git "${kind}" "${ssh_cmd}" fetch "${target}" "refs/heads/${branch}:refs/remotes/${remote}/${branch}" >/dev/null 2>&1 || true
            git_switch -c "${branch}" --track "${remote}/${branch}"
            return 0

        fi

    fi

    (( create )) || die "Branch not found: ${branch}. Use --create to create locally."
    git_switch -c "${branch}"

}

cmd_all_tags () {

    git_repo_guard
    source <(parse "$@" -- remote=origin only_local:bool auth key token token_env)

    if (( only_local )); then
        git tag --list
        return 0
    fi

    git_require_remote "${remote}"

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    ensure_pkg awk
    run_git "${kind}" "${ssh_cmd}" ls-remote --tags --refs "${target}" | awk '{ sub("^refs/tags/","",$2); print $2 }'

}
cmd_all_branches () {

    git_repo_guard
    source <(parse "$@" -- remote=origin only_local:bool)

    if (( only_local )); then
        git for-each-ref --format='%(refname:short)' "refs/heads"
        return 0
    fi

    ensure_pkg awk
    git_require_remote "${remote}"

    GIT_TERMINAL_PROMPT=0 git fetch --prune "${remote}" >/dev/null 2>&1 || true
    git for-each-ref --format='%(refname:short)' "refs/heads" "refs/remotes/${remote}" | awk '!/\/HEAD$/'

}

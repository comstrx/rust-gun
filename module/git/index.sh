
cmd_git_help () {

    info_ln "Git :"

    printf '    %s\n' \
        "" \
        "is-repo                    * Check whether current path is a git repository" \
        "root                       * Print repository root path" \
        "tag                        * Build tag from current project version (guessing tag)" \
        "" \
        "status                     * Print repository state (clean or dirty)" \
        "remote                     * Show remote URL and detected protocol" \
        "ssh-key                    * Create SSH key and optionally upload it" \
        "changelog                  * Prepend release entry to CHANGELOG.md" \
        "" \
        "clone                      * Clone remote repository" \
        "pull                       * Pull latest changes with rebase" \
        "init                       * Initialize repository and configure remote" \
        "push                       * Commit and push current branch" \
        "release                    * Push release with tag and changelog" \
        "" \
        "new-tag                    * Create and push a new tag" \
        "remove-tag                 * Delete tag locally and remotely" \
        "new-branch                 * Create branch locally or track remote branch" \
        "remove-branch              * Delete branch locally and remotely" \
        "" \
        "default-branch             * Print default branch name" \
        "current-branch             * Print current branch name" \
        "switch-branch              * Switch to branch or create it" \
        "" \
        "all-tags                   * List all tags" \
        "all-branches               * List all branches" \
        ''

}

cmd_is_repo () {

    ensure_tool git

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        print yes
        return 0
    fi

    print no
    return 1

}
cmd_root () {

    git_repo_root

}
cmd_tag () {

    local ver="v$(git_root_version)"
    local tag="$(git_norm_tag "${ver}")"

    [[ -n "${tag}" ]] && printf '%s\n' "${tag}"

}

cmd_status () {

    ensure_tool git
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { print no-repo; return 1; }

    if [[ -z "$(git status --porcelain 2>/dev/null || true)" ]]; then
        print clean
        return 0
    fi

    print dirty
    return 1

}
cmd_remote () {

    git_repo_guard
    source <(parse "$@" -- remote=origin)

    local url="$(git_remote_url "${remote}")"
    [[ -n "${url}" ]] || die "Remote not found: ${remote}"

    print "${remote}: $(git_redact_url "${url}")"

    if [[ "${url}" == https://* || "${url}" == http://* ]]; then
        print "Protocol: HTTPS"
        return 0
    fi
    if [[ "${url}" == git@*:* || "${url}" == ssh://* ]]; then
        print "Protocol: SSH"
        return 0
    fi

    print "Protocol: unknown"
    return 1

}
cmd_ssh_key () {

    source <(parse "$@" -- name host alias title upload:bool)

    [[ -n "${host}" ]] || host="${GIT_HOST:-github.com}"
    [[ -n "${name}" ]] || name="$(git_guess_ssh_key 2>/dev/null || true)"
    [[ -n "${name}" ]] || die "ssh: cannot guess key name. Use --name <key>"

    local base="$(git_new_ssh_key "${name}" "${host}" "${alias}" "${kwargs[@]}")"
    local pub="${base}.pub"

    if (( upload )); then

        ensure_tool gh
        gh auth status --hostname "${host}" >/dev/null 2>&1 || die "CLI not authenticated for host: ${host}"

        [[ -n "${title}" ]] || { local os="$(os_name)"; is_wsl && os="wsl"; title="${os}${name:+-${name}}"; }
        title="${title^^}"

        GH_HOST="${host}" run gh ssh-key add "${pub}" --title "${title}" --type authentication
        success "SSH key uploaded : ${title}"

    fi

    git rev-parse --show-toplevel >/dev/null 2>&1 && git_keymap_set "${base}" >/dev/null 2>&1 || true

    success "OK: key created -> ${base}"
    success "Public key:"
    cat -- "${pub}"

}
cmd_changelog () {

    ensure_tool grep mktemp mv date tail git

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

cmd_clone () {

    ensure_tool git
    source <(parse "$@" -- :repo dest auth host)

    local url="${repo}"
    local auth="${auth:-${GIT_AUTH:-ssh}}"
    local host="${host:-${GIT_HOST:-github.com}}"

    if [[ "${repo}" != *"://"* && "${repo}" != git@*:* && "${repo}" != ssh://* ]]; then

        local path="$(git_norm_path_git "${repo}")"

        if [[ "${auth,,}" == http* ]]; then url="$(git_build_https_url "${host}" "${path}")" || die "Can't build https url"
        else url="$(git_build_ssh_url "${host}" "${path}")" || die "Can't build ssh url"
        fi

    fi

    if [[ -n "${dest}" ]]; then run git clone "${kwargs[@]}" -- "${url}" "${dest}"
    else run git clone "${kwargs[@]}" -- "${url}"
    fi

}
cmd_pull () {

    ensure_tool git
    git_repo_guard
    source <(parse "$@" -- repo branch remote=origin auth host rebase:bool=true ff_only:bool)

    local url="" auth="${auth:-${GIT_AUTH:-ssh}}"
    local host="${host:-${GIT_HOST:-github.com}}"

    if [[ -n "${repo}" ]]; then

        if git remote get-url "${repo}" >/dev/null 2>&1; then
            remote="${repo}"
            url="$(git_remote_url "${remote}")"
        elif [[ "${repo}" == *"://"* || "${repo}" == git@*:* || "${repo}" == ssh://* ]]; then
            url="${repo}"
        else
            local path="$(git_norm_path_git "${repo}")"
            if [[ "${auth,,}" == http* ]]; then url="$(git_build_https_url "${host}" "${path}")" || die "Can't build https url"
            else url="$(git_build_ssh_url "${host}" "${path}")" || die "Can't build ssh url"
            fi
        fi

    else

        url="$(git_remote_url "${remote}")"
        [[ -n "${url}" ]] || die "Remote not found: ${remote}"

    fi

    [[ -n "${branch}" ]] || branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "${branch}" ]] || branch="$(cmd_default_branch --remote "${remote}" 2>/dev/null || true)"
    [[ -n "${branch}" ]] || die "Can't detect branch"

    local -a cmd=( pull )

    (( ff_only )) && cmd+=( --ff-only )
    (( rebase )) && (( ! ff_only )) && cmd+=( --rebase )

    cmd+=( "${kwargs[@]}" -- "${url}" "${branch}" )
    run git "${cmd[@]}"

}
cmd_init () {

    ensure_tool git
    source <(parse "$@" -- :repo branch=main remote=origin auth key host create:bool=true)

    local path="" url="" parsed=0 explicit=0 before_url="" after_url="" cur=""
    auth="${auth:-${GIT_AUTH:-ssh}}"
    host="${host:-${GIT_HOST:-github.com}}"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

        if git_initial_branch; then run git init -b "${branch}"
        else run git init; git_set_default_branch "${branch}"
        fi

    fi
    if [[ "${repo}" == *"://"* || "${repo}" == git@*:* || "${repo}" == ssh://* ]]; then
        explicit=1
    fi
    if [[ -n "${key}" && "${auth}" == "ssh" ]]; then

        local key_path="$(git_resolve_ssh_key "${key}")"
        [[ -f "${key_path}" ]] && git_keymap_set "${key_path}" >/dev/null 2>&1 || true
        [[ -f "${key_path}" ]] || cmd_ssh_key "${key}" "${host}" --upload

    fi

    before_url="$(git_remote_url "${remote}")"

    if (( create )) && (( explicit == 0 )) && [[ "$(type -t cmd_new_repo)" == "function" ]]; then
        cmd_new_repo "${repo}" "${kwargs[@]}"
    fi

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
  
    local kind="" target="" safe="" ssh_cmd="" target_is_url=0

    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")
    [[ -n "${kind}" && -n "${target}" ]] || die "Failed to resolve git auth for remote '${remote}'."
    [[ "${target}" == http://* || "${target}" == https://* ]] && target_is_url=1

    (( f )) && force=1
    (( log )) && changelog=1

    [[ -z "${tag}" ]] && tag="${t}"
    (( release )) && [[ -z "${tag}" ]] && tag="auto"

    if [[ -z "${branch}" ]]; then
        branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        [[ -n "${branch}" ]] || die "Detached HEAD. Use --branch <name>."
    fi
    if [[ -n "${tag}" ]]; then

        [[ "${tag}" == "auto" ]] && tag="$(cmd_tag)"
        tag="$(git_norm_tag "${tag}")"
        [[ -z "${message}" ]] && message="Track ${tag} release."

    fi
    if [[ -z "$message" ]]; then
        [[ -n "${tag}" ]] && message="Track ${tag} release." || message="new commit"
    fi
    if [[ -n "${tag}" ]]; then

        if git_remote_has_tag "${kind}" "${ssh_cmd}" "${target}" "${tag}" && (( force == 0 )); then

            log "Tag exists on remote (${remote}/${tag}). Use --force to overwrite."
            tag=""

        elif (( changelog )); then

            cmd_changelog "${tag}" "${message}"

        fi

    fi

    git_guard_no_unborn "$(git_repo_root)"
    run_git "${kind}" "${ssh_cmd}" add -A || die "git add failed."

    if run_git "${kind}" "${ssh_cmd}" diff --cached --quiet >/dev/null 2>&1; then
        git_has_commit || die "Nothing to push: no commits yet. Make changes then run: push"
    else
        git_require_identity
        run_git "${kind}" "${ssh_cmd}" commit -m "${message}" || die "git commit failed."
    fi

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

        (( force )) && { run_git "${kind}" "${ssh_cmd}" push "${target}" --delete "${tag}" >/dev/null 2>&1 || true; }

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
cmd_release () {

    cmd_push --release --changelog "$@"

}

cmd_new_tag () {

    source <(parse "$@" -- :tag)
    cmd_push --tag "${tag}" --changelog "${kwargs[@]}"

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

cmd_current_branch () {

    git_repo_guard

    local b="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "${b}" ]] || return 1

    printf '%s\n' "${b}"

}
cmd_default_branch () {

    git_repo_guard
    source <(parse "$@" -- remote=origin auth key token token_env)

    git_require_remote "${remote}"

    local b="$(git symbolic-ref -q --short "refs/remotes/${remote}/HEAD" 2>/dev/null || true)"
    [[ -n "${b}" ]] && { printf '%s\n' "${b#"${remote}"/}"; return 0; }

    local kind="" target="" safe="" ssh_cmd="" line="" sym=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    while IFS= read -r line; do
        case "${line}" in
            "ref: refs/heads/"*" HEAD")
                sym="${line#ref: }"
                sym="${sym% HEAD}"
                break
            ;;
        esac
    done < <(run_git "${kind}" "${ssh_cmd}" ls-remote --symref "${target}" HEAD 2>/dev/null || true)

    local def="$(git config --get init.defaultBranch 2>/dev/null || true)"

    if [[ -n "${sym}" ]]; then
        printf '%s\n' "${sym#refs/heads/}"
        return 0
    fi
    if [[ -n "${def}" ]] && git show-ref --verify --quiet "refs/heads/${def}"; then
        printf '%s\n' "${def}"
        return 0
    fi

    for def in main master trunk production prod; do
        git show-ref --verify --quiet "refs/heads/${def}" && { printf '%s\n' "${def}"; return 0; }
    done

    def="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "${def}" ]] && { printf '%s\n' "${def}"; return 0; }

    return 1

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
    [[ -n "${kind}" && -n "${target}" ]] || die "Failed to resolve git auth for remote '${remote}'."

    ensure_tool awk
    run_git "${kind}" "${ssh_cmd}" ls-remote --tags --refs "${target}" | awk '{ sub("^refs/tags/","",$2); print $2 }'

}
cmd_all_branches () {

    git_repo_guard
    ensure_tool awk
    source <(parse "$@" -- remote=origin only_local:bool auth key token token_env)

    if (( only_local )); then
        git for-each-ref --format='%(refname:short)' "refs/heads" | awk 'NF && !seen[$0]++'
        return 0
    fi

    git_require_remote "${remote}"

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")
    [[ -n "${kind}" && -n "${target}" ]] || die "Failed to resolve git auth for remote '${remote}'."

    run_git "${kind}" "${ssh_cmd}" fetch --prune "${target}" >/dev/null 2>&1 || true

    git for-each-ref --format='%(refname:short)' "refs/heads" "refs/remotes/${remote}" |
    awk -v remote="${remote}" '
        NF == 0 { next }
        $0 == remote { next }
        $0 ~ ("^" remote "/$") { next }
        $0 ~ ("^" remote "/HEAD$") { next }

        {
            name = $0
            sub("^" remote "/", "", name)
            if (name != "" && !seen[name]++) print name
        }
    '

}

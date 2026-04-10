
gh_cmd () {

    ensure_pkg gh
    source <(parse "$@" -- profile)

    local p="${profile:-${GH_PROFILE:-${GIT_PROFILE:-"$(git_guess_ssh_key)"}}}"

    if [[ -z "${p}" ]]; then
        command gh "${kwargs[@]}"
        return $?
    fi

    local cfg="${p}"
    [[ "${cfg}" == /* ]] || cfg="${HOME}/.config/gh-${p}"

    if [[ ! -f "${cfg}/hosts.yml" ]]; then

        mkdir -p "${cfg}" 2>/dev/null || true
        local host="${GH_HOST:-${GIT_HOST:-}}"

        if [[ -n "${host}" ]]; then GH_CONFIG_DIR="${cfg}" command gh auth login --hostname "${host}" || return $?
        else GH_CONFIG_DIR="${cfg}" command gh auth login || return $?
        fi

    fi

    GH_CONFIG_DIR="${cfg}" command gh "${kwargs[@]}"
    return $?

}
gh_repo () {

    local repo="${1:-}"

    [[ -n "${repo}" ]] || repo="$(gh_cmd repo view --json nameWithOwner -q .nameWithOwner "${kwargs[@]}" 2>/dev/null || true)"
    [[ -n "${repo}" ]] || die "Cannot detect repo. Use --repo owner/repo"

    if [[ "${repo}" != */* ]]; then

        local owner="$(gh_cmd api user -q .login "${kwargs[@]}" 2>/dev/null || true)"
        [[ -n "${owner}" ]] || die "Cannot detect owner. Login to gh or pass --repo owner/repo"

        repo="${owner}/${repo}"

    fi

    printf '%s\n' "${repo}"

}
gh_file_keys () {

    local file="${1:-}" line="" k=""

    while IFS= read -r line || [[ -n "${line}" ]]; do

        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"

        [[ -n "${line}" ]] || continue
        [[ "${line}" == \#* ]] && continue
        [[ "${line}" == export[[:space:]]* ]] && line="${line#export }"

        case "${line}" in
            [A-Za-z_]*=*) ;;
            *) continue ;;
        esac

        k="${line%%=*}"
        k="${k%"${k##*[![:space:]]}"}"

        [[ "${k}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        printf '%s\n' "${k}"

    done < "${file}"

}
gh_set_var () {

    source <(parse "$@" -- :action :type :repo :name value force:bool)

    if [[ "${action}" == "remove" ]]; then

        (( force )) || confirm "Delete ${type} '${name}' from ${repo}?" || return 0
        gh_cmd "${type}" delete "${name}" --repo "${repo}" "${kwargs[@]}"
        return 0

    fi

    gh_cmd "${type}" set "${name}" --repo "${repo}" --body "${value}" "${kwargs[@]}"

}

gh_cleanup_vars () {

    source <(parse "$@" -- :type :repo :file)

    local -A keep=()
    local remote_k="" k="" have_keep=0

    while IFS= read -r k || [[ -n "${k}" ]]; do

        keep["${k^^}"]=1
        have_keep=1

    done < <(gh_file_keys "${file}")

    (( have_keep )) || { warn "cleanup: no keys found in file -> skip"; return 0; }

    while IFS= read -r remote_k || [[ -n "${remote_k}" ]]; do

        [[ -n "${remote_k}" && -z "${keep["${remote_k^^}"]+x}" ]] || continue
        gh_set_var remove "${type}" "${repo}" "${remote_k}" "${kwargs[@]}"

    done < <(gh_cmd "${type}" list --repo "${repo}" "${kwargs[@]}" --json name -q '.[].name' 2>/dev/null || true)

}
gh_sync_vars () {

    source <(parse "$@" -- :type :repo :file force:bool)

    [[ -f "${file}" ]] || die "File not found: ${file}"

    gh_cmd "${type}" set -f "${file}" --repo "${repo}" "${kwargs[@]}"
    (( force )) && gh_cleanup_vars "${type}" "${repo}" "${file}" "${kwargs[@]}" --force

    return 0

}
gh_var_action () {

    source <(parse "$@" -- action type repo name value file force:bool)
    repo="$(gh_repo "${repo}")"

    if [[ "${action}" == "sync" ]]; then

        local root="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"

        if [[ -z "${file}" && "${type}" == "secret" ]]; then

            file="${root}/.secrets"
            [[ -f "${file}" ]] || file="${root}/.secrets.example"
            [[ -f "${file}" ]] || file="${root}/.secrets.dev"
            [[ -f "${file}" ]] || file="${root}/.secrets.local"
            [[ -f "${file}" ]] || file="${root}/.secrets.stg"
            [[ -f "${file}" ]] || file="${root}/.secrets.stage"
            [[ -f "${file}" ]] || file="${root}/.secrets.prod"
            [[ -f "${file}" ]] || file="${root}/.secrets.production"

        elif [[ -z "${file}" ]]; then

            file="${root}/.vars"
            [[ -f "${file}" ]] || file="${root}/.vars.example"
            [[ -f "${file}" ]] || file="${root}/.vars.dev"
            [[ -f "${file}" ]] || file="${root}/.vars.local"
            [[ -f "${file}" ]] || file="${root}/.vars.stg"
            [[ -f "${file}" ]] || file="${root}/.vars.stage"
            [[ -f "${file}" ]] || file="${root}/.vars.prod"
            [[ -f "${file}" ]] || file="${root}/.vars.production"
            [[ -f "${file}" ]] || file="${root}/.env"
            [[ -f "${file}" ]] || file="${root}/.env.example"
            [[ -f "${file}" ]] || file="${root}/.env.dev"
            [[ -f "${file}" ]] || file="${root}/.env.local"
            [[ -f "${file}" ]] || file="${root}/.env.stg"
            [[ -f "${file}" ]] || file="${root}/.env.stage"
            [[ -f "${file}" ]] || file="${root}/.env.prod"
            [[ -f "${file}" ]] || file="${root}/.env.production"

        fi

        [[ -f "${file}" ]] || return 0

        gh_sync_vars "${type}" "${repo}" "${file}" "${force}" "${kwargs[@]}"

    else

        case "${action}" in add|remove) ;; *) die "Invalid --action (use add|remove)" ;; esac
        case "${type}" in secret|variable) ;; *) die "Invalid --type (use variable|secret)" ;; esac

        [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Invalid ${type} key: ${name}"

        gh_set_var "${action}" "${type}" "${repo}" "${name}" "${value}" "${force}" "${kwargs[@]}"

    fi

}
gh_clear_vars () {

    source <(parse "$@" -- type repo force:bool)

    repo="$(gh_repo "${repo}")"
    (( force )) || confirm "Delete all ${type}s from ${repo}?" || return 0

    while IFS= read -r name || [[ -n "${name}" ]]; do

        [[ -n "${name}" ]] || continue
        gh_set_var remove "${type}" "${repo}" "${name}" "${kwargs[@]}" --force

    done < <(gh_cmd "${type}" list --repo "${repo}" "${kwargs[@]}" --json name -q '.[].name' 2>/dev/null || true)

}

gh_new_env () {

    source <(parse "$@" -- :name repo)

    repo="$(gh_repo "${repo}")"
    gh_cmd api -X PUT "repos/${repo}/environments/${name}" "${kwargs[@]}"

}
gh_remove_env () {

    source <(parse "$@" -- :name repo force:bool)

    repo="$(gh_repo "${repo}")"
    (( force )) || confirm "Delete environment '${name}' from ${repo}?" || return 0

    gh_cmd api -X DELETE "repos/${repo}/environments/${name}" "${kwargs[@]}"

}
gh_env_list () {

    source <(parse "$@" -- name repo count:bool ids:bool names:bool json:bool)

    repo="$(gh_repo "${repo}")"
    local mode="full"

    if (( json )); then mode="json"
    elif (( ids )); then mode="ids"
    elif (( names )); then mode="names"
    fi

    if (( count )); then
        
        if [[ -n "${name}" ]]; then gh_cmd api "repos/${repo}/environments/${name}" "${kwargs[@]}" >/dev/null 2>&1 && printf '1\n' || printf '0\n'
        else gh_cmd api "repos/${repo}/environments" --jq '.total_count' "${kwargs[@]}"
        fi

        return 0

    fi
    if [[ -n "${name}" ]]; then

        case "${mode}" in
            ids) gh_cmd api "repos/${repo}/environments/${name}" "${kwargs[@]}" --jq '.id' ;;
            names) gh_cmd api "repos/${repo}/environments/${name}" "${kwargs[@]}" --jq '.name' ;;
            *) gh_cmd api "repos/${repo}/environments/${name}" "${kwargs[@]}" ;;
        esac

        return 0

    fi

    case "${mode}" in
        ids) gh_cmd api "repos/${repo}/environments" "${kwargs[@]}" --jq '.environments[].id' ;;
        names) gh_cmd api "repos/${repo}/environments" "${kwargs[@]}" --jq '.environments[].name' ;;
        *) gh_cmd api "repos/${repo}/environments" "${kwargs[@]}" ;;
    esac

}
gh_var_list () {

    source <(parse "$@" -- type name repo names:bool values:bool json:bool info:bool)

    repo="$(gh_repo "${repo}")"
    local mode="full"

    if (( info )); then mode="info"
    elif (( json )); then mode="json"
    elif (( names && values )); then mode="full"
    elif (( names )); then mode="names"
    elif (( values )); then mode="values"
    fi

    if [[ -n "${name}" ]]; then

        if [[ "${type}" == "secret" ]]; then

            case "${mode}" in
                names) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" --json name -q ".[] | select(.name == \"${name^^}\") | .name" ;;
                values) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" --json name -q ".[] | select(.name == \"${name^^}\") | \"******\"" ;;
                json) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" --json name ;;
                info) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" ;;
                *) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" --json name -q ".[] | select(.name == \"${name^^}\") | \"\(.name) = ******\"" ;;
            esac

        else

            case "${mode}" in
                names) gh_cmd variable get "${name^^}" --repo "${repo}" "${kwargs[@]}" --json name -q '.name' ;;
                values) gh_cmd variable get "${name^^}" --repo "${repo}" "${kwargs[@]}" --json value -q '.value' ;;
                json) gh_cmd variable get "${name^^}" --repo "${repo}" "${kwargs[@]}" --json name,value ;;
                info) gh_cmd variable get "${name^^}" --repo "${repo}" "${kwargs[@]}" ;;
                *) gh_cmd variable get "${name^^}" --repo "${repo}" "${kwargs[@]}" --json name,value -q '"\(.name) = \(.value)"' ;;
            esac

        fi

        return 0

    fi
    if [[ "${type}" == "secret" ]]; then

        case "${mode}" in
            names) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" --json name -q '.[].name' ;;
            values) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" --json name -q '.[].name | "******"' ;;
            json) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" --json name ;;
            info) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" ;;
            *) gh_cmd secret list --repo "${repo}" "${kwargs[@]}" --json name -q '.[] | "\(.name) = ******"' ;;
        esac

        return 0

    fi

    case "${mode}" in
        names) gh_cmd variable list --repo "${repo}" "${kwargs[@]}" --json name -q '.[].name' ;;
        values) gh_cmd variable list --repo "${repo}" "${kwargs[@]}" --json value -q '.[].value' ;;
        json) gh_cmd variable list --repo "${repo}" "${kwargs[@]}" --json name,value ;;
        info) gh_cmd variable list --repo "${repo}" "${kwargs[@]}" ;;
        *) gh_cmd variable list --repo "${repo}" "${kwargs[@]}" --json name,value -q '.[] | "\(.name) = \(.value)"' ;;
    esac

}

gh_new_repo () {

    ensure_pkg git
    source <(parse "$@" -- :name private:bool)

    local full="${name}" ssh_url=""

    if [[ "${full}" != */* ]]; then

        local owner="$(gh_cmd api user -q .login "${kwargs[@]}" 2>/dev/null || true)"
        [[ -n "${owner}" ]] || die "repo: use owner/repo (cannot detect owner)"
        full="${owner}/${full}"

    fi

    (( private )) && kwargs+=( --private ) || kwargs+=( --public )
    gh_cmd repo view "${full}" "${kwargs[@]}" >/dev/null 2>&1 || gh_cmd repo create "${full}" "${kwargs[@]}"

    ssh_url="$(gh_cmd repo view "${full}" --json sshUrl -q .sshUrl "${kwargs[@]}" 2>/dev/null || true)"
    [[ -n "${ssh_url}" ]] || die "Cannot detect sshUrl for repo: ${full}"

    git remote get-url origin >/dev/null 2>&1 || git remote add origin "${ssh_url}"

}
gh_remove_repo () {

    source <(parse "$@" -- :name force:bool)

    local full="${name}"
    (( YES || force )) && kwargs+=( --yes )

    if [[ "${full}" != */* ]]; then

        local owner="$(gh_cmd api user -q .login "${kwargs[@]}" 2>/dev/null || true)"
        [[ -n "${owner}" ]] || die "repo: use owner/repo (cannot detect owner)"

        full="${owner}/${full}"

    fi

    (( force )) || confirm "Delete repository: '${full}'?" || return 0
    gh_cmd repo delete "${full}" "${kwargs[@]}"

}

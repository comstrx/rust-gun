
gh_path () {

    local p="${1:-}"

    [[ -n "${p}" ]] || { printf '%s\n' ""; return 0; }

    [[ "${p}" == gh ]] && p="${HOME}/.config/gh"
    [[ "${p}" == /* ]] || p="${HOME}/.config/gh-${p}"

    printf '%s\n' "${p}"

}
gh_profile () {

    local profile="${1:-}"
    [[ -n "${profile}" ]] && { printf '%s\n' "${profile}"; return 0; }

    local p="$(git_guess_ssh_key 2>/dev/null || true)"
    local cfg="$(gh_path "${p}")"

    [[ -f "${cfg}/hosts.yml" ]] && { printf '%s\n' "${p}"; return 0; }
    printf '%s\n' "${GH_PROFILE:-}"

}
gh_cmd () {

    ensure_tool gh mkdir

    local host="" profile="" default_host=0
    local -a kwargs=()

    while (( $# )); do
        case "${1}" in
            --host)    host="${2:-}";    shift 2 || break ;;
            --profile) profile="${2:-}"; shift 2 || break ;;
            *)         kwargs+=( "$1" ); shift || true ;;
        esac
    done

    host="${host:-${GH_HOST:-}}"
    [[ -z "${host}" || "${host}" == "github.com" ]] && default_host=1

    local prf="$(gh_profile "${profile}")"
    local cfg="$(gh_path "${prf}")" 

    if [[ -z "${prf}" ]]; then

        if (( default_host )); then command gh "${kwargs[@]}"
        else GH_HOST="${host}" command gh "${kwargs[@]}"
        fi

    else

        if [[ ! -f "${cfg}/hosts.yml" ]]; then

            is_ci && die "gh auth missing for profile/host in CI"
            mkdir -p "${cfg}" 2>/dev/null

            if (( default_host )); then GH_CONFIG_DIR="${cfg}" command gh auth login
            else GH_CONFIG_DIR="${cfg}" command gh auth login --hostname "${host}"
            fi

        fi

        if (( default_host )); then GH_CONFIG_DIR="${cfg}" command gh "${kwargs[@]}"
        else GH_CONFIG_DIR="${cfg}" GH_HOST="${host}" command gh "${kwargs[@]}"
        fi

    fi

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
gh_keys () {

    local file="${1:-}" line="" k=""

    [[ -f "${file}" ]] || return 1

    while IFS= read -r line || [[ -n "${line}" ]]; do

        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"

        [[ -n "${line}" ]] || continue
        [[ "${line}" == \#* ]] && continue

        if [[ "${line}" == export[[:space:]]* ]]; then
            line="${line#export}"
            line="${line#"${line%%[![:space:]]*}"}"
        fi

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
gh_vars () {

    local root="${1:-}" name="" file=""
    shift || true

    for name in "$@"; do

        file="${name}"

        [[ -f "${file}" ]] || file="${root}/${name}"
        [[ -f "${file}" ]] || file="${root}/${name}.example"
        [[ -f "${file}" ]] || file="${root}/${name}.dev"
        [[ -f "${file}" ]] || file="${root}/${name}.local"
        [[ -f "${file}" ]] || file="${root}/${name}.stg"
        [[ -f "${file}" ]] || file="${root}/${name}.stage"
        [[ -f "${file}" ]] || file="${root}/${name}.prod"
        [[ -f "${file}" ]] || file="${root}/${name}.production"
        [[ -f "${file}" ]] || continue

        printf '%s\n' "${file}"
        return 0

    done

    return 1

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
gh_clean_vars () {

    source <(parse "$@" -- :type :repo :file)

    local -A keep=()
    local remote_k="" k="" have_keep=0

    while IFS= read -r k || [[ -n "${k}" ]]; do

        keep["${k^^}"]=1
        have_keep=1

    done < <(gh_keys "${file}")

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
    (( force )) && gh_clean_vars "${type}" "${repo}" "${file}" "${kwargs[@]}" --force

    return 0

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
gh_var_action () {

    source <(parse "$@" -- action type repo name value file force:bool)
    repo="$(gh_repo "${repo}")"

    if [[ "${action}" == "sync" ]]; then

        local root="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"

        if [[ -z "${file}" && "${type}" == "secret" ]]; then file="$(gh_vars "${root}" .secrets secrets .sec sec)" || true
        elif [[ -z "${file}" ]]; then file="$(gh_vars "${root}" .vars vars .env env .var var)" || true
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

gh_new_ssh () {

    source <(parse "$@" -- name host alias title profile upload:bool=true login:bool=true)

    host="${host:-${GIT_HOST:-${GH_HOST:-github.com}}}"

    [[ -n "${name}" ]] || name="$(git_guess_ssh_key 2>/dev/null || true)"
    [[ -n "${name}" ]] || die "ssh: cannot guess key name. Use --name <key>"

    local base="$(git_new_ssh_key "${name}" "${host}" "${alias}" "${kwargs[@]}")"
    local path="${base}.pub"
    local key="${base##*/}"

    [[ -f "${path}" ]] || die "SSH public key not found: ${path}"

    success "OK: SSH key created: ${base}"
    cat -- "${path}"

    if git rev-parse --show-toplevel >/dev/null 2>&1; then

        git_keymap_set "${key}" >/dev/null 2>&1
        (( login )) && [[ -z "${profile}" ]] && profile="${key}"

    fi
    if (( upload )); then

        if [[ -z "${title}" ]]; then

            local os="$(os_name)"
            is_wsl && os="${os}-wsl"
            is_ci && os="${os}-ci"

            title="${os^^}-${key^^}"

        fi

        gh_cmd ssh-key add "${path}" --title "${title}" --type authentication --host "${host}" --profile "${profile}" "${kwargs[@]}"
        success "OK: Public key uploaded: ${title}"

    fi

}
gh_remove_ssh () {

    source <(parse "$@" -- :key force:bool)

    local id="${key}"

    [[ "${id}" =~ ^[0-9]+$ ]] || id="$(gh_cmd api user/keys "${kwargs[@]}" --jq ".[] | select(.title == \"${key}\") | .id" 2>/dev/null || true)"
    [[ -n "${id}" ]] || die "ssh key not found: ${key}"

    (( force )) || confirm "Delete ssh key '${key}'?" || return 0
    gh_cmd ssh-key delete "${id}" "${kwargs[@]}"

}
gh_new_repo () {

    ensure_tool git
    source <(parse "$@" -- :name private:bool)

    local full="${name}" ssh_url=""

    if [[ "${full}" != */* ]]; then

        local owner="$(gh_cmd api user -q .login "${kwargs[@]}" 2>/dev/null || true)"
        [[ -n "${owner}" ]] || die "repo: use owner/repo (cannot detect owner)"
        full="${owner}/${full}"

    fi

    local -a cmd=()
    (( private )) && cmd+=( --private ) || cmd+=( --public )
    gh_cmd repo view "${full}" "${kwargs[@]}" >/dev/null 2>&1 || gh_cmd repo create "${full}" "${cmd[@]}" "${kwargs[@]}"

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

gh_ssh_list () {

    source <(parse "$@" -- id count:bool ids:bool titles:bool keys:bool json:bool)

    local mode="full"
    local endpoint="user/keys"

    if (( json )); then mode="json"
    elif (( ids )); then mode="ids"
    elif (( titles )); then mode="titles"
    elif (( keys )); then mode="keys"
    fi

    if (( count )); then

        if [[ -n "${id}" ]]; then

            if gh_cmd api "${endpoint}" "${kwargs[@]}" --jq ".[] | select(.id == ${id}) | .id" | grep -q .; then printf '1\n'
            else printf '0\n'
            fi

        else

            gh_cmd api "${endpoint}" "${kwargs[@]}" --jq 'length'

        fi

        return 0

    fi
    if [[ -n "${id}" ]]; then

        case "${mode}" in
            ids) gh_cmd api "${endpoint}" "${kwargs[@]}" --jq ".[] | select(.id == ${id}) | .id" ;;
            titles) gh_cmd api "${endpoint}" "${kwargs[@]}" --jq ".[] | select(.id == ${id}) | .title" ;;
            keys) gh_cmd api "${endpoint}" "${kwargs[@]}" --jq ".[] | select(.id == ${id}) | .key" ;;
            *) gh_cmd api "${endpoint}" "${kwargs[@]}" --jq ".[] | select(.id == ${id}) | { id, title, key }" ;;
        esac

        return 0

    fi

    case "${mode}" in
        ids) gh_cmd api "${endpoint}" "${kwargs[@]}" --jq '.[].id' ;;
        titles) gh_cmd api "${endpoint}" "${kwargs[@]}" --jq '.[].title' ;;
        keys) gh_cmd api "${endpoint}" "${kwargs[@]}" --jq '.[].key' ;;
        *) gh_cmd api "${endpoint}" "${kwargs[@]}" --jq '.[] | { id, title, key }' ;;
    esac

}
gh_repo_list () {

    source <(parse "$@" -- owner name limit source visibility fork:bool archived:bool names:bool urls:bool ssh:bool json:bool count:bool)

    local mode="full"
    local -a owner_arg=()
    local -a args=()

    if (( json )); then mode="json"
    elif (( ssh )); then mode="ssh"
    elif (( urls )); then mode="urls"
    elif (( names )); then mode="names"
    fi

    [[ -n "${owner}" ]] && owner_arg+=( "${owner}" )
    [[ -n "${limit}" ]] && args+=( --limit "${limit}" )
    [[ -n "${source}" ]] && args+=( --source "${source}" )
    [[ -n "${visibility}" ]] && args+=( --visibility "${visibility}" )
    (( fork )) && args+=( --fork )
    (( archived )) && args+=( --archived )

    if (( count )); then

        if [[ -n "${name}" ]]; then

            if gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json nameWithOwner -q ".[] | select(.nameWithOwner == \"${name}\" or (.nameWithOwner | endswith(\"/${name}\"))) | .nameWithOwner" | grep -q .; then printf '1\n'
            else printf '0\n'
            fi

        else
            gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json nameWithOwner -q 'length'

        fi

        return 0

    fi
    if [[ -n "${name}" ]]; then


        case "${mode}" in
            names) gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json nameWithOwner -q ".[] | select(.nameWithOwner == \"${name}\" or (.nameWithOwner | endswith(\"/${name}\"))) | .nameWithOwner" ;;
            urls) gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json nameWithOwner,url -q ".[] | select(.nameWithOwner == \"${name}\" or (.nameWithOwner | endswith(\"/${name}\"))) | .url" ;;
            ssh) gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json nameWithOwner,sshUrl -q ".[] | select(.nameWithOwner == \"${name}\" or (.nameWithOwner | endswith(\"/${name}\"))) | .sshUrl" ;;
            *) gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json nameWithOwner,url,sshUrl,isPrivate,isFork,isArchived -q ".[] | select(.nameWithOwner == \"${name}\" or (.nameWithOwner | endswith(\"/${name}\")))" ;;
        esac

        return 0

    fi

    case "${mode}" in
        names) gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json nameWithOwner -q '.[].nameWithOwner' ;;
        urls) gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json url -q '.[].url' ;;
        ssh) gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json sshUrl -q '.[].sshUrl' ;;
        *) gh_cmd repo list "${owner_arg[@]}" "${kwargs[@]}" "${args[@]}" --json nameWithOwner,url,sshUrl,isPrivate,isFork,isArchived ;;
    esac

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

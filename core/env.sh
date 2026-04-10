
return_or_exit () {

    local code="${1:-1}"

    [[ "${code}" =~ ^[0-9]+$ ]] || code=1
    if [[ "${-}" == *i* ]]; then return "${code}" 2>/dev/null || exit "${code}"; fi

    exit "${code}"

}
message () {

    local tag="${1-}"
    shift || true

    local IFS=' '
    (( $# )) || { printf '%s\n' "${tag}" >&2; return 0; }

    printf '%s %s\n' "${tag}" "$*" >&2

}
messageln () {

    local tag="${1-}"
    shift || true

    local IFS=' '
    (( $# )) || { printf '%s\n' "${tag}" >&2; return 0; }

    printf '\n%s %s\n' "${tag}" "$*" >&2

}
info () {

    message "💥" "$@";

}
success () {

    message "✅" "$@";

}
warn () {

    message "⚠️" "$@";

}
error () {

    message "❌" "$@";

}
info_ln () {

    messageln "💥" "$@";

}
success_ln () {

    messageln "✅" "$@";

}
warn_ln () {

    messageln "⚠️" "$@";

}
error_ln () {

    messageln "❌" "$@";

}
log () {

    local IFS=' '

    (( $# )) || { printf '\n' >&2; return 0; }
    printf '%s\n' "$*" >&2

}
print () {

    local IFS=' '

    (( $# )) || { printf '\n'; return 0; }
    printf '%s\n' "$*"

}
eprint () {

    local IFS=' '

    (( $# )) || { printf '\n' >&2; return 0; }
    printf '%s\n' "$*" >&2

}
die () {

    local msg="${1-}" code="${2:-1}"

    [[ -n "${msg}" ]] && error "${msg}"
    return_or_exit "${code}"

}

input () {

    local prompt="${1-}" def="${2-}" line="" tty="/dev/tty" rc=0

    if [[ -c "${tty}" && -r "${tty}" && -w "${tty}" ]]; then
        [[ -n "${prompt}" ]] && printf '%s' "${prompt}" >"${tty}"
        IFS= read -r line <"${tty}" || rc=$?
    else
        [[ -n "${prompt}" ]] && printf '%s' "${prompt}" >&2
        IFS= read -r line || rc=$?
    fi

    if (( rc != 0 )); then
        [[ -n "${def}" ]] && { printf '%s' "${def}"; return 0; }
        return "${rc}"
    fi

    [[ -z "${line}" && -n "${def}" ]] && line="${def}"
    printf '%s' "${line}"

}
input_bool () {

    local prompt="${1-}" def="${2-}" tries="${3:-3}"
    local def_norm="" v="" i=0

    case "${def}" in
        1|true|TRUE|True|yes|YES|Yes|y|Y) def_norm="1" ;;
        0|false|FALSE|False|no|NO|No|n|N) def_norm="0" ;;
    esac

    for (( i=0; i<tries; i++ )); do

        v="$(input "${prompt}" "${def}")" || return $?

        case "${v}" in
            1|true|TRUE|True|yes|YES|Yes|y|Y) printf '1'; return 0 ;;
            0|false|FALSE|False|no|NO|No|n|N) printf '0'; return 0 ;;
            "") [[ -n "${def_norm}" ]] && { printf '%s' "${def_norm}"; return 0; } ;;
        esac

        eprint "Invalid bool. Use: y/n, yes/no, 1/0, true/false"

    done

    die "input_bool: too many invalid attempts" 2

}
input_int () {

    local prompt="${1-}" def="${2-}" tries="${3:-3}" v="" i=0

    for (( i=0; i<tries; i++ )); do

        v="$(input "${prompt}" "${def}")" || return $?
        [[ -z "${v}" && -n "${def}" ]] && v="${def}"
        [[ "${v}" =~ ^-?[0-9]+$ ]] && { printf '%s' "${v}"; return 0; }

        eprint "Invalid int. Example: 0, 12, -7"

    done

    die "input_int: too many invalid attempts" 2

}
input_uint () {

    local prompt="${1-}" def="${2-}" tries="${3:-3}" v="" i=0

    for (( i=0; i<tries; i++ )); do

        v="$(input "${prompt}" "${def}")" || return $?
        [[ -z "${v}" && -n "${def}" ]] && v="${def}"
        [[ "${v}" =~ ^[0-9]+$ ]] && { printf '%s' "${v}"; return 0; }

        eprint "Invalid uint. Example: 0, 12, 7"

    done

    die "input_uint: too many invalid attempts" 2

}
input_float () {

    local prompt="${1-}" def="${2-}" tries="${3:-3}" v="" i=0

    for (( i=0; i<tries; i++ )); do

        v="$(input "${prompt}" "${def}")" || return $?
        [[ -z "${v}" && -n "${def}" ]] && v="${def}"
        [[ "${v}" =~ ^[+-]?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]] && { printf '%s' "${v}"; return 0; }

        eprint "Invalid float. Example: 0, 12.5, -7, .3"

    done

    die "input_float: too many invalid attempts" 2

}
input_char () {

    local prompt="${1-}" def="${2-}" tries="${3:-3}" v="" i=0

    for (( i=0; i<tries; i++ )); do

        v="$(input "${prompt}" "${def}")" || return $?
        [[ -z "${v}" && -n "${def}" ]] && v="${def}"
        (( ${#v} == 1 )) && { printf '%s' "${v}"; return 0; }

        eprint "Invalid char. Example: a"

    done

    die "input_char: too many invalid attempts" 2

}
input_pass () {

    local prompt="${1-}" tty="/dev/tty" line=""

    [[ -c "${tty}" && -r "${tty}" && -w "${tty}" ]] || die "input_pass: no /dev/tty" 2

    [[ -n "${prompt}" ]] && printf '%s' "${prompt}" >"${tty}"
    IFS= read -r -s line <"${tty}" || return $?
    printf '\n' >"${tty}"

    printf '%s' "${line}"

}
input_path () {

    local prompt="${1-}" def="${2-}" mode="${3:-any}" tries="${4:-3}"
    local p="" i=0

    for (( i=0; i<tries; i++ )); do

        p="$(input "${prompt}" "${def}")" || return $?

        [[ -z "${p}" && -n "${def}" ]] && p="${def}"
        [[ -n "${p}" ]] || { eprint "Path is required"; continue; }

        case "${mode}" in
            any)    printf '%s' "${p}"; return 0 ;;
            exists) [[ -e "${p}" ]] && { printf '%s' "${p}"; return 0; } ;;
            file)   [[ -f "${p}" ]] && { printf '%s' "${p}"; return 0; } ;;
            dir)    [[ -d "${p}" ]] && { printf '%s' "${p}"; return 0; } ;;
            *)      die "input_path: invalid mode '${mode}'" 2 ;;
        esac

        eprint "Invalid path for mode '${mode}': ${p}"

    done

    die "input_path: too many invalid attempts" 2

}
confirm () {

    local msg="${1:-Continue?}" def="${2:-N}" hint="[y/N]: " d_is_yes=0 ans=""
    (( YES )) && return 0

    case "${def}" in
        y|Y|yes|YES|Yes|1|true|TRUE|True) d_is_yes=1 ;;
    esac

    (( d_is_yes )) && hint="[Y/n]: "
    ans="$(input "${msg} ${hint}" "${def}")" || return $?

    case "${ans}" in
        y|Y|yes|YES|Yes|yep|Yep|YEP|1|true|TRUE|True) return 0 ;;
        n|N|no|NO|No|0|false|FALSE|False) return 1 ;;
        "") (( d_is_yes )) && return 0 || return 1 ;;
        *) return 1 ;;
    esac

}
confirm_bool () {

    if confirm "$@"; then
        printf '1'
        return 0
    fi

    printf '0'
    return 1

}
choose () {

    local prompt="${1:-Choose:}" pick="" i=0 try=0
    shift || true

    local -a items=( "$@" )
    (( ${#items[@]} )) || die "choose: missing items" 2

    eprint "${prompt}"

    for (( i=0; i<${#items[@]}; i++ )); do
        eprint "  $(( i + 1 ))) ${items[$i]}"
    done

    for (( try=0; try<3; try++ )); do

        pick="$(input "Enter number [1-${#items[@]}]: ")" || return $?

        [[ "${pick}" =~ ^[0-9]+$ ]] || { eprint "Invalid number"; continue; }
        (( pick >= 1 && pick <= ${#items[@]} )) || { eprint "Out of range"; continue; }

        printf '%s' "${items[$(( pick - 1 ))]}"
        return 0

    done

    die "choose: too many invalid attempts" 2

}

cd_root () {

    cd -- "${ROOT_DIR}" || die "cd_root: cannot cd to ROOT_DIR='${ROOT_DIR}'"

}
cd_current_root () {

    local root="" dir="" up=0 max_up=50

    command -v git >/dev/null 2>&1 && root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "${root}" && -d "${root}" ]] && { cd -P -- "${root}" || return 1; return 0; }

    dir="$(pwd -P 2>/dev/null || true)"
    [[ -n "${dir}" ]] || { eprint "cd_current_root: cannot resolve PWD"; return 2; }

    while (( up < max_up )); do

        if [[ -e "${dir}/.git" || -e "${dir}/.hg" || -e "${dir}/.svn" \
           || -f "${dir}/Cargo.toml" || -f "${dir}/go.mod" || -f "${dir}/package.json" \
           || -f "${dir}/pyproject.toml" || -f "${dir}/requirements.txt" || -f "${dir}/Pipfile" || -f "${dir}/poetry.lock" \
           || -f "${dir}/composer.json" || -f "${dir}/conanfile.txt" || -f "${dir}/conanfile.py" \
           || -f "${dir}/Makefile" || -f "${dir}/justfile" || -f "${dir}/Taskfile.yml" || -f "${dir}/Taskfile.yaml" \
           || -f "${dir}/.tool-versions" || -f "${dir}/.env" || -f "${dir}/flake.nix" ]]; then

            cd -P -- "${dir}" || return 1
            return 0

        fi

        [[ "${dir}" == "/" ]] && break

        dir="$(dirname -- "${dir}")"
        up=$(( up + 1 ))

    done

    eprint "cd_current_root: cannot detect root"
    return 2

}
get_env () {

    local key="${1:-}" def="${2-}"

    [[ -n "${key}" ]] || { printf '%s' "${def}"; return 0; }
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { printf '%s' "${def}"; return 0; }

    if [[ -n "${!key+x}" ]]; then printf '%s' "${!key}"
    else printf '%s' "${def}"
    fi

}
run () {

    (( $# )) || return 0

    if (( VERBOSE )); then

        local s="" a="" q=""

        for a in "$@"; do

            q="$(printf '%q' "${a}")"

            if [[ -z "${s}" ]]; then s="${q}"
            else s="${s} ${q}"
            fi

        done

        eprint "+ ${s}"

    fi

    "$@"

}
has () {

    local cmd="${1:-}"

    [[ -n "${cmd}" ]] || return 1
    command -v -- "${cmd}" >/dev/null 2>&1

}
trap_on_err () {

    local handler="${1:-}" code="${2:-1}" cmd="${3-}" file="${4-}" line="${5-}"

    trap - ERR
    [[ -n "${handler}" ]] && declare -F "${handler}" >/dev/null 2>&1 && "${handler}" "${code}" "${cmd}" "${file}" "${line}" || true

    return_or_exit "${code}"

}
on_err () {

    local handler="${1:-}"

    [[ -n "${handler}" ]] || die "on_err: missing handler function name" 2
    declare -F "${handler}" >/dev/null 2>&1 || die "on_err: handler not found: ${handler}" 2

    set -E
    trap 'trap_on_err "'"${handler}"'" "$?" "${BASH_COMMAND}" "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" "${LINENO}"' ERR

}

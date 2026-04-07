
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf "%s\n" "env.sh: this file should not be run externally." >&2; exit 2; }
[[ -n "${ENV_LOADED:-}" ]] && return 0
ENV_LOADED=1

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
YES="${YES:-0}"
VERBOSE="${VERBOSE:-0}"

info () {

    local IFS=' '
    printf '%b\n' "💥 $*" >&2

}
success () {

    local IFS=' '
    printf '%b\n' "✅ $*" >&2

}
warn () {

    local IFS=' '
    printf '%b\n' "⚠️ $*" >&2

}
error () {

    local IFS=' '
    printf '%b\n' "❌ $*" >&2

}
log () {

    local IFS=' '
    (( $# )) || { printf '\n' >&2; return 0; }

    printf '%b\n' "$*" >&2

}
print () {

    local IFS=' '

    if (( $# == 0 )); then
        printf '\n'
        return 0
    fi

    printf '%b\n' "$*"

}
eprint () {

    local IFS=' '

    if (( $# == 0 )); then
        printf '\n' >&2
        return 0
    fi

    printf '%b\n' "$*" >&2

}
die () {

    local msg="${1-}" code="${2:-1}"

    [[ "${code}" =~ ^[0-9]+$ ]] || code=1
    [[ -n "${msg}" ]] && printf '%s\n' "❌ ${msg}" >&2
    [[ "${-}" == *i* && "${BASH_SOURCE[0]-}" != "${0-}" ]] && return "${code}"

    exit "${code}"

}

input () {

    local prompt="${1-}" def="${2-}"
    local tty="/dev/tty" line="" rc=0

    if [[ -c "${tty}" && -r "${tty}" && -w "${tty}" ]]; then

        [[ -n "${prompt}" ]] && printf '%b' "${prompt}" >"${tty}"
        rc=0
        IFS= read -r line <"${tty}" || rc=$?

    else

        [[ -n "${prompt}" ]] && printf '%b' "${prompt}" >&2
        rc=0
        IFS= read -r line || rc=$?

    fi

    if (( rc != 0 )); then

        [[ -n "${def}" ]] && { printf '%s' "${def}"; return 0; }
        return 1

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

        if [[ "${v}" =~ ^-?[0-9]+$ ]]; then
            printf '%s' "${v}"
            return 0
        fi

        eprint "Invalid int. Example: 0, 12, -7"

    done

    die "input_int: too many invalid attempts" 2

}
input_uint () {

    local prompt="${1-}" def="${2-}" tries="${3:-3}" v="" i=0

    for (( i=0; i<tries; i++ )); do

        v="$(input "${prompt}" "${def}")" || return $?
        [[ -z "${v}" && -n "${def}" ]] && v="${def}"

        if [[ "${v}" =~ ^[0-9]+$ ]]; then
            printf '%s' "${v}"
            return 0
        fi

        eprint "Invalid uint. Example: 0, 12, 7"

    done

    die "input_uint: too many invalid attempts" 2

}
input_float () {

    local prompt="${1-}" def="${2-}" tries="${3:-3}" v="" i=0

    for (( i=0; i<tries; i++ )); do

        v="$(input "${prompt}" "${def}")" || return $?
        [[ -z "${v}" && -n "${def}" ]] && v="${def}"

        if [[ "${v}" =~ ^[+-]?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]; then
            printf '%s' "${v}"
            return 0
        fi

        eprint "Invalid float. Example: 0, 12.5, -7, .3"

    done

    die "input_float: too many invalid attempts" 2

}
input_char () {

    local prompt="${1-}" def="${2-}" tries="${3:-3}" v="" i=0

    for (( i=0; i<tries; i++ )); do

        v="$(input "${prompt}" "${def}")" || return $?
        [[ -z "${v}" && -n "${def}" ]] && v="${def}"

        if (( ${#v} == 1 )); then
            printf '%s' "${v}"
            return 0
        fi

        eprint "Invalid char. Example: a"

    done

    die "input_char: too many invalid attempts" 2

}
input_pass () {

    local prompt="${1-}" tty="/dev/tty" line=""

    [[ -c "${tty}" && -r "${tty}" && -w "${tty}" ]] || die "input_pass: no /dev/tty (cannot securely read password)" 2
    [[ -n "${prompt}" ]] && printf '%b' "${prompt}" >"${tty}"

    if IFS= read -r -s line <"${tty}" 2>/dev/null; then
        printf '\n' >"${tty}"
        printf '%s' "${line}"
        return 0
    fi

    command -v stty >/dev/null 2>&1 || die "input_pass: cannot disable echo (read -s failed, stty missing)" 2

    local stty_old="$(stty -g <"${tty}" 2>/dev/null || true)"
    local old_int="$(trap -p INT 2>/dev/null || true)"
    local old_term="$(trap -p TERM 2>/dev/null || true)"
    local old_return="$(trap -p RETURN 2>/dev/null || true)"
    local abort=0 rc=0

    __input_pass_restore () {

        [[ -n "${stty_old}" ]] && stty "${stty_old}" <"${tty}" 2>/dev/null || stty echo <"${tty}" 2>/dev/null || true

        if [[ -n "${old_int}" ]]; then eval "${old_int}"
        else trap - INT
        fi
        if [[ -n "${old_term}" ]]; then eval "${old_term}"
        else trap - TERM
        fi
        if [[ -n "${old_return}" ]]; then eval "${old_return}"
        else trap - RETURN
        fi

    }

    __input_pass_abort_int () { abort=130; __input_pass_restore; }
    __input_pass_abort_term () { abort=143; __input_pass_restore; }

    trap '__input_pass_abort_int' INT
    trap '__input_pass_abort_term' TERM
    trap '__input_pass_restore' RETURN

    stty -echo <"${tty}" 2>/dev/null || true

    rc=0
    IFS= read -r line <"${tty}" || rc=$?

    __input_pass_restore

    unset -f __input_pass_restore __input_pass_abort_int __input_pass_abort_term 2>/dev/null || true
    printf '\n' >"${tty}"

    (( abort )) && return "${abort}"
    (( rc != 0 )) && return "${rc}"

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
            any) printf '%s' "${p}"; return 0 ;;
            exists) [[ -e "${p}" ]] && { printf '%s' "${p}"; return 0; } ;;
            file) [[ -f "${p}" ]] && { printf '%s' "${p}"; return 0; } ;;
            dir) [[ -d "${p}" ]] && { printf '%s' "${p}"; return 0; } ;;
            *) die "input_path: invalid mode '${mode}'" 2 ;;
        esac

        eprint "Invalid path for mode '${mode}': ${p}"

    done

    die "input_path: too many invalid attempts" 2

}
confirm () {

    local msg="${1:-Continue?}" def="${2:-N}" hint="[y/N]: " d_is_yes=0
    (( YES )) && return 0

    case "${def}" in y|Y|yes|YES|Yes|1|true|TRUE|True) d_is_yes=1 ;; esac

    (( d_is_yes )) && hint="[Y/n]: "
    local ans="$(input "${msg} ${hint}" "${def}")" || return $?

    case "${ans}" in
        y|Y|yes|YES|Yes|yep|Yep|YEP|1|true|TRUE|True) return 0 ;;
        n|N|no|NO|No|0|false|FALSE|False) return 1 ;;
        "") (( d_is_yes )) && return 0 || return 1 ;;
    esac

    return 1

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

    local prompt="${1:-Choose:}"
    shift || true

    local -a items=( "$@" )
    (( ${#items[@]} )) || die "choose: missing items" 2

    local i=0
    eprint "${prompt}"
    for (( i=0; i<${#items[@]}; i++ )); do eprint "  $((i+1))) ${items[$i]}"; done

    local pick="$(input "Enter number [1-${#items[@]}]: ")" || return $?

    [[ "${pick}" =~ ^[0-9]+$ ]] || die "choose: invalid number" 2
    (( pick >= 1 && pick <= ${#items[@]} )) || die "choose: out of range" 2

    printf '%s' "${items[$((pick-1))]}"

}

os_name () {

    local u="$(uname -s 2>/dev/null || printf '%s' unknown)"

    case "${u}" in
        Linux)   printf '%s' linux ;;
        Darwin)  printf '%s' mac ;;
        MSYS*|MINGW*|CYGWIN*) printf '%s' windows ;;
        *)       printf '%s' unknown ;;
    esac

}
get_env () {

    local key="${1:-}" def="${2-}"

    [[ -n "${key}" ]] || { printf '%s' "${def}"; return 0; }
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { printf '%s' "${def}"; return 0; }

    if [[ -n "${!key+x}" ]]; then printf '%s' "${!key}"
    else printf '%s' "${def}"
    fi

}
cd_root () {

    cd -- "${ROOT_DIR:-}" || die "cd_root: cannot cd to ROOT_DIR='${ROOT_DIR:-}'"

}
cd_current_root () {

    local root="" up=0 max_up=50

    command -v git >/dev/null 2>&1 && root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "${root}" && -d "${root}" ]] && { cd -P -- "${root}" || return 1; return 0; }

    local dir="$(pwd -P 2>/dev/null || true)"
    [[ -n "${dir}" ]] || { echo "cd_current_root: cannot resolve PWD" >&2; return 2; }

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

    echo "cd_current_root: cannot detect root" >&2
    return 2

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

        printf '%s\n' "+ ${s}" >&2

    fi

    "$@"

}
has () {

    local cmd="${1:-}"
    [[ -n "${cmd}" ]] || return 1
    command -v -- "${cmd}" >/dev/null 2>&1

}
trap_on_err () {

    local handler="${1:-}" code="$?" || true
    local cmd="${BASH_COMMAND-}" file="${BASH_SOURCE[1]-}" line="${BASH_LINENO[0]-}"

    trap - ERR
    "${handler}" "${code}" "${cmd}" "${file}" "${line}" || true

    if [[ "${-}" == *i* && "${BASH_SOURCE[0]-}" != "${0-}" ]]; then
        return "${code}" 2>/dev/null || exit "${code}"
    fi

    exit "${code}"

}
on_err () {

    local handler="${1:-}"
    [[ -n "${handler}" ]] || die "on_err: missing handler function name" 2

    declare -F "${handler}" >/dev/null 2>&1 || die "on_err: handler not found: ${handler}" 2

    set -E
    trap 'trap_on_err "'"${handler}"'"' ERR

}

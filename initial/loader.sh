
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/boot.sh"

normalize () {

    local s="${1-}"

    s="${s//-/_}"
    s="${s//./_}"

    printf '%s' "${s}"

}
should_skip () {

    local name="${1-}" s=""
    shift || true

    [[ -n "${name}" ]] || return 0
    [[ "${name}" == _* ]] && return 0

    for s in "$@"; do
        [[ -n "${s}" ]] || continue
        [[ "${name}" == "${s}" ]] && return 0
    done

    return 1

}
load_walk () {

    local mode="${1-}"
    local dir="${2-}"
    local seen_ref="${3-}"
    local mods_ref="${4-}"

    shift 4 || true

    [[ -n "${mode}" ]] || die "load_walk: missing mode" 2
    [[ -n "${dir}" && -d "${dir}" ]] || return 0

    if [[ "${mode}" == "doc" ]]; then
        [[ -n "${seen_ref}" && -n "${mods_ref}" ]] || die "load_walk: doc mode requires seen/mods refs" 2
        local -n _seen="${seen_ref}"
        local -n _mods="${mods_ref}"
    fi

    local nullglob_was_set=0
    local file="" base="" name="" subdir="" sd=""
    local -a extra_skip=()

    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob

    (( $# > 0 )) && extra_skip=( "$@" ) || extra_skip=()

    for file in "${dir}"/*.sh; do

        base="${file##*/}"
        [[ -n "${base}" ]] || continue

        name="${base%.sh}"

        case "${mode}" in
            source)
                should_skip "${name}" "${extra_skip[@]-}" && continue

                source "${file}" || {
                    (( nullglob_was_set )) || shopt -u nullglob
                    die "Failed to source: ${file}" 2
                }
            ;;
            doc)
                should_skip "${name}" && continue
                [[ -n "${_seen[${name}]-}" ]] && continue

                _seen["${name}"]=1
                _mods+=( "${name}" )
            ;;
            *)
                (( nullglob_was_set )) || shopt -u nullglob
                die "load_walk: unknown mode '${mode}'" 2
            ;;
        esac

    done

    for subdir in "${dir}"/*/; do

        sd="${subdir%/}"
        [[ -L "${sd}" ]] && continue

        base="${sd##*/}"
        [[ -n "${base}" ]] || continue

        case "${mode}" in
            source)
                should_skip "${base}" "${extra_skip[@]-}" && continue
                load_walk source "${sd}" "" "" "${extra_skip[@]-}" || {
                    (( nullglob_was_set )) || shopt -u nullglob
                    return $?
                }
            ;;
            doc)
                should_skip "${base}" && continue
                load_walk doc "${sd}" "${seen_ref}" "${mods_ref}" || {
                    (( nullglob_was_set )) || shopt -u nullglob
                    return $?
                }
            ;;
        esac

    done

    (( nullglob_was_set )) || shopt -u nullglob
    return 0

}
load_source () {

    [[ -n "${MODULES_LOADED:-}" ]] && return 0
    MODULES_LOADED=1

    local dir="${1-}"
    local -a extra_skip=()

    if [[ -z "${dir}" ]]; then
        [[ -n "${ROOT_DIR:-}" && -n "${MODULE_DIR:-}" ]] || die "load_source: ROOT_DIR/MODULE_DIR not set" 2
        dir="${ROOT_DIR}/${MODULE_DIR}"
    fi

    [[ -d "${dir}" ]] || die "load_source: not a dir: ${dir}" 2
    (( $# > 1 )) && extra_skip=( "${@:2}" ) || extra_skip=()

    load_walk source "${dir}" "" "" "${extra_skip[@]-}"

}
module_usage () {

    local name="${1-}" mod="" chosen=""

    [[ -n "${name}" ]] || return 0
    mod="$(normalize "${name}")"

    local fn1="${mod}_usage"
    local fn2="help_${mod}"
    local fn3="${mod}_help"
    local fn4="usage_${mod}"
    local fn5="cmd_${mod}_usage"
    local fn6="cmd_help_${mod}"
    local fn7="cmd_${mod}_help"
    local fn8="cmd_usage_${mod}"

    declare -F "${fn1}" >/dev/null 2>&1 && chosen="${fn1}"
    [[ -z "${chosen}" ]] && declare -F "${fn2}" >/dev/null 2>&1 && chosen="${fn2}"
    [[ -z "${chosen}" ]] && declare -F "${fn3}" >/dev/null 2>&1 && chosen="${fn3}"
    [[ -z "${chosen}" ]] && declare -F "${fn4}" >/dev/null 2>&1 && chosen="${fn4}"
    [[ -z "${chosen}" ]] && declare -F "${fn5}" >/dev/null 2>&1 && chosen="${fn5}"
    [[ -z "${chosen}" ]] && declare -F "${fn6}" >/dev/null 2>&1 && chosen="${fn6}"
    [[ -z "${chosen}" ]] && declare -F "${fn7}" >/dev/null 2>&1 && chosen="${fn7}"
    [[ -z "${chosen}" ]] && declare -F "${fn8}" >/dev/null 2>&1 && chosen="${fn8}"
    [[ -n "${chosen}" ]] || return 0

    "${chosen}" || true

}
render_doc () {

    local dir="${ROOT_DIR:-}/${MODULE_DIR:-}"
    [[ -n "${ROOT_DIR:-}" && -n "${MODULE_DIR:-}" ]] || die "render_doc: ROOT_DIR/MODULE_DIR not set" 2
    [[ -d "${dir}" ]] || die "render_doc: module dir not found: ${dir}" 2

    local -a mods=()
    local -A seen=()
    local -A printed_mod=()
    local name="" want="" printed=0
    local alias_name="${ALIAS:-${APP_NAME:-app}}"

    load_source "${dir}" || return $?
    load_walk doc "${dir}" seen mods || return 2

    info_ln "Usage:\n"
    printf '%s\n' \
        "    ${alias_name} [--yes] [--quiet] [--verbose] <cmd> [args...]" \
        ''

    info_ln "Global:\n"
    printf '%s\n' \
        '    --yes,    -y     Non-interactive (assume yes)' \
        '    --quiet,  -q     Less output' \
        '    --verbose,-v     Print executed commands' \
        '    --help,   -h     Show help' \
        '    --version        Show version' \
        ''

    for want in "${SORTED_LIST[@]-}"; do

        [[ -n "${want}" ]] || continue

        for name in "${mods[@]-}"; do
            [[ "${name}" == "${want}" ]] || continue

            module_usage "${name}"
            printed=1
            printed_mod["${name}"]=1
            break
        done

    done

    for name in "${mods[@]-}"; do

        [[ -n "${name}" ]] || continue
        [[ -n "${printed_mod[${name}]-}" ]] && continue

        module_usage "${name}"
        printed=1
        printed_mod["${name}"]=1

    done

    (( printed )) || printf '%s\n' '(no module usage found)' ''

}
parse_global () {

    YES=0
    QUIET=0
    VERBOSE=0

    YES_ENV=0
    QUIET_ENV=0
    VERBOSE_ENV=0

    CMD=""
    ARGS=()

    local saw_help=0
    local saw_version=0

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --yes|-y)
                YES=1
                YES_ENV=1
                shift || true
            ;;
            --quiet|-q)
                QUIET=1
                QUIET_ENV=1
                shift || true
            ;;
            --verbose|-v)
                VERBOSE=1
                VERBOSE_ENV=1
                shift || true
            ;;
            -h|--help)
                saw_help=1
                shift || true
            ;;
            --version)
                saw_version=1
                shift || true
            ;;
            --)
                shift || true
                break
            ;;
            -*)
                die "Unknown global flag: ${1}" 2
            ;;
            *)
                break
            ;;
        esac
    done

    if (( saw_help )); then
        CMD="help"
        ARGS=()
        return 0
    fi

    if (( saw_version )); then
        CMD="version"
        ARGS=()
        return 0
    fi

    CMD="${1:-}"
    [[ $# -gt 0 ]] && shift || true
    ARGS=( "$@" )

}
dispatch () {

    local cmd="${1:-}" sub="${2:-}"
    local mod="$(normalize "${cmd}")" fn="cmd_${mod}"
    shift 2 || true

    case "${cmd}" in
        ""|help|-h|--help|h)
            render_doc
            return 0
        ;;
        version|v|--version)
            printf '%s\n' "${APP_VERSION:-1.0.0}"
            return 0
        ;;
    esac

    if ! [[ "${cmd}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        eprint "Unknown command: ( ${cmd} )"
        eprint "See Docs: --help"
        return 2
    fi
    if [[ -n "${sub}" && "${sub}" != -* ]]; then
        local fn_sub="cmd_${mod}_$(normalize "${sub}")"

        if declare -F "${fn_sub}" >/dev/null 2>&1; then
            "${fn_sub}" "$@"
            return $?
        fi
    fi
    if declare -F "${fn}" >/dev/null 2>&1; then
        "${fn}" "$@"
        return $?
    fi

    eprint "Unknown command: ( ${cmd} )"
    eprint "See Docs: --help"
    return 2

}
load () {

    cd_current_root || die "You must run this command inside a project "

    local old_trap="$(trap -p ERR 2>/dev/null || true)" ec=0
    trap 'on_err "$?"' ERR
    load_source
    parse_global "$@"

    if [[ ${#ARGS[@]} -gt 0 ]]; then dispatch "${CMD}" "${ARGS[@]}" || ec=$?
    else dispatch "${CMD}" || ec=$?
    fi
    if [[ -n "${old_trap}" ]]; then eval "${old_trap}"
    else trap - ERR 2>/dev/null || true
    fi

    return "${ec}"

}

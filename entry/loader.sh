
load_norm_name () {

    local s="${1-}"
    [[ -n "${s}" ]] || return 0

    s="${s//[^[:alnum:]_]/_}"
    while [[ "${s}" == *"__"* ]]; do s="${s//__/_}"; done

    s="${s##_}"
    s="${s%%_}"

    [[ -z "${s}" ]] && s="_"
    [[ "${s}" =~ ^[0-9] ]] && s="_${s}"

    printf '%s' "${s}"

}
load_path_names () {

    local path="${1:-}"
    [[ -n "${path}" ]] || die "load_path_names: missing path"

    local base="${path##*/}"
    local name="${base%.sh}"
    local dir="${path%/*}"
    local parent="${dir##*/}"

    printf '%s\n' "${name}" "${parent}"

}

load_walk_modules () {

    local dir="${1:-}" path="" ex="" skip=0
    shift || true

    [[ -n "${dir}" && -d "${dir}" ]] || die "load_walk_modules: not a dir: ${dir}"

    for path in "${dir}"/*; do

        [[ -e "${path}" ]] || continue
        [[ -L "${path}" ]] && continue
        skip=0

        for ex in "$@"; do

            [[ -n "${ex}" ]] || continue
            ex="${ex%/}"

            if [[ "${path%/}" == "${ex}" || "${path}" == "${ex}/"* ]]; then
                skip=1
                break
            fi

        done

        (( skip )) && continue

        if [[ -d "${path}" ]]; then
            load_walk_modules "${path%/}" "$@"
            continue
        fi

        [[ -f "${path}" ]] || continue
        [[ "${path}" == *.sh ]] || continue

        printf '%s\n' "${path}"

    done

}
load_find_modules () {

    local -a paths=()
    local -a stacks=()

    [[ -d "${MODULE_DIR:-}" ]] || die "load_find_modules: module dir not found: ${MODULE_DIR:-}"
    mapfile -t paths < <( load_walk_modules "${MODULE_DIR:-}" "${STACK_DIR:-}" )

    local lang="$(which_lang "${PWD}" 2>/dev/null || true)"
    local stack=""
    [[ -d "${STACK_DIR:-}" && -n "${lang}" ]] && stack="${STACK_DIR:-}/${lang}"

    if [[ -n "${stack}" && -d "${stack}" ]]; then
        mapfile -t stacks < <( load_walk_modules "${stack}" )
        paths+=( "${stacks[@]}" )
    fi

    printf '%s\n' "${paths[@]}"

}
load_source_modules () {

    local path=""
    (( $# > 0 )) || die "load_source_modules: missing path"

    for path in "$@"; do

        [[ -n "${path}"      ]] || continue
        [[ -e "${path}"      ]] || die "load_source_modules: path not found: ${path}"
        [[ -L "${path}"      ]] || die "load_source_modules: refusing symlink: ${path}"
        [[ -f "${path}"      ]] || die "load_source_modules: not a file: ${path}"
        [[ "${path}" == *.sh ]] || die "load_source_modules: not a .sh file: ${path}"

        source "${path}" || die "Failed to source: ${path}"

    done

}

load_find_usage () {

    local mod="$(load_norm_name "${1:-}")" fn=""
    [[ -n "${mod}" ]] || return 1

    for fn in \
        "${mod}_usage" \
        "usage_${mod}" \
        "cmd_${mod}_usage" \
        "cmd_usage_${mod}" \
        "${mod}_help" \
        "help_${mod}" \
        "cmd_${mod}_help" \
        "cmd_help_${mod}"
    do
        declare -F "${fn}" >/dev/null 2>&1 && { printf '%s\n' "${fn}"; return 0; }
    done

    return 1

}
load_module_usage () {

    local -a names=()
    mapfile -t names < <( load_path_names "${1:-}" )

    local name1="${names[0]-}"
    local name2="${names[1]-}"

    local chosen="$(load_find_usage "${name1}")" || true
    [[ -z "${chosen}" ]] && { chosen="$(load_find_usage "${name2}")" || true; }
    [[ -z "${chosen}" ]] && return 0

    "${chosen}" || true

}
load_module_docs () {

    local -n modules="${1:-}"
    local -A printed_mod=()

    local name="" want="" printed=0
    local alias="${ALIAS:-${ALIAS_NAME:-${APP_NAME:-app}}}"

    info_ln "Usage:\n"

    printf '%s\n' \
        "    ${alias} [--yes] [--verbose] <cmd> [args...]" \
        ''

    info_ln "Global:\n"

    printf '%s\n' \
        '    --yes,    -y     Non-interactive (assume yes)' \
        '    --verbose,-v     Print executed commands' \
        '    --help,   -h     Show help docs' \
        '    --version        Show version' \
        ''

    for want in "${SORTED_LIST[@]-}"; do

        [[ -n "${want}" ]] || continue

        for name in "${modules[@]-}"; do

            local path="${name%/}"
            local rel="${path#${MODULE_DIR%/}/}"
            local rel_no_ext="${rel%.sh}"
            local base="${path##*/}"
            local mod="${base%.sh}"

            [[ -z "${name}" ]] && continue
            [[ "${want}" != "${rel}" && "${want}" != "${rel_no_ext}" && "${want}" != "${mod}" ]] && continue

            load_module_usage "${name}"
            printed_mod["${name}"]=1
            printed=1

            break

        done

    done
    for name in "${modules[@]-}"; do

        [[ -z "${name}" || -n "${printed_mod[${name}]-}" ]] && continue

        load_module_usage "${name}"
        printed_mod["${name}"]=1
        printed=1

    done

    (( printed )) || printf '%s\n' '(no module usage found)' ''

}

load_dispatch () {

    local cmd="${1:-}" docs=0
    local fn="cmd_$(load_norm_name "${cmd}")"
    local fn_sub="${fn}_$(load_norm_name "${2:-}")"
    shift || true

    case "${cmd}" in
        version|v|--version)
            printf '%s\n' "${APP_VERSION:-}"
            return 0
        ;;
        ""|help|-h|--help|h)
            docs=1
        ;;
    esac

    local -a modules=()
    mapfile -t modules < <( load_find_modules )

    load_source_modules "${modules[@]}"
    (( docs )) && { load_module_docs modules; return 0; }

    if declare -F "${fn_sub}" >/dev/null 2>&1; then
        shift || true
        "${fn_sub}" "$@"
        return $?
    fi
    if declare -F "${fn}" >/dev/null 2>&1; then
        "${fn}" "$@"
        return $?
    fi

    eprint "Unknown command: ( ${cmd} )"
    eprint "See Docs: --help"

    return 2

}
load_parse () {

    YES=0 VERBOSE=0 CMD="" ARGS=()
    local saw_help=0 saw_version=0

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --yes|-y)
                YES=1
                shift || true
            ;;
            --verbose|-v)
                VERBOSE=1
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
                die "Unknown global flag: ${1}"
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
load () {

    cd_current_root

    local old_trap="$(trap -p ERR 2>/dev/null || true)" ec=0
    trap 'on_err "$?"' ERR

    load_parse "$@"

    if [[ ${#ARGS[@]} -gt 0 ]]; then load_dispatch "${CMD}" "${ARGS[@]}" || ec=$?
    else load_dispatch "${CMD}" || ec=$?
    fi
    if [[ -n "${old_trap}" ]]; then eval "${old_trap}"
    else trap - ERR 2>/dev/null || true
    fi

    return "${ec}"

}

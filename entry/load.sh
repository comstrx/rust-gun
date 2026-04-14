
load_norm_name () {

    local s="${1-}"

    [[ -n "${s}" ]] || return 0

    s="${s//[^[:alnum:]_]/_}"

    while [[ "${s}" == *"__"* ]]; do
        s="${s//__/_}"
    done

    s="${s##_}"
    s="${s%%_}"

    [[ -n "${s}" ]] || s="_"
    [[ "${s}" =~ ^[0-9] ]] && s="_${s}"

    printf '%s' "${s}"

}
load_path_names () {

    local path="${1-}" base="" name="" dir="" parent=""

    [[ -n "${path}" ]] || die "load_path_names: missing path"

    path="${path%/}"
    [[ -n "${path}" ]] || die "load_path_names: invalid path"

    base="${path##*/}"
    name="${base%.sh}"

    if [[ "${path}" == */* ]]; then
        dir="${path%/*}"
        parent="${dir##*/}"
    else
        parent=""
    fi

    printf '%s\n' "${name}" "${parent}"

}

load_walk_modules () {

    local dir="${1:-${MODULE_DIR:-}}" path="" ex="" skip=0
    shift || true

    [[ -n "${dir}" ]] || die "load_walk_modules: missing module dir"
    [[ -d "${dir}" ]] || die "load_walk_modules: invalid module dir: ${dir}"

    dir="${dir%/}"

    for path in "${dir}"/*; do

        [[ -e "${path}" ]] || continue
        [[ -L "${path}" ]] && continue

        path="${path%/}"
        skip=0

        for ex in "$@"; do

            [[ -n "${ex}" ]] || continue
            ex="${ex%/}"

            if [[ "${path}" == "${ex}" || "${path}" == "${ex}/"* ]]; then
                skip=1
                break
            fi

        done

        (( skip )) && continue

        if [[ -d "${path}" ]]; then
            load_walk_modules "${path}" "$@"
            continue
        fi

        [[ -f "${path}" ]] || continue
        [[ "${path}" == *.sh ]] || continue

        printf '%s\n' "${path}"

    done

}
load_source_modules () {

    local dir="${1:-${MODULE_DIR:-}}" path=""
    local -a modules=()

    [[ -n "${dir}" ]] || die "load_source_modules: missing module dir"
    [[ -d "${dir}" ]] || die "load_source_modules: invalid module dir: ${dir}"

    mapfile -t modules < <( load_walk_modules "${dir}" )

    for path in "${modules[@]}"; do

        [[ -n "${path}" ]] || continue
        [[ -e "${path}" ]] || die "load_source_modules: path not found: ${path}"
        [[ -L "${path}" ]] && die "load_source_modules: refusing symlink: ${path}"
        [[ -f "${path}" ]] || die "load_source_modules: not a file: ${path}"
        [[ "${path}" == *.sh ]] || die "load_source_modules: not a .sh file: ${path}"

        source "${path}" || die "load_source_modules: failed to source: ${path}"

    done

}
load_doc_approved () {

    local fn="${1:-}" lang="${2:-}" tail=""
    [[ -n "${fn}" ]] || return 1

    case "${fn}" in
        cmd_"${lang}"_*_usage|cmd_"${lang}"_*_help)
            return 0
        ;;
        cmd_*_usage|cmd_*_help)
            tail="${fn#cmd_}"
            tail="${tail%_usage}"
            tail="${tail%_help}"

            [[ -n "${tail}" ]] || return 1
            [[ "${tail}" != *_* ]] || return 1

            return 0
        ;;
    esac

    return 1

}
load_module_docs () {

    local alias="${ALIAS:-${ALIAS_NAME:-${APP_NAME:-"--alias"}}}"
    local lang="$(which_lang)" line="" fn="" seen_any=0

    info_ln "Usage:"

    printf '%s\n' \
        "" \
        "    ${alias} [--yes] [--verbose] <cmd> [args...]" \
        ''

    info_ln "Global:"

    printf '%s\n' \
        "" \
        '    --yes,    -y     Non-interactive (assume yes)' \
        '    --verbose,-v     Print executed commands' \
        '    --help,   -h     Show help docs' \
        '    --version        Show version' \
        ''

    while IFS= read -r line; do

        fn="${line##declare -f }"
        load_doc_approved "${fn}" "${lang}" || continue

        "${fn}" || true
        seen_any=1

    done < <(declare -F)

    (( seen_any )) || printf '%s\n' '(no command docs found)' ''

}

load_dispatch () {

    local cmd="${1-}" sub="${2-}"

    case "${cmd}" in
        version|v|--version) printf '%s\n' "${APP_VERSION:-unknown}"; return 0 ;;
        ""|help|-h|--help|h) load_module_docs; return 0 ;;
    esac

    local lang="$(which_lang)"

    local fn="cmd_$(load_norm_name "${cmd}")"
    local fn_sub="${fn}_$(load_norm_name "${sub}")"

    local fn_lang="cmd_${lang}_$(load_norm_name "${cmd}")"
    local fn_sub_lang="${fn_lang}_$(load_norm_name "${sub}")"

    if declare -F "${fn_sub_lang}" >/dev/null 2>&1; then
        shift 2 || true
        "${fn_sub_lang}" "$@"
        return $?
    fi
    if declare -F "${fn_lang}" >/dev/null 2>&1; then
        shift || true
        "${fn_lang}" "$@"
        return $?
    fi
    if declare -F "${fn_sub}" >/dev/null 2>&1; then
        shift 2 || true
        "${fn_sub}" "$@"
        return $?
    fi
    if declare -F "${fn}" >/dev/null 2>&1; then
        shift || true
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
            --yes|-y)     YES=1; shift || true ;;
            --verbose|-v) VERBOSE=1; shift || true ;;
            -h|--help)    saw_help=1; shift || true ;;
            --version)    saw_version=1; shift || true ;;
            --)           shift || true; break ;;
            -*)           die "Unknown global flag: ${1}" ;;
            *)            break ;;
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

    CMD="${1-}"
    [[ $# -gt 0 ]] && shift || true
    ARGS=( "$@" )

}
load_run () {

    local ec=0
    load_parse "$@"

    if [[ ${#ARGS[@]} -gt 0 ]]; then load_dispatch "${CMD}" "${ARGS[@]}" || ec=$?
    else load_dispatch "${CMD}" || ec=$?
    fi

    return "${ec}"

}
load_run_entry () {

    cd_root
    load_source_modules
    load_run "$@"

}

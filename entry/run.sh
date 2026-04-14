
run_version () {

    printf '%s\n' "${APP_VERSION:-unknown}"

}
run_norm_name () {

    local s="${1-}"
    [[ -n "${s}" ]] || return 0

    s="${s//[^[:alnum:]_]/_}"
    while [[ "${s}" == *"__"* ]]; do s="${s//__/_}"; done

    s="${s##_}"
    s="${s%%_}"

    [[ -n "${s}" ]] || s="_"
    [[ "${s}" =~ ^[0-9] ]] && s="_${s}"

    printf '%s' "${s}"

}
run_walk_modules () {

    local dir="${1:-}" path="" ex="" skip=0
    shift || true

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
            run_walk_modules "${path}" "$@"
            continue
        fi

        [[ -f "${path}" ]] || continue
        [[ "${path}" == *.sh ]] || continue

        printf '%s\n' "${path}"

    done

}
run_source_modules () {

    local dir="${1:-}" path=""
    local -a modules=()

    [[ -n "${dir}" ]] || die "Missing module dir"
    [[ -d "${dir}" ]] || die "Invalid module dir: ${dir}"

    mapfile -t modules < <( run_walk_modules "${dir%/}" )

    for path in "${modules[@]}"; do

        [[ "${path}" == *.sh ]] || die "Invalid .sh file: ${path}"
        [[ -f "${path}" ]] || die "Invalid file: ${path}"
        [[ -L "${path}" ]] && die "Refusing symlink: ${path}"

        source "${path}" || die "Failed to source: ${path}"

    done

}

run_validate_docs () {

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
run_docs () {

    local alias="${ALIAS:-${ALIAS_NAME:-${APP_NAME:-"--alias"}}}"
    local line="" fn="" seen_any=0
    local lang="$(which_lang)"

    info_ln "Usage:"

    printf '%s\n' \
        "" \
        "    ${alias} [--yes] [--verbose] <cmd> [args...]" \
        ''

    info_ln "Global:"

    printf '%s\n' \
        "" \
        '    --yes,     -y      * Non-interactive (assume yes)' \
        '    --verbose, -r      * Print executed commands' \
        '    --help,    -h      * Show help docs' \
        '    --version, -v      * Show version' \
        "    --install, -i      * Install ${alias} at ~/.local/bin/" \
        "    --upgrade, -u      * Upgrade ${alias} and update ~/.local/bin/" \
        ''

    while IFS= read -r line; do

        fn="${line##declare -f }"
        run_validate_docs "${fn}" "${lang}" || continue
        "${fn}" || true
        seen_any=1

    done < <(declare -F)

    (( seen_any )) || printf '%s\n' '(no command docs found)' ''

}
run_dispatch () {

    local cmd="${1:-}" sub="${2:-}"
    shift || true

    case "${cmd}" in
        help)    run_docs;    return 0 ;;
        version) run_version; return 0 ;;
        install) install "$@"; return 0 ;;
        upgrade) install "$@" --force; return 0 ;;
    esac

    local lang="$(which_lang)"
    local fn="cmd_$(run_norm_name "${cmd}")"
    local fn_sub="${fn}_$(run_norm_name "${sub}")"
    local fn_lang="cmd_${lang}_$(run_norm_name "${cmd}")"
    local fn_sub_lang="${fn_lang}_$(run_norm_name "${sub}")"

    if declare -F "${fn_sub_lang}" >/dev/null 2>&1; then
        shift || true
        "${fn_sub_lang}" "$@"
        return $?
    fi
    if declare -F "${fn_lang}" >/dev/null 2>&1; then
        "${fn_lang}" "$@"
        return $?
    fi
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
run_parse () {

    YES=0 VERBOSE=0 CMD="" ARGS=()
    local help=0 version=0 install=0 upgrade=0

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -y|--yes)     YES=1;     shift || true ;;
            -r|--verbose) VERBOSE=1; shift || true ;;
            -h|--help)    help=1;    shift || true ;;
            -v|--version) version=1; shift || true ;;
            -i|--install) install=1; shift || true ;;
            -u|--upgrade) upgrade=1; shift || true ;;
            --)           shift || true; break ;;
            -*)           die "Unknown global flag: ${1}" ;;
            *)            break ;;
        esac
    done

    (( help ))    && { CMD="help";    return 0; }
    (( version )) && { CMD="version"; return 0; }
    (( install )) && { CMD="install"; return 0; }
    (( upgrade )) && { CMD="upgrade"; return 0; }

    CMD="${1:-}"
    [[ $# -gt 0 ]] && shift || true
    ARGS=( "$@" )

}

run () {

    cd_root
    [[ -d "${MODULE_DIR:-}" ]] && run_source_modules "${MODULE_DIR}"

    run_parse "$@"
    run_dispatch "${CMD}" "${ARGS[@]}"

}

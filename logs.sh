#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/entry/arch.sh"
install "$@"
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "entry files should not be run directly." >&2; exit 2; }
[[ -n "${ENTRY_LOADED:-}" ]] && return 0

readonly ENTRY_LOADED=1

readonly ENTRY_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
readonly TEMPLATE_DIR="${ENTRY_DIR}/../template"
readonly MODULE_DIR="${ENTRY_DIR}/../module"
readonly STACK_DIR="${MODULE_DIR}/stack"

readonly APP_VERSION="1.0.0"
readonly MIN_BASH_VERSION="5.2"

readonly SORTED_LIST=( forge ops notify git github fs )

source "${ENTRY_DIR}/../core/bash.sh"
ensure_bash "${MIN_BASH_VERSION}" "$@"

source "${ENTRY_DIR}/../core/arch.sh"
source "${ENTRY_DIR}/../ensure/arch.sh"

source "${ENTRY_DIR}/installer.sh"
source "${ENTRY_DIR}/loader.sh"

install_line_once () (

    ensure_pkg grep rm mv dirname mktemp cat sleep kill tail 1>&2

    local file="${1:-}" line="${2:-}"
    local tmp="" owner_pid="" i=0 max_tries=200

    [[ -n "${file}" ]] || die "install_line_once: missing file"
    [[ -n "${line}" ]] || die "install_line_once: missing line"
    [[ -L "${file}" ]] && die "install_line_once: refusing to modify symlink: ${file}"

    ensure_file "${file}"

    LC_ALL=C grep -Fqx -- "${line}" "${file}" 2>/dev/null && return 0
    LC_ALL=C grep -Fqx -- "${line}"$'\r' "${file}" 2>/dev/null && return 0

    local dir="$(dirname -- "${file}")"
    local lock_file="${file}.lock"

    while ! ( set -o noclobber; printf '%s\n' "${BASHPID:-$$}" > "${lock_file}" ) 2>/dev/null; do

        owner_pid=""

        if [[ -f "${lock_file}" ]]; then
            IFS= read -r owner_pid < "${lock_file}" 2>/dev/null || owner_pid=""

            if [[ ! "${owner_pid}" =~ ^[0-9]+$ ]]; then
                rm -f -- "${lock_file}" 2>/dev/null || true
                continue
            fi
        fi
        if [[ -n "${owner_pid}" ]] && ! kill -0 "${owner_pid}" 2>/dev/null; then
            rm -f -- "${lock_file}" 2>/dev/null || true
            continue
        fi

        (( i++ ))
        (( i < max_tries )) || die "install_line_once: lock timeout for ${file}"

        sleep 0.05 || true

    done

    trap 'rm -f -- "${tmp}" "${lock_file}" 2>/dev/null || true' EXIT INT TERM HUP

    LC_ALL=C grep -Fqx -- "${line}" "${file}" 2>/dev/null && return 0
    LC_ALL=C grep -Fqx -- "${line}"$'\r' "${file}" 2>/dev/null && return 0

    tmp="$(mktemp "${dir}/.tmp.install_line_once.XXXXXX")" || die "install_line_once: mktemp failed in ${dir}"

    {
        cat -- "${file}"
        [[ -s "${file}" && -n "$(tail -c 1 -- "${file}" 2>/dev/null)" ]] && printf '\n'
        printf '%s\n' "${line}"
    } > "${tmp}" || die "install_line_once: failed writing temp file for ${file}"

    mv -f -- "${tmp}" "${file}" || die "install_line_once: failed replacing ${file}"

)
install_path_once () {

    local rc="${1:-}" alias="${2:-}"

    [[ -n "${rc}" ]] || die "install_path_once: missing rc"
    [[ -n "${alias}" ]] || die "install_path_once: missing alias"
    [[ -L "${rc}" ]] && die "install_path_once: refusing to modify symlink: ${rc}"

    ensure_file "${rc}"
    install_line_once "${rc}" "# ${alias}"

    case "${rc}" in
        */.config/fish/config.fish) install_line_once "${rc}" 'set -gx PATH $HOME/.local/bin $PATH' ;;
        *)                          install_line_once "${rc}" 'export PATH="$HOME/.local/bin:$PATH"' ;;
    esac

}
install_launcher () (

    ensure_pkg chmod mkdir mv rm mktemp 1>&2

    local root="${1:-}" alias="${2:-}" root_q="" tmp=""
    local run_sh="${root}/entry/run.sh"
    local bin_dir="$(home_path)/.local/bin"
    local bin="${bin_dir}/${alias}"

    [[ -n "${root}" ]] || die "install_launcher: missing root"
    [[ -f "${run_sh}" ]] || die "install_launcher: missing ${run_sh}"

    validate_alias "${alias}"
    ensure_dir "${bin_dir}"

    [[ -e "${bin}" && ! -f "${bin}" ]] && die "install_launcher: refusing non-file target ${bin}"
    [[ -L "${bin}" ]] && die "install_launcher: refusing to overwrite symlink ${bin}"

    if [[ -e "${bin}" && ! (( YES )) ]]; then confirm "Overwrite ${bin}?" "N" || die "Canceled."; fi

    printf -v root_q '%q' "${root}"

    tmp="$(mktemp "${bin_dir}/.tmp.${alias}.XXXXXX")" || die "install_launcher: mktemp failed in ${bin_dir}"
    trap 'rm -f -- "${tmp}" 2>/dev/null || true' EXIT INT TERM HUP

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        '' \
        "ROOT=${root_q}" \
        '' \
        'exec /usr/bin/env bash "${ROOT}/entry/run.sh" "$@"' \
        > "${tmp}" || die "install_launcher: failed writing ${tmp}"

    run chmod +x -- "${tmp}" || die "install_launcher: chmod failed ${tmp}"
    mv -f -- "${tmp}" "${bin}" || die "install_launcher: failed replacing ${bin}"

    printf '%s\n' "${bin}"

)
install () {

    local alias="${1:-gun}"
    local rc="$(rc_path)"
    local bin_path="$(install_launcher "${ROOT_DIR:-}" "${alias}")"

    install_path_once "${rc}" "${alias}"

    success "Installed: ( ${alias} ) at ${bin_path}"
    success "Reload: source \"${rc}\""

}

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
#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/arch.sh"
load "$@"
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "ensure files should not be run directly." >&2; exit 2; }
[[ -n "${ENSURE_LOADED:-}" ]] && return 0

readonly ENSURE_LOADED=1
readonly ENSURE_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"

source "${ENSURE_DIR}/work.sh"
source "${ENSURE_DIR}/rust.sh"
source "${ENSURE_DIR}/node.sh"
source "${ENSURE_DIR}/python.sh"

ensure () {

    local -a wants=()
    local want=""

    for want in "$@"; do
        [[ -n "${want}" ]] || continue
        wants+=( "${want}" )
    done

    unique_list wants
    (( ${#wants[@]} )) || return 0

    for want in "${wants[@]}"; do

        case "${want}" in
            node|nodejs|npm|npx)       ensure_node ;;
            bun)                       ensure_bun ;;
            pnpm)                      ensure_pnpm ;;
            volta)                     ensure_volta ;;

            python|pip)                ensure_python ;;

            cargo|rust|rustc|rustup)   ensure_rust ;;

            rustfmt|rust-src)          ensure_component "${want}" stable; ensure_component "${want}" nightly ;;
            miri)                      ensure_component miri nightly ;;
            clippy|llvm-tools-preview) ensure_component "${want}" stable ;;

            taplo)                     ensure_crate taplo-cli taplo ;;
            cargo-audit)               ensure_crate cargo-audit cargo-audit --features fix ;;
            cargo-edit|cargo-upgrade)  ensure_cargo_edit ;;
            cargo-add|cargo-rm)        ensure_cargo_edit ;;
            cargo-set-version)         ensure_cargo_edit ;;

            cargo-*)                   ensure_crate "${want}" "${want}" ;;

            *)                         ensure_tool "${want}" 1>&2 ;;
        esac

    done

}

tool_export_cargo_bin () {

    local cargo_home="${CARGO_HOME:-${HOME}/.cargo}"
    tool_export_path_if_dir "${cargo_home}/bin"

}
tool_source_cargo_env () {

    local cargo_env="${CARGO_HOME:-${HOME}/.cargo}/env"
    [[ -f "${cargo_env}" ]] && source "${cargo_env}" || true
    tool_export_cargo_bin

}
tool_crate_bin_ok () {

    local bin="${1-}"
    [[ -n "${bin}" ]] || return 1
    has "${bin}" || has "${bin#cargo-}"

}

tool_stable_version () {

    tool_normalize_version "${RUST_STABLE:-stable}"

}
tool_nightly_version () {

    tool_normalize_version "${RUST_NIGHTLY:-nightly}"

}
tool_workspace_msrv () {

    has cargo || return 1
    ensure_pkg jq tail sort 1>&2

    local want="$(
        cargo metadata --no-deps --format-version 1 2>/dev/null \
        | jq -r '.packages[].rust_version // empty' \
        | tool_sort_ver \
        | tail -n 1
    )"

    [[ -n "${want}" ]] || return 1
    printf '%s\n' "${want}"

}
tool_msrv_version () {

    local tc=""

    if [[ -n "${RUST_MSRV:-}" ]]; then
        tc="$(tool_normalize_version "${RUST_MSRV}")"
        [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid RUST_MSRV (need x.y.z): ${RUST_MSRV}" 2
        printf '%s\n' "${tc}"
        return 0
    fi

    tc="$(tool_workspace_msrv 2>/dev/null || true)"

    if [[ -n "${tc}" ]]; then
        tc="$(tool_normalize_version "${tc}")"
        [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid workspace rust_version: ${tc}" 2
        printf '%s\n' "${tc}"
        return 0
    fi

    tool_stable_version

}
tool_resolve_chain () {

    local tc="${1-}"
    [[ -n "${tc}" ]] || die "tool_resolve_chain: empty toolchain" 2

    case "${tc}" in
        stable)  tc="$(tool_stable_version)" ;;
        nightly) tc="$(tool_nightly_version)" ;;
        msrv)    tc="$(tool_msrv_version)" ;;
        *)       tc="$(tool_normalize_version "${tc}")" ;;
    esac

    printf '%s\n' "${tc}"

}
tool_setup_chain () {

    local tc="$(tool_resolve_chain "${1:-}")"
    rustup run "${tc}" rustc -V >/dev/null 2>&1 && return 0

    run rustup toolchain install "${tc}" --profile minimal
    run rustup run "${tc}" rustc -V >/dev/null 2>&1 || die "rustc not working after install: ${tc}" 2

}

tool_rustup_windows_url () {

    local arch="$(uname -m 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    case "${PROCESSOR_ARCHITECTURE:-${arch}}" in
        amd64|AMD64|x86_64|x64) printf '%s\n' "https://win.rustup.rs/x86_64" ;;
        arm64|ARM64|aarch64)    printf '%s\n' "https://win.rustup.rs/aarch64" ;;
        x86|i386|i686)          printf '%s\n' "https://win.rustup.rs/i686" ;;
        *)                      printf '%s\n' "https://win.rustup.rs/x86_64" ;;
    esac

}
tool_install_rustup_unix () {

    ensure_pkg curl 1>&2
    local stable="${1:-stable}"

    run bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "'"${stable}"'"' \
        || die "Failed to install rustup." 2

}
tool_install_rustup_windows () {

    ensure_pkg curl 1>&2

    local stable="${1:-stable}"
    local url="$(tool_rustup_windows_url)"
    local tmp="${TMPDIR:-${TEMP:-/tmp}}/rustup-init.$$.exe"

    run curl -fsSL -o "${tmp}" "${url}" || die "Failed to download rustup-init.exe" 2
    run "${tmp}" -y --profile minimal --default-toolchain "${stable}" || die "Failed to install rustup (Windows)." 2

    rm -f "${tmp}" 2>/dev/null || true

}

ensure_rust () {

    local stable="$(tool_stable_version)"
    local nightly="$(tool_nightly_version)"
    local msrv="$(tool_msrv_version)"
    local target="$(tool_target)"

    tool_source_cargo_env

    if ! has rustup; then

        case "${target}" in
            linux|macos) tool_install_rustup_unix "${stable}" ;;
            msys|mingw|gitbash|cygwin) tool_install_rustup_windows "${stable}" ;;
            *) die "Unsupported target for rustup install: ${target}" 2 ;;
        esac

        tool_source_cargo_env
        has rustup || die "rustup installed but not found in PATH." 2

    fi

    tool_setup_chain "${stable}"
    tool_setup_chain "${nightly}"
    tool_setup_chain "${msrv}"

    rustup run "${stable}" cargo -V >/dev/null 2>&1 || die "cargo (stable) not working after install." 2
    rustup run "${nightly}" rustc -V >/dev/null 2>&1 || die "rustc (nightly) not working after install." 2
    rustup run "${msrv}" rustc -V >/dev/null 2>&1 || die "rustc (msrv) not working after install." 2

    tool_source_cargo_env
    tool_hash_clear

}
ensure_component () {

    local comp="${1-}" tc="${2:-stable}"
    [[ -n "${comp}" ]] || die "ensure_component: requires a component name" 2

    has rustup || ensure_rust

    tc="$(tool_resolve_chain "${tc}")"
    tool_setup_chain "${tc}"

    if [[ "${comp}" == "llvm-tools-preview" ]]; then
        rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE '^(llvm-tools|llvm-tools-preview)\b' && return 0
        run rustup component add --toolchain "${tc}" llvm-tools-preview 2>/dev/null || run rustup component add --toolchain "${tc}" llvm-tools
        rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE '^(llvm-tools|llvm-tools-preview)\b' || die "Failed to install llvm-tools on '${tc}'." 2
        return 0
    fi

    rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE "^${comp}\b" && return 0
    run rustup component add --toolchain "${tc}" "${comp}"
    rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE "^${comp}\b" || die "Failed to install component '${comp}' on '${tc}'." 2

}
ensure_crate () {

    local crate="${1-}" bin="${2-}"
    shift 2 || true

    [[ -n "${crate}" ]] || die "ensure_crate: requires <crate>" 2
    [[ -n "${bin}" ]]   || die "ensure_crate: requires <bin>" 2

    has cargo || ensure_rust
    tool_source_cargo_env

    tool_crate_bin_ok "${bin}" && return 0

    if ! has cargo-binstall; then
        run cargo install --locked cargo-binstall || die "Failed to install cargo-binstall" 2
        tool_source_cargo_env
        has cargo-binstall || die "cargo-binstall installed but not found in PATH" 2
    fi

    if (( $# == 0 )); then
        local -a extra=()
        is_ci && extra+=( --no-confirm --force )
        run cargo binstall "${crate}" "${extra[@]}" || run cargo install --locked "${crate}"
    else
        run cargo install --locked "${crate}" "$@"
    fi

    tool_source_cargo_env
    tool_crate_bin_ok "${bin}" || die "crate '${crate}' installed but binary '${bin}' not found" 2

}
ensure_cargo_edit () {

    has cargo || ensure_rust
    tool_source_cargo_env

    if has cargo-add && has cargo-rm && has cargo-upgrade; then
        return 0
    fi
    if has cargo-binstall; then
        local -a extra=()
        is_ci && extra+=( --no-confirm --force )

        run cargo binstall cargo-edit "${extra[@]}" || true
    fi
    if ! { has cargo-add && has cargo-rm && has cargo-upgrade; }; then
        run cargo install --locked cargo-edit || die "Failed to install cargo-edit" 2
    fi

    tool_source_cargo_env

    has cargo-add     || die "cargo-edit installed but cargo-add not found" 2
    has cargo-rm      || die "cargo-edit installed but cargo-rm not found" 2
    has cargo-upgrade || die "cargo-edit installed but cargo-upgrade not found" 2

}

tool_python_run () {

    if has python; then
        python "$@"
        return $?
    fi
    if has python3; then
        python3 "$@"
        return $?
    fi
    if has py; then
        py -3 "$@"
        return $?
    fi

    return 127

}
tool_export_python_bin () {

    local dir="$(tool_python_run -c 'import sysconfig; print(sysconfig.get_path("scripts") or "")' 2>/dev/null || true)"
    [[ -n "${dir}" ]] || return 0

    dir="$(tool_to_unix_path "${dir}")"
    tool_export_path_if_dir "${dir}"

}
tool_python_aliases_unix () {

    local target="$(tool_target)"

    case "${target}" in
        linux|macos) ;;
        *) return 0 ;;
    esac

    if ! has python && has python3; then
        ensure_bin_link "python" "$(command -v python3)" || true
    fi
    if ! has pip && has pip3; then
        ensure_bin_link "pip" "$(command -v pip3)" || true
    fi

    tool_hash_clear
    tool_export_python_bin

}
tool_python_ok () {

    local want="${1:-3}" major=""

    tool_python_run -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1 || return 1

    if [[ -n "${want}" && "${want}" =~ ^[0-9]+$ ]]; then
        major="$(tool_python_run -c 'import sys; print(sys.version_info[0])' 2>/dev/null || true)"
        [[ "${major}" =~ ^[0-9]+$ ]] || return 1
        (( major >= want )) || return 1
    fi

    return 0

}
tool_pip_ok () {

    if has pip; then
        pip --version >/dev/null 2>&1
        return $?
    fi
    if has pip3; then
        pip3 --version >/dev/null 2>&1
        return $?
    fi

    tool_python_run -m pip --version >/dev/null 2>&1

}
ensure_python () {

    local want="${1:-${PYTHON_VERSION:-3}}"

    tool_export_python_bin
    tool_python_ok "${want}" && tool_pip_ok && return 0

    ensure_pkg python pip 1>&2

    tool_export_python_bin
    tool_python_aliases_unix
    tool_hash_clear

    tool_python_ok "${want}" || die "Python install did not satisfy requirement." 2
    tool_pip_ok || die "pip is not available after Python install." 2

}

tool_export_npm_bin () {

    local prefix="" dir=""
    has npm || return 0

    prefix="$(npm config get prefix 2>/dev/null || true)"
    [[ -n "${prefix}" ]] || return 0

    prefix="$(tool_to_unix_path "${prefix}")"
    [[ -n "${prefix}" ]] || return 0

    if tool_is_windows_target; then dir="${prefix}"
    else dir="${prefix}/bin"
    fi

    tool_export_path_if_dir "${dir}"

}
tool_export_volta_bin () {

    local localapp="" userprofile=""
    local -a dirs=()
    local dir=""

    dirs+=( "${VOLTA_HOME:-${HOME}/.volta}/bin" )

    if [[ -n "${LOCALAPPDATA:-}" ]]; then
        localapp="$(tool_to_unix_path "${LOCALAPPDATA}")"
        [[ -n "${localapp}" ]] && dirs+=( "${localapp}/Volta/bin" )
    fi
    if [[ -n "${USERPROFILE:-}" ]]; then
        userprofile="$(tool_to_unix_path "${USERPROFILE}")"
        [[ -n "${userprofile}" ]] && dirs+=( "${userprofile}/AppData/Local/Volta/bin" )
    fi

    dirs+=( "/c/Program Files/Volta/bin" )
    dirs+=( "/c/Users/${USERNAME:-}/AppData/Local/Volta/bin" )

    for dir in "${dirs[@]}"; do
        tool_export_path_if_dir "${dir}"
    done

}
tool_export_bun_bin () {

    local userprofile=""
    local -a dirs=()
    local dir=""

    dirs+=( "${BUN_INSTALL:-${HOME}/.bun}/bin" )

    if [[ -n "${USERPROFILE:-}" ]]; then
        userprofile="$(tool_to_unix_path "${USERPROFILE}")"
        [[ -n "${userprofile}" ]] && dirs+=( "${userprofile}/.bun/bin" )
    fi

    for dir in "${dirs[@]}"; do
        tool_export_path_if_dir "${dir}"
    done

}

tool_install_volta_unix () {

    ensure_pkg curl 1>&2

    export VOLTA_HOME="${VOLTA_HOME:-${HOME}/.volta}"
    tool_export_volta_bin

    if ! has volta; then
        run bash -c 'curl -fsSL https://get.volta.sh | bash' || die "Failed to install Volta." 2
    fi

    tool_export_volta_bin
    has volta || die "Volta installed but not found in PATH." 2

}
tool_install_volta_windows () {

    local target="${1:-$(tool_target)}"

    local backend="$(tool_backend "${target}" 2>/dev/null || true)"
    [[ -n "${backend}" ]] || die "No usable backend to install Volta on '${target}'." 2

    case "${backend}" in
        winget)
            run winget install --id Volta.Volta --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
                || run winget upgrade --id Volta.Volta --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
                || die "Failed to install Volta via winget." 2
        ;;
        choco)
            if tool_assume_yes; then
                run choco install -y volta || run choco upgrade -y volta || die "Failed to install Volta via choco." 2
            else
                run choco install volta || run choco upgrade volta || die "Failed to install Volta via choco." 2
            fi
        ;;
        scoop)
            run scoop install volta || run scoop update volta || die "Failed to install Volta via scoop." 2
        ;;
        *)
            die "Unsupported backend '${backend}' for Volta install on '${target}'." 2
        ;;
    esac

    tool_export_volta_bin
    has volta || die "Volta installed but not found in PATH." 2
    run volta setup >/dev/null 2>&1 || true
    tool_export_volta_bin

}
tool_install_node_pacman () {

    local target="${1:-$(tool_target)}" prefix=""

    case "${target}" in
        msys|gitbash)
            if tool_assume_yes; then run pacman -S --needed --noconfirm nodejs
            else run pacman -S --needed nodejs
            fi
        ;;
        mingw)
            prefix="$(tool_mingw_prefix)"
            if tool_assume_yes; then run pacman -S --needed --noconfirm "${prefix}-nodejs"
            else run pacman -S --needed "${prefix}-nodejs"
            fi
        ;;
        *)
            die "tool_install_node_pacman: unsupported target '${target}'" 2
        ;;
    esac

}
tool_install_bun_unix () {

    ensure_pkg curl 1>&2

    export BUN_INSTALL="${BUN_INSTALL:-${HOME}/.bun}"
    tool_export_bun_bin

    run bash -c 'curl -fsSL https://bun.sh/install | bash' || return 1
    tool_export_bun_bin
    has bun

}
tool_install_bun_windows () {

    local target="${1:-$(tool_target)}"
    local backend="$(tool_backend "${target}" 2>/dev/null || true)"

    if has powershell.exe; then
        run powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'irm bun.sh/install.ps1|iex' || true
        tool_export_bun_bin
        has bun && return 0
    fi

    case "${backend}" in
        scoop) run scoop install bun || run scoop update bun || return 1 ;;
        *) return 1 ;;
    esac

    tool_export_bun_bin
    has bun

}
tool_install_bun_via_npm () {

    has npm || return 1
    run npm install -g bun || return 1

    tool_export_npm_bin
    has bun

}

tool_volta_ok () {

    tool_export_volta_bin
    has volta

}
tool_node_ok () {

    local want="${1-}" v="" major=""

    has node || return 1
    has npm  || return 1
    has npx  || return 1

    if [[ -n "${want}" && "${want}" =~ ^[0-9]+$ ]]; then
        v="$(node --version 2>/dev/null || true)"
        v="${v#v}"
        major="${v%%.*}"

        [[ "${major}" =~ ^[0-9]+$ ]] || return 1
        (( major >= want )) || return 1
    fi

    return 0

}
tool_bun_ok () {

    local want="${1-}" v="" major=""

    has bun || return 1

    if [[ -n "${want}" && "${want}" =~ ^[0-9]+$ ]]; then
        v="$(bun --version 2>/dev/null || true)"
        major="${v%%.*}"

        [[ "${major}" =~ ^[0-9]+$ ]] || return 1
        (( major >= want )) || return 1
    fi

    return 0

}
tool_node_spec () {

    local want="${1-}"

    if [[ -z "${want}" ]]; then
        printf '%s\n' "node"
        return 0
    fi
    case "${want}" in
        node|node@*) printf '%s\n' "${want}" ;;
        *)           printf '%s\n' "node@${want}" ;;
    esac

}

ensure_volta () {

    tool_export_volta_bin
    has volta && return 0

    local target="$(tool_target)"

    case "${target}" in
        linux|macos) tool_install_volta_unix ;;
        msys|mingw|gitbash|cygwin) tool_install_volta_windows "${target}" ;;
        *) die "Unsupported target for Volta install: ${target}" 2 ;;
    esac

    tool_hash_clear
    tool_export_volta_bin
    has volta || die "Volta install failed." 2

}
ensure_node () {

    local want="${1:-${NODE_VERSION:-}}"

    tool_export_volta_bin
    tool_export_npm_bin
    tool_node_ok "${want}" && return 0

    local target="$(tool_target)"
    local backend="$(tool_backend "${target}" 2>/dev/null || true)"

    case "${target}" in
        linux|macos)
            ensure_volta
            run volta install "$(tool_node_spec "${want}")" || die "Failed to install Node via Volta." 2
        ;;
        msys|mingw|gitbash)
            case "${backend}" in
                pacman)
                    tool_install_node_pacman "${target}"
                ;;
                winget|choco|scoop)
                    ensure_volta
                    run volta install "$(tool_node_spec "${want}")" || die "Failed to install Node via Volta." 2
                ;;
                *)
                    die "No supported backend for Node on '${target}'." 2
                ;;
            esac
        ;;
        cygwin)
            ensure_volta
            run volta install "$(tool_node_spec "${want}")" || die "Failed to install Node via Volta." 2
        ;;
        *)
            die "Unsupported target for Node install: ${target}" 2
        ;;
    esac

    tool_hash_clear
    tool_export_volta_bin
    tool_export_npm_bin
    tool_node_ok "${want}" || die "Node install did not satisfy requirement." 2

}
ensure_pnpm () {

    local want="${1:-${PNPM_VERSION:-}}"

    ensure_node "${NODE_VERSION:-}"

    if has pnpm; then
        return 0
    fi

    ensure_volta

    if [[ -n "${want}" ]]; then
        run volta install "pnpm@${want}" || die "Failed to install pnpm via Volta." 2
    else
        run volta install pnpm || die "Failed to install pnpm via Volta." 2
    fi

    tool_export_volta_bin

    has pnpm || die "pnpm installed but not found in PATH." 2

}
ensure_bun () {

    local want="${1:-${BUN_VERSION:-}}"
    local target=""

    tool_export_bun_bin
    tool_export_npm_bin
    tool_bun_ok "${want}" && return 0

    target="$(tool_target)"

    case "${target}" in
        linux|macos)
            tool_install_bun_unix || tool_install_bun_via_npm || die "Failed to install Bun." 2
        ;;
        msys|mingw|gitbash|cygwin)
            tool_install_bun_windows "${target}" || tool_install_bun_via_npm || die "Failed to install Bun." 2
        ;;
        *)
            die "Unsupported target for Bun install: ${target}" 2
        ;;
    esac

    tool_hash_clear
    tool_export_bun_bin
    tool_export_npm_bin
    tool_bun_ok "${want}" || die "Bun install did not satisfy requirement." 2

}
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "core files should not be run directly." >&2; exit 2; }
[[ -n "${CORE_LOADED:-}" ]] && return 0

readonly CORE_LOADED=1
readonly CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)"

YES="${YES:-0}"
VERBOSE="${VERBOSE:-0}"

source "${CORE_DIR}/env.sh"
source "${CORE_DIR}/fsys.sh"
source "${CORE_DIR}/parse.sh"
source "${CORE_DIR}/pkg.sh"
source "${CORE_DIR}/tool.sh"

bash_die () {

    local msg="${1:-ensure-bash: failed}" code="${2:-2}"

    printf '%s\n' "${msg}" >&2
    exit "${code}"

}
bash_log () {

    printf '%s\n' "${1-}" >&2

}
bash_has () {

    command -v "${1-}" >/dev/null 2>&1

}
bash_sudo () {

    if (( EUID == 0 )); then
        "$@"
        return $?
    fi

    bash_has sudo || return 127
    sudo "$@"

}
bash_trim () {

    local s="${1-}"

    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"

    printf '%s' "${s}"

}

bash_ver_norm () {

    local ver="${1-}" major="0" minor="0"

    ver="$(bash_trim "${ver}")"
    ver="${ver%%[^0-9.]*}"

    if [[ "${ver}" =~ ^([0-9]+)(\.([0-9]+))? ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[3]:-0}"
    fi

    printf '%s.%s' "${major}" "${minor}"

}
bash_ver_ge () {

    local cur="${1-}" req="${2-}"
    local cur_major="0" cur_minor="0"
    local req_major="0" req_minor="0"

    cur="$(bash_ver_norm "${cur}")"
    req="$(bash_ver_norm "${req}")"

    cur_major="${cur%%.*}"
    cur_minor="${cur#*.}"
    req_major="${req%%.*}"
    req_minor="${req#*.}"

    (( cur_major > req_major )) && return 0
    (( cur_major < req_major )) && return 1
    (( cur_minor >= req_minor ))

}
bash_current_version () {

    if [[ -n "${BASH_VERSINFO[0]:-}" ]]; then
        printf '%s.%s' "${BASH_VERSINFO[0]:-0}" "${BASH_VERSINFO[1]:-0}"
        return 0
    fi

    printf '0.0'

}
bash_version_from_bin () {

    local bin="${1-}" out=""

    [[ -n "${bin}" && -x "${bin}" ]] || { printf '0.0'; return 0; }

    out="$("${bin}" -c 'printf "%s.%s" "${BASH_VERSINFO[0]:-0}" "${BASH_VERSINFO[1]:-0}"' 2>/dev/null || true)"
    [[ -n "${out}" ]] || out="0.0"

    printf '%s' "$(bash_ver_norm "${out}")"

}
bash_path_prepend () {

    local dir="${1-}"

    [[ -n "${dir}" && -d "${dir}" ]] || return 0

    case ":${PATH}:" in
        *":${dir}:"*) ;;
        *) PATH="${dir}:${PATH}" ;;
    esac

    export PATH

}
bash_path_bootstrap () {

    bash_path_prepend "/opt/homebrew/bin"
    bash_path_prepend "/usr/local/bin"
    bash_path_prepend "/home/linuxbrew/.linuxbrew/bin"
    bash_path_prepend "/mingw64/bin"
    bash_path_prepend "/usr/bin"
    bash_path_prepend "/bin"

    [[ -n "${LOCALAPPDATA:-}" ]] && bash_path_prepend "${LOCALAPPDATA}/Programs/Git/bin"
    [[ -n "${LOCALAPPDATA:-}" ]] && bash_path_prepend "${LOCALAPPDATA}/Programs/Git/usr/bin"
    [[ -n "${USERPROFILE:-}" ]] && bash_path_prepend "${USERPROFILE}/scoop/apps/git/current/bin"
    [[ -n "${USERPROFILE:-}" ]] && bash_path_prepend "${USERPROFILE}/scoop/apps/git/current/usr/bin"
    [[ -n "${USERPROFILE:-}" ]] && bash_path_prepend "${USERPROFILE}/scoop/apps/msys2/current/usr/bin"

}
bash_is_wsl () {

    [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
    [[ -n "${WSL_INTEROP:-}" ]] && return 0
    [[ -r /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && return 0
    [[ -r /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null && return 0

    return 1

}
bash_os_kind () {

    local uname_s="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    case "${uname_s}" in
        linux*) echo "linux" ;;
        darwin*) echo "macos" ;;
        msys*|mingw*|cygwin*) echo "windows" ;;
        *) echo "unknown" ;;
    esac

}
bash_find_best_candidate () {

    local req="${1-}" best_bin="" best_ver="0.0" bin="" ver=""
    local -a candidates=()

    bash_path_bootstrap

    candidates+=(
        "$(command -v bash 2>/dev/null || true)"
        "/usr/bin/bash"
        "/bin/bash"
        "/usr/local/bin/bash"
        "/opt/homebrew/bin/bash"
        "/home/linuxbrew/.linuxbrew/bin/bash"
        "/mingw64/bin/bash.exe"
        "/usr/bin/bash.exe"
        "/bin/bash.exe"
        "/c/Program Files/Git/bin/bash.exe"
        "/c/Program Files/Git/usr/bin/bash.exe"
        "/c/tools/msys64/usr/bin/bash.exe"
        "${USERPROFILE:-}/scoop/apps/git/current/bin/bash.exe"
        "${USERPROFILE:-}/scoop/apps/git/current/usr/bin/bash.exe"
        "${USERPROFILE:-}/scoop/apps/msys2/current/usr/bin/bash.exe"
        "${LOCALAPPDATA:-}/Programs/Git/bin/bash.exe"
        "${LOCALAPPDATA:-}/Programs/Git/usr/bin/bash.exe"
    )

    for bin in "${candidates[@]}"; do

        [[ -n "${bin}" && -x "${bin}" ]] || continue

        ver="$(bash_version_from_bin "${bin}")"

        if bash_ver_ge "${ver}" "${req}" && ! bash_ver_ge "${best_ver}" "${ver}"; then
            best_bin="${bin}"
            best_ver="${ver}"
        fi

    done

    [[ -n "${best_bin}" ]] || return 1

    printf '%s\n' "${best_bin}"

}

bash_try_pkg_linux () {

    if bash_has apt-get; then
        bash_sudo apt-get update || true
        bash_sudo apt-get install -y bash
        return $?
    fi
    if bash_has apt; then
        bash_sudo apt update || true
        bash_sudo apt install -y bash
        return $?
    fi
    if bash_has dnf; then
        bash_sudo dnf install -y bash
        return $?
    fi
    if bash_has yum; then
        bash_sudo yum install -y bash
        return $?
    fi
    if bash_has pacman; then
        bash_sudo pacman -Sy --noconfirm bash
        return $?
    fi
    if bash_has zypper; then
        bash_sudo zypper --non-interactive install bash
        return $?
    fi
    if bash_has apk; then
        bash_sudo apk add --no-cache bash
        return $?
    fi

    return 1

}
bash_try_pkg_brew () {

    bash_has brew || return 1

    brew update || true
    brew install bash || brew upgrade bash || return 1

}
bash_try_pkg_winget_git () {

    bash_has winget || return 1

    winget install --id Git.Git --exact --accept-package-agreements --accept-source-agreements --silent \
        || winget upgrade --id Git.Git --exact --accept-package-agreements --accept-source-agreements --silent

}
bash_try_pkg_choco_git () {

    bash_has choco || return 1
    choco upgrade git.install -y --no-progress || choco install git.install -y --no-progress

}
bash_try_pkg_scoop_git () {

    bash_has scoop || return 1
    scoop install git || scoop update git

}
bash_try_pkg_scoop_msys2 () {

    bash_has scoop || return 1
    scoop install msys2 || scoop update msys2 || return 1

    local msys_bash="${USERPROFILE:-}/scoop/apps/msys2/current/usr/bin/bash.exe"
    [[ -x "${msys_bash}" ]] || return 1

    "${msys_bash}" -lc 'pacman -Sy --noconfirm bash' || true

}
bash_try_pkg_msys2_native () {

    bash_has pacman || return 1
    pacman -Sy --noconfirm bash

}

bash_install_for_os () {

    local os="${1-}"

    case "${os}" in
        linux) bash_try_pkg_linux || bash_try_pkg_brew ;;
        macos) bash_try_pkg_brew ;;
        windows)
            if bash_is_wsl; then
                bash_try_pkg_linux || bash_try_pkg_brew
            else
                bash_try_pkg_msys2_native || bash_try_pkg_winget_git || bash_try_pkg_choco_git || bash_try_pkg_scoop_git || bash_try_pkg_scoop_msys2
            fi
        ;;
        *)
            return 1
        ;;
    esac

}
ensure_bash () {

    local req="" cur_ver="" os="" best_bin="" best_ver=""
    local -a reexec_argv=()

    req="$(bash_ver_norm "${1:-${BASH_MIN_VERSION:-5.2}}")"
    shift || true

    reexec_argv=( "$@" )
    cur_ver="$(bash_current_version)"
    os="$(bash_os_kind)"

    if bash_ver_ge "${cur_ver}" "${req}"; then
        export BASH_BIN="${BASH:-$(command -v bash 2>/dev/null || true)}"
        return 0
    fi
    if [[ -n "${BASH_BOOTSTRAPPED:-}" ]]; then
        bash_die "ensure-bash: requires bash >= ${req}, current=${cur_ver}" 2
    fi

    case "${os}" in
        linux)   bash_log "ensure-bash: current=${cur_ver}, need>=${req}; trying Linux managers" ;;
        macos)   bash_log "ensure-bash: current=${cur_ver}, need>=${req}; trying Homebrew" ;;
        windows) bash_log "ensure-bash: current=${cur_ver}, need>=${req}; trying Windows/MSYS2/Git managers" ;;
        *)       bash_die "ensure-bash: unsupported OS '${os}'" 2 ;;
    esac

    bash_install_for_os "${os}" || bash_die "ensure-bash: failed to install or upgrade bash >= ${req}" 2
    bash_path_bootstrap

    best_bin="$(bash_find_best_candidate "${req}" || true)"
    [[ -n "${best_bin}" ]] || bash_die "ensure-bash: no bash >= ${req} found after install/upgrade" 2

    best_ver="$(bash_version_from_bin "${best_bin}")"
    bash_ver_ge "${best_ver}" "${req}" || bash_die "ensure-bash: found bash ${best_ver}, need >= ${req}" 2

    export BASH_BOOTSTRAPPED=1
    export BASH_BIN="${best_bin}"

    exec "${best_bin}" "$0" "${reexec_argv[@]}" || bash_die "ensure-bash: failed to re-exec via '${best_bin}'" 2

}

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

year () {

    LC_ALL=C command date '+%Y'

}
month () {

    LC_ALL=C command date '+%m'

}
day () {

    LC_ALL=C command date '+%d'

}
date_only () {

    LC_ALL=C command date '+%Y-%m-%d'

}
time_only () {

    LC_ALL=C command date '+%H:%M:%S'

}
datetime () {

    LC_ALL=C command date '+%Y-%m-%d %H:%M:%S'

}

os_name () {

    local u="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    case "${u}" in
        linux*) printf '%s' linux ;;
        darwin*) printf '%s' macos ;;
        msys*|mingw*|cygwin*) printf '%s' windows ;;
        *) printf '%s' unknown ;;
    esac

}
is_linux () {

    [[ "$(os_name)" == "linux" ]]

}
is_macos () {

    [[ "$(os_name)" == "macos" ]]

}
is_mac () {

    is_macos

}
is_windows () {

    [[ "$(os_name)" == "windows" ]]

}
is_wsl () {

    [[ -n "${WSL_INTEROP:-}" || -n "${WSL_DISTRO_NAME:-}" ]] && return 0
    [[ -r /proc/version ]] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && return 0
    [[ -r /proc/sys/kernel/osrelease ]] && grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null && return 0

    return 1

}
is_ci () {

    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${GITLAB_CI:-}" || -n "${BUILDKITE:-}" || -n "${TF_BUILD:-}" ]]

}
is_ci_pull () {

    is_ci && [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" || -n "${CI_MERGE_REQUEST_IID:-}" ]]

}
is_ci_push () {

    is_ci && [[ "${GITHUB_EVENT_NAME:-}" == "push" || "${CI_PIPELINE_SOURCE:-}" == "push" ]]

}
is_ci_tag_push () {

    is_ci_push && [[ "${GITHUB_REF:-}" == refs/tags/* || -n "${CI_COMMIT_TAG:-}" ]]

}

slugify () {

    local s="${1-}"
    [[ -n "${s}" ]] || { printf '%s' ""; return 0; }

    s="$(LC_ALL=C printf '%s' "${s}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-')"
    s="${s#-}"
    s="${s%-}"

    printf '%s' "${s}"

}
uc_first () {

    local s="${1:-}"
    [[ -n "${s}" ]] || { printf '%s' ""; return 0; }
    printf '%s%s' "$(printf '%s' "${s:0:1}" | tr '[:lower:]' '[:upper:]')" "${s:1}"

}
unique_list () {

    local -n in="${1}"
    local -a out=()
    local -A seen=()
    local x=""

    for x in "${in[@]-}"; do

        [[ -n "${x}" ]] || continue
        [[ -n "${seen["$x"]+x}" ]] && continue

        seen["$x"]=1
        out+=( "$x" )

    done

    in=( "${out[@]}" )

}
is_danger_path () {

    local p="${1:-}"

    case "${p}" in
        ""|"-"*|"/"|"."|".."|"~"|"/."|"/.."|"/c"|"/c/"|"/d"|"/d/"|"/e"|"/e/"|"/f"|"/f/"|[A-Za-z]:|[A-Za-z]:/|[A-Za-z]:\\)
            return 0
        ;;
    esac

    return 1

}
assert_safe_path () {

    local p="${1:-}" label="${2:-path}"
    [[ -n "${p}" ]] || die "${label}: empty path"
    is_danger_path "${p}" && die "${label}: refused dangerous path '${p}'"

}
validate_alias () {

    local a="${1:-}"

    [[ -n "${a}" ]] || die "validate_alias: empty alias"
    [[ "${a}" != *"/"* && "${a}" != *"\\"* ]] || die "validate_alias: invalid alias '${a}'"
    [[ "${a}" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || die "validate_alias: invalid alias '${a}'"

}
ignore_list () {

    printf '%s\n' \
        ".git" \
        ".vscode" \
        ".idea" \
        ".DS_Store" \
        "Thumbs.db" \
        "out" \
        "dist" \
        "build" \
        "coverage" \
        "target" \
        "vendor" \
        "venv" \
        "node_modules" \
        ".nyc_output" \
        ".next" \
        ".nuxt" \
        ".turbo" \
        "__pycache__" \
        ".venv" \
        ".pytest_cache" \
        ".mypy_cache" \
        ".ruff_cache" \
        ".cache" \
        ".dart_tool" \
        ".flutter-plugins" \
        ".flutter-plugins-dependencies" \
        "pubspec.lock" \
        "obj" \
        ".vs" \
        ".xmake" \
        ".build" \
        ".ccls-cache" \
        "compile_commands.json" \
        ".zig-cache" \
        "zig-out" \
        "gradlew" \
        "mvnw" \
        ".mojo" \
        ".modular"

}
which_lang () {

    local dir="${1:-${PWD}}" hit=""

    [[ -d "${dir}" ]] || dir="$(dirname -- "${dir}")"
    [[ -d "${dir}" ]] || { printf '%s' "null"; return 0; }

    while :; do

        if [[ -f "${dir}/Cargo.toml" ]]; then printf '%s' "rust"; return 0; fi
        if [[ -f "${dir}/build.zig" || -f "${dir}/build.zig.zon" ]]; then printf '%s' "zig"; return 0; fi
        if [[ -f "${dir}/go.mod" || -f "${dir}/go.work" ]]; then printf '%s' "go"; return 0; fi

        if compgen -G "${dir}/*.sln" >/dev/null || compgen -G "${dir}/*.csproj" >/dev/null || compgen -G "${dir}/*.fsproj" >/dev/null || [[ -f "${dir}/Directory.Build.props" || -f "${dir}/Directory.Build.targets" || -f "${dir}/global.json" ]]; then
            printf '%s' "csharp"
            return 0
        fi
        if [[ -f "${dir}/settings.gradle" || -f "${dir}/settings.gradle.kts" || -f "${dir}/build.gradle" || -f "${dir}/build.gradle.kts" || -f "${dir}/pom.xml" || -f "${dir}/gradlew" || -f "${dir}/mvnw" ]]; then
            printf '%s' "java"
            return 0
        fi

        if [[ -f "${dir}/pubspec.yaml" ]]; then printf '%s' "dart"; return 0; fi
        if [[ -f "${dir}/composer.json" || -f "${dir}/artisan" ]]; then printf '%s' "php"; return 0; fi

        if [[ -f "${dir}/pyproject.toml" || -f "${dir}/uv.toml" || -f "${dir}/uv.lock" || -f "${dir}/requirements.txt" || -f "${dir}/Pipfile" || -f "${dir}/poetry.lock" ]]; then
            printf '%s' "python"
            return 0
        fi
        if [[ -f "${dir}/mojoproject.toml" || -f "${dir}/mod.toml" ]]; then
            printf '%s' "mojo"
            return 0
        fi

        hit="$(find "${dir}" -maxdepth 3 -type f -name '*.mojo' -print -quit 2>/dev/null || true)"
        [[ -n "${hit}" ]] && { printf '%s' "mojo"; return 0; }

        if [[ -f "${dir}/bun.lockb" || -f "${dir}/bun.lock" || -f "${dir}/bunfig.toml" ]]; then printf '%s' "bun"; return 0; fi
        if [[ -f "${dir}/package.json" ]]; then printf '%s' "node"; return 0; fi

        if [[ -f "${dir}/xmake.lua" || -f "${dir}/CMakeLists.txt" || -f "${dir}/meson.build" || -f "${dir}/Makefile" || -f "${dir}/conanfile.txt" || -f "${dir}/conanfile.py" ]]; then
            hit="$(find "${dir}" -maxdepth 6 -type f \( \
                -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' -o -name '*.C' -o \
                -name '*.hpp' -o -name '*.hh' -o -name '*.hxx' -o \
                -name '*.ipp' -o -name '*.inl' -o \
                -name '*.ixx' -o -name '*.cppm' -o -name '*.cxxm' \
            \) -print -quit 2>/dev/null || true)"

            [[ -n "${hit}" ]] && { printf '%s' "cpp"; return 0; }
            printf '%s' "c"
            return 0
        fi
        if [[ -f "${dir}/rocks.toml" ]] || compgen -G "${dir}/*.rockspec" >/dev/null; then
            printf '%s' "lua"
            return 0
        fi

        hit="$(find "${dir}" -maxdepth 2 -type f -name '*.lua' -print -quit 2>/dev/null || true)"
        [[ -n "${hit}" ]] && { printf '%s' "lua"; return 0; }

        hit="$(find "${dir}" -maxdepth 2 -type f -name '*.sh' -print -quit 2>/dev/null || true)"
        [[ -n "${hit}" ]] && { printf '%s' "bash"; return 0; }

        [[ "$(dirname -- "${dir}")" != "${dir}" ]] || break
        dir="$(dirname -- "${dir}")"

    done

    printf '%s' "null"

}

tmp_dir () {

    local tag="${1:-tmp}" base="${2:-${TMPDIR:-/tmp}}" tmp=""

    mkdir -p "${base}" 2>/dev/null || true
    tmp="$(mktemp -d "${base%/}/${tag}.XXXXXX" 2>/dev/null || true)"

    if [[ -z "${tmp}" || ! -d "${tmp}" ]]; then
        tmp="${base%/}/${tag}.$$.$RANDOM"
        mkdir -p "${tmp}" 2>/dev/null || die "tmp_dir: failed (${base})"
    fi

    chmod 700 -- "${tmp}" 2>/dev/null || true
    printf '%s' "${tmp}"

}
tmp_file () {

    local tag="${1:-tmp}" base="${2:-${TMPDIR:-/tmp}}" dir="" tmp=""

    dir="$(tmp_dir "${tag}" "${base}")"
    tmp="$(mktemp "${dir%/}/${tag}.XXXXXX" 2>/dev/null || true)"

    if [[ -z "${tmp}" || ! -f "${tmp}" ]]; then
        tmp="${dir%/}/${tag}"
        : > "${tmp}" 2>/dev/null || die "tmp_file: failed (${dir})"
    fi

    chmod 600 -- "${tmp}" 2>/dev/null || true
    printf '%s' "${tmp}"

}
abs_dir () {

    local p="${1:-}" d=""

    if [[ -z "${p}" ]]; then
        pwd -P
        return 0
    fi

    if [[ -d "${p}" ]]; then d="${p}"
    else d="$(dirname -- "${p}")"
    fi

    ( cd -- "${d}" 2>/dev/null && pwd -P ) || return 1

}
config_file () {

    local name="${1:-}" ext1="${2:-}" ext2="${3:-}" base=""
    [[ -n "${name}" ]] || { printf '\n'; return 0; }
    base="${name%%-*}"

    if [[ -n "${ext1}" && -f "${name}.${ext1}" ]]; then printf '%s\n' "${name}.${ext1}"; return 0; fi
    if [[ -n "${ext1}" && -f ".${name}.${ext1}" ]]; then printf '%s\n' ".${name}.${ext1}"; return 0; fi
    if [[ -n "${ext2}" && -f "${name}.${ext2}" ]]; then printf '%s\n' "${name}.${ext2}"; return 0; fi
    if [[ -n "${ext2}" && -f ".${name}.${ext2}" ]]; then printf '%s\n' ".${name}.${ext2}"; return 0; fi

    if [[ "${base}" != "${name}" ]]; then
        if [[ -n "${ext1}" && -f "${base}.${ext1}" ]]; then printf '%s\n' "${base}.${ext1}"; return 0; fi
        if [[ -n "${ext1}" && -f ".${base}.${ext1}" ]]; then printf '%s\n' ".${base}.${ext1}"; return 0; fi
        if [[ -n "${ext2}" && -f "${base}.${ext2}" ]]; then printf '%s\n' "${base}.${ext2}"; return 0; fi
        if [[ -n "${ext2}" && -f ".${base}.${ext2}" ]]; then printf '%s\n' ".${base}.${ext2}"; return 0; fi
    fi

    printf '\n'

}
home_path () {

    local h="${HOME:-}"

    if [[ -n "${h}" ]]; then
        printf '%s' "${h}"
        return 0
    fi

    h="$(cd ~ 2>/dev/null && pwd)" || h=""
    [[ -n "${h}" ]] || die "home_path: HOME not set and cannot resolve"

    printf '%s' "${h}"

}
rc_path () {

    local shell_name="${SHELL##*/}"

    case "${shell_name}" in
        zsh)  printf '%s' "$(home_path)/.zshrc" ;;
        fish) printf '%s' "$(home_path)/.config/fish/config.fish" ;;
        *)    printf '%s' "$(home_path)/.bashrc" ;;
    esac

}
remove_path () {

    local p="${1:-}" label="${2:-remove_path}"

    assert_safe_path "${p}" "${label}"
    [[ -e "${p}" || -L "${p}" ]] || return 0

    run rm -rf "${p}"

}
ln_sf () {

    local src="${1:-}" dst="${2:-}"

    [[ -n "${src}" && -n "${dst}" ]] || die "ln_sf: usage: ln_sf <src> <dst>"
    [[ -e "${src}" || -L "${src}" ]] || die "ln_sf: missing source '${src}'"

    assert_safe_path "${dst}" "ln_sf"
    ensure_dir "$(dirname -- "${dst}")"
    remove_path "${dst}" "ln_sf"

    run ln -s "${src}" "${dst}" && return 0

    if [[ -d "${src}" ]]; then run cp -R "${src}" "${dst}"
    else run cp "${src}" "${dst}"
    fi

}

ensure_dir () {

    local dir="${1:-}"

    [[ -n "${dir}" ]] || die "ensure_dir: missing dir"
    [[ -d "${dir}" ]] && return 0

    run mkdir -p "${dir}"

}
ensure_file () {

    local file="${1:-}"

    [[ -n "${file}" ]] || die "ensure_file: missing file"
    [[ -f "${file}" ]] && return 0

    ensure_dir "$(dirname -- "${file}")"
    run touch "${file}"

}
ensure_symlink () {

    local src="${1:-}" dst="${2:-}"

    [[ -n "${src}" && -n "${dst}" ]] || die "ensure_symlink: usage: ensure_symlink <src> <dst>"
    [[ -e "${src}" || -L "${src}" ]] || die "ensure_symlink: missing source '${src}'"

    assert_safe_path "${dst}" "ensure_symlink"
    ensure_dir "$(dirname -- "${dst}")"
    remove_path "${dst}" "ensure_symlink"

    run ln -s "${src}" "${dst}"

}
ensure_bin_link () {

    local alias_name="${1:-}" target="${2:-}" prefix="${3:-$(home_path)/.local}"
    local bin_dir="${prefix}/bin" bin_path="${bin_dir}/${alias_name}"

    [[ -n "${target}" ]] || die "ensure_bin_link: missing target"

    validate_alias "${alias_name}"
    ensure_dir "${bin_dir}"
    ensure_symlink "${target}" "${bin_path}"

}

pkg_hash_clear () {

    hash -r 2>/dev/null || true

}
pkg_assume_yes () {

    (( YES )) || is_ci

}
pkg_target () {

    if is_wsl; then
        printf '%s' "linux"
        return 0
    fi

    case "$(os_name)" in
        linux)
            printf '%s' "linux"
            return 0
        ;;
        macos)
            printf '%s' "macos"
            return 0
        ;;
    esac

    local uname_s="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    case "${uname_s}" in
        msys*)   printf '%s' "msys" ;;
        mingw*)
            if [[ -n "${MSYSTEM:-}" || -n "${MSYSTEM_PREFIX:-}" || -d /etc/pacman.d ]]; then
                printf '%s' "mingw"
            else
                printf '%s' "gitbash"
            fi
        ;;
        cygwin*) printf '%s' "cygwin" ;;
        *)       printf '%s' "unknown" ;;
    esac

}
pkg_require_target () {

    case "${1:-}" in
        linux|macos|msys|mingw|gitbash|cygwin) return 0 ;;
    esac

    die "pkg: unsupported target '${1:-}'." 2

}
pkg_with_privilege () {

    local target="${1-}"
    shift || true

    case "${target}" in
        linux|macos) ;;
        *) run "$@"; return $? ;;
    esac

    if (( ${EUID:-$(id -u 2>/dev/null || printf '%s' 1)} == 0 )); then
        run "$@"
        return $?
    fi
    if has sudo; then
        if is_ci; then run sudo -n "$@"
        else run sudo "$@"
        fi
        return $?
    fi
    if has doas; then
        if is_ci; then run doas -n "$@"
        else run doas "$@"
        fi
        return $?
    fi

    die "pkg: root privileges required (sudo/doas not found)." 2

}
pkg_backend () {

    local target="${1:-$(pkg_target)}"

    case "${target}" in
        linux)
            if has apt-get; then printf '%s' "apt"; return 0; fi
            if has dnf;     then printf '%s' "dnf"; return 0; fi
            if has yum;     then printf '%s' "yum"; return 0; fi
            if has pacman;  then printf '%s' "pacman"; return 0; fi
            if has zypper;  then printf '%s' "zypper"; return 0; fi
            if has apk;     then printf '%s' "apk"; return 0; fi
            if has brew;    then printf '%s' "brew"; return 0; fi
        ;;
        macos)
            has brew || die "pkg: Homebrew not found on macOS." 2
            printf '%s' "brew"
            return 0
        ;;
        msys|mingw|gitbash)
            if has pacman; then printf '%s' "pacman"; return 0; fi
            if has winget; then printf '%s' "winget"; return 0; fi
            if has choco;  then printf '%s' "choco"; return 0; fi
            if has scoop;  then printf '%s' "scoop"; return 0; fi
        ;;
        cygwin)
            if has apt-cyg;          then printf '%s' "apt-cyg"; return 0; fi
            if has setup-x86_64.exe; then printf '%s' "cygwin-setup"; return 0; fi
            if has setup-x86.exe;    then printf '%s' "cygwin-setup"; return 0; fi
            if has winget;           then printf '%s' "winget"; return 0; fi
            if has choco;            then printf '%s' "choco"; return 0; fi
            if has scoop;            then printf '%s' "scoop"; return 0; fi
        ;;
    esac

    return 1

}
pkg_mingw_prefix () {

    case "${MSYSTEM:-}" in
        MINGW64)    printf '%s' "mingw-w64-x86_64" ;;
        MINGW32)    printf '%s' "mingw-w64-i686" ;;
        UCRT64)     printf '%s' "mingw-w64-ucrt-x86_64" ;;
        CLANG64)    printf '%s' "mingw-w64-clang-x86_64" ;;
        CLANG32)    printf '%s' "mingw-w64-clang-i686" ;;
        CLANGARM64) printf '%s' "mingw-w64-clang-aarch64" ;;
        *)          printf '%s' "mingw-w64-x86_64" ;;
    esac

}
pkg_apt_update_once () {

    (( ${PKG_APT_UPDATED:-0} )) && return 0
    PKG_APT_UPDATED=1

    pkg_with_privilege linux apt-get update >/dev/null 2>&1 || pkg_with_privilege linux apt-get update

}

pkg_is_llvm_family () {

    case "${1-}" in
        clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config) return 0 ;;
    esac

    return 1

}
pkg_is_coreutils_name () {

    case "${1-}" in
        mv|cp|rm|ln|mkdir|rmdir|cat|touch|head|tail|cut|tr|sort|uniq|wc|date|sleep|mktemp|basename|dirname|realpath|tee|chmod|readlink|stat)
            return 0
        ;;
    esac

    return 1

}
pkg_is_findutils_name () {

    case "${1-}" in
        find|xargs) return 0 ;;
    esac

    return 1

}
pkg_is_python_family () {

    case "${1-}" in
        python|pip) return 0 ;;
    esac

    return 1

}
pkg_is_macos_managed_want () {

    local want="${1-}"

    pkg_is_llvm_family "${want}" && return 0
    pkg_is_coreutils_name "${want}" && return 0
    pkg_is_findutils_name "${want}" && return 0

    case "${want}" in
        awk|sed|grep) return 0 ;;
    esac

    return 1

}

pkg_user_bin_dir () {

    printf '%s' "$(home_path)/.local/bin"

}
pkg_activate_user_bin () {

    local dir="$(pkg_user_bin_dir)"
    [[ -d "${dir}" ]] || return 0

    case ":${PATH}:" in
        *":${dir}:"*) ;;
        *) PATH="${dir}:${PATH}" ;;
    esac

    export PATH

}
pkg_cmd_name () {

    printf '%s' "${1-}"

}
pkg_verify_macos_managed_command () {

    local cmd="${1-}" path=""
    [[ -n "${cmd}" ]] || return 1

    pkg_activate_user_bin

    path="$(command -v "${cmd}" 2>/dev/null || true)"
    [[ -n "${path}" ]] || return 1
    [[ "${path}" != "/usr/bin/${cmd}" && "${path}" != "/bin/${cmd}" ]]

}
pkg_has_any () {

    local cmd=""

    for cmd in "$@"; do

        [[ -n "${cmd}" ]] || continue
        has "${cmd}" && return 0

    done

    return 1

}
pkg_verify_one () {

    local target="${1-}" want="${2-}"

    if [[ "${target}" == "macos" ]] && pkg_is_macos_managed_want "${want}"; then
        case "${want}" in
            clang|clang-dev)
                pkg_verify_macos_managed_command "clang"
                return $?
            ;;
            llvm|llvm-dev|llvm-config)
                pkg_verify_macos_managed_command "llvm-config" || pkg_verify_macos_managed_command "clang"
                return $?
            ;;
            libclang|libclang-dev)
                pkg_verify_macos_managed_command "llvm-config" || pkg_verify_macos_managed_command "clang"
                return $?
            ;;
            *)
                pkg_verify_macos_managed_command "$(pkg_cmd_name "${want}")"
                return $?
            ;;
        esac
    fi
    case "${want}" in
        python)
            pkg_has_any python python3
            return $?
        ;;
        pip)
            pkg_has_any pip pip3
            return $?
        ;;
        llvm|llvm-dev|llvm-config)
            pkg_has_any llvm-config llvm-ar llc
            return $?
        ;;
        clang|clang-dev)
            has clang
            return $?
        ;;
        libclang|libclang-dev)
            pkg_has_any clang llvm-config llc
            return $?
        ;;
    esac

    has "$(pkg_cmd_name "${want}")"

}
pkg_collect_missing () {

    local -n out_ref="${1}"
    local target="${2-}" want=""
    shift 2 || true

    out_ref=()

    for want in "$@"; do

        [[ -n "${want}" ]] || continue
        pkg_verify_one "${target}" "${want}" || out_ref+=( "${want}" )

    done

}

pkg_map_linux_native () {

    local backend="${1-}" want="${2-}"

    if pkg_is_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_is_findutils_name "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        git|gh|jq|curl|perl|grep|sed)
            printf '%s' "${want}"
        ;;
        awk)
            printf '%s' "gawk"
        ;;
        python)
            case "${backend}" in
                apt|dnf|yum|zypper) printf '%s' "python3" ;;
                pacman)             printf '%s' "python" ;;
                apk)                printf '%s' "python3" ;;
                brew)               printf '%s' "python" ;;
                *)                  printf '%s' "python3" ;;
            esac
        ;;
        pip)
            case "${backend}" in
                apt|dnf|yum|zypper) printf '%s' "python3-pip" ;;
                pacman)             printf '%s' "python-pip" ;;
                apk)                printf '%s' "py3-pip" ;;
                brew)               printf '%s' "python" ;;
                *)                  printf '%s' "python3-pip" ;;
            esac
        ;;
        clang)
            printf '%s' "clang"
        ;;
        clang-dev|libclang|libclang-dev)
            case "${backend}" in
                apt)            printf '%s' "libclang-dev" ;;
                dnf|yum|zypper) printf '%s' "clang-devel" ;;
                pacman)         printf '%s' "clang" ;;
                apk)            printf '%s' "clang-dev" ;;
                brew)           printf '%s' "llvm" ;;
                *)              printf '%s' "libclang-dev" ;;
            esac
        ;;
        llvm|llvm-dev|llvm-config)
            case "${backend}" in
                apt)            printf '%s' "llvm-dev" ;;
                dnf|yum|zypper) printf '%s' "llvm-devel" ;;
                pacman)         printf '%s' "llvm" ;;
                apk)            printf '%s' "llvm-dev" ;;
                brew)           printf '%s' "llvm" ;;
                *)              printf '%s' "llvm-dev" ;;
            esac
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}
pkg_map_brew () {

    local want="${1-}"

    if pkg_is_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_is_findutils_name "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        git|gh|jq|curl|perl)
            printf '%s' "${want}"
        ;;
        awk)
            printf '%s' "gawk"
        ;;
        sed)
            printf '%s' "gnu-sed"
        ;;
        grep)
            printf '%s' "grep"
        ;;
        python|pip)
            printf '%s' "python"
        ;;
        clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config)
            printf '%s' "llvm"
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}
pkg_map_msys_pacman () {

    local want="${1-}"

    if pkg_is_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_is_findutils_name "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        git|gh|jq|curl|perl|sed|grep)
            printf '%s' "${want}"
        ;;
        awk)
            printf '%s' "gawk"
        ;;
        python|pip)
            printf '%s' "python"
        ;;
        clang|clang-dev|libclang|libclang-dev)
            printf '%s' "clang"
        ;;
        llvm|llvm-dev|llvm-config)
            printf '%s' "llvm"
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}
pkg_map_mingw_pacman () {

    local prefix="${1:-$(pkg_mingw_prefix)}" want="${2-}"

    if pkg_is_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_is_findutils_name "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        git|gh|jq|curl|perl|sed|grep)
            printf '%s' "${want}"
        ;;
        awk)
            printf '%s' "gawk"
        ;;
        python|pip)
            printf '%s' "${prefix}-python"
        ;;
        clang|clang-dev|libclang|libclang-dev)
            printf '%s' "${prefix}-clang"
        ;;
        llvm|llvm-dev|llvm-config)
            printf '%s' "${prefix}-llvm"
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}
pkg_map_cygwin () {

    local want="${1-}"

    if pkg_is_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_is_findutils_name "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        git|gh|jq|curl|perl|sed|grep)
            printf '%s' "${want}"
        ;;
        awk)
            printf '%s' "gawk"
        ;;
        python)
            printf '%s' "python3"
        ;;
        pip)
            printf '%s' "python3-pip"
        ;;
        clang)
            printf '%s' "clang"
        ;;
        clang-dev|libclang|libclang-dev)
            printf '%s' "libclang-devel"
        ;;
        llvm|llvm-dev|llvm-config)
            printf '%s' "llvm"
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}
pkg_map_scoop () {

    local want="${1-}"

    if pkg_is_coreutils_name "${want}" || pkg_is_findutils_name "${want}" || [[ "${want}" == awk || "${want}" == sed || "${want}" == grep ]]; then
        printf '%s' "msys2"
        return 0
    fi

    case "${want}" in
        git)
            printf '%s' "git"
        ;;
        gh)
            printf '%s' "gh"
        ;;
        jq)
            printf '%s' "jq"
        ;;
        curl)
            printf '%s' "curl"
        ;;
        perl)
            printf '%s' "perl"
        ;;
        python|pip)
            printf '%s' "python"
        ;;
        clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config)
            printf '%s' "llvm"
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}
pkg_map_choco () {

    local want="${1-}"

    if pkg_is_coreutils_name "${want}" || pkg_is_findutils_name "${want}" || [[ "${want}" == awk || "${want}" == sed || "${want}" == grep ]]; then
        printf '%s' "git"
        return 0
    fi

    case "${want}" in
        git)
            printf '%s' "git"
        ;;
        gh)
            printf '%s' "gh"
        ;;
        jq)
            printf '%s' "jq"
        ;;
        curl)
            printf '%s' "curl"
        ;;
        perl)
            printf '%s' "strawberryperl"
        ;;
        python|pip)
            printf '%s' "python"
        ;;
        clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config)
            printf '%s' "llvm"
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}
pkg_map_winget () {

    local want="${1-}"

    if pkg_is_coreutils_name "${want}" || pkg_is_findutils_name "${want}" || [[ "${want}" == awk || "${want}" == sed || "${want}" == grep ]]; then
        printf '%s' "Git.Git"
        return 0
    fi

    case "${want}" in
        git)
            printf '%s' "Git.Git"
        ;;
        gh)
            printf '%s' "GitHub.cli"
        ;;
        jq)
            printf '%s' "jqlang.jq"
        ;;
        curl)
            printf '%s' "cURL.cURL"
        ;;
        perl)
            printf '%s' "StrawberryPerl.StrawberryPerl"
        ;;
        python|pip)
            printf '%s' "Python.Python.3"
        ;;
        clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config)
            printf '%s' "LLVM.LLVM"
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}
pkg_map () {

    local target="${1-}" backend="${2-}" aux="${3-}" want="${4-}"

    case "${backend}" in
        apt|dnf|yum|zypper|apk)
            pkg_map_linux_native "${backend}" "${want}"
        ;;
        pacman)
            case "${target}" in
                msys|gitbash) pkg_map_msys_pacman "${want}" ;;
                mingw)        pkg_map_mingw_pacman "${aux}" "${want}" ;;
                linux)        pkg_map_linux_native "pacman" "${want}" ;;
                *)            printf '%s' "" ;;
            esac
        ;;
        brew)
            pkg_map_brew "${want}"
        ;;
        apt-cyg|cygwin-setup)
            pkg_map_cygwin "${want}"
        ;;
        scoop)
            pkg_map_scoop "${want}"
        ;;
        choco)
            pkg_map_choco "${want}"
        ;;
        winget)
            pkg_map_winget "${want}"
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}

pkg_install_brew () {

    local pkg=""

    for pkg in "$@"; do

        run env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install "${pkg}" \
            || run env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew upgrade "${pkg}" \
            || die "pkg: brew failed for '${pkg}'." 2

    done

}
pkg_install_linux_native () {

    local backend="${1-}"
    shift || true

    local -a pkgs=( "$@" )
    (( ${#pkgs[@]} )) || return 0

    case "${backend}" in
        apt)
            pkg_apt_update_once

            if pkg_assume_yes; then
                pkg_with_privilege linux env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
            else
                pkg_with_privilege linux env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends "${pkgs[@]}"
            fi
        ;;
        dnf)
            if pkg_assume_yes; then pkg_with_privilege linux dnf install -y "${pkgs[@]}"
            else pkg_with_privilege linux dnf install "${pkgs[@]}"
            fi
        ;;
        yum)
            if pkg_assume_yes; then pkg_with_privilege linux yum install -y "${pkgs[@]}"
            else pkg_with_privilege linux yum install "${pkgs[@]}"
            fi
        ;;
        pacman)
            if pkg_assume_yes; then pkg_with_privilege linux pacman -S --needed --noconfirm "${pkgs[@]}"
            else pkg_with_privilege linux pacman -S --needed "${pkgs[@]}"
            fi
        ;;
        zypper)
            if pkg_assume_yes; then pkg_with_privilege linux zypper --non-interactive install --no-recommends "${pkgs[@]}"
            else pkg_with_privilege linux zypper install --no-recommends "${pkgs[@]}"
            fi
        ;;
        apk)
            pkg_with_privilege linux apk add --no-cache "${pkgs[@]}"
        ;;
        brew)
            pkg_install_brew "${pkgs[@]}"
        ;;
        *)
            die "pkg: unsupported Linux backend '${backend}'." 2
        ;;
    esac

}
pkg_install_pacman_userland () {

    local -a pkgs=( "$@" )
    (( ${#pkgs[@]} )) || return 0

    if pkg_assume_yes; then run pacman -S --needed --noconfirm "${pkgs[@]}"
    else run pacman -S --needed "${pkgs[@]}"
    fi

}
pkg_install_apt_cyg () {

    local -a pkgs=( "$@" )
    (( ${#pkgs[@]} )) || return 0

    run apt-cyg install "${pkgs[@]}"

}
pkg_install_cygwin_setup () {

    local -a pkgs=( "$@" )
    (( ${#pkgs[@]} )) || return 0

    local setup=""

    if has setup-x86_64.exe; then setup="setup-x86_64.exe"
    elif has setup-x86.exe; then setup="setup-x86.exe"
    else die "pkg: cygwin setup executable not found." 2
    fi

    run "${setup}" -q -P "$(IFS=,; printf '%s' "${pkgs[*]}")"

}
pkg_install_scoop () {

    local pkg=""

    for pkg in "$@"; do
        run scoop install "${pkg}" || run scoop update "${pkg}" || die "pkg: scoop failed for '${pkg}'." 2
    done

}
pkg_install_choco () {

    local pkg=""

    for pkg in "$@"; do

        if pkg_assume_yes; then run choco install -y "${pkg}" || run choco upgrade -y "${pkg}" || die "pkg: choco failed for '${pkg}'." 2
        else run choco install "${pkg}" || run choco upgrade "${pkg}" || die "pkg: choco failed for '${pkg}'." 2
        fi

    done

}
pkg_install_winget () {

    local pkg=""

    for pkg in "$@"; do

        run winget install --id "${pkg}" --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || run winget upgrade --id "${pkg}" --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || run winget install --name "${pkg}" --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || die "pkg: winget failed for '${pkg}'." 2

    done

}
pkg_install () {

    local target="${1-}" backend="${2-}"
    shift 2 || true

    local -a pkgs=( "$@" )
    (( ${#pkgs[@]} )) || return 0

    case "${target}:${backend}" in
        linux:apt|linux:dnf|linux:yum|linux:pacman|linux:zypper|linux:apk|linux:brew)
            pkg_install_linux_native "${backend}" "${pkgs[@]}"
        ;;
        macos:brew)
            pkg_install_brew "${pkgs[@]}"
        ;;
        msys:pacman|mingw:pacman|gitbash:pacman)
            pkg_install_pacman_userland "${pkgs[@]}"
        ;;
        cygwin:apt-cyg)
            pkg_install_apt_cyg "${pkgs[@]}"
        ;;
        cygwin:cygwin-setup)
            pkg_install_cygwin_setup "${pkgs[@]}"
        ;;
        msys:scoop|mingw:scoop|gitbash:scoop|cygwin:scoop)
            pkg_install_scoop "${pkgs[@]}"
        ;;
        msys:choco|mingw:choco|gitbash:choco|cygwin:choco)
            pkg_install_choco "${pkgs[@]}"
        ;;
        msys:winget|mingw:winget|gitbash:winget|cygwin:winget)
            pkg_install_winget "${pkgs[@]}"
        ;;
        *)
            die "pkg: unsupported install path '${target}:${backend}'." 2
        ;;
    esac

}

pkg_build_plan () {

    local -n out_ref="${1}"
    local target="${2-}" backend="${3-}" aux="${4-}"
    shift 4 || true

    local want="" mapped=""
    out_ref=()

    for want in "$@"; do
        [[ -n "${want}" ]] || continue

        mapped="$(pkg_map "${target}" "${backend}" "${aux}" "${want}")"
        [[ -n "${mapped}" ]] || die "pkg: no package mapping for '${want}' on '${target}/${backend}'." 2

        out_ref+=( "${mapped}" )
    done

    unique_list out_ref

}
pkg_path_prepend () {

    local dir="${1-}"

    [[ -n "${dir}" && -d "${dir}" ]] || return 0

    case ":${PATH:-}:" in
        *":${dir}:"*) ;;
        *)
            if [[ -n "${PATH:-}" ]]; then PATH="${dir}:${PATH}"
            else PATH="${dir}"
            fi
        ;;
    esac

    export PATH

}
pkg_refresh_path () {

    pkg_activate_user_bin

    pkg_path_prepend "/opt/homebrew/bin"
    pkg_path_prepend "/usr/local/bin"
    pkg_path_prepend "/home/linuxbrew/.linuxbrew/bin"
    pkg_path_prepend "/mingw64/bin"
    pkg_path_prepend "/usr/bin"
    pkg_path_prepend "/bin"

    [[ -n "${LOCALAPPDATA:-}" ]] && pkg_path_prepend "${LOCALAPPDATA}/Microsoft/WinGet/Links"
    [[ -n "${LOCALAPPDATA:-}" ]] && pkg_path_prepend "${LOCALAPPDATA}/Programs/Git/bin"
    [[ -n "${LOCALAPPDATA:-}" ]] && pkg_path_prepend "${LOCALAPPDATA}/Programs/Git/usr/bin"

    [[ -n "${USERPROFILE:-}" ]] && pkg_path_prepend "${USERPROFILE}/scoop/shims"
    [[ -n "${USERPROFILE:-}" ]] && pkg_path_prepend "${USERPROFILE}/scoop/apps/git/current/bin"
    [[ -n "${USERPROFILE:-}" ]] && pkg_path_prepend "${USERPROFILE}/scoop/apps/git/current/usr/bin"
    [[ -n "${USERPROFILE:-}" ]] && pkg_path_prepend "${USERPROFILE}/scoop/apps/msys2/current/usr/bin"

    [[ -d "/c/Program Files/Git/bin" ]] && pkg_path_prepend "/c/Program Files/Git/bin"
    [[ -d "/c/Program Files/Git/usr/bin" ]] && pkg_path_prepend "/c/Program Files/Git/usr/bin"
    [[ -d "/c/ProgramData/chocolatey/bin" ]] && pkg_path_prepend "/c/ProgramData/chocolatey/bin"
    [[ -d "/c/tools/msys64/usr/bin" ]] && pkg_path_prepend "/c/tools/msys64/usr/bin"

    [[ -d "/cygdrive/c/Program Files/Git/bin" ]] && pkg_path_prepend "/cygdrive/c/Program Files/Git/bin"
    [[ -d "/cygdrive/c/Program Files/Git/usr/bin" ]] && pkg_path_prepend "/cygdrive/c/Program Files/Git/usr/bin"
    [[ -d "/cygdrive/c/ProgramData/chocolatey/bin" ]] && pkg_path_prepend "/cygdrive/c/ProgramData/chocolatey/bin"
    [[ -d "/cygdrive/c/tools/msys64/usr/bin" ]] && pkg_path_prepend "/cygdrive/c/tools/msys64/usr/bin"
    [[ -d "/cygdrive/c/cygwin64/bin" ]] && pkg_path_prepend "/cygdrive/c/cygwin64/bin"
    [[ -d "/cygdrive/c/cygwin/bin" ]] && pkg_path_prepend "/cygdrive/c/cygwin/bin"

}
pkg_brew_prefix () {

    has brew || return 1
    brew --prefix "${1-}" 2>/dev/null || true

}
pkg_brew_link () {

    local alias_name="${1-}" target="${2-}"

    [[ -n "${alias_name}" && -n "${target}" ]] || return 0
    [[ -x "${target}" ]] || return 0

    ensure_bin_link "${alias_name}" "${target}"
    pkg_activate_user_bin

}
pkg_windows_target () {

    case "$(pkg_target)" in
        msys|mingw|gitbash|cygwin) return 0 ;;
    esac

    return 1

}
pkg_to_unix_path () {

    local p="${1-}"

    [[ -n "${p}" ]] || { printf '%s' ""; return 0; }

    if has cygpath; then
        cygpath -u "${p}" 2>/dev/null || printf '%s' "${p}"
        return 0
    fi

    printf '%s' "${p}"

}
pkg_write_exec_alias () {

    local alias_name="${1-}" target="${2-}"
    local bin_dir="" bin_path="" unix_target=""

    [[ -n "${alias_name}" && -n "${target}" ]] || return 1
    [[ -x "${target}" ]] || return 1

    validate_alias "${alias_name}"

    bin_dir="$(pkg_user_bin_dir)"
    bin_path="${bin_dir}/${alias_name}"
    unix_target="$(pkg_to_unix_path "${target}")"

    ensure_dir "${bin_dir}"

    printf '%s\n' '#!/usr/bin/env bash' "exec \"${unix_target}\" \"\$@\"" > "${bin_path}"
    run chmod +x "${bin_path}"

    pkg_activate_user_bin

}

pkg_post_install_python_aliases () {

    local target="${1-}" want="" py_bin="" pip_bin=""
    shift || true

    for want in "$@"; do

        case "${want}" in
            python)
                if ! has python && has python3; then
                    py_bin="$(command -v python3 2>/dev/null || true)"

                    if [[ -n "${py_bin}" ]]; then
                        if [[ "${target}" == "msys" || "${target}" == "mingw" || "${target}" == "gitbash" || "${target}" == "cygwin" ]]; then
                            pkg_write_exec_alias "python" "${py_bin}" || true
                        else
                            ensure_bin_link "python" "${py_bin}" || true
                        fi
                    fi
                fi
            ;;
            pip)
                if ! has pip && has pip3; then
                    pip_bin="$(command -v pip3 2>/dev/null || true)"

                    if [[ -n "${pip_bin}" ]]; then
                        if [[ "${target}" == "msys" || "${target}" == "mingw" || "${target}" == "gitbash" || "${target}" == "cygwin" ]]; then
                            pkg_write_exec_alias "pip" "${pip_bin}" || true
                        else
                            ensure_bin_link "pip" "${pip_bin}" || true
                        fi
                    fi
                fi
            ;;
        esac

    done

    pkg_activate_user_bin

}
pkg_post_install_brew () {

    local target="${1-}" want="" prefix=""
    shift || true

    for want in "$@"; do

        case "${want}" in
            clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config)
                prefix="$(pkg_brew_prefix llvm)"
                [[ -n "${prefix}" ]] || true

                pkg_brew_link "clang" "${prefix}/bin/clang"
                pkg_brew_link "llvm-config" "${prefix}/bin/llvm-config"
            ;;
        esac

        [[ "${target}" == "macos" ]] || continue

        case "${want}" in
            awk)
                prefix="$(pkg_brew_prefix gawk)"
                [[ -x "${prefix}/bin/gawk" ]] && pkg_brew_link "awk" "${prefix}/bin/gawk"
            ;;
            sed)
                prefix="$(pkg_brew_prefix gnu-sed)"
                [[ -x "${prefix}/libexec/gnubin/sed" ]] && pkg_brew_link "sed" "${prefix}/libexec/gnubin/sed"
            ;;
            grep)
                prefix="$(pkg_brew_prefix grep)"
                [[ -x "${prefix}/libexec/gnubin/grep" ]] && pkg_brew_link "grep" "${prefix}/libexec/gnubin/grep"
            ;;
            find|xargs)
                prefix="$(pkg_brew_prefix findutils)"
                [[ -x "${prefix}/libexec/gnubin/${want}" ]] && pkg_brew_link "${want}" "${prefix}/libexec/gnubin/${want}"
            ;;
            *)
                if pkg_is_coreutils_name "${want}"; then
                    prefix="$(pkg_brew_prefix coreutils)"
                    [[ -x "${prefix}/libexec/gnubin/${want}" ]] && pkg_brew_link "${want}" "${prefix}/libexec/gnubin/${want}"
                fi
            ;;
        esac

    done

}
pkg_post_install () {

    local target="${1-}" backend="${2-}"
    shift 2 || true

    pkg_post_install_python_aliases "${target}" "$@"

    case "${backend}" in
        brew) pkg_post_install_brew "${target}" "$@" ;;
    esac

    pkg_refresh_path
    pkg_hash_clear

}
ensure_pkg () {

    local -a wants=()
    local -a missing=()
    local -a plan=()

    local target="" backend="" aux="" want=""

    for want in "$@"; do
        [[ -n "${want}" ]] || continue
        wants+=( "${want}" )
    done

    unique_list wants
    (( ${#wants[@]} )) || return 0

    target="$(pkg_target)"
    pkg_require_target "${target}"

    backend="$(pkg_backend "${target}")" || die "pkg: no usable backend for target '${target}'." 2
    [[ "${target}" == "mingw" && "${backend}" == "pacman" ]] && aux="$(pkg_mingw_prefix)"

    pkg_post_install "${target}" "${backend}" "${wants[@]}"
    pkg_collect_missing missing "${target}" "${wants[@]}"

    if (( ${#missing[@]} == 0 )); then
        pkg_hash_clear
        return 0
    fi

    pkg_build_plan plan "${target}" "${backend}" "${aux}" "${missing[@]}"
    pkg_install "${target}" "${backend}" "${plan[@]}"

    pkg_post_install "${target}" "${backend}" "${wants[@]}"
    pkg_collect_missing missing "${target}" "${wants[@]}"

    (( ${#missing[@]} == 0 )) || die "pkg: failed to ensure tools: ${missing[*]}" 2
    return 0

}

tool_path_prepend () {

    local dir="${1-}"
    [[ -n "${dir}" && -d "${dir}" ]] || return 0

    case ":${PATH:-}:" in
        *":${dir}:"*) ;;
        *)
            if [[ -n "${PATH:-}" ]]; then PATH="${dir}:${PATH}"
            else PATH="${dir}"
            fi
        ;;
    esac

    export PATH

}
tool_export_path_if_dir () {

    local dir="${1-}"
    [[ -n "${dir}" && -d "${dir}" ]] || return 0

    tool_path_prepend "${dir}"

    if [[ -n "${GITHUB_PATH:-}" ]]; then
        printf '%s\n' "${dir}" >> "${GITHUB_PATH}"
    fi

}
tool_to_unix_path () {

    local p="${1-}"
    [[ -n "${p}" ]] || { printf '%s' ""; return 0; }

    if has cygpath; then
        cygpath -u "${p}" 2>/dev/null || printf '%s' "${p}"
        return 0
    fi

    printf '%s' "${p}"

}
tool_is_unix_target () {

    case "$(pkg_target)" in
        linux|macos) return 0 ;;
    esac

    return 1

}
tool_is_windows_target () {

    case "$(pkg_target)" in
        msys|mingw|gitbash|cygwin) return 0 ;;
    esac

    return 1

}

tool_pick_sort_bin () {

    if sort -V </dev/null >/dev/null 2>&1; then
        printf '%s\n' "sort"
        return 0
    fi
    if has gsort && gsort -V </dev/null >/dev/null 2>&1; then
        printf '%s\n' "gsort"
        return 0
    fi

    ensure_pkg sort 1>&2

    if sort -V </dev/null >/dev/null 2>&1; then
        printf '%s\n' "sort"
        return 0
    fi
    if has gsort && gsort -V </dev/null >/dev/null 2>&1; then
        printf '%s\n' "gsort"
        return 0
    fi

    die "tool: need GNU sort with -V support." 2

}
tool_sort_ver () {

    local sbin="$(tool_pick_sort_bin)"
    LC_ALL=C "${sbin}" -V

}
tool_normalize_version () {

    local tc="${1-}"
    tc="${tc#v}"

    case "${tc}" in
        "" )                 printf '%s\n' "" ; return 0 ;;
        stable|beta|nightly) printf '%s\n' "${tc}" ; return 0 ;;
        nightly-????-??-??)  printf '%s\n' "${tc}" ; return 0 ;;
    esac

    [[ "${tc}" =~ ^[0-9]+\.[0-9]+$ ]] && tc="${tc}.0"
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid version: ${1-}" 2

    printf '%s\n' "${tc}"

}
tool_version_major () {

    local v="${1-}"
    v="${v#v}"
    printf '%s\n' "${v%%.*}"

}

tool_target () {

    pkg_target

}
tool_backend () {

    pkg_backend

}
tool_assume_yes () {

    pkg_assume_yes

}
tool_mingw_prefix () {

    pkg_mingw_prefix

}
tool_hash_clear () {

    pkg_hash_clear

}

ensure_tool () {

    ensure_pkg "$@"

}

forge_replace_all () {

    ensure_pkg find mktemp rm perl xargs 1>&2

    local root="${1:-}" map_name="${2:-}" ig="" f="" any=0 k=""

    [[ -n "${root}" && -d "${root}" ]] || die "replace: root dir not found: ${root}"
    [[ -n "${map_name}" ]] || die "replace: missing map name"

    local -n map="${map_name}"
    ((${#map[@]})) || return 0

    local -a ignore_list=( .git target node_modules dist build vendor .next .nuxt .venv venv .vscode __pycache__ )
    local -a find_cmd=( find "${root}" -type d "(" )

    local kv="$(mktemp "${TMPDIR:-/tmp}/replace.map.XXXXXX")" || die "replace: mktemp failed"
    trap 'rm -rf -- "${kv}" 2>/dev/null || true; trap - RETURN' RETURN
    : > "${kv}" || { rm -f "${kv}" 2>/dev/null || true; die "replace: cannot write tmp file"; }

    for k in "${!map[@]}"; do
        [[ "${k}" != *$'\0'* && "${map["${k}"]}" != *$'\0'* ]] || die "replace: NUL not allowed in map"
        printf '%s\0%s\0' "${k}" "${map["${k}"]}" >> "${kv}"
    done

    for ig in "${ignore_list[@]}"; do find_cmd+=( -name "${ig}" -o ); done
    find_cmd+=( -false ")" -prune -o -type f ! -lname '*' -print0 )

    while IFS= read -r -d '' f; do any=1; break; done < <("${find_cmd[@]}")
    (( any )) || { rm -f "${kv}" 2>/dev/null || true; return 0; }

    "${find_cmd[@]}" | KV_FILE="${kv}" xargs -0 perl -0777 -i -pe '
        BEGIN {
            our %map = ();
            our $re  = "";

            my $kv = $ENV{KV_FILE} // "";
            open my $fh, "<", $kv or die "kv open failed: $kv";
            local $/;
            my $buf = <$fh>;
            close $fh;

            my @p = split(/\0/, $buf, -1);
            pop @p if @p && $p[-1] eq "";
            die "kv pairs mismatch\n" if @p % 2;

            for (my $i = 0; $i < @p; $i += 2) {
                $map{$p[$i]} = $p[$i + 1];
            }

            my @keys = sort { length($b) <=> length($a) } keys %map;
            $re = @keys ? join("|", map { quotemeta($_) } @keys) : "";
        }
        if ( $re ne "" && index($_, "\0") == -1 ) {
            s/($re)/$map{$1}/g;
        }
    ' || { rm -f "${kv}" 2>/dev/null || true; die "replace failed"; }

}
forge_placeholders () {

    source <(parse "$@" -- :root :name alias user repo branch description discord_url docs_url site_url host)

    [[ -n "${repo}"   ]] || repo="${name}"
    [[ -n "${alias}"  ]] || alias="${name}"
    [[ -n "${host}"   ]] || host="https://github.com"
    [[ "${host}" == *"://"* ]] || host="https://${host}"
    [[ -n "${branch}" ]] || branch="$(git_default_branch "${root}")"

    cd -- "${root}" || die "set_placeholders: cannot cd to ${root}"

    local -A ph_map=()

    append () {

        local k="${1-}" v="${2-}"
        [[ -n "${k}" && -n "${v}" ]] || return 0

        ph_map["__${k,,}__"]="${v}"
        ph_map["__${k^^}__"]="${v}"

        ph_map["--${k,,}--"]="${v}"
        ph_map["--${k^^}--"]="${v}"

        ph_map["{{${k,,}}}"]="${v}"
        ph_map["{{${k^^}}}"]="${v}"

    }
    blob_gh_url () {

        local repo_url="${1:-}" branch="${2:-}" rel="${3:-}"
        printf '%s/blob/%s/%s' "${repo_url}" "${branch}" "${rel#/}"

    }
    tree_gh_url () {

        local repo_url="${1:-}" branch="${2:-}" rel="${3:-}"
        printf '%s/tree/%s/%s' "${repo_url}" "${branch}" "${rel#/}"

    }

    append "year"         "$(date +%Y)"
    append "name"         "${name}"
    append "alias"        "${alias}"
    append "user"         "${user}"
    append "repo"         "${repo}"
    append "branch"       "${branch}"
    append "description"  "${description}"
    append "docs_url"     "${docs_url}"
    append "site_url"     "${site_url}"
    append "discord_url"  "${discord_url}"
    append "crate_name"   "${name}"
    append "package_name" "${name}"
    append "project_name" "${name}"

    if [[ -n "${user}" && -n "${repo}" ]]; then

        local repo_url="${host}/${user}/${repo}"
        local issues_url="${repo_url}/issues"
        local new_issue_url="${repo_url}/issues/new/choose"
        local discussions_url="${repo_url}/discussions"
        local community_url="${repo_url}/graphs/community"
        local categories_url="${repo_url}/discussions/categories"
        local announcements_url="${repo_url}/discussions/categories/announcements"
        local general_url="${repo_url}/discussions/categories/general"
        local ideas_url="${repo_url}/discussions/categories/ideas"
        local polls_url="${repo_url}/discussions/categories/polls"
        local qa_url="${repo_url}/discussions/categories/q-a"
        local show_and_tell_url="${repo_url}/discussions/categories/show-and-tell"

        append "repo_url"             "${repo_url}"
        append "issues_url"           "${issues_url}"
        append "new_issue_url"        "${new_issue_url}"
        append "discussions_url"      "${discussions_url}"
        append "community_url"        "${community_url}"
        append "categories_url"       "${categories_url}"
        append "announcements_url"    "${announcements_url}"
        append "general_url"          "${general_url}"
        append "ideas_url"            "${ideas_url}"
        append "polls_url"            "${polls_url}"
        append "qa_url"               "${qa_url}"
        append "show_and_tell_url"    "${show_and_tell_url}"
        append "bug_report_url"       "${new_issue_url}"
        append "feature_request_url"  "${new_issue_url}"

        [[ -f "${root}/SECURITY.md"          ]] && append "security_url"             "$(blob_gh_url "${repo_url}" "${branch}" "SECURITY.md")"
        [[ -f "${root}/SUPPORT.md"           ]] && append "support_url"              "$(blob_gh_url "${repo_url}" "${branch}" "SUPPORT.md")"
        [[ -f "${root}/CONTRIBUTING.md"      ]] && append "contributing_url"         "$(blob_gh_url "${repo_url}" "${branch}" "CONTRIBUTING.md")"
        [[ -f "${root}/CODE_OF_CONDUCT.md"   ]] && append "code_of_conduct_url"      "$(blob_gh_url "${repo_url}" "${branch}" "CODE_OF_CONDUCT.md")"
        [[ -f "${root}/README.md"            ]] && append "readme_url"               "$(blob_gh_url "${repo_url}" "${branch}" "README.md")"
        [[ -f "${root}/CHANGELOG.md"         ]] && append "changelog_url"            "$(blob_gh_url "${repo_url}" "${branch}" "CHANGELOG.md")"

        [[ -z "${ph_map["__security_url__"]:-}"          ]] && append "security_url"              "${repo_url}/security"
        [[ -z "${ph_map["__support_url__"]:-}"           ]] && append "support_url"               "${discussions_url}"
        [[ -z "${ph_map["__contributing_url__"]:-}"      ]] && append "contributing_url"          "${repo_url}"
        [[ -z "${ph_map["__code_of_conduct_url__"]:-}"   ]] && append "code_of_conduct_url"       "${repo_url}"
        [[ -d "${root}/.github/ISSUE_TEMPLATE"           ]] && append "issue_templates_url"       "$(tree_gh_url "${repo_url}" "${branch}" ".github/ISSUE_TEMPLATE")"
        [[ -f "${root}/.github/PULL_REQUEST_TEMPLATE.md" ]] && append "pull_request_template_url" "$(blob_gh_url "${repo_url}" "${branch}" ".github/PULL_REQUEST_TEMPLATE.md")"

    fi

    forge_replace_all  "${root}" ph_map

}
forge_init_git () {

    source <(parse "$@" -- :root :name repo branch)

    cd -- "${root}" || die "set_git: cannot cd to ${root}"
    cmd_init "${repo:-${name}}" "${kwargs[@]}"

}

forge_resolve_name () {

    local name="${1:-}"

    name="${name%%[[:space:]]*}"
    name="${name##*/}"
    name="${name//_/-}"
    name="${name,,}"

    name="${name//-app/-pure}"
    name="${name//-project/-pure}"
    name="${name//-framework/-web}"
    name="${name//-package/-lib}"
    name="${name//-crate/-lib}"
    name="${name//-workspace/-ws}"
    name="${name//-monorepo/-ws}"

    printf '%s\n' "${name}"

}
forge_display_name () {

    local name="${1:-}"
    local first="${name%%-*}"

    [[ "${name}" == *-pure ]] || { printf '%s\n' "${name}"; return 0; }
    printf '%s\n' "${first}"

}
forge_resolve_dest () {

    local dir="${1:-}" name="${2:-}"

    dir="${dir:-${PROJECTS_DIR:-${WORKSPACE_DIR:-${PWD}}}}"
    dir="${dir/#\~/${HOME}}"
    dir="${dir%/}"

    ensure_dir "${dir}"
    dir="${dir}/${name}"

    printf '%s\n' "${dir}"

}
forge_resolve_path () {

    local root="${1:-}" name="${2:-}" base="" try=""

    for base in "pure" "web" "lib" "ws"; do

        try="${base}/${name}"
        [[ -d "${root}/${try}" ]] && { printf '%s\n' "${root}/${try}" ; return 0 ; }

        [[ "${name}" == *-"${base}" ]] || continue

        try="${base}/${name%-${base}}"
        [[ -d "${root}/${try}" ]] && { printf '%s\n' "${root}/${try}" ; return 0 ; }

    done

    printf '%s\n' ""
    return 1

}

forge_copy_template () {

    ensure_pkg mkdir find tar grep 1>&2

    local src="${1:-}" dest="${2:-}"
    local -a tar_out=()

    [[ -e "${src}" ]] || die "cannot resolve template src: ${src}"
    [[ -e "${dest}" ]] && die "dest path already exists: ${dest}"

    mkdir -p -- "${dest}" 2>/dev/null || die "cannot create dir: ${dest}"
    [[ -n "$(find "${dest}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]] && die "dest dir not empty: ${dest}"

    tar_out=( tar -C "${dest}" -xf - )
    ( tar --help 2>/dev/null || true ) | grep -q -- '--no-same-owner' && tar_out=( tar --no-same-owner -C "${dest}" -xf - )

    tar -C "${src}" -cf - . | "${tar_out[@]}" || die "copy failed: ${src} -> ${dest}"

}
forge_copy_global_config () {

    local src_dir="${1:-}" dest_dir="${2:-}" path="" base="" out=""
    [[ -d "${src_dir}" ]] || return 0

    for path in "${src_dir}"/* "${src_dir}"/.[!.]* "${src_dir}"/..?*; do

        [[ -e "${path}" ]] || continue

        base="${path##*/}"
        out="${dest_dir}/${base}"

        if [[ -f "${path}" ]]; then

            [[ -e "${out}" ]] && continue

            mkdir -p -- "${out%/*}" || die "Failed mkdir ${out}" 2
            cp -f -- "${path}" "${out}" || die "Failed copying ${path}" 2

        elif [[ -d "${path}" ]]; then

            [[ "${base}" == .* ]] || continue
            [[ -e "${out}" ]] && continue

            mkdir -p -- "${out}" || die "Failed mkdir ${out}" 2
            cp -R -- "${path}/." "${out}" || die "Failed copying dir ${path}" 2

        fi

    done

}
forge_copy_custom_config () {

    local src_dir="${1:-}" dest_dir="${2:-}" rel="" out="" f=""
    [[ -d "${src_dir}" ]] || return 0

    while IFS= read -r -d '' f; do

        rel="${f#${src_dir}/}"
        out="${dest_dir}/${rel}"

        [[ -e "${out}" ]] && continue

        mkdir -p -- "${out%/*}" || die "Failed mkdir ${out}" 2
        cp -p -- "${f}" "${out}" || die "Failed copying ${f}" 2

    done < <(find "${src_dir}" -type f -print0)

}
forge_copy_config () {

    source <(parse "$@" -- \
        :name :config_dir :dest_dir \
        env:bool=true docs:bool=true license:bool=true pretty:bool=true safety:bool=true \
        format:bool=true lint:bool=true audit:bool=true coverage:bool=true github:bool=true docker:bool=false \
    )

    [[ -e "${config_dir}" ]] || die "cannot resolve config src: ${config_dir}"

    local path="" base="" cfg=""
    local -a configs=()

    for path in "${config_dir}"/* "${config_dir}"/.[!.]* "${config_dir}"/..?*; do

        base="${path##*/}"

        [[ -d "${path}" ]] || continue
        [[ "${base}" == "." || "${base}" == ".." ]] && continue

        configs+=( "${base}" )

    done
    for cfg in "${configs[@]}"; do

        declare -n _flag="${cfg}" 2>/dev/null && (( ! _flag )) && continue

        forge_copy_custom_config "${config_dir}/${cfg}/${name%%-*}" "${dest_dir}"
        forge_copy_global_config "${config_dir}/${cfg}" "${dest_dir}"

    done

}

cmd_new () {

    source <(parse "$@" -- :template name dest placeholders:bool=true git:bool=true)

    template="$(forge_resolve_name "${template}")"

    name="${name:-"$(forge_display_name "${template}")"}"
    dest="$(forge_resolve_dest "${dest}" "${name}")"

    local root="${TEMPLATE_DIR:-}"
    local conf="${root}/conf"

    local src="$(forge_resolve_path "${root}" "${template}")"

    forge_copy_template "${src}" "${dest}"

    forge_copy_config "${template}" "${conf}" "${dest}" "${kwargs[@]}"

    (( placeholders )) && forge_placeholders "${dest}" "${name}" "${name}" "${kwargs[@]}"
    (( git ))          && forge_init_git "${dest}" "${name}" "${name}" "${kwargs[@]}"

    success "OK: ${name} was successfully set up at ${dest}"

}
cmd_new_project () {

    source <(parse "$@" -- :template)
    cmd_new "${template}-pure" "${kwargs[@]}"

}
cmd_new_bin () {

    source <(parse "$@" -- :template)
    cmd_new "${template}-pure" "${kwargs[@]}"

}
cmd_new_lib () {

    source <(parse "$@" -- :template)
    cmd_new "${template}-lib" "${kwargs[@]}"

}
cmd_new_ws () {

    source <(parse "$@" -- :template)
    cmd_new "${template}-ws" "${kwargs[@]}"

}

fs_new_dir () {

    ensure_pkg mkdir chmod
    source <(parse "$@" -- src mode)

    run mkdir -p -- "${src}"
    [[ -n "${mode}" ]] && run chmod -- "${mode}" "${src}"

}
fs_new_file () {

    ensure_pkg mkdir chmod touch
    source <(parse "$@" -- src mode)

    run mkdir -p -- "$(dirname -- "${src}")"
    run touch -- "${src}"

    [[ -n "${mode}" ]] && run chmod -- "${mode}" "${src}"

}
fs_file_exists () {

    [[ -f "${1:-}" ]]

}
fs_dir_exists () {

    [[ -d "${1:-}" ]]

}
fs_path_exists () {

    [[ -e "${1:-}" || -L "${1:-}" ]]

}
fs_path_type () {

    local p="${1:-}" type="unknow"

    [[ -e "${p}" ]] && type="other"
    [[ -d "${p}" ]] && type="dir"
    [[ -f "${p}" ]] && type="file"
    [[ -L "${p}" ]] && type="symlink"

    printf '%s\n' "${type}"
    return 0

}
fs_file_type () {

    ensure_pkg file
    local p="${1:-}" mime="" enc=""

    [[ -L "${p}" ]] && { printf '%s\n' "symlink"; return 0; }
    [[ -d "${p}" ]] && { printf '%s\n' "dir"; return 0; }
    [[ -e "${p}" ]] || { printf '%s\n' "missing"; return 1; }

    mime="$(file -b --mime-type -- "${p}" 2>/dev/null || true)"
    enc="$(file -b --mime-encoding -- "${p}" 2>/dev/null || true)"

    case "${mime}" in
        text/*) printf '%s\n' "text"; return 0 ;;
        image/*) printf '%s\n' "image"; return 0 ;;
        video/*) printf '%s\n' "video"; return 0 ;;
        audio/*) printf '%s\n' "audio"; return 0 ;;
        application/pdf) printf '%s\n' "pdf"; return 0 ;;
    esac
    case "${p,,}" in
        *.pdf) printf '%s\n' "pdf"; return 0 ;;
        *.doc|*.docx|*.dot|*.dotx|*.docm|*.dotm) printf '%s\n' "word"; return 0 ;;
        *.xls|*.xlsx|*.xlsm|*.xlt|*.xltx|*.xltm) printf '%s\n' "excel"; return 0 ;;
    esac

    [[ "${enc}" == "binary" ]] && { printf '%s\n' "binary"; return 0; }

    printf '%s\n' "other"
    return 0

}

fs_capitalize_path () {

    local p="${1:-}" lead="" out="" seg="" trailing=0
    local -a parts=()

    [[ "${p}" == /* ]] && lead="/"
    [[ "${p}" == */ && "${p}" != "/" ]] && trailing=1

    p="${p#/}"
    IFS='/' read -r -a parts <<< "${p}"

    for seg in "${parts[@]}"; do
        [[ -n "${seg}" ]] || continue
        [[ -n "${out}" ]] && out+="/${seg^}" || out="${seg^}"
    done

    if [[ -n "${lead}" ]]; then
        [[ -n "${out}" ]] && out="/${out}" || out="/"
    fi

    (( trailing )) && out+="/"
    printf '%s\n' "${out}"

}
fs_copy_path () {

    ensure_pkg cp mkdir
    source <(parse "$@" -- :src :dest)

    run mkdir -p -- "$(dirname -- "${dest}")"
    local -a cmd=( cp )

    if cp --version >/dev/null 2>&1; then cmd+=( -a )
    else cmd+=( -pPR )
    fi

    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" "${dest}"

}
fs_move_path () {

    ensure_pkg mv mkdir
    source <(parse "$@" -- :src :dest)

    run mkdir -p -- "$(dirname -- "${dest}")"
    run mv "${kwargs[@]}" -- "${src}" "${dest}"

}
fs_remove_path () {

    ensure_pkg rm find
    source <(parse "$@" -- :src clear:bool)

    [[ "${src}" == "/" || "${src}" == "." ]] && die "Refuse to delete '/' '.'"

    if (( clear )); then

        [[ -d "${src}" ]] || die "Not a directory: ${src}"
        find "${src}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
        return 0

    fi

    run rm -rf "${kwargs[@]}" -- "${src}"

}
fs_trash_path () {

    ensure_pkg mkdir mv date
    source <(parse "$@" -- :src trash_dir)

    [[ "${src}" == "/" || "${src}" == "." ]] && die "Refuse to trash '/' '.'"
    local dir=""

    if [[ -n "${trash_dir}" ]]; then dir="${trash_dir%/}"
    elif [[ "${OSTYPE:-}" == darwin* ]]; then dir="${HOME}/.Trash"
    else dir="${XDG_DATA_HOME:-"${HOME}/.local/share"}/Trash/files"
    fi

    run mkdir -p -- "${dir}"

    local base="$(basename -- "${src%/}")"
    local ts="$(date +'%Y-%m-%d_%H-%M-%S')"
    local dest="${dir}/${base}__${ts}__$$"

    run mv "${kwargs[@]}" -- "${src}" "${dest}"
    printf '%s\n' "${dest}"

}
fs_link_path () {

    ensure_pkg mkdir ln
    source <(parse "$@" -- :src :dest)

    run mkdir -p -- "$(dirname -- "${dest}")"
    run ln -sfn "${kwargs[@]}" -- "${src}" "${dest}"

}

fs_stats_path () {

    ensure_pkg stat
    source <(parse "$@" -- :src)

    if stat --version >/dev/null 2>&1; then stat -c $'path=%n\ntype=%F\nsize=%s\nperm=%a\nowner=%U\ngroup=%G\nmtime=%y' -- "${src}"
    else stat -f $'path=%N\ntype=%HT\nsize=%z\nperm=%Lp\nowner=%Su\ngroup=%Sg\nmtime=%Sm' -t "%Y-%m-%d %H:%M:%S" -- "${src}"
    fi

}
fs_diff_path () {

    ensure_pkg diff
    source <(parse "$@" -- :src :dest recursive:bool=true brief:bool=true)

    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"
    [[ -e "${dest}" || -L "${dest}" ]] || die "Path not found: ${dest}"

    local -a cmd=( diff )

    (( brief )) && cmd+=( -q )
    [[ -d "${src}" && -d "${dest}" ]] && (( recursive )) && cmd+=( -r )

    cmd+=( "${kwargs[@]}" -- "${src}" "${dest}" )
    "${cmd[@]}"

}
fs_synced_path () {

    ensure_pkg diff
    source <(parse "$@" -- :src :dest recursive:bool=true)

    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"
    [[ -e "${dest}" || -L "${dest}" ]] || die "Path not found: ${dest}"

    local -a cmd=( diff -q )

    [[ -d "${src}" && -d "${dest}" ]] && (( recursive )) && cmd+=( -r )
    cmd+=( "${kwargs[@]}" -- "${src}" "${dest}" )

    if "${cmd[@]}" >/dev/null 2>&1; then printf '%s\n' "yes"
    else printf '%s\n' "no"
    fi

}

fs_compress_path () {

    ensure_pkg mkdir
    source <(parse "$@" -- src dest name type=zip exclude:list)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." || "${src}" == "/" ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    local base="${src%/}"
    local dir="$(dirname -- "${base}")"
    local entry="$(basename -- "${base}")"
    name="${name:-"${entry}"}"

    [[ -n "${dest}" ]] || dest="${PWD}/${name}.${type}"
    [[ "${dest}" == /* ]] || dest="${PWD}/${dest#./}"

    run mkdir -p -- "$(dirname -- "${dest}")"

    local ext="${dest,,}" i=""
    local -a cmd=() ignore_list=( .git .next .env .venv .vscode node_modules build target vendor __pycache__ )
    ignore_list+=( "${exclude[@]-}" )

    if [[ "${type,,}" == "zip" || "${ext}" == *.zip ]]; then

        ensure_pkg zip

        cmd=( zip -rq )
        cmd+=( "${kwargs[@]}" )
        cmd+=( "${dest}" "${entry}" )

        for i in "${ignore_list[@]-}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( -x "*${i}*" )
        done

        ( cd -- "${dir}" && run "${cmd[@]}" )

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${type,,}" == "rar" || "${ext}" == *.rar ]]; then

        ensure_pkg rar

        cmd=( rar a -r -idq )
        cmd+=( "${kwargs[@]}" )
        cmd+=( "${dest}" "${entry}" )

        for i in "${ignore_list[@]-}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( "-x*${i}*" )
        done

        ( cd -- "${dir}" && run "${cmd[@]}" )

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${type,,}" == "7z" || "${ext}" == *.7z ]]; then

        ensure_pkg 7z

        cmd=( 7z a -y )
        cmd+=( "${kwargs[@]}" )
        cmd+=( "${dest}" "${entry}" )

        for i in "${ignore_list[@]-}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( "-xr!*${i}*" )
        done

        ( cd -- "${dir}" && run "${cmd[@]}" )

        printf '%s\n' "${dest}"
        return 0

    fi

    ensure_pkg tar

    if [[ "${ext}" == *.tar.gz || "${ext}" == *.tgz ]]; then cmd=( tar -czf "${dest}" )
    elif [[ "${ext}" == *.tar.xz || "${ext}" == *.txz ]]; then cmd=( tar -cJf "${dest}" )
    elif [[ "${ext}" == *.tar.bz2 || "${ext}" == *.tbz2 ]]; then cmd=( tar -cjf "${dest}" )
    elif [[ "${ext}" == *.tar ]]; then cmd=( tar -cf "${dest}" )
    else die "Unsupported archive type: ${dest}"
    fi

    for i in "${ignore_list[@]-}"; do
        [[ -n "${i}" ]] || continue
        cmd+=( --exclude "${i}" )
    done

    run "${cmd[@]}" "${kwargs[@]}" -C "${dir}" -- "${entry}"
    printf '%s\n' "${dest}"

}
fs_extract_path () {

    ensure_pkg mkdir
    source <(parse "$@" -- :src dest strip:int)

    [[ -e "${src}" ]] || die "Archive not found: ${src}"
    [[ -n "${dest}" ]] || dest="."

    run mkdir -p -- "${dest}"
    local ext="${src,,}"

    if [[ "${ext}" == *.zip ]]; then

        ensure_pkg unzip
        run unzip -oq "${kwargs[@]}" -- "${src}" -d "${dest}"

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.rar ]]; then

        ensure_pkg unrar
        run unrar x -o+ -y "${kwargs[@]}" "${src}" "${dest}/"

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.7z ]]; then

        ensure_pkg 7z
        run 7z x -y "${kwargs[@]}" -o"${dest}" "${src}"

        printf '%s\n' "${dest}"
        return 0

    fi

    ensure_pkg tar
    local -a cmd=( tar )

    if [[ "${ext}" == *.tar.gz || "${ext}" == *.tgz ]]; then cmd+=( -xzf )
    elif [[ "${ext}" == *.tar.xz || "${ext}" == *.txz ]]; then cmd+=( -xJf )
    elif [[ "${ext}" == *.tar.bz2 || "${ext}" == *.tbz2 ]]; then cmd+=( -xjf )
    else cmd+=( -xf )
    fi

    (( strip > 0 )) && cmd+=( --strip-components "${strip}" )
    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" -C "${dest}"

    printf '%s\n' "${dest}"

}
fs_backup_path () {

    ensure_pkg date
    source <(parse "$@" -- src dest name type=zip archive_dir="${ARCHIVE_DIR:-}")

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." || "${src}" == "/" ]] && src="${PWD}"
    local base_name="$(basename -- "${src%/}")" ts="$(date +'%Y-%m-%d_%H-%M-%S')" _dest_=""

    [[ "${archive_dir}" == /mnt/* ]] && base_name="$(fs_capitalize_path "${base_name}")"
    [[ -n "${name}" ]] && _dest_="${dest:-${base_name}}/${name}" || _dest_="${dest:-"${base_name}/${ts}.${type:-zip}"}"
    [[ -n "${archive_dir}" && "${_dest_}" != /* && "${_dest_}" != *:* ]] && dest="${archive_dir%/}/${_dest_}" || dest="${_dest_}"

    fs_compress_path "${src}" "${dest}" "${name}" "${type}" "${kwargs[@]}"
    success "OK: ${src} archived at ${dest}"

}
fs_sync_path () {

    ensure_pkg rsync mkdir
    source <(parse "$@" -- src dest src_dir="${WORKSPACE_DIR:-}" sync_dir="${SYNC_DIR:-}" force:bool=true ignore:bool=true exclude:list)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." || "${src}" == "/" ]] && src="${PWD}"

    local rel="${src#${src_dir%/}/}"
    [[ "${rel}" == "${src}" ]] && rel="${src#/}"

    if [[ -z "${dest}" && "${sync_dir}" == /mnt/* ]]; then dest="${sync_dir%/}/$(fs_capitalize_path "${rel}")"
    elif [[ -z "${dest}" && -n "${sync_dir}" ]]; then dest="${sync_dir%/}/${rel}"
    elif [[ -z "${dest}" ]]; then dest="${rel}"
    fi

    [[ -d "${src}" && "${src}" != */ ]] && src="${src}/"
    [[ -d "${src}" && "${dest}" != */ ]] && dest="${dest}/"
    [[ -d "${src}" ]] && run mkdir -p -- "${dest%/}" || run mkdir -p -- "$(dirname -- "${dest}")"

    local -a cmd=( rsync -a )
    (( force )) && cmd+=( --delete )

    if (( ignore )); then

        local i=""
        local -a ignore_list=( .git .next .env .venv .vscode node_modules build target vendor __pycache__ )
        ignore_list+=( "${exclude[@]-}" )
        for i in "${ignore_list[@]}"; do [[ -n "${i}" ]] || continue; cmd+=( --exclude "${i}" ); done

    fi

    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" "${dest}"
    success "OK: ${src} synced at ${dest}"

}

cmd_new_dir () {

    source <(parse "$@" -- :src mode)
    fs_new_dir "${src}" "${mode}" "${kwargs[@]}"

}
cmd_new_file () {

    source <(parse "$@" -- :src mode)
    fs_new_file "${src}" "${mode}" "${kwargs[@]}"

}
cmd_path_type () {

    source <(parse "$@" -- :src)
    fs_path_exists "${src}" && fs_path_type "${src}" "${kwargs[@]}"

}
cmd_file_type () {

    source <(parse "$@" -- :src)
    fs_file_exists "${src}" && fs_file_type "${src}" "${kwargs[@]}"

}
cmd_copy () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_copy_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_move () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_move_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_remove () {

    source <(parse "$@" -- :src)
    fs_path_exists "${src}" && fs_remove_path "${src}" "${kwargs[@]}"

}
cmd_trash () {

    source <(parse "$@" -- :src trash_dir)
    fs_path_exists "${src}" && fs_trash_path "${src}" "${trash_dir}" "${kwargs[@]}"

}
cmd_clear () {

    source <(parse "$@" -- :src)

    fs_dir_exists "${src}" && fs_remove_path "${src}" true "${kwargs[@]}"
    fs_file_exists "${src}" && : > "${src}"

}
cmd_link () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_link_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_stats () {

    source <(parse "$@" -- :src)
    fs_path_exists "${src}" && fs_stats_path "${src}" "${kwargs[@]}"

}
cmd_diff () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_diff_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_synced () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_synced_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_compress () {

    source <(parse "$@" -- src)
    fs_path_exists "${src:-${PWD}}" && fs_compress_path "${src}" "${kwargs[@]}"

}
cmd_backup () {

    source <(parse "$@" -- src)
    fs_path_exists "${src:-${PWD}}" && fs_backup_path "${src}" "${kwargs[@]}"

}
cmd_sync () {

    source <(parse "$@" -- src)
    fs_path_exists "${src:-${PWD}}" && fs_sync_path "${src}" "${kwargs[@]}"

}

run_git () {

    ensure_pkg git

    local kind="${1:-ssh}" ssh_cmd="${2:-}"
    shift 2 || true

    if [[ "${kind}" == http* ]]; then
        local old="${VERBOSE:-0}"
        VERBOSE=0
        GIT_TERMINAL_PROMPT=0 run git "$@"
        VERBOSE="${old}"
        return $?
    fi
    if [[ -n "${ssh_cmd}" ]]; then
        GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${ssh_cmd}" run git "$@"
        return $?
    fi

    GIT_TERMINAL_PROMPT=0 run git "$@"

}
git_repo_guard () {

    ensure_pkg git
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository."

}
git_repo_root () {

    ensure_pkg git
    git rev-parse --show-toplevel 2>/dev/null || pwd -P

}
git_has_switch () {

    git switch -h >/dev/null 2>&1

}
git_switch () {

    if git_has_switch; then

        git switch "$@"
        return $?

    fi
    if [[ "${1:-}" == "-c" ]]; then

        shift || true
        local b="${1:-}"
        shift || true

        if [[ "${1:-}" == "--track" ]]; then

            shift || true
            local upstream="${1:-}"
            shift || true

            git checkout -b "${b}" --track "${upstream}" "$@"
            return $?

        fi

        git checkout -b "${b}" "$@"
        return $?

    fi

    git checkout "$@"

}
git_has_commit () {

    git rev-parse --verify HEAD >/dev/null 2>&1

}
git_require_remote () {

    local remote="${1:-origin}"
    git remote get-url "${remote}" >/dev/null 2>&1 || die "Remote not found: ${remote}. Run: init <user/repo>"

}
git_require_identity () {

    local n="$(git config user.name  2>/dev/null || true)"
    local e="$(git config user.email 2>/dev/null || true)"

    [[ -n "${n}" && -n "${e}" ]] && return 0
    die "Missing git identity. Set: git config user.name \"Your Name\" && git config user.email \"you@example.com\""

}

git_is_semver () {

    local v="${1:-}" main="" rest="" pre="" build=""
    [[ -n "${v}" ]] || return 1

    if [[ "${v}" == *+* ]]; then
        main="${v%%+*}"
        build="${v#*+}"
    else
        main="${v}"
        build=""
    fi
    if [[ "${main}" == *-* ]]; then
        rest="${main%%-*}"
        pre="${main#*-}"
    else
        rest="${main}"
        pre=""
    fi
    if [[ "${rest}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        :
    else
        return 1
    fi

    if [[ -n "${pre}" ]]; then

        local -a ids=()
        IFS='.' read -r -a ids <<< "${pre}"
        ((${#ids[@]})) || return 1

        local id=""
        for id in "${ids[@]}"; do

            [[ -n "${id}" ]] || return 1
            [[ "${id}" =~ ^[0-9A-Za-z-]+$ ]] || return 1

            if [[ "${id}" =~ ^[0-9]+$ ]]; then
                [[ "${id}" == "0" || "${id}" =~ ^[1-9][0-9]*$ ]] || return 1
            fi

        done

    fi
    if [[ -n "${build}" ]]; then

        local -a ids=()
        IFS='.' read -r -a ids <<< "${build}"
        ((${#ids[@]})) || return 1

        local id=""
        for id in "${ids[@]}"; do
            [[ -n "${id}" ]] || return 1
            [[ "${id}" =~ ^[0-9A-Za-z-]+$ ]] || return 1
        done

    fi

    return 0

}
git_norm_tag () {

    local t="${1:-}"
    local core="${t}"
    [[ -n "${t}" ]] || { printf '%s\n' ""; return 0; }

    if [[ "${t}" == v* ]]; then

        core="${t#v}"
        git_is_semver "${core}" && { printf 'v%s\n' "${core}"; return 0; }
        printf '%s\n' "${t}"
        return 0

    fi

    git_is_semver "${t}" && { printf 'v%s\n' "${t}"; return 0; }
    printf '%s\n' "${t}"

}
git_redact_url () {

    local url="${1:-}" proto="" rest=""
    [[ -n "${url}" ]] || { printf ''; return 0; }

    if [[ "${url}" == http://* || "${url}" == https://* ]]; then

        proto="${url%%://*}://"
        rest="${url#*://}"

        if [[ "${rest}" == *@* ]]; then
            printf '%s***@%s\n' "${proto}" "${rest#*@}"
            return 0
        fi

    fi

    printf '%s\n' "${url}"

}
git_remote_url () {

    local remote="${1:-origin}"
    git remote get-url "${remote}" 2>/dev/null || true

}
git_remote_has_tag () {

    local kind="${1:-ssh}" ssh_cmd="${2:-}" target="${3:-origin}" tag="${4:-}"
    [[ -n "${tag}" ]] || return 1
    run_git "${kind}" "${ssh_cmd}" ls-remote --exit-code --tags --refs "${target}" "refs/tags/${tag}" >/dev/null 2>&1

}
git_remote_has_branch () {

    local kind="${1:-ssh}" ssh_cmd="${2:-}" target="${3:-origin}" b="${4:-}"
    [[ -n "${b}" ]] || return 1
    run_git "${kind}" "${ssh_cmd}" ls-remote --exit-code --heads "${target}" "${b}" >/dev/null 2>&1

}
git_parse_remote () {

    local url="${1:-}" rest="" left="" host="" path=""
    [[ -n "${url}" ]] || return 1

    if [[ "${url}" != *"://"* && "${url}" == *:* ]]; then

        left="${url%%:*}"
        path="${url#*:}"
        host="${left#*@}"
        host="${host%%:*}"
        [[ -n "${host}" && -n "${path}" && "${path}" == */* ]] || return 1

        printf '%s %s\n' "${host}" "${path}"
        return 0

    fi
    if [[ "${url}" == ssh://* || "${url}" == git+ssh://* ]]; then

        rest="${url#*://}"
        [[ "${rest}" == */* ]] || return 1

        left="${rest%%/*}"
        path="${rest#*/}"
        host="${left#*@}"
        host="${host%%:*}"

        printf '%s %s\n' "${host}" "${path}"
        return 0

    fi
    if [[ "${url}" == http://* || "${url}" == https://* ]]; then

        rest="${url#*://}"
        [[ "${rest}" == *@* ]] && rest="${rest#*@}"
        [[ "${rest}" == */* ]] || return 1

        host="${rest%%/*}"
        path="${rest#*/}"

        printf '%s %s\n' "${host}" "${path}"
        return 0

    fi

    return 1

}
git_build_https_token_url () {

    local token="${1:-}" host="${2:-}" path="${3:-}"
    [[ -n "${token}" && -n "${host}" && -n "${path}" ]] || return 1
    printf 'https://%s:%s@%s/%s\n' "${GIT_HTTP_USER:-x-access-token}" "${token}" "${host}" "${path}"

}
git_upstream_exists_for () {

    local b="${1:-}"
    [[ -n "${b}" ]] || return 1
    git rev-parse --abbrev-ref --symbolic-full-name "${b}@{u}" >/dev/null 2>&1

}

git_keymap_set () {

    ensure_pkg mkdir mktemp mv awk chmod
    source <(parse "$@" -- :key repo)

    local file="${HOME}/.ssh/git-keymap.tsv"
    local dir="$(dirname -- "${file}")"

    local repo_root="${repo:-"$(git_repo_root)"}"
    repo_root="$(cd -- "${repo_root}" 2>/dev/null && pwd -P || printf '%s' "${repo_root}")"

    [[ -n "${repo_root}" ]] || die "keymap: cannot detect repo root"
    [[ -z "${key}" || "${key}" == *$'\t'* || "${key}" == *$'\n'* || "${key}" == *$'\r'* ]] && die "keymap: invalid key"

    local tmp="$(mktemp "${TMPDIR:-/tmp}/vx.keymap.XXXXXX")" || die "mktemp failed"
    run mkdir -p -- "${dir}"
    chmod 700 "${dir}" 2>/dev/null || true
    [[ -f "${file}" ]] || : > "${file}" || die "keymap: create failed: ${file}"

    awk -F $'\t' -v p="${repo_root}" '$1 != p' "${file}" > "${tmp}"
    printf '%s\t%s\n' "${repo_root}" "${key}" >> "${tmp}"

    run mv -f -- "${tmp}" "${file}"
    chmod 600 "${file}" 2>/dev/null || true

    printf '%s\n' "${file}"

}
git_keymap_get () {

    source <(parse "$@" -- repo)

    local file="${HOME}/.ssh/git-keymap.tsv"
    local repo_root="${repo:-"$(git_repo_root)"}"
    repo_root="$(cd -- "${repo_root}" 2>/dev/null && pwd -P || printf '%s' "${repo_root}")"

    [[ -n "${repo_root}" ]] || return 1
    [[ -f "${file}" ]] || return 1

    awk -F $'\t' -v p="${repo_root}" '
        $1 == p { print $2; found=1; exit }
        END { if (!found) exit 1 }
    ' "${file}"

}
git_guess_ssh_key () {

    local p="$(pwd -P)" key="$(git_keymap_get 2>/dev/null || true)"

    [[ -n "${key}" ]] && { printf '%s\n' "${key}"; return 0; }
    [[ "${p}" == */private/* || "${p}" == */private ]] && { printf '%s\n' "private"; return 0; }
    [[ "${p}" == */public/*  || "${p}" == */public  ]] && { printf '%s\n' "public"; return 0; }

    if [[ -n "${WORKSPACE_DIR:-}" && "${p}" == "${WORKSPACE_DIR%/}/"* ]]; then

        local scope="${p#${WORKSPACE_DIR%/}/}"
        scope="${scope%%/*}"
        [[ -n "${scope}" ]] && { printf '%s\n' "${scope}"; return 0; }

    fi

    return 1

}
git_resolve_ssh_key () {

    local hint="${1:-${GIT_SSH_KEY:-"$(git_guess_ssh_key 2>/dev/null || true)"}}"
    hint="${hint/#\~/${HOME}}"

    local key="${hint}"
    [[ -f "${key}" ]] || key="${HOME}/.ssh/${hint}"
    [[ -f "${key}" ]] || key="${HOME}/.ssh/id_ed25519${hint:+_${hint}}"
    [[ -f "${key}" ]] || key="${HOME}/.ssh/id_ed25519_private"
    [[ -f "${key}" ]] || key="${HOME}/.ssh/id_ed25519"

    printf '%s\n' "${key}"
    return 0

}
git_auth_resolve () {

    local auth="${1:-ssh}" remote="${2:-origin}" key="${3:-}" token="${4:-}" token_env="${5:-GIT_TOKEN}"
    local kind="" target="" safe="" ssh_cmd=""

    if [[ -z "${auth}" ]]; then

        local env_auth="${GIT_AUTH:-}"
        [[ -n "${env_auth}" ]] && auth="${env_auth}" || auth="ssh"

    fi
    if [[ "${auth}" == "ssh" ]]; then

        kind="ssh" target="${remote}" safe="${remote}" key="$(git_resolve_ssh_key "${key}")"

        if [[ -f "${key}" ]]; then printf -v ssh_cmd 'ssh -i %q -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=60 -o ServerAliveInterval=15 -o ServerAliveCountMax=2' "${key}"
        else ssh_cmd='ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=60 -o ServerAliveInterval=15 -o ServerAliveCountMax=2'
        fi

        printf '%s\t%s\t%s\t%s\n' "${kind}" "${target}" "${safe}" "${ssh_cmd}"
        return 0

    fi
    if [[ "${auth}" == "http" ]]; then

        local cur="" host="" path="" url=""
        kind="http"

        [[ -n "${token}" ]] || token="$(get_env "${token_env}")"
        [[ -n "${token}" ]] || die "Missing token. Use --token or --token-env <VAR> (default: ${token_env})."

        cur="$(git_remote_url "${remote}")"
        [[ -n "${cur}" ]] || die "Remote not found: ${remote}"

        read -r host path < <(git_parse_remote "${cur}") || die "Can't parse remote url: $(git_redact_url "${cur}")"
        url="$(git_build_https_token_url "${token}" "${host}" "${path}")" || die "Can't build token url"

        target="${url}"
        safe="https://***@${host}/${path}"

        printf '%s\t%s\t%s\t%s\n' "${kind}" "${target}" "${safe}" ""
        return 0

    fi

    die "Unknown auth: ${auth} (use ssh|http)"

}
git_new_ssh_key () {

    ensure_pkg ssh-keygen mkdir chmod rm
    source <(parse "$@" -- name host alias type=ed25519 bits=4096 comment passphrase file config:bool=true add_agent:bool force:bool)

    local ssh_dir="${HOME}/.ssh" pub="" n="${name}" c="${comment}" base="${file}"
    base="${base/#\~/${HOME}}"

    [[ -n "${host}" ]] || host="${GIT_HOST:-github.com}"
    [[ -n "${passphrase}" ]] || passphrase=""
    [[ -n "${c}" ]] || c="$(git config user.email 2>/dev/null || true)"
    [[ -n "${c}" ]] || c="${USER:-user}@${HOSTNAME:-host}"
    [[ -n "${base}" ]] || base="id_${type}${n:+_${n}}"
    [[ "${base}" == */* ]] || base="${ssh_dir}/${base}"

    pub="${base}.pub"
    (( force )) || [[ ! -e "${base}" && ! -e "${pub}" ]] || die "Key exists: ${base} (use --force to override)"

    mkdir -p "${ssh_dir}"
    chmod 700 "${ssh_dir}" 2>/dev/null || true
    rm -f "${base}" "${pub}" 2>/dev/null || true

    if [[ "${type}" == "rsa" ]]; then run ssh-keygen -t rsa -b "${bits}" -f "${base}" -C "${c}" -N "${passphrase}"
    else run ssh-keygen -t ed25519 -a 64 -f "${base}" -C "${c}" -N "${passphrase}"
    fi

    chmod 600 "${base}" 2>/dev/null || true
    chmod 644 "${pub}" 2>/dev/null || true

    if (( config )); then

        ensure_pkg touch awk mktemp mv

        local cfg="${ssh_dir}/config"
        local a="${alias:-}"
        [[ -n "${a}" ]] || a="${host}${n:+-${n}}"

        run touch -- "${cfg}"
        chmod 600 "${cfg}" 2>/dev/null || true

        local tmp="$(mktemp "${TMPDIR:-/tmp}/vx.sshcfg.XXXXXX")" || die "mktemp failed"

        awk -v a="${a}" '
            BEGIN { drop=0; seen_host=0 }
            $0 == "### vx-key:" a { drop=1; seen_host=0; next }
            drop && $0 ~ /^Host[[:space:]]+/ {
                if (seen_host == 0) { seen_host=1; next }
                drop=0
            }
            drop && $0 ~ /^### vx-key:/ { drop=0 }
            drop { next }
            { print }
        ' "${cfg}" > "${tmp}"

        {
            printf '\n### vx-key:%s\n' "${a}"
            printf 'Host %s\n' "${a}"
            printf '    HostName %s\n' "${host}"
            printf '    User git\n'
            printf '    IdentityFile %s\n' "${base}"
            printf '    IdentitiesOnly yes\n'
        } >> "${tmp}"

        run mv -f -- "${tmp}" "${cfg}"
        chmod 600 "${cfg}" 2>/dev/null || true

    fi
    if (( add_agent )); then

        ensure_pkg ssh-add
        [[ -n "${SSH_AUTH_SOCK:-}" ]] && run ssh-add "${base}"

    fi

    printf '%s\n' "${base}"

}

git_build_ssh_url () {

    local host="${1:-}" path="${2:-}"
    [[ -n "${host}" && -n "${path}" ]] || return 1

    printf 'git@%s:%s\n' "${host}" "${path}"

}
git_build_https_url () {

    local host="${1:-}" path="${2:-}"
    [[ -n "${host}" && -n "${path}" ]] || return 1

    printf 'https://%s/%s\n' "${host}" "${path}"

}
git_norm_path_git () {

    local p="${1:-}"
    [[ -n "${p}" ]] || { printf ''; return 0; }

    p="${p%/}"
    p="${p#/}"
    p="${p%.git}"

    printf '%s.git\n' "${p}"

}
git_initial_branch () {

    ensure_pkg grep git
    ( git init -h 2>&1 || true ) | grep -q -- '--initial-branch'

}
git_set_default_branch () {

    local branch="${1:-main}"

    git branch -M "${branch}" >/dev/null 2>&1 && return 0
    git symbolic-ref HEAD "refs/heads/${branch}" >/dev/null 2>&1 && return 0

    return 0

}
git_guard_no_unborn () {

    ensure_pkg find git

    local root="${1:-.}" d="" repo=""
    local root_abs="$(cd -- "${root}" && pwd -P)" || die "Invalid root: ${root}"

    while IFS= read -r -d '' d; do

        repo="${d%/.git}"

        local repo_abs="$(cd -- "${repo}" && pwd -P 2>/dev/null || true)"
        [[ -n "${repo_abs}" && "${repo_abs}" == "${root_abs}" ]] && continue

        git -C "${repo}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
        git -C "${repo}" rev-parse --verify HEAD >/dev/null 2>&1 && continue

        die "Nested git repo with no commit checked out: ${repo}. Remove its .git or initialize/commit it."

    done < <(find "${root}" -mindepth 2 \( -name .git -type d -o -name .git -type f \) -print0 2>/dev/null)

}
git_root_version () {

    ensure_pkg awk git
    local v="" root="$(git_repo_root)"

    if [[ -f "${root}/Cargo.toml" ]]; then

        v="$(
            awk '
                BEGIN { sect=""; ws=""; pkg="" }

                /^\[workspace\.package\][[:space:]]*$/ { sect="ws"; next }
                /^\[package\][[:space:]]*$/            { sect="pkg"; next }
                /^\[[^]]+\][[:space:]]*$/              { sect=""; next }

                sect=="ws"  && ws==""  && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { ws=m[1]; next }
                sect=="pkg" && pkg=="" && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { pkg=m[1]; next }

                END {
                    if (ws  != "") { print ws;  exit 0 }
                    if (pkg != "") { print pkg; exit 0 }
                    exit 1
                }
            ' "${root}/Cargo.toml" 2>/dev/null
        )" || die "Can't detect version from ${root}/Cargo.toml."

    fi
    if [[ -z "${v}" && -f "${root}/composer.json" ]]; then

        ensure_pkg php
        v="$(
            php -r '$j=@json_decode(@file_get_contents($argv[1]), true); echo is_array($j)&&isset($j["version"])?$j["version"]:"";' \
                "${root}/composer.json" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && -f "${root}/package.json" ]]; then

        ensure_pkg node
        v="$(
            node -e '
                const fs = require("fs");
                const p = process.argv[2];
                try {
                    const j = JSON.parse(fs.readFileSync(p, "utf8"));
                    process.stdout.write(j.version || "");
                } catch (e) {}
            ' "${root}/package.json" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && -f "${root}/pyproject.toml" ]]; then

        v="$(
            awk '
                BEGIN { sect=""; v="" }

                /^\[project\][[:space:]]*$/      { sect="proj"; next }
                /^\[tool\.poetry\][[:space:]]*$/ { sect="poetry"; next }
                /^\[[^]]+\][[:space:]]*$/        { sect=""; next }

                sect=="proj"   && v=="" && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { v=m[1]; print v; exit 0 }
                sect=="poetry" && v=="" && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { v=m[1]; print v; exit 0 }

                END { exit 1 }
            ' "${root}/pyproject.toml" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && -f "${root}/setup.cfg" ]]; then

        v="$(
            awk '
                BEGIN { sect=""; v="" }

                /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
                    s=$0
                    gsub(/^[[:space:]]*\[/,"",s); gsub(/\][[:space:]]*$/,"",s)
                    sect=tolower(s)
                    next
                }

                sect=="metadata" && v=="" && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*([^#;[:space:]]+)/, m) {
                    v=m[1]
                    gsub(/^[[:space:]]+|[[:space:]]+$/,"",v)
                    print v
                    exit 0
                }

                END { exit 1 }
            ' "${root}/setup.cfg" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && -f "${root}/setup.py" ]]; then

        v="$(
            awk '
                match($0, /version[[:space:]]*=[[:space:]]*["'\'']([^"'\'']+)["'\'']/, m) { print m[1]; exit 0 }
                END { exit 1 }
            ' "${root}/setup.py" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && ( -f "${root}/go.mod" || -f "${root}/go.work" ) ]]; then

        v="$(
            git -C "${root}" tag --list |
            awk '
                /^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/ {
                    raw = $0
                    tag = raw
                    sub(/^v/, "", tag)

                    split(tag, a, /[-+]/)
                    split(a[1], n, ".")

                    major = n[1] + 0
                    minor = n[2] + 0
                    patch = n[3] + 0

                    pre = (tag ~ /-/) ? 0 : 1

                    printf "%020d %020d %020d %d %s\n", major, minor, patch, pre, raw
                }
            ' |
            sort |
            tail -n 1 |
            awk '{ print $5 }'
        )" || true

        [[ -n "${v}" ]] && v="${v#v}"

    fi
    if [[ -z "${v}" && -f "${root}/xmake.lua" ]]; then

        v="$(
            awk '
                match($0, /^[[:space:]]*set_version[[:space:]]*\([[:space:]]*"([^"]+)"/, m) {
                    print m[1]
                    exit 0
                }
                END { exit 1 }
            ' "${root}/xmake.lua" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" ]]; then

        local proj=""
        local -a proj_globs=(
            "${root}"/*.csproj
            "${root}"/*.fsproj
            "${root}"/*.vbproj
            "${root}"/src/*.csproj
            "${root}"/src/*.fsproj
            "${root}"/src/*.vbproj
            "${root}"/src/*/*.csproj
            "${root}"/src/*/*.fsproj
            "${root}"/src/*/*.vbproj
            "${root}"/app/*.csproj
            "${root}"/app/*.fsproj
            "${root}"/app/*.vbproj
            "${root}"/app/*/*.csproj
            "${root}"/app/*/*.fsproj
            "${root}"/app/*/*.vbproj
            "${root}"/apps/*.csproj
            "${root}"/apps/*.fsproj
            "${root}"/apps/*.vbproj
            "${root}"/apps/*/*.csproj
            "${root}"/apps/*/*.fsproj
            "${root}"/apps/*/*.vbproj
        )

        for proj in "${proj_globs[@]}"; do

            [[ -f "${proj}" ]] || continue

            v="$(
                awk '
                    match($0, /<Version>[[:space:]]*([^<[:space:]]+)[[:space:]]*<\/Version>/, m) {
                        print m[1]
                        exit 0
                    }
                    match($0, /<VersionPrefix>[[:space:]]*([^<[:space:]]+)[[:space:]]*<\/VersionPrefix>/, m) {
                        vp=m[1]
                    }
                    match($0, /<VersionSuffix>[[:space:]]*([^<[:space:]]+)[[:space:]]*<\/VersionSuffix>/, m) {
                        vs=m[1]
                    }
                    END {
                        if (vp != "" && vs != "") {
                            print vp "-" vs
                            exit 0
                        }
                        if (vp != "") {
                            print vp
                            exit 0
                        }
                        exit 1
                    }
                ' "${proj}" 2>/dev/null
            )" || true

            [[ -n "${v}" ]] && break

        done

    fi
    if [[ -z "${v}" ]]; then

        local f=""
        for f in "${root}/VERSION" "${root}/version" "${root}/.version"; do

            [[ -f "${f}" ]] || continue
            v="$(awk 'NR==1{ gsub(/\r/,""); print $1; exit }' "${f}" 2>/dev/null)" || true
            [[ -n "${v}" ]] && break

        done

    fi

    [[ -n "${v}" ]] || die "Can't detect version from ${root}."
    printf '%s\n' "${v}"

}
git_default_branch () {

    local remote="${1:-origin}" auth="${2:-ssh}" key="${3:-}" token="${4:-}" token_env="${5:-GIT_TOKEN}"

    git_repo_guard
    git_require_remote "${remote}"

    local b="$(git symbolic-ref -q --short "refs/remotes/${remote}/HEAD" 2>/dev/null || true)"
    [[ -n "${b}" ]] && { printf '%s\n' "${b#${remote}/}"; return 0; }

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

    if [[ -n "${sym}" ]]; then
        printf '%s\n' "${sym#refs/heads/}"
        return 0
    fi

    local def="$(git config --get init.defaultBranch 2>/dev/null || true)"

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

cmd_repo_root () {

    git_repo_root

}
cmd_guess_tag () {

    printf '%s\n' "$(git_norm_tag "v$(git_root_version)")"

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
cmd_remote () {

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
    success "Public key:"
    cat -- "${pub}"

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
cmd_init () {

    ensure_pkg git
    source <(parse "$@" -- :repo branch=main remote=origin auth key host create:bool=true)

    local path="" url="" parsed=0 explicit=0 before_url="" after_url="" cur=""

    auth="${auth:-${GIT_AUTH:-ssh}}"
    host="${host:-${GIT_HOST:-github.com}}"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

        if git_initial_branch; then
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
        [[ -n "${branch}" ]] || die "Detached HEAD. Use --branch <name>."
    fi
    if [[ -z "$message" ]]; then
        [[ -n "${tag}" ]] && message="Track ${tag} release." || message="new commit"
    fi

    local root="$(git_repo_root)"
    git_guard_no_unborn "${root}"

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
    ensure_pkg awk
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
        $0 ~ ("^" remote "/HEAD$") { next }

        {
            name = $0
            sub("^" remote "/", "", name)
            if (name != "" && !seen[name]++) print name
        }
    '

}

gh_cmd () {

    ensure_pkg gh mkdir
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

cmd_env_list () {

    gh_env_list "$@"

}
cmd_var_list () {

    gh_var_list variable "$@"

}
cmd_secret_list () {

    gh_var_list secret "$@"

}

cmd_add_var () {

    source <(parse "$@" -- :name value repo)
    gh_var_action add variable "${repo}" "${name}" "${value}" "${kwargs[@]}"

}
cmd_add_secret () {

    source <(parse "$@" -- :name value repo)
    gh_var_action add secret "${repo}" "${name}" "${value}" "${kwargs[@]}"

}
cmd_remove_var () {

    source <(parse "$@" -- :name repo)
    gh_var_action remove variable "${repo}" "${name}" "${kwargs[@]}"

}
cmd_remove_secret () {

    source <(parse "$@" -- :name repo)
    gh_var_action remove secret "${repo}" "${name}" "${kwargs[@]}"

}

cmd_sync_vars () {

    source <(parse "$@" -- file repo)
    gh_var_action sync variable "${repo}" --file "${file}" "${kwargs[@]}"

}
cmd_sync_secrets () {

    source <(parse "$@" -- file repo)
    gh_var_action sync secret "${repo}" --file "${file}" "${kwargs[@]}"

}
cmd_clear_vars () {

    gh_clear_vars variable "$@"

}
cmd_clear_secrets () {

    gh_clear_vars secret "$@"

}

cmd_new_repo () {

    source <(parse "$@" -- sync:bool=true)

    gh_new_repo "${kwargs[@]}"

    (( sync )) && { cmd_sync_vars "${kwargs[@]}"; cmd_sync_secrets "${kwargs[@]}"; }

}
cmd_remove_repo () {

    gh_remove_repo "$@"

}
cmd_new_env () {

    gh_new_env "$@"

}
cmd_remove_env () {

    gh_remove_env "$@"

}

notify_message () {

    local status="${1:-}" title="${2:-}"

    local ref="${REF:-${GITHUB_REF:-}}"
    local sha="${SHA:-${GITHUB_SHA:-}}"
    local url="${URL:-${GITHUB_URL:-${GITHUB_WORKFLOW_URL:-${WORKFLOW_URL:-}}}}"
    local started_at="${STARTED_AT:-${RUN_STARTED_AT:-${GITHUB_RUN_STARTED_AT:-}}}"
    local finished_at="${FINISHED_AT:-${RUN_FINISHED_AT:-${GITHUB_RUN_FINISHED_AT:-}}}"
    local run_id="${RUN_ID:-${GITHUB_RUN_ID:-}}"
    local server_url="${SERVER_URL:-${GITHUB_SERVER_URL:-}}"
    local repo="${REPOSITORY:-${GITHUB_REPOSITORY:-}}"
    local repo_name="${repo##*/}"
    local status_icon="🤔" status_label="Unknown"
    local duration="0s" date_str="$(date -u +%F 2>/dev/null || date +%F)"

    [[ -n "${status}" ]] || status="${STATUS:-${GITHUB_STATUS:-}}"
    [[ -n "${title}" ]] || title="${WORKFLOW_NAME:-${GITHUB_WORKFLOW_NAME:-CI}} Workflow"
    [[ -z "${url}" && -n "${server_url}" && -n "${repo}" && -n "${run_id}" ]] && url="${server_url}/${repo}/actions/runs/${run_id}"

    case "${status,,}" in
        success|succeeded|ok|passed|pass)    status_icon="✅" ; status_label="Success" ;;
        warn|warning|warnings)     status_icon="⚠️" ; status_label="Warning" ;;
        fail|failed|failure|error)  status_icon="❌" ; status_label="Failed" ;;
        cancel|canceled|cancelled) status_icon="🟡" ; status_label="Cancelled" ;;
        skip|skipped)              status_icon="⚪" ; status_label="Skipped" ;;
    esac
    case "${ref}" in
        refs/heads/*) ref="${ref#refs/heads/}" ;;
        refs/tags/*)  ref="${ref#refs/tags/}"  ;;
    esac

    if [[ -n "${started_at}" ]]; then

        local st="${started_at}"
        local ft="${finished_at}"

        [[ "${st}" == *.*Z ]] && st="${st%%.*}Z"
        [[ "${ft}" == *.*Z ]] && ft="${ft%%.*}Z"

        local start_s="$(date -u -d "${st}" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${st}" +%s 2>/dev/null || true)"
        local end_s="$(date -u -d "${ft}" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${ft}" +%s 2>/dev/null || true)"

        [[ -n "${end_s}" ]] || end_s="$(date -u +%s 2>/dev/null || date +%s)"

        if [[ -n "${start_s}" ]]; then

            local delta=$(( end_s - start_s ))
            (( delta < 0 )) && delta=0

            local h=$(( delta / 3600 ))
            local m=$(( (delta % 3600) / 60 ))
            local s=$(( delta % 60 ))

            if (( h > 0 )); then duration="${h}h ${m}m ${s}s"
            elif (( m > 0 )); then duration="${m}m ${s}s"
            else duration="${s}s"
            fi

        fi

    fi

    [[ -n "${url}" ]] || url="--"
    [[ -n "${ref}" ]] || ref="--"
    [[ -n "${repo}" ]] || repo="--"
    [[ -n "${repo_name}" ]] || repo_name="--"
    [[ -n "${sha}" ]] && sha="${sha:0:7}" || sha="--"

    printf '%s\n' \
        "==>" \
        "" \
        "💥 ${title} :" \
        "" \
        "      ( Status )      :  ${status_icon} ${status_label}" \
        "" \
        "      ( Duration )  :  ${duration}" \
        "" \
        "      ( Date )         :  ${date_str}" \
        "" \
        "      ( Repo )        :  ${repo}" \
        "" \
        "      ( Commit )   :  ${repo_name}@${ref} • ${sha}" \
        "" \
        "      ( URL )          :  ${url}" \
        "" \
        "==>"

}
notify_telegram () {

    ensure_pkg curl

    local -n curl_args="${1}"
    local token="${2:-}" chat="${3:-}" msg="${4:-}"

    [[ -n "${token}" ]] || token="${TELEGRAM_TOKEN:-${TOKEN:-}}"
    [[ -n "${chat}"  ]] || chat="${TELEGRAM_CHAT_ID:-${TELEGRAM_CHAT:-${CHAT_ID:-${CHAT:-}}}}"

    [[ -n "${token}" ]] || die "notify: missing telegram token"
    [[ -n "${chat}"  ]] || die "notify: missing telegram chat"

    local -a payload=( -d "chat_id=${chat}" --data-urlencode "text=${msg}" -d "disable_web_page_preview=true" )
    curl "${curl_args[@]}" -X POST "https://api.telegram.org/bot${token}/sendMessage" "${payload[@]}" >/dev/null 2>&1 || return 1

}
notify_slack () {

    ensure_pkg curl jq

    local -n curl_args="${1}"
    local webhook="${2:-}" msg="${3:-}"

    [[ -n "${webhook}" ]] || webhook="${SLACK_WEBHOOK_URL:-${SLACK_WEBHOOK:-${SLACK_URL:-}}}"
    [[ -n "${webhook}" ]] || die "notify_slack: missing slack webhook"

    local -a payload=( --data "$(jq -cn --arg t "${msg}" '{text:$t}')" "${webhook}" )
    curl "${curl_args[@]}" -X POST -H "Content-Type: application/json" "${payload[@]}" >/dev/null 2>&1 || return 1

}
notify_discord () {

    ensure_pkg curl jq

    local -n curl_args="${1}"
    local webhook="${2:-}" msg="${3:-}"

    [[ -n "${webhook}" ]] || webhook="${DISCORD_WEBHOOK_URL:-${DISCORD_WEBHOOK:-${DISCORD_URL:-}}}"
    [[ -n "${webhook}" ]] || die "notify_discord: missing discord webhook"

    local -a payload=( --data "$(jq -cn --arg t "${msg}" '{content:$t}')" "${webhook}" )
    curl "${curl_args[@]}" -X POST -H "Content-Type: application/json" "${payload[@]}" >/dev/null 2>&1 || return 1

}
notify_webhook () {

    ensure_pkg curl jq

    local -n curl_args="${1}"
    local webhook="${2:-}" msg="${3:-}"

    [[ -n "${webhook}" ]] || webhook="${WEBHOOK_URL:-${WEBHOOK:-}}"
    [[ -n "${webhook}" ]] || die "notify_webhook: missing webhook url"

    local -a payload=( --data "$(jq -cn --arg t "${msg}" '{text:$t}')" "${webhook}" )
    curl "${curl_args[@]}" -X POST -H "Content-Type: application/json" "${payload[@]}" >/dev/null 2>&1 || return 1

}

cmd_notify () {

    source <(parse "$@" -- \
        platform:list platforms:list \
        status title message \
        token chat telegram_token telegram_chat \
        webhook url slack_webhook discord_webhook webhook_url \
        retries:int=3 delay:int=1 timeout:float=10 max_time:float=20 retry_max_time:float=60 \
    )

    local msg="${message:-"$(notify_message "${status}" "${title}")"}"

    local -a args=(
        -fsS
        --connect-timeout "${timeout}"
        --max-time "${max_time}"
        --retry-max-time "${retry_max_time}"
        --retry "${retries}"
        --retry-delay "${delay}"
        --retry-connrefused
    )

    local -a plats=() failed=()
    local  p=""

    if (( ${#platform[@]} )); then plats=( "${platform[@]}" )
    elif (( ${#platforms[@]} )); then plats=( "${platforms[@]}" )
    else plats=( telegram )
    fi

    for p in "${plats[@]}"; do

        case "${p,,}" in
            telegram) notify_telegram args "${telegram_token:-${token}}" "${telegram_chat:-${chat}}" "${msg}" || failed+=( telegram ) ;;
            slack)    notify_slack    args "${slack_webhook:-${webhook:-${url:-}}}" "${msg}" || failed+=( slack ) ;;
            discord)  notify_discord  args "${discord_webhook:-${webhook:-${url:-}}}" "${msg}" || failed+=( discord ) ;;
            webhook)  notify_webhook  args "${webhook_url:-${webhook:-${url:-}}}" "${msg}" || failed+=( webhook ) ;;
            *) failed+=( "${p}" ) ;;
        esac

    done

    if (( ${#failed[@]} )); then die "Failed to send ( ${failed[*]} ) notification"
    else success "Ok: Notification sent successfully ( ${plats[*]} )"
    fi

}
cmd_notify_telegram () {

    source <(parse "$@" -- status title message token chat)

    cmd_notify --platform telegram \
        --status "${status}" --title "${title}" --message "${message}" \
        --token "${token}" --chat "${chat}" "${kwargs[@]}"

}
cmd_notify_slack () {

    source <(parse "$@" -- status title message webhook)

    cmd_notify --platform slack \
        --status "${status}" --title "${title}" --message "${message}" \
        --webhook "${webhook}" "${kwargs[@]}"

}
cmd_notify_discord () {

    source <(parse "$@" -- status title message webhook)

    cmd_notify --platform discord \
        --status "${status}" --title "${title}" --message "${message}" \
        --webhook "${webhook}" "${kwargs[@]}"

}
cmd_notify_webhook () {

    source <(parse "$@" -- status title message webhook)

    cmd_notify --platform webhook \
        --status "${status}" --title "${title}" --message "${message}" \
        --webhook "${webhook}" "${kwargs[@]}"

}
cmd_notify_all () {

    cmd_notify --platforms telegram --platforms slack --platforms discord --platforms webhook "$@"

}

cmd_safety_help () {

    info_ln "Safety :\n"

    printf '    %s\n' \
        "leaks                      * Remove trailing whitespace in git-tracked files" \
        "sbom                       * Remove trailing whitespace in git-tracked files" \
        "trivy                      * Remove trailing whitespace in git-tracked files" \
        ''

}

cmd_leaks () {

    ensure gitleaks
    source <(parse "$@" -- mode format target out config baseline redact=100 fail:bool=true)

    out="${out:-/dev/stdout}"

    local exit_code="0"; (( fail )) && exit_code="1"
    local -a cmd=()

    config="${config:-"$(config_file gitleaks toml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    [[ -n "${baseline}" ]] && cmd+=( --baseline-path "${baseline}" )
    [[ -n "${redact}" ]] && cmd+=( --redact="${redact}" )

    [[ -n "${mode}" ]] || { is_ci && mode="git" || mode="dir"; }
    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"

    run gitleaks "${mode}" --no-banner --report-path "${out}" --report-format "${format:-json}" \
        --exit-code "${exit_code}" "${cmd[@]}" "${kwargs[@]}" -- "${target:-.}"

}
cmd_sbom () {

    ensure syft
    source <(parse "$@" -- src format out config)

    format="${format:-cyclonedx-json}"
    out="${out:-${OUT_DIR:-out}/sbom.json}"

    local -a cmd=()

    config="${config:-"$(config_file syft yaml yml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )
    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"
    run syft scan -o "${format}=${out}" "${cmd[@]}" "${kwargs[@]}" -- "${src:-dir:.}"

}
cmd_trivy () {

    ensure trivy
    source <(parse "$@" -- mode format target out scanners severity config no_progress:bool=true ignore_unfixed:bool=true fail:bool=true)

    out="${out:-/dev/stdout}"
    scanners="${scanners:-vuln,secret,misconfig,license}"
    severity="${severity:-CRITICAL,HIGH}"

    local exit_code="0"; (( fail )) && exit_code="1"
    local -a cmd=()

    config="${config:-"$(config_file trivy yaml yml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    [[ -n "${severity}" ]] && cmd+=( --severity "${severity}" )
    [[ -n "${scanners}" ]] && cmd+=( --scanners "${scanners}" )

    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"

    (( no_progress )) && cmd+=( --no-progress )
    (( ignore_unfixed )) && [[ "${scanners}" == *vuln* ]] && cmd+=( --ignore-unfixed )

    run trivy "${mode:-fs}" --output "${out}" --format "${format:-table}" \
        --exit-code "${exit_code}" "${cmd[@]}" "${kwargs[@]}" "${target:-.}"

}

cmd_pretty_help () {

    info_ln "Pretty :\n"

    printf '    %s\n' \
        "typo-check                 * Typos check docs and text files" \
        "typo-fix                   * Typos fix docs and text files" \
        "" \
        "taplo-check                * Validate TOML formatting (no changes)" \
        "taplo-fix                  * Auto-format TOML files" \
        "" \
        "prettier-check             * Validate formatting for Markdown/YAML/etc. (no changes)" \
        "prettier-fix               * Auto-format Markdown/YAML/etc." \
        "" \
        "normalize                  * Remove trailing whitespace in git-tracked files" \
        ''

}

cmd_typo_check () {

    ensure typos

    local -a cmd=()

    local config="$(config_file typos toml)"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    run typos --format brief "${cmd[@]}" "$@"

}
cmd_typo_fix () {

    ensure typos

    local -a cmd=()

    local config="$(config_file typos toml)"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    run typos -w "${cmd[@]}" "$@"

}

cmd_taplo_check () {

    ensure taplo
    run taplo fmt --check "$@"

}
cmd_taplo_fix () {

    ensure taplo
    run taplo fmt "$@"

}

cmd_prettier_check () {

    ensure node
    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --check "**/*.{md,mdx,yml,yaml,json,jsonc}" ".prettierrc.yml" "$@"

}
cmd_prettier_fix () {

    ensure node
    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --write "**/*.{md,mdx,yml,yaml,json,jsonc}" ".prettierrc.yml" "$@"

}

cmd_normalize () {

    ensure git perl

    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo"
    git diff --quiet -- && { git diff --cached --quiet -- || die "normalize: requires clean worktree"; }

    git ls-files -z | perl -e '
        use strict;
        use warnings;
        use File::Basename qw(dirname);
        use File::Temp qw(tempfile);

        binmode(STDIN);
        local $/ = "\0";
        my $ec = 0;

        while (defined(my $path = <STDIN>)) {

            chomp($path);
            next if $path eq "";
            next if -l $path;
            next if !-f $path;
            open my $in, "<:raw", $path or do { $ec = 1; next; };
            local $/;

            my $data = <$in>;
            close $in;
            next if !defined $data;
            next if index($data, "\0") != -1;

            my $changed = ($data =~ s/[ \t]+(?=\r?$)//mg);
            next if !$changed;
            my $dir = dirname($path);
            my ($tmpfh, $tmp) = tempfile(".wsfix.XXXXXX", DIR => $dir, UNLINK => 0) or do { $ec = 1; next; };
            binmode($tmpfh);

            print $tmpfh $data or do { close $tmpfh; unlink($tmp); $ec = 1; next; };
            close $tmpfh or do { unlink($tmp); $ec = 1; next; };
            my @st = stat($path);

            if (@st) {

                chmod($st[2] & 07777, $tmp);
                eval { chown($st[4], $st[5], $tmp); 1; };

            }

            if (rename($tmp, $path)) { next; }
            my $bak = $path . ".wsfix.bak.$$";

            if (!rename($path, $bak)) {

                unlink($tmp);
                $ec = 1;
                next;

            }
            if (!rename($tmp, $path)) {

                rename($bak, $path);
                unlink($tmp);
                $ec = 1;
                next;

            }

            unlink($bak);

        }

        exit($ec);
    '

    run git add --renormalize .
    run git restore .

}
#!/usr/bin/env bash

active_version () {

    tool_active_version

}
stable_version () {

    tool_stable_version

}
nightly_version () {

    tool_nightly_version

}
msrv_version () {

    tool_msrv_version

}

publishable_pkgs () {

    ensure cargo jq

    run cargo metadata --format-version=1 --no-deps | jq -r '
        def publish_list:
            if .publish == null then ["crates-io"]
            elif .publish == false then []
            elif (.publish | type) == "array" then .publish
            else []
            end;

        . as $m
        | ($m.workspace_members) as $ws
        | $m.packages[]
        | select(.id as $id | $ws | index($id) != null)
        | select(.source == null)
        | select((publish_list | length) > 0)
        | select(publish_list | index("crates-io") != null)
        | .name
    ' | tool_sort_uniq

}
not_publishable_pkgs () {

    ensure cargo jq

    run cargo metadata --format-version=1 --no-deps | jq -r '
        def publish_list:
            if .publish == null then ["crates-io"]
            elif .publish == false then []
            elif (.publish | type) == "array" then .publish
            else []
            end;

        . as $m
        | ($m.workspace_members) as $ws
        | $m.packages[]
        | select(.id as $id | $ws | index($id) != null)
        | select(.source == null)
        | select((publish_list | length) == 0 or (publish_list | index("crates-io") == null))
        | .name
    ' | tool_sort_uniq

}
workspace_pkgs () {

    ensure cargo jq

    run cargo metadata --format-version=1 --no-deps | jq -r '
        . as $m
        | ($m.workspace_members) as $ws
        | $m.packages[]
        | select(.id as $id | $ws | index($id) != null)
        | select(.source == null)
        | .name
    ' | tool_sort_uniq

}
ensure_workspace_pkg () {

    (( $# > 0 )) || die "ensure_workspace_pkg: missing package name(s)" 2

    local -a ws_pkgs=()
    mapfile -t ws_pkgs < <(workspace_pkgs)

    (( ${#ws_pkgs[@]} > 0 )) || die "ensure_workspace_pkg: no workspace packages found" 2

    local -A ws_set=()
    local -A miss_set=()
    local -a missing=()
    local x="" p=""

    for x in "${ws_pkgs[@]-}"; do
        ws_set["${x}"]=1
    done

    for p in "$@"; do

        [[ -n "${p}" ]] || continue
        [[ -n "${ws_set[${p}]-}" ]] && continue
        [[ -n "${miss_set[${p}]-}" ]] && continue

        miss_set["${p}"]=1
        missing+=( "${p}" )

    done

    (( ${#missing[@]} == 0 )) || die "Unknown workspace package(s): ${missing[*]}" 2

}

resolve_cmd () {

    source <(parse "$@" -- :name:str)

    case "${name}" in
        taplo-cli) name="taplo" ;;
        fd|fd-find) name="fdfind" ;;
        ripgrep) name="rg" ;;
        rust) name="rustc" ;;
        bat) name="batcat" ;;
        ci-cache-clean|semver-checks ) name="cargo-${name}" ;;
    esac

    local n="${name}" n1="${name//_/-}" n2="${name//-/_}"

    command -v -- "${n}"  >/dev/null 2>&1 && { printf '%s\n' "${n}"; return 0; }
    command -v -- "${n1}" >/dev/null 2>&1 && { printf '%s\n' "${n1}"; return 0; }
    command -v -- "${n2}" >/dev/null 2>&1 && { printf '%s\n' "${n2}"; return 0; }

    if [[ "${n}" != cargo-* ]]; then

        [[ "${n}" == "miri" ]] && command -v -- cargo-miri >/dev/null 2>&1 && { printf '%s\n' "cargo +nightly miri"; return 0; }

        command -v -- "cargo-${n}"  >/dev/null 2>&1 && { printf '%s\n' "cargo ${n}";  return 0; }
        command -v -- "cargo-${n1}" >/dev/null 2>&1 && { printf '%s\n' "cargo ${n1}"; return 0; }
        command -v -- "cargo-${n2}" >/dev/null 2>&1 && { printf '%s\n' "cargo ${n2}"; return 0; }

    else

        command -v -- "${n}"  >/dev/null 2>&1 && { printf '%s\n' "${n}"; return 0; }
        command -v -- "${n1}" >/dev/null 2>&1 && { printf '%s\n' "${n1}"; return 0; }
        command -v -- "${n2}" >/dev/null 2>&1 && { printf '%s\n' "${n2}"; return 0; }

    fi

    return 1

}
set_perf_paranoid () {

    [[ "$(os_name)" == "linux" ]] || return 0

    local paranoid_file="/proc/sys/kernel/perf_event_paranoid"
    [[ -r "${paranoid_file}" ]] || return 0

    local current_val="$(tr -d ' \t\r\n' < "${paranoid_file}" 2>/dev/null || true)"
    [[ -n "${current_val}" ]] || return 0
    [[ "${current_val}" =~ ^-?[0-9]+$ ]] || { warn "perf_event_paranoid: unexpected value '${current_val}'"; return 0; }

    (( current_val <= 1 )) && return 0

    info "Kernel perf_event_paranoid=${current_val} (too restrictive for profiling; need <= 1)."

    if run sudo sysctl -w kernel.perf_event_paranoid=1; then
        success "perf_event_paranoid set to 1."
        return 0
    fi

    die "Failed to change perf_event_paranoid. Try: echo 1 | sudo tee ${paranoid_file}" 2

}
set_perf_flame () {

    ensure linux-tools-common linux-tools-generic linux-cloud-tools-generic

    local k="$(uname -r)"
    local real="$(readlink -f /usr/lib/linux-tools/*/perf 2>/dev/null | head -n 1)"

    sudo mkdir -p "/usr/lib/linux-tools/${k}"
    sudo ln -sf "${real}" "/usr/lib/linux-tools/${k}/perf"

    export PERF="${real}"

}
check_max_size () {

    local file="${1-}" max_size="${2-}" bytes="" limit_bytes="" s=""
    [[ -n "${file}" && -n "${max_size}" && -f "${file}" ]] || return 0

    s="${max_size}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    s="${s//[[:space:]]/}"

    case "${s}" in
        *[!0-9A-Za-z.]*) die "bloat: invalid max_size: ${max_size}" 2 ;;
    esac

    limit_bytes="$(
        awk -v s="${s}" '
            BEGIN {
                if (!match(s, /^([0-9]+(\.[0-9]+)?)([A-Za-z]*)$/, a)) exit 2

                val = a[1]
                u = tolower(a[3])

                mul = 1

                if (u == "" || u == "b" || u == "bytes") mul = 1
                else if (u == "k" || u == "kb") mul = 1024
                else if (u == "m" || u == "mb") mul = 1024 * 1024
                else if (u == "g" || u == "gb") mul = 1024 * 1024 * 1024
                else exit 3

                out = int((val + 0) * mul + 0.5)
                if (out < 0) out = 0
                printf "%.0f", out
            }
        ' 2>/dev/null
    )" || die "bloat: invalid max_size: ${max_size}" 2

    [[ -n "${limit_bytes}" && "${limit_bytes}" =~ ^[0-9]+$ ]] || die "bloat: invalid max_size: ${max_size}" 2

    if bytes="$(stat -c%s -- "${file}" 2>/dev/null)"; then :
    elif bytes="$(stat -f%z -- "${file}" 2>/dev/null)"; then :
    else bytes="$(wc -c < "${file}" 2>/dev/null | tr -d ' ')" || true
    fi

    [[ -n "${bytes}" && "${bytes}" =~ ^[0-9]+$ ]] || die "bloat: failed to read file size: ${file}" 2
    (( bytes > limit_bytes )) && die "bloat: max_size exceeded: ${file} (${bytes} bytes > ${max_size})" 2

}

run_cargo () {

    ensure cargo

    local sub="${1:-}" tc="" mode="stable" use_plus=0 need_docflags=0
    local -a pass=()

    [[ -n "${sub}" ]] || die "run_cargo requires a cargo subcommand." 2

    shift || true
    has rustup && use_plus=1

    case "${sub}" in
        add|rm|bench|build|check|test|clean|doc|fetch|fix|generate-lockfile|help|init|install|locate-project|login|logout|metadata|new|info) : ;;
        owner|package|pkgid|publish|remove|report|run|rustc|rustdoc|search|tree|uninstall|update|upgrade|vendor|verify-project|version|yank) : ;;
        clippy|taplo|miri|samply|flamegraph|hunspell) ensure "${sub}" ;;
        fmt|rustfmt) ensure rustfmt ;;
        *) ensure "cargo-${sub}" ;;
    esac

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--nightly) mode="nightly"; shift || true ;;
            -m|--msrv|--min) mode="msrv"; shift || true ;;
            -s|--stable) mode="stable"; shift || true ;;
            --) pass+=( "--" ); shift || true; pass+=( "$@" ); break ;;
            *) pass+=( "$1" ); shift || true ;;
        esac
    done

    if (( use_plus )); then

        if [[ "${mode}" == "nightly" ]]; then tc="$(tool_nightly_version)"
        elif [[ "${mode}" == "msrv" ]]; then tc="$(tool_msrv_version)"
        else tc="$(tool_stable_version)"
        fi

    else

        [[ "${mode}" == "stable" ]] || die "rustup not found: Use --stable or install rustup." 2

    fi

    if [[ "${sub}" == "doc" || "${sub}" == "rustdoc" ]]; then

        need_docflags=1

    elif [[ "${sub}" == "test" ]]; then

        local a=""

        for a in "${pass[@]}"; do
            [[ "${a}" == "--doc" ]] && { need_docflags=1; break; }
        done

    fi

    if (( need_docflags )); then

        local docflags="$(tool_docflags_deny)"

        if (( use_plus )); then
            RUSTDOCFLAGS="${docflags}" run cargo +"${tc}" "${sub}" "${pass[@]}"
            return $?
        fi

        RUSTDOCFLAGS="${docflags}" run cargo "${sub}" "${pass[@]}"
        return $?

    fi
    if (( use_plus )); then

        run cargo +"${tc}" "${sub}" "${pass[@]}"
        return $?

    fi

    run cargo "${sub}" "${pass[@]}"

}
run_workspace () {

    local command="${1:-}" features=0 targets=0 no_deps=0 all=0 workspace=1 a="" nested=""
    local -a extra=()

    [[ -n "${command}" ]] || die "run_workspace: missing sub-command" 2
    shift || true

    if [[ "${1-}" == "features-on" || "${1-}" == "features-off" ]]; then
        [[ "${1}" == "features-on" ]] && features=1
        shift || true
    fi
    if [[ "${1-}" == "targets-on" || "${1-}" == "targets-off" ]]; then
        [[ "${1}" == "targets-on" ]] && targets=1
        shift || true
    fi
    if [[ "${1-}" == "deps-on" || "${1-}" == "deps-off" ]]; then
        [[ "${1}" == "deps-off" ]] && no_deps=1
        shift || true
    fi
    if [[ "${1-}" == "all-on" || "${1-}" == "all-off" ]]; then
        [[ "${1}" == "all-on" ]] && all=1
        shift || true
    fi
    if [[ "${command}" == "nextest" || "${command}" == "hack" ]]; then
        if [[ "${1-}" != "" && "${1}" != "--" && "${1}" != -* ]]; then
            nested="${1}"
            shift || true
        fi
    fi

    for a in "$@"; do

        [[ "${a}" == "--" ]] && break

        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
                workspace=0
            ;;
        esac
        case "${a}" in
            -F|--features|--features=*|--no-default-features|--all-features)
                features=0
            ;;
        esac
        case "${a}" in
            --lib|--bin|--bin=*|--bins|--example|--example=*|--examples|--test|--test=*|--tests|--bench|--bench=*|--benches|--all-targets)
                targets=0
            ;;
        esac
        case "${a}" in
            --no-deps|--no-deps=*) no_deps=0 ;;
        esac
        case "${a}" in
            --all|--all=*) all=0 ;;
        esac

    done

    (( features )) && extra+=( --all-features )
    (( targets )) && extra+=( --all-targets )
    (( no_deps )) && extra+=( --no-deps )
    (( all )) && extra+=( --all )

    if (( ! workspace || all )); then

        [[ -n "${nested}" ]] &&
            run_cargo "${command}" "${nested}" "${extra[@]}" "$@" ||
            run_cargo "${command}" "${extra[@]}" "$@"

        return 0

    fi

    if [[ -n "${nested}" ]]; then run_cargo "${command}" "${nested}" --workspace "${extra[@]}" "$@"
    else run_cargo "${command}" --workspace "${extra[@]}" "$@"
    fi

}
run_workspace_publishable () {

    local command="${1:-}" features=0 targets=0 no_deps=0 all=0 workspace=1 a=""
    local -a extra=()

    [[ -n "${command}" ]] || die "run_workspace: missing sub-command" 2
    shift || true

    if [[ "${1-}" == "features-on" || "${1-}" == "features-off" ]]; then
        [[ "${1}" == "features-on" ]] && features=1
        shift || true
    fi
    if [[ "${1-}" == "targets-on" || "${1-}" == "targets-off" ]]; then
        [[ "${1}" == "targets-on" ]] && targets=1
        shift || true
    fi
    if [[ "${1-}" == "deps-on" || "${1-}" == "deps-off" ]]; then
        [[ "${1}" == "deps-off" ]] && no_deps=1
        shift || true
    fi
    if [[ "${1-}" == "all-on" || "${1-}" == "all-off" ]]; then
        [[ "${1}" == "all-on" ]] && all=1
        shift || true
    fi

    for a in "$@"; do

        [[ "${a}" == "--" ]] && break

        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--all)
                workspace=0
            ;;
        esac
        case "${a}" in
            -F|--features|--features=*|--no-default-features|--all-features)
                features=0
            ;;
        esac
        case "${a}" in
            --lib|--bin|--bin=*|--bins|--example|--example=*|--examples|--test|--test=*|--tests|--bench|--bench=*|--benches|--all-targets)
                targets=0
            ;;
        esac
        case "${a}" in
            --no-deps|--no-deps=*) no_deps=0 ;;
        esac
        case "${a}" in
            --all|--all=*) all=0 ;;
        esac

    done

    (( features )) && extra+=( --all-features )
    (( targets )) && extra+=( --all-targets )
    (( no_deps )) && extra+=( --no-deps )
    (( all )) && extra+=( --all )

    if (( ! workspace || all )); then
        run_cargo "${command}" "${extra[@]}" "$@"
        return 0
    fi

    local -a pkgs=()
    local p=""

    while IFS= read -r p; do [[ -n "${p}" ]] && pkgs+=( --package "${p}" ); done < <(publishable_pkgs)
    (( ${#pkgs[@]} )) || die "No publishable workspace crates found" 2

    run_cargo "${command}" "${pkgs[@]}" "${extra[@]}" "$@"

}

ENSURE_TOOLS=1

cmd_gates_help () {

    info_ln "CI Gates :\n"

    printf '    %s\n' \
        "ci-stable                  * CI stable (check + test) no-default-features + all-features + release" \
        "ci-nightly                 * CI nightly (check + test) no-default-features + all-features + release" \
        "ci-msrv                    * CI msrv (check + test) no-default-features + all-features + release" \
        "" \
        "ci-doc                     * CI docs (doc-check + doc-test)" \
        "ci-bench                   * CI benches (check --benches)" \
        "ci-example                 * CI examples (check --examples)" \
        "ci-panic                   * CI panic=abort (nightly + all-features)" \
        "" \
        "ci-fmt                     * CI format (fmt-check)" \
        "ci-safety                  * CI lint (taplo + prettier + spellcheck)" \
        "ci-lint                    * CI clippy check (cargo-clippy)" \
        "" \
        "ci-audit                   * CI audit (cargo-audit/deny)" \
        "ci-vet                     * CI vet (cargo-vet)" \
        "ci-hack                    * CI hack (cargo-hack)" \
        "ci-udeps                   * CI udeps (cargo-udeps)" \
        "ci-bloat                   * CI bloat (cargo-bloat)" \
        "" \
        "ci-fuzz                    * CI fuzz (runs targets with timeout & corpus)" \
        "ci-sanitizer               * CI sanitizer detect UB" \
        "ci-miri                    * CI miri detect UB / unsafe issues" \
        "" \
        "ci-semver                  * CI Semver (check semver)" \
        "ci-coverage                * CI coverage (llvm-cov)" \
        "" \
        "ci-publish                 * CI publish gate then publish (full checks + publish)" \
        "" \
        "ci-local                   * Run a pipeline simulation ( full previous ci-xxx features )" \
        ''

}

cmd_ci_stable () {

    (( ENSURE_TOOLS )) && cmd_ensure nextest

    info_ln "Check Stable ...\n"

    cmd_check "$@"
    cmd_check --no-default-features "$@"
    cmd_check --all-features "$@"
    cmd_check --release "$@"

    info_ln "Test Stable ...\n"

    cmd_test "$@"
    cmd_test --no-default-features "$@"
    cmd_test --all-features "$@"
    cmd_test --release "$@"

    success_ln "CI Stable Succeeded.\n"

}
cmd_ci_nightly () {

    (( ENSURE_TOOLS )) && cmd_ensure nextest

    info_ln "Check Nightly ...\n"

    cmd_check --nightly "$@"
    cmd_check --nightly --no-default-features "$@"
    cmd_check --nightly --all-features "$@"
    cmd_check --nightly --release "$@"

    info_ln "Test Nightly ...\n"

    cmd_test --nightly "$@"
    cmd_test --nightly --no-default-features "$@"
    cmd_test --nightly --all-features "$@"
    cmd_test --nightly --release "$@"

    success_ln "CI Nightly Succeeded.\n"

}
cmd_ci_msrv () {

    (( ENSURE_TOOLS )) && cmd_ensure nextest

    info_ln "Check Msrv ...\n"

    cmd_check --msrv "$@"
    cmd_check --msrv --no-default-features "$@"
    cmd_check --msrv --all-features "$@"
    cmd_check --msrv --release "$@"

    info_ln "Test Msrv ...\n"

    cmd_test --msrv "$@"
    cmd_test --msrv --no-default-features "$@"
    cmd_test --msrv --all-features "$@"
    cmd_test --msrv --release "$@"

    success_ln "CI Msrv Succeeded.\n"

}

cmd_ci_doc () {

    (( ENSURE_TOOLS )) && cmd_ensure nextest

    info_ln "Check Doc ...\n"
    cmd_doc_check "$@"

    info_ln "Test Doc ...\n"
    cmd_doc_test "$@"

    success_ln "CI Doc Succeeded.\n"

}
cmd_ci_bench () {

    info_ln "Check Benches ...\n"
    cmd_check --benches "$@"

    success_ln "CI Bench Succeeded.\n"

}
cmd_ci_example () {

    info_ln "Check Examples ...\n"
    cmd_check --examples "$@"

    success_ln "CI Example Succeeded.\n"

}
cmd_ci_panic () {

    (( ENSURE_TOOLS )) && cmd_ensure nextest

    info_ln "Panic ...\n"
    RUSTFLAGS="${RUSTFLAGS:-} -C panic=abort -Zpanic-abort-tests" cmd_test --nightly --all-features "$@"

    success_ln "CI Panic Succeeded.\n"

}

cmd_ci_fmt () {

    (( ENSURE_TOOLS )) && cmd_ensure fmt

    info_ln "Format ...\n"
    cmd_fmt_check "$@"

    success_ln "CI Format Succeeded.\n"

}
cmd_ci_lint () {

    (( ENSURE_TOOLS )) && cmd_ensure taplo spell

    info_ln "Taplo ...\n"
    cmd_taplo_check "$@"

    info_ln "Prettier ...\n"
    cmd_prettier_check "$@"

    info_ln "Spellcheck ...\n"
    cmd_spell_check "$@"

    success_ln "CI Lint Succeeded.\n"

}
cmd_ci_clippy () {

    (( ENSURE_TOOLS )) && cmd_ensure clippy

    info_ln "Clippy ...\n"
    cmd_clippy "$@"

    success_ln "CI Clippy Succeeded.\n"

}

cmd_ci_audit () {

    (( ENSURE_TOOLS )) && cmd_ensure audit deny

    info_ln "Audit ...\n"
    cmd_audit_check "$@"

    success_ln "CI Audit Succeeded.\n"

}
cmd_ci_vet () {

    (( ENSURE_TOOLS )) && cmd_ensure vet

    info_ln "Vet ...\n"
    cmd_vet_check "$@"

    success_ln "CI Vet Succeeded.\n"

}
cmd_ci_hack () {

    (( ENSURE_TOOLS )) && cmd_ensure hack

    info_ln "Hack ...\n"
    cmd_hack "$@"

    success_ln "CI Hack Succeeded.\n"

}
cmd_ci_udeps () {

    (( ENSURE_TOOLS )) && cmd_ensure udeps

    info_ln "Udeps ...\n"
    cmd_udeps "$@"

    success_ln "CI Udeps Succeeded.\n"

}
cmd_ci_bloat () {

    (( ENSURE_TOOLS )) && cmd_ensure bloat

    info_ln "Bloat ...\n"
    cmd_bloat "$@"

    success_ln "CI Bloat Succeeded.\n"

}

cmd_ci_sanitizer () {

    (( ENSURE_TOOLS )) && cmd_ensure sanitizer

    info_ln "Sanitizer ...\n"

    cmd_sanitizer asan "$@"
    cmd_sanitizer tsan "$@"
    cmd_sanitizer lsan "$@"
    cmd_sanitizer msan "$@"

    success_ln "CI Sanitizer Succeeded.\n"

}
cmd_ci_fuzz () {

    (( ENSURE_TOOLS )) && cmd_ensure fuzz

    info_ln "Fuzz ...\n"
    cmd_fuzz "$@"

    success_ln "CI Fuzz Succeeded.\n"

}
cmd_ci_miri () {

    (( ENSURE_TOOLS )) && cmd_ensure miri

    info_ln "Miri ...\n"
    cmd_miri "$@"

    success_ln "CI Miri Succeeded.\n"

}

cmd_ci_semver () {

    (( ENSURE_TOOLS )) && cmd_ensure semver

    info_ln "Semver ...\n"
    cmd_semver "$@"

    success_ln "CI Semver Succeeded.\n"

}
cmd_ci_coverage () {

    (( ENSURE_TOOLS )) && cmd_ensure cov

    info_ln "Coverage ...\n"
    cmd_coverage --upload "$@"

    success_ln "CI Coverage Succeeded.\n"

}
cmd_ci_publish () {

    info_ln "Publish ...\n"
    # cmd_publish "$@"

    success_ln "CI Publish Succeeded.\n"

}

cmd_ci_local () {

    ENSURE_TOOLS=0

    cmd_ensure

    cmd_ci_stable
    cmd_ci_nightly
    cmd_ci_msrv

    cmd_ci_doc
    cmd_ci_bench
    cmd_ci_example
    cmd_ci_panic

    cmd_ci_fmt
    cmd_ci_lint
    cmd_ci_clippy

    cmd_ci_audit
    cmd_ci_vet
    cmd_ci_hack
    cmd_ci_udeps
    cmd_ci_bloat

    cmd_ci_sanitizer
    cmd_ci_miri
    cmd_ci_fuzz

    cmd_ci_semver

    cmd_ci_coverage --no-upload
    cmd_ci_publish --dry-run

    success_ln "CI Pipeline Succeeded.\n"

}

cmd_perf_help () {

    info_ln "Safety :\n"

    printf '    %s\n' \
        "semver                     * Semver via cargo llvm-cov (lcov/codecov)" \
        "coverage                   * Coverage via cargo llvm-cov (lcov/codecov)" \
        "" \
        "bloat                      * Check bloat for (binary size)" \
        "udeps                      * Detect unused dependencies (cargo udeps)" \
        "hack                       * Feature-matrix checks (cargo hack)" \
        "" \
        "fuzz                       * Fuzz targets (cargo fuzz) with sane defaults" \
        "miri                       * Miri interpreter checks (UB / unsafe issues)" \
        "sanitizer                  * Sanitizers pipeline (asan/tsan/msan/lsan) for UB detection" \
        "" \
        "samply                     * CPU profiling via samply (Firefox Profiler UI) for one target" \
        "samply-load                * Load saved samply profile (default: profiles/samply.json)" \
        "" \
        "flame                      * CPU flamegraph via cargo flamegraph (output: SVG)" \
        "flame-open                 * Open saved flamegraph SVG (default: profiles/flamegraph.svg)" \
        ''

}

semver_baseline () {

    local baseline="${1:-}" remote="${2:-origin}" def="" base=""

    [[ -n "${baseline}" ]] && { printf '%s' "${baseline}"; return 0; }
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

    if is_ci_pull; then

        base="${GITHUB_BASE_REF:-}"
        [[ -n "${base}" ]] || die "semver: missing GITHUB_BASE_REF (or pass --base <rev>)"

        git show-ref --verify --quiet "refs/remotes/${remote}/${base}" 2>/dev/null || \
            run git fetch --no-tags "${remote}" "${base}:refs/remotes/${remote}/${base}" >/dev/null 2>&1 || \
                die "semver: git fetch failed"

        printf '%s' "${remote}/${base}"
        return 0

    fi

    def="$(git symbolic-ref -q "refs/remotes/${remote}/HEAD" 2>/dev/null || true)"
    def="${def#refs/remotes/"${remote}"/}"
    [[ -n "${def}" ]] || def="main"

    git show-ref --verify --quiet "refs/remotes/${remote}/${def}" 2>/dev/null || \
        run git fetch --no-tags "${remote}" "${def}:refs/remotes/${remote}/${def}" >/dev/null 2>&1 || true

    git show-ref --verify --quiet "refs/remotes/${remote}/${def}" 2>/dev/null || return 0
    printf '%s' "${remote}/${def}"

}
cmd_semver () {

    ensure cargo cargo-semver-checks
    source <(parse "$@" -- base remote)

    local baseline="$(semver_baseline "${base}" "${remote}")"
    [[ -n "${baseline}" ]] || die "semver: cannot detect baseline"

    run cargo semver-checks check-release --baseline-rev "${base}" "${kwargs[@]}"

}

cov_upload_out () {

    ensure curl chmod mv mkdir
    source <(parse "$@" -- mode name version token flags out)

    [[ -n "${flags}" ]] || flags="${name}"
    [[ -n "${name}"  ]] || name="coverage-rust-${GITHUB_RUN_ID:-local}"

    [[ -n "${version}" ]] || version="latest"
    [[ -n "${version}" && "${version}" != "latest" && "${version}" != v* ]] && version="v${version}"
    [[ -n "${out}" ]] || out="lcov.info"

    [[ -n "${token}" ]] || token="${CODECOV_TOKEN:-}"
    [[ -n "${token}" ]] || die "codecov: CODECOV_TOKEN is missing."

    [[ -f "${out}" ]] || die "codecov: file not found: ${out}"

    local os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    local arch="$(uname -m)" dist="linux"

    if [[ "${os}" == "darwin" ]]; then dist="macos"; fi
    if [[ "${dist}" == "linux" && ( "${arch}" == "aarch64" || "${arch}" == "arm64" ) ]]; then dist="linux-arm64"; fi

    local cache_dir="${TMPDIR:-/tmp}/.codecov/cache" resolved="${version}"
    local bin="${cache_dir}/codecov-${dist}-${resolved}"

    mkdir -p -- "${cache_dir}"

    if [[ "${version}" == "latest" ]]; then

        local latest_page="$(curl -fsSL "https://cli.codecov.io/${dist}/latest" 2>/dev/null || true)"
        local v="$(printf '%s\n' "${latest_page}" | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"

        [[ -n "${v}" ]] && resolved="${v}"
        bin="${cache_dir}/codecov-${dist}-${resolved}"

    fi
    if [[ ! -x "${bin}" ]]; then

        local url_a="https://cli.codecov.io/${dist}/${resolved}/codecov"
        local url_b="https://cli.codecov.io/${resolved}/${dist}/codecov"
        local sha_a="https://cli.codecov.io/${dist}/${resolved}/codecov.SHA256SUM"
        local sha_b="https://cli.codecov.io/${resolved}/${dist}/codecov.SHA256SUM"
        local sig_a="https://cli.codecov.io/${dist}/${resolved}/codecov.SHA256SUM.sig"
        local sig_b="https://cli.codecov.io/${resolved}/${dist}/codecov.SHA256SUM.sig"

        local tmp_dir="$(mktemp -d "${cache_dir}/codecov.tmp.XXXXXX" 2>/dev/null || true)"

        if [[ -z "${tmp_dir}" || ! -d "${tmp_dir}" ]]; then
            tmp_dir="${cache_dir}/codecov.tmp.$$"
            mkdir -p -- "${tmp_dir}" || die "Codecov: failed to create temp dir."
        fi

        local tmp_bin="${tmp_dir}/codecov"
        local tmp_sha="${tmp_dir}/codecov.SHA256SUM"
        local tmp_sig="${tmp_dir}/codecov.SHA256SUM.sig"

        trap 'rm -rf -- "${tmp_dir:-}" 2>/dev/null || true; trap - RETURN' RETURN
        rm -f -- "${tmp_bin}" "${tmp_sha}" "${tmp_sig}" 2>/dev/null || true

        run curl -fsSL -o "${tmp_bin}" "${url_a}" || run curl -fsSL -o "${tmp_bin}" "${url_b}"
        run curl -fsSL -o "${tmp_sha}" "${sha_a}" || run curl -fsSL -o "${tmp_sha}" "${sha_b}"

        curl -fsSL -o "${tmp_sig}" "${sig_a}" 2>/dev/null || curl -fsSL -o "${tmp_sig}" "${sig_b}" 2>/dev/null || rm -f -- "${tmp_sig}" 2>/dev/null || true

        if [[ -f "${tmp_sig}" ]] && has gpg; then

            local keyring="${tmp_dir}/trustedkeys.gpg"
            local keyfile="${tmp_dir}/codecov.pgp.asc"
            local want_fp="27034E7FDB850E0BBC2C62FF806BB28AED779869"

            run curl -fsSL -o "${keyfile}" "https://keybase.io/codecovsecurity/pgp_keys.asc"
            gpg --no-default-keyring --keyring "${keyring}" --import "${keyfile}" >/dev/null 2>&1 || true

            local got_fp="$(gpg --no-default-keyring --keyring "${keyring}" --fingerprint --with-colons 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}' || true)"

            [[ -n "${got_fp}" ]] || die "Codecov: cannot read PGP fingerprint."
            [[ "${got_fp}" == "${want_fp}" ]] || die "Codecov: PGP fingerprint mismatch."

            gpg --no-default-keyring --keyring "${keyring}" --verify "${tmp_sig}" "${tmp_sha}" >/dev/null 2>&1 || die "Codecov: SHA256SUM signature verification failed."

        fi

        local got="" want="$(awk '$2 ~ /(^|\/)codecov$/ { print $1; exit }' "${tmp_sha}" 2>/dev/null || true)"
        [[ -n "${want}" ]] || die "Codecov: invalid SHA256SUM file."

        if has sha256sum; then got="$(sha256sum "${tmp_bin}" 2>/dev/null | awk '{print $1}' || true)"
        elif has shasum; then got="$(shasum -a 256 "${tmp_bin}" 2>/dev/null | awk '{print $1}' || true)"
        elif has openssl; then got="$(openssl dgst -sha256 "${tmp_bin}" 2>/dev/null | awk '{print $NF}' || true)"
        else die "Codecov: no SHA256 tool found (need sha256sum or shasum or openssl)."
        fi

        [[ -n "${got}" ]] || die "Codecov: failed to compute checksum."
        [[ "${got}" == "${want}" ]] || die "Codecov: checksum mismatch."

        run chmod +x "${tmp_bin}"
        run mv -f -- "${tmp_bin}" "${bin}"
        run "${bin}" --version >/dev/null 2>&1

    fi

    export CODECOV_TOKEN="${token}"
    local -a args=( --verbose upload-process --disable-search --fail-on-error -f "${out}" )

    [[ -n "${flags}" ]] && args+=( -F "${flags}" )
    [[ -n "${name}"  ]] && args+=( -n "${name}" )

    run "${bin}" "${args[@]}"
    success "Ok: Codecov file uploaded."

}
cmd_coverage () {

    ensure cargo cargo-llvm-cov
    source <(parse "$@" -- name version flags token out mode=lcov upload:bool)

    local -a args=( --exclude bloats --exclude fuzz --"${mode}" )

    out="${out:-"${OUT_DIR:-out}/lcov.info"}"
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"
    [[ -f "${out}" ]] || : > "${out}"

    run cargo llvm-cov clean --workspace
    run cargo llvm-cov --workspace --all-targets --all-features "${args[@]}" --output-path "${out}" --remap-path-prefix "${kwargs[@]}"

    success "Ok: coverage processed -> ${out}"
    (( upload )) && cov_upload_out "${mode}" "${name}" "${version}" "${token}" "${flags}" "${out}"

}

cmd_bloat () {

    source <(parse "$@" -- package:list out="profiles/bloat.info" max_size=10MB all:bool release:bool=true)

    local -a pkgs=()

    if [[ ${#package[@]} -gt 0 ]]; then pkgs=( "${package[@]}" ); ensure_workspace_pkg "${pkgs[@]}"
    elif (( all )); then mapfile -t pkgs < <(workspace_pkgs)
    else mapfile -t pkgs < <(publishable_pkgs)
    fi

    [[ ${#pkgs[@]} -gt 0 ]] || die "bloat: no packages selected" 2
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"
    : > "${out}"

    printf '\n%s\n' "---------------------------------------" >> "${out}"
    printf '%s' "- Bloats Report: " >> "${out}"

    [[ -n "${max_size}" ]] && printf '%s' " Max-Size ( ${max_size} )" >> "${out}"

    printf '\n%s\n' "- Version: $(cmd_version)" >> "${out}"
    printf '%s\n\n' "---------------------------------------" >> "${out}"

    local meta="$(run_cargo metadata --no-deps --format-version 1 2>/dev/null)" || die "bloat: failed to get metadata" 2
    local target_dir="$(jq -r '.target_directory' <<<"${meta}" 2>/dev/null || true)"
    [[ -n "${target_dir}" ]] || die "bloat: failed to read target_directory" 2

    local mod="debug" flag="--dev"
    (( release )) && { mod="release"; flag="--release"; }

    local exe="" pkg="" out_text="" i=1
    [[ "$(os_name)" == "windows" ]] && exe=".exe"

    for pkg in "${pkgs[@]}"; do

        printf '%s\n' "Analysing : ${pkg} ..."

        printf '%d) %s:\n\n' "${i}" "${pkg}" >> "${out}"
        (( i++ ))

        local -a bins=()
        mapfile -t bins < <(jq -r --arg n "${pkg}" '.packages[] | select(.name == $n) | .targets[] | select(.kind | index("bin")) | .name' <<<"${meta}")

        if (( ${#bins[@]} > 0 )); then

            local x="" bin_name="${bins[0]}"
            for x in "${bins[@]}"; do [[ "${x}" == "${pkg}" ]] && { bin_name="${x}"; break; }; done

            local bin_path="${target_dir}/${mod}/${bin_name}${exe}"

            if out_text="$(NO_COLOR=1 CARGO_TERM_COLOR=never run_cargo bloat -p "${pkg}" --bin "${bin_name}" "${flag}" "${kwargs[@]}" 2>&1)"; then

                awk '{ sub(/\r$/, "") } !on && /^[[:space:]]*File[[:space:]]/ { on=1 } on { print }' <<<"${out_text}" >> "${out}"
                printf '\n' >> "${out}"

                [[ -n "${max_size}" ]] && check_max_size "${bin_path}" "${max_size}" || true

            else

                printf 'ERROR: %s\n\n' "can't resolve ${bin_path}" >> "${out}"

            fi

        else

            local bin_name="bloat-${pkg}"

            if out_text="$(NO_COLOR=1 CARGO_TERM_COLOR=never run_cargo bloat -p bloats --bin "${bin_name}" --features "bloat-${pkg}" "${flag}" "${kwargs[@]}" 2>&1)"; then

                local bin_path="${target_dir}/${mod}/${bin_name}${exe}"

                awk '{ sub(/\r$/, "") } !on && /^[[:space:]]*File[[:space:]]/ { on=1 } on { print }' <<<"${out_text}" >> "${out}"
                printf '\n' >> "${out}"

                [[ -n "${max_size}" ]] && check_max_size "${bin_path}" "${max_size}" || true

            elif out_text="$(NO_COLOR=1 CARGO_TERM_COLOR=never run_cargo bloat -p bloats --bin "${pkg}" --features "bloat-${pkg}" "${flag}" "${kwargs[@]}" 2>&1)"; then

                bin_name="${pkg}"
                local bin_path="${target_dir}/${mod}/${bin_name}${exe}"

                awk '{ sub(/\r$/, "") } !on && /^[[:space:]]*File[[:space:]]/ { on=1 } on { print }' <<<"${out_text}" >> "${out}"
                printf '\n' >> "${out}"

                [[ -n "${max_size}" ]] && check_max_size "${bin_path}" "${max_size}" || true

            else

                printf 'ERROR: cargo bloat failed for %s (via bloats)\n%s\n\n' "${pkg}" "${out_text}" >> "${out}"

            fi


        fi

    done

    success "Analysed: out file -> ${out}"

}
cmd_udeps () {

    run_cargo udeps --nightly --all-targets "$@"

}
cmd_hack () {

    source <(parse "$@" -- depth:int=2 each_feature:bool)

    if (( each_feature )); then
        run_cargo hack check --keep-going --each-feature "${kwargs[@]}"
        return 0
    fi

    run_cargo hack check --keep-going --feature-powerset --depth "${depth}" "${kwargs[@]}"

}

cmd_fuzz () {

    source <(parse "$@" -- timeout:int=10 len:int=4096 have_max_total_time:bool have_max_len:bool in_post:bool)

    local -a pre=() post=()

    while [[ $# -gt 0 ]]; do

        if [[ "$1" == "--" ]]; then
            in_post=1
            shift || true
            continue
        fi
        if (( in_post )); then
            case "$1" in
                -max_total_time|-max_total_time=*) have_max_total_time=1 ;;
                -max_len|-max_len=*) have_max_len=1 ;;
            esac
            post+=( "$1" )
            shift || true
            continue
        fi
        case "$1" in
            --timeout) shift || true; [[ $# -gt 0 ]] || die "Missing value for --timeout" 2; timeout="$1"; shift || true ;;
            --timeout=*) timeout="${1#*=}"; shift || true ;;
            --len) shift || true; [[ $# -gt 0 ]] || die "Missing value for --len" 2; len="$1"; shift || true ;;
            --len=*) len="${1#*=}"; shift || true ;;
            -max_total_time|-max_total_time=*) have_max_total_time=1; post+=( "$1" ); shift || true ;;
            -max_len|-max_len=*) have_max_len=1; post+=( "$1" ); shift || true ;;
            *) pre+=( "$1" ); shift || true ;;
        esac

    done

    if [[ -z "${CARGO_BUILD_TARGET:-}" ]] || [[ "${CARGO_BUILD_TARGET:-}" == *-musl ]]; then

        pre+=( "--target" "x86_64-unknown-linux-gnu" )

    fi
    if [[ "${#pre[@]}" -eq 0 ]] || [[ "${pre[0]-}" == -* ]]; then

        (( have_max_total_time )) || [[ "${timeout}" == "0" ]] || post+=( "-max_total_time=${timeout}" )
        (( have_max_len )) || [[ "${len}" == "0" ]] || post+=( "-max_len=${len}" )

        local -a targets=()
        local t=""

        while IFS= read -r line; do
            [[ -n "${line}" ]] || continue
            targets+=( "${line}" )
        done < <(run_cargo fuzz --nightly list 2>/dev/null || true)

        [[ "${#targets[@]}" -gt 0 ]] || die "No fuzz targets found. Run: cargo fuzz init && cargo fuzz add <name>" 2

        for t in "${targets[@]}"; do

            if [[ "${#post[@]}" -gt 0 ]]; then run_cargo fuzz --nightly run "${t}" "${pre[@]}" -- "${post[@]}" || die "Fuzzing failed: ${t}" 2
            else run_cargo fuzz --nightly run "${t}" "${pre[@]}" || die "Fuzzing failed: ${t}" 2
            fi

        done

        return 0

    fi
    if [[ "${#pre[@]}" -gt 0 ]]; then

        case "${pre[0]}" in
            run|list|init|add|clean|cmin|tmin|coverage|fmt) ;;
            *) pre=( "run" "${pre[@]}" ) ;;
        esac

    fi
    if [[ "${pre[0]}" == "run" ]]; then

        (( have_max_total_time )) || [[ "${timeout}" == "0" ]] || post+=( "-max_total_time=${timeout}" )
        (( have_max_len )) || [[ "${len}" == "0" ]] || post+=( "-max_len=${len}" )

    fi
    if [[ "${#post[@]}" -gt 0 ]]; then

        run_cargo fuzz --nightly "${pre[@]}" -- "${post[@]}"
        return $?

    fi

    run_cargo fuzz --nightly "${pre[@]}"

}
cmd_miri () {

    source <(parse "$@" -- command=test :target=auto clean:bool setup:bool=1)

    local target="${target}" tc="$(nightly_version)"
    local target_dir="target/miri"

    if [[ -z "${target}" || "${target}" == "auto" ]]; then

        local vv="$(rustc +"${tc}" -vV 2>/dev/null)" || die "miri: failed to read rustc -vV for ${tc}" 2
        target="$(awk '/^host: / { print $2; exit }' <<< "${vv}")"
        [[ -n "${target}" ]] || die "miri: failed to detect host target." 2

    fi

    (( clean )) && { CARGO_TARGET_DIR="${target_dir}" run_cargo clean --nightly --target "${target}" >/dev/null 2>&1 || true; }
    (( setup )) && { CARGO_TARGET_DIR="${target_dir}" run_cargo miri --nightly setup >/dev/null 2>&1 || true; }

    CARGO_TARGET_DIR="${target_dir}" CARGO_INCREMENTAL=0 run_cargo miri --nightly "${command}" --target "${target}" "${kwargs[@]}"

}
cmd_sanitizer () {

    source <(parse "$@" -- :sanitizer=asan command=test :target=auto clean:bool=0 track_origins:bool=1)

    local target="${target}" san="${sanitizer}" zsan="" opt="" tc="$(nightly_version)"
    local -a extra=()

    case "${san}" in
        asan|address)      san="asan"  ; zsan="address" ;;
        tsan|thread)       san="tsan"  ; zsan="thread" ;;
        lsan|leak)         san="lsan"  ; zsan="leak" ;;
        msan|memory)
            san="msan"
            zsan="memory"
            (( track_origins )) && extra+=( "-Zsanitizer-memory-track-origins" )
        ;;
        *) die "sanitizer: unknown sanitizer '${sanitizer}' (use: asan|tsan|msan|lsan)" 2 ;;
    esac

    if [[ -z "${target}" || "${target}" == "auto" ]]; then

        local vv="$(rustc +"${tc}" -vV 2>/dev/null)" || die "sanitizer: failed to read rustc -vV for ${tc}" 2
        target="$(awk '/^host: / { print $2; exit }' <<< "${vv}")"
        [[ -n "${target}" ]] || die "sanitizer: failed to detect host target." 2

    fi

    local target_dir="target/sanitizers/${san}"
    local rf="${RUSTFLAGS:-}"
    local rdf="${RUSTDOCFLAGS:-}"

    [[ -n "${rf}" ]] && rf+=" "
    [[ -n "${rdf}" ]] && rdf+=" "

    rf+="-Zsanitizer=${zsan} -Cforce-frame-pointers=yes -Cdebuginfo=1"
    rdf+="-Zsanitizer=${zsan} -Cforce-frame-pointers=yes -Cdebuginfo=1"

    for opt in "${extra[@]}"; do
        rf+=" ${opt}"
        rdf+=" ${opt}"
    done

    (( clean )) && { CARGO_TARGET_DIR="${target_dir}" run_cargo clean --nightly --target "${target}" >/dev/null 2>&1 || true; }
    log "=> sanitizer: ${san} (-Zsanitizer=${zsan}) target=${target} command=${command} \n"

    CARGO_TARGET_DIR="${target_dir}" \
        CARGO_INCREMENTAL=0 \
        RUSTFLAGS="${rf}" \
        RUSTDOCFLAGS="${rdf}" \
        run_cargo "${command}" --nightly -Zbuild-std=std --target "${target}" "${kwargs[@]}"

}

cmd_samply () {

    ensure samply
    set_perf_paranoid

    source <(parse "$@" -- \
        bin test bench example toolchain out="profiles/samply.json" nightly:bool stable:bool msrv:bool save_only:bool \
        rate address duration package:list \
    )

    [[ -z "${bin}"  || -z "${example}" ]] || die "samply: use only one of --bin or --example" 2
    [[ -z "${bench}" || -z "${test}"   ]] || die "samply: use only one of --bench or --test" 2
    [[ -z "${bench}${example}"         ]] || die "samply: use only one of --bench or --example" 2

    local -a args=( samply record )
    local -a cargo=( cargo )
    local -a pkgs=()
    local -A seen=()
    local p=""

    (( stable  )) && toolchain="stable"
    (( nightly )) && toolchain="nightly"
    (( msrv    )) && toolchain="msrv"

    if [[ "${toolchain}" == "stable" ]]; then cargo+=( +"$(stable_version)" )
    elif [[ "${toolchain}" == "nightly" ]]; then cargo+=( +"$(nightly_version)" )
    elif [[ "${toolchain}" == "msrv" ]]; then cargo+=( +"$(msrv_version)" )
    elif [[ -n "${toolchain}" ]]; then cargo+=( +"${toolchain}" )
    fi

    if [[ -n "${bench}" ]]; then cargo+=( bench --bench "${bench}" )
    elif [[ -n "${example}" ]]; then cargo+=( run --example "${example}" )
    elif [[ -n "${test}" ]]; then cargo+=( test --test "${test}" )
    else cargo+=( run ); [[ -n "${bin}" ]] && cargo+=( --bin "${bin}" )
    fi

    for p in "${package[@]-}"; do

        [[ -n "${p}" ]] || continue
        [[ -n "${seen[${p}]-}" ]] && continue

        seen["${p}"]=1
        pkgs+=( -p "${p}" )

    done

    (( ${#seen[@]} <= 1 )) || die "samply: --package supports at most one package" 2

    (( save_only )) && args+=( --save-only )

    [[ -n "${rate}"  ]] && args+=( --rate "${rate}" )
    [[ -n "${address}"  ]] && args+=( --address "${address}" )
    [[ -n "${duration}"  ]] && args+=( --duration "${duration}" )

    [[ -n "${out}"  ]] && args+=( -o "${out}" )
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"
    : > "${out}"

    CARGO_PROFILE_RELEASE_DEBUG=true \
        RUSTFLAGS="${RUSTFLAGS:-} -C force-frame-pointers=yes -g" \
        run "${args[@]}" -- "${cargo[@]}" "${pkgs[@]}" "${kwargs[@]}"

}
cmd_samply_load () {

    ensure samply
    source <(parse "$@" -- :file="profiles/samply.json")

    [[ -f "${file}" ]] || die "file not found: ${file}" 2
    run samply load "${file}"

}

cmd_flame () {

    ensure flamegraph
    set_perf_flame

    source <(parse "$@" -- \
        bin test bench example toolchain out="profiles/flamegraph.svg" nightly:bool stable:bool msrv:bool package:list \
    )

    [[ -z "${bin}"  || -z "${example}" ]] || die "flame: use only one of --bin or --example" 2
    [[ -z "${bench}" || -z "${test}"   ]] || die "flame: use only one of --bench or --test" 2
    [[ -z "${bench}${example}"         ]] || die "flame: use only one of --bench or --example" 2

    local -a cargo=( cargo )
    local -a args=( flamegraph )
    local -a pkgs=()
    local -A seen=()
    local p=""

    (( stable  )) && toolchain="stable"
    (( nightly )) && toolchain="nightly"
    (( msrv    )) && toolchain="msrv"

    if [[ "${toolchain}" == "stable" ]]; then cargo+=( +"$(stable_version)" )
    elif [[ "${toolchain}" == "nightly" ]]; then cargo+=( +"$(nightly_version)" )
    elif [[ "${toolchain}" == "msrv" ]]; then cargo+=( +"$(msrv_version)" )
    elif [[ -n "${toolchain}" ]]; then cargo+=( +"${toolchain}" )
    fi

    if [[ -n "${bench}" ]]; then args+=( --bench "${bench}" )
    elif [[ -n "${example}" ]]; then args+=( --example "${example}" )
    elif [[ -n "${test}" ]]; then args+=( --test "${test}" )
    else [[ -n "${bin}" ]] && args+=( --bin "${bin}" )
    fi

    for p in "${package[@]-}"; do

        [[ -n "${p}" ]] || continue
        [[ -n "${seen[${p}]-}" ]] && continue

        seen["${p}"]=1
        pkgs+=( -p "${p}" )

    done

    (( ${#seen[@]} <= 1 )) || die "flame: --package supports at most one package" 2

    [[ -n "${out}"  ]] && args+=( -o "${out}" )
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"
    : > "${out}"

    CARGO_PROFILE_RELEASE_DEBUG=true \
        RUSTFLAGS="${RUSTFLAGS:-} -C force-frame-pointers=yes -g" \
        run "${cargo[@]}" "${args[@]}" "${pkgs[@]}" "${kwargs[@]}"

}
cmd_flame_open () {

    ensure flamegraph
    source <(parse "$@" -- :file="profiles/flamegraph.svg")

    [[ -f "${file}" ]] || die "file not found: ${file}" 2
    open_path "${file}"

}

cmd_safety_help () {

    info_ln "Safety :\n"

    printf '    %s\n' \
        "audit-check                * Security advisories gate (cargo deny advisories/bans/licenses/sources)" \
        "audit-fix                  * Auto-fix advisories by upgrading dependencies (cargo audit fix)" \
        "" \
        "fmt-check                  * Verify formatting --nightly (no changes)" \
        "fmt-fix                    * Auto-format code --nightly" \
        "fmt-stable-check           * Verify formatting checks (no changes)" \
        "fmt-stable-fix             * Auto-format code" \
        "" \
        "lint-check                 * Clippy check lint for publishable crates only (workspace gate)" \
        "lint-fix                   * Clippy fix lint / update depds with cargo update for publishable crates only (workspace gate)" \
        "lint-strict-check          * Clippy check lint for full workspace (including non-publishable crates)" \
        "lint-strict-fix            * Clippy fix lint or update depds with cargo update (including non-publishable crates)" \
        ''

}

cmd_audit_check () {

    if [[ -f deny.toml ]] || [[ -f .deny.toml ]]; then run_cargo deny check advisories bans licenses sources "$@"
    else run_cargo audit "$@"
    fi

}
cmd_audit_fix () {

    # run_cargo audit fix "$@"
    run_cargo update "$@"

}

cmd_fmt_check () {

    run_cargo fmt --nightly --all -- --check "$@"

}
cmd_fmt_fix () {

    run_cargo fmt --nightly --all "$@"

}

cmd_fmt_stable_check () {

    run_cargo fmt --all -- --check "$@"

}
cmd_fmt_stable_fix () {

    run_cargo fmt --all "$@"

}

cmd_lint_check () {

    run_workspace_publishable clippy --workspace --all-targets --all-features "$@"

}
cmd_lint_fix () {

    run_workspace_publishable clippy --fix --allow-dirty --allow-staged --workspace --all-targets --all-features "$@"

}

cmd_lint_strict_check () {

    run_workspace clippy --workspace --all-targets --all-features "$@"

}
cmd_lint_strict_fix () {

    run_workspace clippy --fix --allow-dirty --allow-staged --workspace --all-targets --all-features "$@"

}


# project tree

.
├── LICENSE
├── README.md
├── SECURITY.md
├── assets
│   ├── cmd.wav
│   └── say.wav
├── core
│   ├── arch.sh
│   ├── bash.sh
│   ├── env.sh
│   ├── fsys.sh
│   ├── parse.sh
│   ├── pkg.sh
│   └── tool.sh
├── ensure
│   ├── arch.sh
│   ├── node.sh
│   ├── python.sh
│   ├── rust.sh
│   └── work.sh
├── entry
│   ├── arch.sh
│   ├── installer.sh
│   ├── loader.sh
│   └── run.sh
├── install.sh
├── logs.sh
├── module
│   ├── forge
│   │   ├── base.sh
│   │   └── index.sh
│   ├── fs
│   │   ├── base.sh
│   │   └── index.sh
│   ├── git
│   │   ├── base.sh
│   │   └── index.sh
│   ├── github
│   │   ├── base.sh
│   │   └── index.sh
│   ├── notify
│   │   ├── base.sh
│   │   └── index.sh
│   ├── ops
│   │   ├── cinema.sh
│   │   └── user.sh
│   ├── public
│   │   ├── pretty.sh
│   │   └── safety.sh
│   └── stack
│       └── rust
│           ├── base.sh
│           ├── cmd.sh
│           ├── doctor.sh
│           ├── gates.sh
│           ├── meta.sh
│           ├── perf.sh
│           ├── safety.sh
│           └── vet.sh
└── template
    ├── conf
    │   ├── audit
    │   │   └── rust
    │   │       └── .deny.toml
    │   ├── coverage
    │   │   └── .codecov.yml
    │   ├── docker
    │   ├── docs
    │   │   ├── CODE_OF_CONDUCT.md
    │   │   ├── CONTRIBUTING.md
    │   │   ├── README.md
    │   │   ├── SECURITY.md
    │   │   └── SUPPORT.md
    │   ├── env
    │   │   ├── .editorconfig
    │   │   ├── .env
    │   │   ├── .gitattributes
    │   │   ├── .gitignore
    │   │   └── .secrets
    │   ├── format
    │   │   └── rust
    │   │       └── .rustfmt.toml
    │   ├── github
    │   │   ├── .github
    │   │   │   ├── CODEOWNERS
    │   │   │   ├── FUNDING.yml
    │   │   │   ├── ISSUE_TEMPLATE
    │   │   │   │   ├── bug_report.md
    │   │   │   │   ├── config.yml
    │   │   │   │   └── feature_request.md
    │   │   │   ├── PULL_REQUEST_TEMPLATE.md
    │   │   │   ├── dependabot.yml
    │   │   │   ├── labeler.yml
    │   │   │   ├── labels.yml
    │   │   │   └── workflows
    │   │   │       ├── _base.yml
    │   │   │       ├── ci.yml
    │   │   │       ├── daily.yml
    │   │   │       ├── labeler.yml
    │   │   │       ├── labels.yml
    │   │   │       └── notify.yml
    │   │   └── rust
    │   │       └── .github
    │   │           ├── labeler.yml
    │   │           └── workflows
    │   │               ├── fuzz.yml
    │   │               ├── miri.yml
    │   │               └── sanitize.yml
    │   ├── license
    │   │   ├── LICENSE-APACHE
    │   │   └── LICENSE-MIT
    │   ├── lint
    │   │   └── rust
    │   │       └── .clippy.toml
    │   ├── pretty
    │   │   ├── .prettierrc.yml
    │   │   ├── .taplo.toml
    │   │   └── .typos.toml
    │   └── safety
    │       ├── .gitleaks.toml
    │       ├── .syft.yml
    │       └── .trivy.yml
    ├── lib
    │   └── rust
    │       ├── Cargo.toml
    │       ├── benches
    │       │   └── hello.rs
    │       ├── bloats
    │       │   ├── Cargo.toml
    │       │   └── demo.rs
    │       ├── examples
    │       │   └── hello.rs
    │       ├── fuzz
    │       │   ├── Cargo.toml
    │       │   └── fuzz_targets
    │       │       └── demo.rs
    │       ├── src
    │       │   ├── lib.rs
    │       │   └── main.rs
    │       ├── supply-chain
    │       │   ├── audits.toml
    │       │   ├── config.toml
    │       │   └── imports.lock
    │       └── tests
    │           └── hello.rs
    ├── pure
    │   └── rust
    │       ├── Cargo.toml
    │       └── src
    │           └── main.rs
    ├── web
    │   ├── actix
    │   ├── fastapi
    │   ├── fiber
    │   └── laravel
    └── ws
        └── rust
            ├── Cargo.toml
            ├── benches
            │   ├── Cargo.toml
            │   └── demo.rs
            ├── bloats
            │   ├── Cargo.toml
            │   └── demo.rs
            ├── crates
            │   └── demo
            │       ├── Cargo.toml
            │       └── src
            │           ├── lib.rs
            │           └── main.rs
            ├── examples
            │   ├── Cargo.toml
            │   └── demo.rs
            ├── fuzz
            │   ├── Cargo.toml
            │   └── fuzz_targets
            │       └── demo.rs
            ├── supply-chain
            │   ├── audits.toml
            │   ├── config.toml
            │   └── imports.lock
            └── tests
                ├── Cargo.toml
                └── demo.rs

67 directories, 118 files

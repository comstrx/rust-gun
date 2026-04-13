
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
    ensure_tool jq tail sort

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
        [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid RUST_MSRV (need x.y.z): ${RUST_MSRV}"
        printf '%s\n' "${tc}"
        return 0
    fi

    tc="$(tool_workspace_msrv 2>/dev/null || true)"

    if [[ -n "${tc}" ]]; then
        tc="$(tool_normalize_version "${tc}")"
        [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid workspace rust_version: ${tc}"
        printf '%s\n' "${tc}"
        return 0
    fi

    tool_stable_version

}
tool_resolve_chain () {

    local tc="${1-}"
    [[ -n "${tc}" ]] || die "tool_resolve_chain: empty toolchain"

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
    run rustup run "${tc}" rustc -V >/dev/null 2>&1 || die "rustc not working after install: ${tc}"

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

    ensure_tool curl
    local stable="${1:-stable}"

    run bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "'"${stable}"'"' \
        || die "Failed to install rustup."

}
tool_install_rustup_windows () {

    ensure_tool curl

    local stable="${1:-stable}"
    local url="$(tool_rustup_windows_url)"
    local tmp="${TMPDIR:-${TEMP:-/tmp}}/rustup-init.$$.exe"

    run curl -fsSL -o "${tmp}" "${url}" || die "Failed to download rustup-init.exe"
    run "${tmp}" -y --profile minimal --default-toolchain "${stable}" || die "Failed to install rustup (Windows)."

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
            *) die "Unsupported target for rustup install: ${target}" ;;
        esac

        tool_source_cargo_env
        has rustup || die "rustup installed but not found in PATH."

    fi

    tool_setup_chain "${stable}"
    tool_setup_chain "${nightly}"
    tool_setup_chain "${msrv}"

    rustup run "${stable}" cargo -V >/dev/null 2>&1 || die "cargo (stable) not working after install."
    rustup run "${nightly}" rustc -V >/dev/null 2>&1 || die "rustc (nightly) not working after install."
    rustup run "${msrv}" rustc -V >/dev/null 2>&1 || die "rustc (msrv) not working after install."

    tool_source_cargo_env
    tool_hash_clear

}
ensure_component () {

    local comp="${1-}" tc="${2:-stable}"
    [[ -n "${comp}" ]] || die "ensure_component: requires a component name"

    has rustup || ensure_rust

    tc="$(tool_resolve_chain "${tc}")"
    tool_setup_chain "${tc}"

    if [[ "${comp}" == "llvm-tools-preview" ]]; then
        rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE '^(llvm-tools|llvm-tools-preview)\b' && return 0
        run rustup component add --toolchain "${tc}" llvm-tools-preview 2>/dev/null || run rustup component add --toolchain "${tc}" llvm-tools
        rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE '^(llvm-tools|llvm-tools-preview)\b' || die "Failed to install llvm-tools on '${tc}'."
        return 0
    fi

    rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE "^${comp}\b" && return 0
    run rustup component add --toolchain "${tc}" "${comp}"

    rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE "^${comp}\b" || die "Failed to install component '${comp}' on '${tc}'."

}
ensure_edit_crate () {

    has cargo || ensure_rust
    tool_source_cargo_env

    has cargo-add && has cargo-rm && has cargo-upgrade && has cargo-set-version && return 0

    if has cargo-binstall; then
        local -a extra=()
        is_ci && extra+=( --no-confirm --force )
        run cargo binstall cargo-edit "${extra[@]}" || true
    fi
    if ! { has cargo-add && has cargo-rm && has cargo-upgrade && has cargo-set-version; }; then
        run cargo install --locked cargo-edit || die "Failed to install cargo-edit"
    fi

    tool_source_cargo_env
    tool_hash_clear

    has cargo-add         || die "cargo-edit installed but cargo-add not found"
    has cargo-rm          || die "cargo-edit installed but cargo-rm not found"
    has cargo-upgrade     || die "cargo-edit installed but cargo-upgrade not found"
    has cargo-set-version || die "cargo-edit installed but cargo-set-version not found"

}
ensure_crate () {

    local crate="${1-}" bin="${2-}"
    shift 2 || true

    [[ -n "${crate}" ]] || die "ensure_crate: requires <crate>"
    [[ -n "${bin}" ]]   || die "ensure_crate: requires <bin>"

    case "${crate}:${bin}" in
        cargo-edit:*|cargo-upgrade:*|cargo-add:*|cargo-rm:*|cargo-set-version:*) ensure_edit_crate; return 0 ;;
        *:cargo-upgrade|*:cargo-add|*:cargo-rm|*:cargo-set-version) ensure_edit_crate; return 0 ;;
    esac

    has cargo || ensure_rust
    tool_source_cargo_env

    tool_crate_bin_ok "${bin}" && return 0

    if ! has cargo-binstall; then
        run cargo install --locked cargo-binstall || die "Failed to install cargo-binstall"
        tool_source_cargo_env
        has cargo-binstall || die "cargo-binstall installed but not found in PATH"
    fi
    if (( $# == 0 )); then
        local -a extra=()
        is_ci && extra+=( --no-confirm --force )
        run cargo binstall "${crate}" "${extra[@]}" || run cargo install --locked "${crate}"
    else
        run cargo install --locked "${crate}" "$@"
    fi

    tool_source_cargo_env
    tool_crate_bin_ok "${bin}" || die "crate '${crate}' installed but binary '${bin}' not found"

}

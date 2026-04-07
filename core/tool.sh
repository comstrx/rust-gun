
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "tool.sh: this file should not be run externally." >&2; exit 2; }
[[ -n "${TOOL_LOADED:-}" ]] && return 0
TOOL_LOADED=1

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/pkg.sh"

tool_docflags_deny () {

    local cur="${RUSTDOCFLAGS:-}"

    [[ "${cur}" == *"-Dwarnings"* ]] && { printf '%s' "${cur}"; return 0; }
    [[ -n "${cur}" ]] && { printf '%s -Dwarnings' "${cur}"; return 0; }

    printf '%s' "-Dwarnings"

}
tool_path_prepend () {

    local dir="${1-}"
    [[ -n "${dir}" && -d "${dir}" ]] || return 0

    case ":${PATH-}:" in
        *":${dir}:"*) ;;
        *)
            if [[ -n "${PATH-}" ]]; then PATH="${dir}:${PATH}"
            else PATH="${dir}"
            fi
        ;;
    esac

    export PATH

}
tool_to_unix_path () {

    local p="${1-}"
    [[ -n "${p}" ]] || { printf '%s' ""; return 0; }

    if has cygpath; then
        cygpath -u "${p}" 2>/dev/null || printf '%s' ""
        return 0
    fi

    printf '%s' "${p}"

}
tool_export_path_if_dir () {

    local dir="${1-}"
    [[ -n "${dir}" && -d "${dir}" ]] || return 0

    tool_path_prepend "${dir}"

    if [[ -n "${GITHUB_PATH:-}" ]]; then
        printf '%s\n' "${dir}" >> "${GITHUB_PATH}"
    fi

}
tool_export_cargo_bin () {

    local cargo_home="${CARGO_HOME:-${HOME}/.cargo}"
    tool_export_path_if_dir "${cargo_home}/bin"

}
tool_export_volta_bin () {

    local localapp=""
    local -a dirs=()

    dirs+=( "${VOLTA_HOME:-${HOME}/.volta}/bin" )

    if [[ -n "${LOCALAPPDATA:-}" ]]; then
        localapp="$(tool_to_unix_path "${LOCALAPPDATA}")"
        [[ -n "${localapp}" ]] && dirs+=( "${localapp}/Volta/bin" )
    fi

    dirs+=( "/c/Users/${USERNAME:-}/AppData/Local/Volta/bin" )
    dirs+=( "/c/Program Files/Volta/bin" )
    dirs+=( "/c/Program Files/Volta" )

    local dir=""
    for dir in "${dirs[@]}"; do
        tool_export_path_if_dir "${dir}"
    done

}
tool_pick_sort_locale () {

    local line=""

    if has locale; then
        while IFS= read -r line; do
            case "${line}" in
                C.UTF-8)     printf '%s\n' "C.UTF-8"; return 0 ;;
                en_US.UTF-8) printf '%s\n' "en_US.UTF-8"; return 0 ;;
            esac
        done < <(locale -a 2>/dev/null || true)
    fi

    printf '%s\n' "C"

}
tool_pick_sort_bin () {

    ensure_pkg sort 1>&2

    LC_ALL=C sort -V </dev/null >/dev/null 2>&1 && { printf '%s\n' "sort"; return 0; }

    die "tool: need GNU sort with -V support." 2

}
tool_sort_ver () {

    local loc="$(tool_pick_sort_locale)"
    local sbin="$(tool_pick_sort_bin)"

    LC_ALL="${loc}" "${sbin}" -V

}
tool_sort_uniq () {

    local loc="$(tool_pick_sort_locale)"
    local sbin="$(tool_pick_sort_bin)"

    LC_ALL="${loc}" "${sbin}" -u

}

tool_normalize_version () {

    local tc="${1-}"
    tc="${tc#v}"

    case "${tc}" in
        stable|beta|nightly) printf '%s\n' "${tc}"; return 0 ;;
        nightly-????-??-??)  printf '%s\n' "${tc}"; return 0 ;;
    esac

    [[ "${tc}" =~ ^[0-9]+\.[0-9]+$ ]] && tc="${tc}.0"
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid version: ${1}" 2

    printf '%s\n' "${tc}"

}
tool_active_version () {

    rustup show active-toolchain 2>/dev/null | awk '{print $1}' || true

}
tool_stable_version () {

    tool_normalize_version "${RUST_STABLE:-stable}"

}
tool_nightly_version () {

    tool_normalize_version "${RUST_NIGHTLY:-nightly}"

}
tool_msrv_version () {

    ensure_pkg jq awk sed tail sort 1>&2

    local tc="" want="" have=""

    if [[ -n "${RUST_MSRV:-}" ]]; then
        tc="$(tool_normalize_version "${RUST_MSRV}")"
        [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid RUST_MSRV (need x.y.z): ${RUST_MSRV}" 2
        printf '%s\n' "${tc}"
        return 0
    fi

    have="$(rustc -V 2>/dev/null | awk '{print $2}' | sed 's/[^0-9.].*$//')"
    [[ -n "${have}" ]] || die "rustc not available to detect current version" 2

    if has cargo; then
        want="$(
            cargo metadata --no-deps --format-version 1 2>/dev/null \
            | jq -r '.packages[].rust_version // empty' \
            | tool_sort_ver \
            | tail -n 1
        )"
    fi

    [[ -n "${want}" ]] || { printf '%s\n' "${have}"; return 0; }

    tc="$(tool_normalize_version "${want}")"
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid workspace rust_version (need x.y.z): ${want}" 2

    [[ "$(printf '%s\n%s\n' "${tc}" "${have}" | tool_sort_ver | awk 'NR==1{print;exit}')" == "${tc}" ]] \
        || die "Rust too old: need >= ${tc}, have ${have}" 2

    printf '%s\n' "${tc}"

}
tool_resolve_chain () {

    local tc="${1-}"
    [[ -n "${tc}" ]] || die "tool_resolve_chain: needs a toolchain" 2

    case "${tc}" in
        stable)  tc="$(tool_stable_version)" ;;
        nightly) tc="$(tool_nightly_version)" ;;
        msrv)    tc="$(tool_msrv_version)" ;;
    esac

    printf '%s\n' "${tc}"

}
tool_setup_chain () {

    local tc="$(tool_resolve_chain "${1:-}")"
    [[ -n "${tc}" ]] || die "tool_setup_chain: empty toolchain" 2

    rustup run "${tc}" rustc -V >/dev/null 2>&1 && return 0

    run rustup toolchain install "${tc}" --profile minimal
    run rustup run "${tc}" rustc -V >/dev/null 2>&1 || die "rustc not working after install: ${tc}" 2

}

tool_node_version_ok () {

    local want="${1:-25}"
    local v="" major=""

    has node || return 1
    has npx  || return 1

    v="$(node --version 2>/dev/null || true)"
    v="${v#v}"
    major="${v%%.*}"

    [[ "${major}" =~ ^[0-9]+$ ]] || return 1
    (( major >= want )) || return 1

    npx --version >/dev/null 2>&1 || return 1
    return 0

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

    local target="${1:-$(pkg_target)}"
    local backend=""

    backend="$(pkg_backend "${target}" 2>/dev/null || true)"
    [[ -n "${backend}" ]] || die "No usable backend to install Volta on target '${target}'." 2

    case "${backend}" in
        winget)
            run powershell.exe -NoProfile -Command \
                'winget install -e --id Volta.Volta --accept-source-agreements --accept-package-agreements --disable-interactivity' \
                || die "Failed to install Volta via winget." 2
        ;;
        choco) run choco install -y volta || die "Failed to install Volta via choco." 2 ;;
        scoop) run scoop install volta || die "Failed to install Volta via scoop." 2 ;;
        *) die "Unsupported backend '${backend}' for Volta install on '${target}'." 2 ;;
    esac

    tool_export_volta_bin
    has volta || die "Volta installed but not found in PATH." 2

}
tool_install_node_pacman () {

    local target="${1:-$(pkg_target)}"
    local prefix=""

    case "${target}" in
        msys)
            if (( YES )); then run pacman -S --needed --noconfirm nodejs
            else run pacman -S --needed nodejs
            fi
        ;;
        mingw)
            prefix="$(pkg_mingw_prefix)"
            if (( YES )); then run pacman -S --needed --noconfirm "${prefix}-nodejs"
            else run pacman -S --needed "${prefix}-nodejs"
            fi
        ;;
        gitbash)
            if (( YES )); then run pacman -S --needed --noconfirm nodejs
            else run pacman -S --needed nodejs
            fi
        ;;
        *)
            die "tool_install_node_pacman: unsupported target '${target}'" 2
        ;;
    esac

}

ensure_node () {

    local want="${1:-25}"
    local target=""
    local backend=""

    tool_export_volta_bin
    tool_node_version_ok "${want}" && return 0

    target="$(pkg_target)"
    backend="$(pkg_backend "${target}" 2>/dev/null || true)"

    case "${target}" in
        linux|mac)
            tool_install_volta_unix
            run volta install "node@${want}" || die "Failed to install Node via Volta." 2
        ;;
        msys|mingw|gitbash)
            case "${backend}" in
                winget|choco|scoop)
                    tool_install_volta_windows "${target}"
                    run volta install "node@${want}" || die "Failed to install Node via Volta." 2
                ;;
                pacman)
                    tool_install_node_pacman "${target}"
                ;;
                *)
                    die "No supported backend for Node on '${target}'." 2
                ;;
            esac
        ;;
        cygwin)
            case "${backend}" in
                winget|choco|scoop)
                    tool_install_volta_windows "${target}"
                    run volta install "node@${want}" || die "Failed to install Node via Volta." 2
                ;;
                *)
                    die "Node install on Cygwin requires winget/choco/scoop in this layer." 2
                ;;
            esac
        ;;
        *)
            die "Unsupported target for Node install: ${target}" 2
        ;;
    esac

    pkg_hash_clear
    tool_export_volta_bin
    tool_node_version_ok "${want}" || die "Node install did not satisfy requirement (need ${want}+)." 2

}
ensure_rust () {

    ensure_pkg curl 1>&2

    local stable="$(tool_stable_version)"
    local nightly="$(tool_nightly_version)"
    local msrv="$(tool_msrv_version)"
    local uname_s="$(uname -s 2>/dev/null || true)"

    tool_export_cargo_bin

    if ! has rustup; then
        case "${uname_s}" in
            MSYS*|MINGW*|CYGWIN*)
                local tmp="${TMPDIR:-${TEMP:-/tmp}}/rustup-init.$$.exe"

                run curl -fsSL -o "${tmp}" "https://win.rustup.rs/x86_64" || die "Failed to download rustup-init.exe" 2
                run "${tmp}" -y --profile minimal --default-toolchain "${stable}" || die "Failed to install rustup (Windows)" 2
                rm -f -- "${tmp}" 2>/dev/null || true
            ;;
            Darwin|Linux)
                run bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "'"${stable}"'"' \
                    || die "Failed to install rustup." 2
            ;;
            *)
                die "Unsupported OS for rustup install: ${uname_s}" 2
            ;;
        esac

        tool_export_cargo_bin
        [[ -f "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env" || true
        has rustup || die "rustup installed but not found in PATH." 2
    fi

    tool_setup_chain "${stable}"
    tool_setup_chain "${nightly}"
    tool_setup_chain "${msrv}"

    run rustup run "${stable}"  cargo -V >/dev/null 2>&1 || die "cargo (stable) not working after install." 2
    run rustup run "${nightly}" rustc -V >/dev/null 2>&1 || die "rustc (nightly) not working after install." 2
    run rustup run "${msrv}"    rustc -V >/dev/null 2>&1 || die "rustc (msrv) not working after install." 2

}
ensure_component () {

    local comp="${1-}"
    local tc="${2:-stable}"

    [[ -n "${comp}" ]] || die "ensure_component: requires a component name" 2

    has rustup || ensure_rust

    tc="$(tool_resolve_chain "${tc}")"
    tool_setup_chain "${tc}"

    if [[ "${comp}" == "llvm-tools-preview" ]]; then
        rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE '^(llvm-tools|llvm-tools-preview)\b' && return 0
        run rustup component add --toolchain "${tc}" llvm-tools-preview 2>/dev/null || run rustup component add --toolchain "${tc}" llvm-tools
        return 0
    fi

    rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE "^${comp}\b" && return 0
    run rustup component add --toolchain "${tc}" "${comp}"

}
ensure_crate () {

    local crate="${1-}"
    local bin="${2-}"
    shift 2 || true

    [[ -n "${crate}" ]] || die "ensure_crate requires <crate>" 2
    [[ -n "${bin}" ]]   || die "ensure_crate requires <bin>" 2

    has cargo || ensure_rust
    tool_export_cargo_bin

    if ! has cargo-binstall; then
        run cargo install cargo-binstall || die "Failed to install cargo-binstall" 2
        tool_export_cargo_bin
        has cargo-binstall || die "cargo-binstall installed but not found in PATH" 2
    fi

    { has "${bin}" || has "${bin#cargo-}"; } && return 0

    if (( $# == 0 )); then
        local -a extra=()
        is_ci && extra+=( --no-confirm --force )
        run cargo binstall "${crate}" "${extra[@]}"
        { has "${bin}" || has "${bin#cargo-}"; } && return 0
    fi

    run cargo install "${crate}" "$@"
    { has "${bin}" || has "${bin#cargo-}"; } || die "crate '${crate}' installed but binary '${bin}' not found" 2

}
ensure_cargo_edit () {

    has cargo || ensure_rust
    tool_export_cargo_bin

    if has cargo-add && has cargo-rm && has cargo-upgrade; then
        return 0
    fi
    if has cargo-binstall; then
        local -a extra=()
        is_ci && extra+=( --no-confirm --force )
        run cargo binstall cargo-edit "${extra[@]}" || true
    fi
    if ! { has cargo-add && has cargo-rm && has cargo-upgrade; }; then
        run cargo install cargo-edit || die "Failed to install cargo-edit" 2
    fi

    has cargo-add     || die "cargo-edit installed but cargo-add not found" 2
    has cargo-rm      || die "cargo-edit installed but cargo-rm not found" 2
    has cargo-upgrade || die "cargo-edit installed but cargo-upgrade not found" 2

}
ensure () {

    source <(parse "$@" -- :wants:list)

    local want=""
    for want in "${wants[@]}"; do
        case "${want}" in
            node|nodejs|npx|npm|pnpm|volta) tool_node_version_ok 25 || ensure_node ;;
            cargo|rust|rustc|rustup) has cargo || ensure_rust ;;
            rustfmt|rust-src) ensure_component "${want}" stable; ensure_component "${want}" nightly ;;
            miri) ensure_component "${want}" nightly ;;
            clippy|llvm-tools-preview) ensure_component "${want}" stable ;;
            taplo) ensure_crate taplo-cli taplo ;;
            cargo-audit) ensure_crate cargo-audit cargo-audit --features fix ;;
            cargo-edit|cargo-upgrade|cargo-add|cargo-rm|cargo-set-version) ensure_cargo_edit ;;
            samply|flamegraph|cargo-*) ensure_crate "${want}" "${want}" ;;
            *) has "${want}" || ensure_pkg "${want}" 1>&2 ;;
        esac
    done

}

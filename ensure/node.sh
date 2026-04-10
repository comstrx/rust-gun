
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

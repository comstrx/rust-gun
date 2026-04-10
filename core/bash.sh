
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

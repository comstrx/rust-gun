
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
    if bash_has sudo; then
        sudo "$@"
        return $?
    fi

    return 127

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
bash_version_from_bin () {

    local bash_bin="${1-}"
    [[ -n "${bash_bin}" && -x "${bash_bin}" ]] || { printf '0.0'; return 0; }

    local out="$("${bash_bin}" -c 'printf "%s.%s" "${BASH_VERSINFO[0]:-0}" "${BASH_VERSINFO[1]:-0}"' 2>/dev/null)" || true
    [[ -n "${out}" ]] || out="0.0"

    printf '%s' "$(bash_ver_norm "${out}")"

}
bash_current_version () {

    if [[ -n "${BASH_VERSINFO[0]:-}" ]]; then
        printf '%s.%s' "${BASH_VERSINFO[0]:-0}" "${BASH_VERSINFO[1]:-0}"
        return 0
    fi

    printf '0.0'

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
bash_find_best_candidate () {

    local req="${1-}"
    local best_bin="" best_ver="0.0" bin="" ver=""
    local -a candidates=()

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

        [[ -n "${bin}" ]] || continue
        [[ -x "${bin}" ]] || continue

        ver="$(bash_version_from_bin "${bin}")"

        if bash_ver_ge "${ver}" "${req}" && ! bash_ver_ge "${best_ver}" "${ver}"; then
            best_bin="${bin}"
            best_ver="${ver}"
        fi

    done

    if [[ -n "${best_bin}" ]]; then
        printf '%s\n' "${best_bin}"
        return 0
    fi

    return 1

}
bash_is_wsl () {

    [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
    [[ -r /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && return 0
    [[ -r /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null && return 0

    return 1

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

    bash_path_prepend "/opt/homebrew/bin"
    bash_path_prepend "/usr/local/bin"
    bash_path_prepend "/home/linuxbrew/.linuxbrew/bin"

    return 0

}
bash_try_pkg_choco_git () {

    bash_has choco || return 1
    choco upgrade git.install -y --no-progress || choco install git.install -y --no-progress
    return $?

}
bash_try_pkg_scoop_git () {

    bash_has scoop || return 1
    scoop install git || scoop update git
    return $?

}
bash_try_pkg_winget_git () {

    bash_has winget || return 1

    winget install --id Git.Git --exact --accept-package-agreements --accept-source-agreements --silent \
        || winget upgrade --id Git.Git --exact --accept-package-agreements --accept-source-agreements --silent

    return $?

}
bash_try_pkg_scoop_msys2 () {

    bash_has scoop || return 1
    scoop install msys2 || scoop update msys2 || return 1

    local msys_bash="${USERPROFILE:-}/scoop/apps/msys2/current/usr/bin/bash.exe"
    [[ -x "${msys_bash}" ]] || return 1

    "${msys_bash}" -lc 'pacman -Sy --noconfirm bash' || true
    return 0

}
bash_try_pkg_msys2_native () {

    bash_has pacman || return 1
    pacman -Sy --noconfirm bash
    return $?

}

bash_ensure_linux () {

    local req="${1-}"

    if bash_try_pkg_linux; then
        return 0
    fi
    if bash_try_pkg_brew; then
        return 0
    fi

    local found="$(bash_find_best_candidate "${req}")" || true
    [[ -n "${found}" ]]

}
bash_ensure_macos () {

    local req="${1-}"
    bash_try_pkg_brew || return 1

    local found="$(bash_find_best_candidate "${req}")" || true
    [[ -n "${found}" ]]

}
bash_ensure_windows () {

    local req="${1-}"

    if bash_is_wsl; then
        bash_ensure_linux "${req}"
        return $?
    fi

    if bash_try_pkg_msys2_native; then :
    elif bash_try_pkg_winget_git; then :
    elif bash_try_pkg_choco_git; then :
    elif bash_try_pkg_scoop_git; then :
    elif bash_try_pkg_scoop_msys2; then :
    else return 1
    fi

    local found="$(bash_find_best_candidate "${req}")" || true
    [[ -n "${found}" ]]

}
ensure_bash () {

    local req="$(bash_ver_norm "${1:-${BASH_MIN_VERSION:-5.2}}")"
    local cur_ver="$(bash_current_version)"
    local uname_s="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    if bash_ver_ge "${cur_ver}" "${req}"; then
        return 0
    fi
    if [[ -n "${BASH_BOOTSTRAPPED:-}" ]]; then
        bash_die "ensure-bash: requires bash >= ${req}, current=${cur_ver}" 2
    fi

    case "${uname_s}" in
        linux*)
            bash_log "ensure-bash: current bash ${cur_ver} < ${req}; trying Linux package managers"
            bash_ensure_linux "${req}" || bash_die "ensure-bash: failed to install/upgrade bash >= ${req} on Linux" 2
        ;;
        darwin*)
            bash_log "ensure-bash: current bash ${cur_ver} < ${req}; trying Homebrew"
            bash_ensure_macos "${req}" || bash_die "ensure-bash: failed to install/upgrade bash >= ${req} on macOS (need Homebrew)" 2
        ;;
        msys*|mingw*|cygwin*)
            bash_log "ensure-bash: current bash ${cur_ver} < ${req}; trying WinGet/Chocolatey/Scoop/MSYS2/Git for Windows"
            bash_ensure_windows "${req}" || bash_die "ensure-bash: failed to install/upgrade bash >= ${req} on Windows" 2
        ;;
        *)
            bash_die "ensure-bash: unsupported OS '${uname_s}'" 2
        ;;
    esac

    bash_path_prepend "/opt/homebrew/bin"
    bash_path_prepend "/usr/local/bin"
    bash_path_prepend "/home/linuxbrew/.linuxbrew/bin"
    bash_path_prepend "/mingw64/bin"
    bash_path_prepend "/usr/bin"
    bash_path_prepend "/bin"

    local best_bin="$(bash_find_best_candidate "${req}")" || true
    [[ -n "${best_bin}" ]] || bash_die "ensure-bash: no bash >= ${req} found after install/upgrade" 2

    local best_ver="$(bash_version_from_bin "${best_bin}")"
    bash_ver_ge "${best_ver}" "${req}" || bash_die "ensure-bash: found bash ${best_ver}, need >= ${req}" 2

    export BASH_BOOTSTRAPPED=1
    export BASH_BIN="${best_bin}"

    exec "${best_bin}" "$0" "$@" || bash_die "ensure-bash: failed to re-exec via '${best_bin}'" 2

}

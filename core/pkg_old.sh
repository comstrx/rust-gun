
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

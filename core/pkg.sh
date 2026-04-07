
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "pkg.sh: this file should not be run externally." >&2; exit 2; }
[[ -n "${PKG_LOADED:-}" ]] && return 0
PKG_LOADED=1

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/parse.sh"

pkg_hash_clear () {

    hash -r 2>/dev/null || true

}
pkg_target () {

    if is_wsl; then
        printf '%s' "linux"
        return 0
    fi

    case "$(uname -s 2>/dev/null || true)" in
        Linux)   printf '%s' "linux" ;;
        Darwin)  printf '%s' "mac" ;;
        MSYS*)   printf '%s' "msys" ;;
        MINGW*)
            if [[ -n "${MSYSTEM:-}" || -n "${MSYSTEM_PREFIX:-}" || -d /etc/pacman.d ]]; then printf '%s' "mingw"
            else printf '%s' "gitbash"
            fi
        ;;
        CYGWIN*) printf '%s' "cygwin" ;;
        *)       printf '%s' "unknown" ;;
    esac

}
pkg_require_target () {

    local target="${1:-$(pkg_target)}"

    case "${target}" in
        linux|mac|msys|mingw|gitbash|cygwin) return 0 ;;
    esac

    die "pkg: unsupported target '${target}'." 2

}
pkg_with_sudo () {

    local target="${1-}"
    shift || true

    case "${target}" in
        linux|mac) ;;
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
        mac)
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
        *)
            if [[ -n "${MSYSTEM_PREFIX:-}" ]]; then basename -- "${MSYSTEM_PREFIX}"
            else printf '%s' "mingw-w64-x86_64"
            fi
        ;;
    esac

}

pkg_is_llvm_family () {

    case "${1-}" in
        clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config) return 0 ;;
    esac

    return 1

}
pkg_coreutils_name () {

    case "${1-}" in
        mv|cp|rm|ln|mkdir|rmdir|cat|touch|head|tail|cut|tr|sort|uniq|wc|date|sleep|mktemp|basename|dirname|realpath|tee|chmod|readlink|stat)
            return 0
        ;;
    esac

    return 1

}
pkg_findutils_name () {

    case "${1-}" in
        find|xargs) return 0 ;;
    esac

    return 1

}
pkg_cmd_name () {

    local want="${1-}"

    case "${want}" in
        llvm-config) printf '%s' "llvm-config" ;;
        *)           printf '%s' "${want}" ;;
    esac

}
pkg_verify_one () {

    local want="${1-}"

    if pkg_is_llvm_family "${want}"; then
        case "${want}" in
            llvm|llvm-dev|llvm-config)
                has llvm-config || has llvm-ar || has llc
                return $?
            ;;
            clang|clang-dev)
                has clang
                return $?
            ;;
            libclang|libclang-dev)
                has clang || has llvm-config || has llc
                return $?
            ;;
        esac
    fi

    has "$(pkg_cmd_name "${want}")"

}

pkg_map_linux () {

    local want="${1-}" backend="${2-}"

    if pkg_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_findutils_name  "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        git|jq|curl|perl|sed|grep) printf '%s' "${want}" ;;
        awk)                       printf '%s' "gawk" ;;
        clang)                     printf '%s' "clang" ;;
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
        *) printf '%s' "" ;;
    esac

}
pkg_map_msys_pacman () {

    local want="${1-}"

    if pkg_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_findutils_name  "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        git|jq|curl|perl|sed|grep)             printf '%s' "${want}" ;;
        awk)                                   printf '%s' "gawk" ;;
        clang|clang-dev|libclang|libclang-dev) printf '%s' "clang" ;;
        llvm|llvm-dev|llvm-config)             printf '%s' "llvm" ;;
        *) printf '%s' "" ;;
    esac

}
pkg_map_mingw_pacman () {

    local want="${1-}" prefix="${2:-$(pkg_mingw_prefix)}"

    if pkg_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_findutils_name  "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        git|jq|curl|perl|sed|grep)             printf '%s' "${want}" ;;
        awk)                                   printf '%s' "gawk" ;;
        clang|clang-dev|libclang|libclang-dev) printf '%s' "${prefix}-clang" ;;
        llvm|llvm-dev|llvm-config)             printf '%s' "${prefix}-llvm" ;;
        *) printf '%s' "" ;;
    esac

}
pkg_map_cygwin () {

    local want="${1-}"

    if pkg_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_findutils_name  "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        git|jq|curl|perl|sed|grep) printf '%s' "${want}" ;;
        awk)                       printf '%s' "gawk" ;;
        clang)                     printf '%s' "clang" ;;
        clang-dev|libclang|libclang-dev) printf '%s' "libclang-devel" ;;
        llvm|llvm-dev|llvm-config) printf '%s' "llvm" ;;
        *) printf '%s' "" ;;
    esac

}
pkg_map_scoop () {

    local want="${1-}"

    if pkg_coreutils_name "${want}" || pkg_findutils_name "${want}" || [[ "${want}" == awk || "${want}" == sed || "${want}" == grep ]]; then
        printf '%s' "msys2"
        return 0
    fi

    case "${want}" in
        git)   printf '%s' "git" ;;
        jq)    printf '%s' "jq" ;;
        curl)  printf '%s' "curl" ;;
        perl)  printf '%s' "perl" ;;
        clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config)
            printf '%s' "llvm"
        ;;
        *) printf '%s' "" ;;
    esac

}
pkg_map_choco () {

    local want="${1-}"

    if pkg_coreutils_name "${want}" || pkg_findutils_name "${want}" || [[ "${want}" == awk || "${want}" == sed || "${want}" == grep ]]; then
        printf '%s' "git"
        return 0
    fi

    case "${want}" in
        git)   printf '%s' "git" ;;
        jq)    printf '%s' "jq" ;;
        curl)  printf '%s' "curl" ;;
        perl)  printf '%s' "strawberryperl" ;;
        clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config)
            printf '%s' "llvm"
        ;;
        *) printf '%s' "" ;;
    esac

}
pkg_map_winget () {

    local want="${1-}"

    if pkg_coreutils_name "${want}" || pkg_findutils_name "${want}" || [[ "${want}" == awk || "${want}" == sed || "${want}" == grep ]]; then
        printf '%s' "Git.Git"
        return 0
    fi

    case "${want}" in
        git)   printf '%s' "Git.Git" ;;
        jq)    printf '%s' "jqlang.jq" ;;
        curl)  printf '%s' "cURL.cURL" ;;
        perl)  printf '%s' "StrawberryPerl.StrawberryPerl" ;;
        clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config)
            printf '%s' "LLVM.LLVM"
        ;;
        *) printf '%s' "" ;;
    esac

}
pkg_map () {

    local want="${1-}" target="${2-}" backend="${3-}" aux="${4-}"

    case "${backend}" in
        apt|dnf|yum|pacman|zypper|apk|brew)
            case "${target}" in
                msys)  pkg_map_msys_pacman  "${want}" ;;
                mingw) pkg_map_mingw_pacman "${want}" "${aux}" ;;
                *)     pkg_map_linux        "${want}" "${backend}" ;;
            esac
        ;;
        apt-cyg|cygwin-setup) pkg_map_cygwin "${want}" ;;
        scoop)                pkg_map_scoop  "${want}" ;;
        choco)                pkg_map_choco  "${want}" ;;
        winget)               pkg_map_winget "${want}" ;;
        *)                    printf '%s' "" ;;
    esac

}
pkg_collect_missing () {

    local -n out_ref="${1}"
    shift || true

    local want=""
    out_ref=()

    for want in "$@"; do
        [[ -n "${want}" ]] || continue
        pkg_verify_one "${want}" || out_ref+=( "${want}" )
    done

}
pkg_build_plan () {

    local -n out_ref="${1}"
    local target="${2-}" backend="${3-}" aux="${4-}"
    shift 4 || true

    local want="" mapped=""
    out_ref=()

    for want in "$@"; do
        [[ -n "${want}" ]] || continue

        mapped="$(pkg_map "${want}" "${target}" "${backend}" "${aux}")"
        [[ -n "${mapped}" ]] || die "pkg: no package mapping for '${want}' on '${target}/${backend}'." 2

        out_ref+=( "${mapped}" )
    done

    unique_list out_ref

}

pkg_apt_update_once () {

    (( ${PKG_APT_UPDATED:-0} )) && return 0
    PKG_APT_UPDATED=1

    pkg_with_sudo linux apt-get update >/dev/null 2>&1 || pkg_with_sudo linux apt-get update

}
pkg_install_linux () {

    local backend="${1-}"
    shift || true

    local -a pkgs=( "$@" )
    (( ${#pkgs[@]} )) || return 0

    case "${backend}" in
        apt)
            pkg_apt_update_once
            if (( YES )); then pkg_with_sudo linux env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
            else pkg_with_sudo linux env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends "${pkgs[@]}"
            fi
        ;;
        dnf)
            if (( YES )); then pkg_with_sudo linux dnf install -y "${pkgs[@]}"
            else pkg_with_sudo linux dnf install "${pkgs[@]}"
            fi
        ;;
        yum)
            if (( YES )); then pkg_with_sudo linux yum install -y "${pkgs[@]}"
            else pkg_with_sudo linux yum install "${pkgs[@]}"
            fi
        ;;
        pacman)
            if (( YES )); then pkg_with_sudo linux pacman -S --needed --noconfirm "${pkgs[@]}"
            else pkg_with_sudo linux pacman -S --needed "${pkgs[@]}"
            fi
        ;;
        zypper)
            if (( YES )); then pkg_with_sudo linux zypper --non-interactive install --no-recommends "${pkgs[@]}"
            else pkg_with_sudo linux zypper install --no-recommends "${pkgs[@]}"
            fi
        ;;
        apk)
            pkg_with_sudo linux apk add --no-cache "${pkgs[@]}"
        ;;
        brew)
            env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 run brew install "${pkgs[@]}"
        ;;
        *)
            die "pkg: unsupported Linux backend '${backend}'." 2
        ;;
    esac

}
pkg_install_pacman () {

    local -a pkgs=( "$@" )
    (( ${#pkgs[@]} )) || return 0

    if (( YES )); then run pacman -S --needed --noconfirm "${pkgs[@]}"
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

    local -a pkgs=( "$@" )
    (( ${#pkgs[@]} )) || return 0

    run scoop install "${pkgs[@]}"

}
pkg_install_choco () {

    local -a pkgs=( "$@" )
    (( ${#pkgs[@]} )) || return 0

    if (( YES )); then run choco install -y "${pkgs[@]}"
    else run choco install "${pkgs[@]}"
    fi

}
pkg_install_winget () {

    local pkg=""
    for pkg in "$@"; do
        run winget install --id "${pkg}" --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
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
            pkg_install_linux "${backend}" "${pkgs[@]}"
        ;;
        mac:brew)
            pkg_install_linux brew "${pkgs[@]}"
        ;;
        msys:pacman|mingw:pacman|gitbash:pacman)
            pkg_install_pacman "${pkgs[@]}"
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

pkg_mac_gnu_alt () {

    case "${1-}" in
        awk)      printf '%s' "gawk" ;;
        sed)      printf '%s' "gsed" ;;
        grep)     printf '%s' "ggrep" ;;
        find)     printf '%s' "gfind" ;;
        xargs)    printf '%s' "gxargs" ;;
        head)     printf '%s' "ghead" ;;
        tail)     printf '%s' "gtail" ;;
        sort)     printf '%s' "gsort" ;;
        wc)       printf '%s' "gwc" ;;
        chmod)    printf '%s' "gchmod" ;;
        mkdir)    printf '%s' "gmkdir" ;;
        date)     printf '%s' "gdate" ;;
        stat)     printf '%s' "gstat" ;;
        readlink) printf '%s' "greadlink" ;;
        realpath) printf '%s' "grealpath" ;;
        tr)       printf '%s' "gtr" ;;
        tee)      printf '%s' "gtee" ;;
        mktemp)   printf '%s' "gmktemp" ;;
        *)        printf '%s' "" ;;
    esac

}
pkg_mac_post_install () {

    local want="" alt="" llvm_prefix=""

    for want in "$@"; do
        [[ -n "${want}" ]] || continue

        case "${want}" in
            clang|clang-dev|libclang|libclang-dev|llvm|llvm-dev|llvm-config)
                if has brew; then
                    llvm_prefix="$(brew --prefix llvm 2>/dev/null || true)"
                    [[ -n "${llvm_prefix}" && -d "${llvm_prefix}/bin" ]] && pkg_hash_clear
                fi
            ;;
        esac

        alt="$(pkg_mac_gnu_alt "${want}")"
        [[ -n "${alt}" ]] || continue

        has "${alt}" || continue
        ensure_bin_link "${want}" "$(command -v -- "${alt}")"
    done

    pkg_hash_clear

}
ensure_pkg () {

    source <(parse "$@" -- :wants:list)

    local target=""
    local backend=""
    local aux=""
    local -a missing=()
    local -a plan=()

    target="$(pkg_target)"
    pkg_require_target "${target}"

    backend="$(pkg_backend "${target}")" || die "pkg: no usable backend for target '${target}'." 2
    [[ "${target}" == "mingw" && "${backend}" == "pacman" ]] && aux="$(pkg_mingw_prefix)"

    pkg_collect_missing missing "${wants[@]}"

    if (( ${#missing[@]} == 0 )); then
        [[ "${target}" == "mac" ]] && pkg_mac_post_install "${wants[@]}"
        pkg_hash_clear
        return 0
    fi

    pkg_build_plan plan "${target}" "${backend}" "${aux}" "${missing[@]}"
    pkg_install "${target}" "${backend}" "${plan[@]}"

    [[ "${target}" == "mac" ]] && pkg_mac_post_install "${wants[@]}"

    pkg_hash_clear
    pkg_collect_missing missing "${wants[@]}"

    (( ${#missing[@]} == 0 )) || die "pkg: failed to ensure tools: ${missing[*]}" 2
    return 0

}

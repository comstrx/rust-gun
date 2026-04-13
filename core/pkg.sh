
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
        msys*) printf '%s' "msys" ;;
        mingw*)
            if [[ -n "${MSYSTEM:-}" || -n "${MSYSTEM_PREFIX:-}" || -d /etc/pacman.d ]]; then printf '%s' "mingw"
            else printf '%s' "gitbash"
            fi
        ;;
        cygwin*) printf '%s' "cygwin" ;;
        *) printf '%s' "unknown" ;;
    esac

}
pkg_require_target () {

    case "${1:-}" in
        linux|macos|msys|mingw|gitbash|cygwin) return 0 ;;
    esac

    die "pkg: unsupported target '${1:-}'."

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

    die "pkg: root privileges required (sudo/doas not found)."

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
            if has brew; then
                printf '%s' "brew"
                return 0
            fi
        ;;
        msys|mingw|gitbash)
            if has pacman; then printf '%s' "pacman"; return 0; fi
            if pkg_has_any winget winget.exe; then printf '%s' "winget"; return 0; fi
            if pkg_has_any choco choco.exe;   then printf '%s' "choco"; return 0; fi
            if pkg_has_any scoop scoop.cmd;   then printf '%s' "scoop"; return 0; fi
        ;;
        cygwin)
            if has apt-cyg;          then printf '%s' "apt-cyg"; return 0; fi
            if has setup-x86_64.exe; then printf '%s' "cygwin-setup"; return 0; fi
            if has setup-x86.exe;    then printf '%s' "cygwin-setup"; return 0; fi
            if pkg_has_any winget winget.exe; then printf '%s' "winget"; return 0; fi
            if pkg_has_any choco choco.exe;   then printf '%s' "choco"; return 0; fi
            if pkg_has_any scoop scoop.cmd;   then printf '%s' "scoop"; return 0; fi
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
pkg_is_archiveutils_name () {

    case "${1-}" in
        tar|file|diff|zip|unzip|rar|unrar|7z|zstd|rsync) return 0 ;;
    esac

    return 1

}
pkg_is_qualityutils_name () {

    case "${1-}" in
        trivy|syft|gitleaks|taplo|typos) return 0 ;;
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
        awk|sed|grep|tar|diff) return 0 ;;
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

    case "${1-}" in
        diff) printf '%s' "diff" ;;
        7z)   printf '%s' "7z" ;;
        *)    printf '%s' "${1-}" ;;
    esac

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
        kill)
            command -v kill >/dev/null 2>&1
            return $?
        ;;
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
        7z)
            pkg_has_any 7z 7zz 7za
            return $?
        ;;
        typos)
            pkg_has_any typos typos-cli
            return $?
        ;;
        trivy|syft|gitleaks|taplo)
            has "$(pkg_cmd_name "${want}")"
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
        tar)
            printf '%s' "tar"
        ;;
        file)
            printf '%s' "file"
        ;;
        diff)
            printf '%s' "diffutils"
        ;;
        zip)
            printf '%s' "zip"
        ;;
        unzip)
            printf '%s' "unzip"
        ;;
        rar)
            printf '%s' "rar"
        ;;
        unrar)
            printf '%s' "unrar"
        ;;
        7z)
            case "${backend}" in
                apt)            printf '%s' "p7zip-full" ;;
                dnf|yum|zypper) printf '%s' "p7zip" ;;
                pacman)         printf '%s' "7zip" ;;
                apk)            printf '%s' "7zip" ;;
                brew)           printf '%s' "sevenzip" ;;
                *)              printf '%s' "p7zip-full" ;;
            esac
        ;;
        zstd)
            printf '%s' "zstd"
        ;;
        rsync)
            printf '%s' "rsync"
        ;;
        syft)
            printf '%s' "syft"
        ;;
        gitleaks)
            printf '%s' "gitleaks"
        ;;
        taplo)
            case "${backend}" in
                pacman)         printf '%s' "taplo-cli" ;;
                *)              printf '%s' "taplo" ;;
            esac
        ;;
        typos)
            printf '%s' "typos"
        ;;
        git|jq|curl|perl|grep|sed)
            printf '%s' "${want}"
        ;;
        gh)
            case "${backend}" in
                pacman) printf '%s' "github-cli" ;;
                *)      printf '%s' "gh" ;;
            esac
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
        tar)
            printf '%s' "gnu-tar"
        ;;
        file|zip|unzip|zstd|rsync)
            printf '%s' "${want}"
        ;;
        diff)
            printf '%s' "diffutils"
        ;;
        rar|unrar)
            printf '%s' "cask:rar"
        ;;
        7z)
            printf '%s' "sevenzip"
        ;;
        trivy|syft|gitleaks|taplo)
            printf '%s' "${want}"
        ;;
        typos)
            printf '%s' "typos-cli"
        ;;
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
        tar)
            printf '%s' "tar"
        ;;
        file)
            printf '%s' "file"
        ;;
        diff)
            printf '%s' "diffutils"
        ;;
        zip)
            printf '%s' "zip"
        ;;
        unzip)
            printf '%s' "unzip"
        ;;
        rar)
            printf '%s' "rar"
        ;;
        unrar)
            printf '%s' "unrar"
        ;;
        7z)
            printf '%s' "p7zip"
        ;;
        zstd)
            printf '%s' "zstd"
        ;;
        rsync)
            printf '%s' "rsync"
        ;;
        git|jq|curl|perl|sed|grep)
            printf '%s' "${want}"
        ;;
        gh)
            printf '%s' "github-cli"
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
        tar)
            printf '%s' "tar"
        ;;
        file)
            printf '%s' "file"
        ;;
        diff)
            printf '%s' "diffutils"
        ;;
        zip)
            printf '%s' "zip"
        ;;
        unzip)
            printf '%s' "unzip"
        ;;
        rar)
            printf '%s' "rar"
        ;;
        unrar)
            printf '%s' "unrar"
        ;;
        7z)
            printf '%s' "p7zip"
        ;;
        zstd)
            printf '%s' "zstd"
        ;;
        rsync)
            printf '%s' "rsync"
        ;;
        git|jq|curl|perl|sed|grep)
            printf '%s' "${want}"
        ;;
        gh)
            printf '%s' "${prefix}-github-cli"
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
        tar)
            printf '%s' "tar"
        ;;
        file)
            printf '%s' "file"
        ;;
        diff)
            printf '%s' "diffutils"
        ;;
        zip)
            printf '%s' "zip"
        ;;
        unzip)
            printf '%s' "unzip"
        ;;
        rar)
            printf '%s' "rar"
        ;;
        unrar)
            printf '%s' "unrar"
        ;;
        7z)
            printf '%s' "p7zip"
        ;;
        zstd)
            printf '%s' "zstd"
        ;;
        rsync)
            printf '%s' "rsync"
        ;;
        git|jq|curl|perl|sed|grep)
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
pkg_windows_pkg_uses_msys2 () {

    local want="${1-}"

    pkg_is_coreutils_name "${want}" && return 0
    pkg_is_findutils_name "${want}" && return 0

    case "${want}" in
        awk|sed|grep|tar|file|diff|zip|unzip|zstd|rsync) return 0 ;;
    esac

    return 1

}
pkg_windows_msys2_pkg () {

    local want="${1-}"

    if pkg_is_coreutils_name "${want}"; then printf '%s' "coreutils"; return 0; fi
    if pkg_is_findutils_name "${want}"; then printf '%s' "findutils"; return 0; fi

    case "${want}" in
        tar)   printf '%s' "tar" ;;
        file)  printf '%s' "file" ;;
        diff)  printf '%s' "diffutils" ;;
        zip)   printf '%s' "zip" ;;
        unzip) printf '%s' "unzip" ;;
        zstd)  printf '%s' "zstd" ;;
        rsync) printf '%s' "rsync" ;;
        awk)   printf '%s' "gawk" ;;
        sed|grep)
            printf '%s' "${want}"
        ;;
        *)
            printf '%s' ""
        ;;
    esac

}
pkg_windows_msys2_root () {

    local p="" userprofile_u="" home_u=""

    [[ -n "${USERPROFILE:-}" ]] && userprofile_u="$(pkg_to_unix_path "${USERPROFILE}")"
    [[ -n "${HOME:-}" ]] && home_u="$(pkg_to_unix_path "${HOME}")"

    local -a roots=(
        "/c/msys64"
        "/c/tools/msys64"
        "/cygdrive/c/msys64"
        "/cygdrive/c/tools/msys64"
        "${userprofile_u}/scoop/apps/msys2/current"
        "${home_u}/scoop/apps/msys2/current"
    )

    for p in "${roots[@]}"; do

        [[ -n "${p}" ]] || continue
        [[ -x "${p}/usr/bin/pacman.exe" ]] && { printf '%s' "${p}"; return 0; }
        [[ -x "${p}/usr/bin/pacman" ]] && { printf '%s' "${p}"; return 0; }

    done

    return 1

}

pkg_windows_msys2_pacman () {

    local root="$(pkg_windows_msys2_root)" || return 1

    if [[ -x "${root}/usr/bin/pacman.exe" ]]; then
        printf '%s' "${root}/usr/bin/pacman.exe"
        return 0
    fi
    if [[ -x "${root}/usr/bin/pacman" ]]; then
        printf '%s' "${root}/usr/bin/pacman"
        return 0
    fi

    return 1

}
pkg_post_install_windows_msys2 () {

    local target="${1-}" backend="${2-}" want="" mapped="" pacman=""
    shift 2 || true

    case "${target}:${backend}" in
        msys:scoop|mingw:scoop|gitbash:scoop|cygwin:scoop|msys:choco|mingw:choco|gitbash:choco|cygwin:choco|msys:winget|mingw:winget|gitbash:winget|cygwin:winget) ;;
        *) return 0 ;;
    esac

    pacman="$(pkg_windows_msys2_pacman)" || return 0

    local -a pkgs=()

    for want in "$@"; do

        [[ -n "${want}" ]] || continue
        pkg_windows_pkg_uses_msys2 "${want}" || continue

        mapped="$(pkg_windows_msys2_pkg "${want}")"
        [[ -n "${mapped}" ]] && pkgs+=( "${mapped}" )

    done

    unique_list pkgs
    (( ${#pkgs[@]} )) || return 0

    run "${pacman}" -Sy --needed --noconfirm "${pkgs[@]}" || true

}
pkg_map_scoop () {

    local want="${1-}"

    if pkg_windows_pkg_uses_msys2 "${want}"; then
        printf '%s' "msys2"
        return 0
    fi

    case "${want}" in
        7z)
            printf '%s' "7zip"
        ;;
        trivy)
            printf '%s' "trivy"
        ;;
        syft)
            printf '%s' "syft"
        ;;
        gitleaks)
            printf '%s' "gitleaks"
        ;;
        taplo)
            printf '%s' "taplo"
        ;;
        typos)
            printf '%s' "typos"
        ;;
        rar|unrar)
            printf '%s' "winrar"
        ;;
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

    if pkg_windows_pkg_uses_msys2 "${want}"; then
        printf '%s' "msys2"
        return 0
    fi

    case "${want}" in
        7z)
            printf '%s' "7zip"
        ;;
        trivy)
            printf '%s' "trivy"
        ;;
        syft)
            printf '%s' "syft"
        ;;
        gitleaks)
            printf '%s' "gitleaks"
        ;;
        taplo)
            printf '%s' "taplo"
        ;;
        typos)
            printf '%s' "typos"
        ;;
        rar|unrar)
            printf '%s' "winrar"
        ;;
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

    if pkg_windows_pkg_uses_msys2 "${want}"; then
        printf '%s' "MSYS2.MSYS2"
        return 0
    fi

    case "${want}" in
        7z)
            printf '%s' "7zip.7zip"
        ;;
        trivy)
            printf '%s' "AquaSecurity.Trivy"
        ;;
        syft)
            printf '%s' "Anchore.Syft"
        ;;
        gitleaks)
            printf '%s' "Gitleaks.Gitleaks"
        ;;
        taplo)
            printf '%s' "tamasfe.taplo"
        ;;
        typos)
            printf '%s' "Crate-CI.Typos"
        ;;
        rar|unrar)
            printf '%s' "RARLab.WinRAR"
        ;;
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

    local pkg="" formula=""

    for pkg in "$@"; do

        if [[ "${pkg}" == cask:* ]]; then

            formula="${pkg#cask:}"

            run env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --cask "${formula}" || \
                run env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew upgrade --cask "${formula}" || \
                die "pkg: brew cask failed for '${formula}'."

            continue

        fi

        run env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install "${pkg}" || \
            run env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew upgrade "${pkg}" || \
            die "pkg: brew failed for '${pkg}'."

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
            die "pkg: unsupported Linux backend '${backend}'."
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
    else die "pkg: cygwin setup executable not found."
    fi

    run "${setup}" -q -P "$(IFS=,; printf '%s' "${pkgs[*]}")"

}
pkg_install_scoop () {

    local exe="scoop" pkg=""

    has "${exe}" || exe="scoop.cmd"

    for pkg in "$@"; do
        run "${exe}" install "${pkg}" || run "${exe}" update "${pkg}" || die "pkg: scoop failed for '${pkg}'."
    done

}
pkg_install_choco () {

    local exe="choco" pkg=""

    has "${exe}" || exe="choco.exe"

    for pkg in "$@"; do

        if pkg_assume_yes; then run "${exe}" install -y "${pkg}" || run "${exe}" upgrade -y "${pkg}" || die "pkg: choco failed for '${pkg}'."
        else run "${exe}" install "${pkg}" || run "${exe}" upgrade "${pkg}" || die "pkg: choco failed for '${pkg}'."
        fi

    done

}
pkg_install_winget () {

    local exe="winget" pkg=""

    has "${exe}" || exe="winget.exe"

    for pkg in "$@"; do

        run "${exe}" install --id "${pkg}" --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || run "${exe}" upgrade --id "${pkg}" --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || run "${exe}" install --name "${pkg}" --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || die "pkg: winget failed for '${pkg}'."

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
            die "pkg: unsupported install path '${target}:${backend}'."
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
        [[ -n "${mapped}" ]] || die "pkg: no package mapping for '${want}' on '${target}/${backend}'."

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
pkg_path_prepend_glob () {

    local pattern="${1-}" p=""
    [[ -n "${pattern}" ]] || return 0

    while IFS= read -r p; do
        [[ -d "${p}" ]] || continue
        pkg_path_prepend "${p%/}"
    done < <(compgen -G "${pattern}" || true)

}
pkg_refresh_path () {

    local localapp_u="" userprofile_u="" home_u=""

    [[ -n "${LOCALAPPDATA:-}" ]] && localapp_u="$(pkg_to_unix_path "${LOCALAPPDATA}")"
    [[ -n "${USERPROFILE:-}" ]] && userprofile_u="$(pkg_to_unix_path "${USERPROFILE}")"
    [[ -n "${HOME:-}" ]] && home_u="$(pkg_to_unix_path "${HOME}")"

    pkg_activate_user_bin

    pkg_path_prepend "/opt/homebrew/bin"
    pkg_path_prepend "/opt/homebrew/sbin"
    pkg_path_prepend "/usr/local/bin"
    pkg_path_prepend "/usr/local/sbin"
    pkg_path_prepend "/home/linuxbrew/.linuxbrew/bin"
    pkg_path_prepend "/home/linuxbrew/.linuxbrew/sbin"
    pkg_path_prepend "/mingw64/bin"
    pkg_path_prepend "/mingw32/bin"
    pkg_path_prepend "/ucrt64/bin"
    pkg_path_prepend "/clang64/bin"
    pkg_path_prepend "/clang32/bin"
    pkg_path_prepend "/clangarm64/bin"
    pkg_path_prepend "/usr/bin"
    pkg_path_prepend "/usr/sbin"
    pkg_path_prepend "/bin"
    pkg_path_prepend "/sbin"

    [[ -n "${localapp_u}" ]] && pkg_path_prepend "${localapp_u}/Microsoft/WinGet/Links"
    [[ -n "${localapp_u}" ]] && pkg_path_prepend "${localapp_u}/Programs/Git/bin"
    [[ -n "${localapp_u}" ]] && pkg_path_prepend "${localapp_u}/Programs/Git/usr/bin"

    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/shims"
    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/apps/git/current/bin"
    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/apps/git/current/usr/bin"
    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/apps/msys2/current/usr/bin"
    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/apps/msys2/current/mingw64/bin"
    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/apps/msys2/current/mingw32/bin"
    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/apps/msys2/current/ucrt64/bin"
    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/apps/msys2/current/clang64/bin"
    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/apps/msys2/current/clang32/bin"
    [[ -n "${userprofile_u}" ]] && pkg_path_prepend "${userprofile_u}/scoop/apps/msys2/current/clangarm64/bin"

    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/shims"
    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/apps/git/current/bin"
    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/apps/git/current/usr/bin"
    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/apps/msys2/current/usr/bin"
    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/apps/msys2/current/mingw64/bin"
    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/apps/msys2/current/mingw32/bin"
    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/apps/msys2/current/ucrt64/bin"
    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/apps/msys2/current/clang64/bin"
    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/apps/msys2/current/clang32/bin"
    [[ -n "${home_u}" ]] && pkg_path_prepend "${home_u}/scoop/apps/msys2/current/clangarm64/bin"

    [[ -d "/c/Program Files/Git/bin" ]] && pkg_path_prepend "/c/Program Files/Git/bin"
    [[ -d "/c/Program Files/Git/usr/bin" ]] && pkg_path_prepend "/c/Program Files/Git/usr/bin"
    [[ -d "/c/Program Files/GitHub CLI" ]] && pkg_path_prepend "/c/Program Files/GitHub CLI"
    [[ -d "/c/Program Files/LLVM/bin" ]] && pkg_path_prepend "/c/Program Files/LLVM/bin"
    [[ -d "/c/Strawberry/perl/bin" ]] && pkg_path_prepend "/c/Strawberry/perl/bin"
    [[ -d "/c/Program Files/WinRAR" ]] && pkg_path_prepend "/c/Program Files/WinRAR"
    [[ -d "/c/Program Files/7-Zip" ]] && pkg_path_prepend "/c/Program Files/7-Zip"
    [[ -d "/c/ProgramData/chocolatey/bin" ]] && pkg_path_prepend "/c/ProgramData/chocolatey/bin"
    [[ -d "/c/msys64/usr/bin" ]] && pkg_path_prepend "/c/msys64/usr/bin"
    [[ -d "/c/msys64/mingw64/bin" ]] && pkg_path_prepend "/c/msys64/mingw64/bin"
    [[ -d "/c/msys64/mingw32/bin" ]] && pkg_path_prepend "/c/msys64/mingw32/bin"
    [[ -d "/c/msys64/ucrt64/bin" ]] && pkg_path_prepend "/c/msys64/ucrt64/bin"
    [[ -d "/c/msys64/clang64/bin" ]] && pkg_path_prepend "/c/msys64/clang64/bin"
    [[ -d "/c/msys64/clang32/bin" ]] && pkg_path_prepend "/c/msys64/clang32/bin"
    [[ -d "/c/msys64/clangarm64/bin" ]] && pkg_path_prepend "/c/msys64/clangarm64/bin"
    [[ -d "/c/tools/msys64/usr/bin" ]] && pkg_path_prepend "/c/tools/msys64/usr/bin"
    [[ -d "/c/tools/msys64/mingw64/bin" ]] && pkg_path_prepend "/c/tools/msys64/mingw64/bin"
    [[ -d "/c/tools/msys64/mingw32/bin" ]] && pkg_path_prepend "/c/tools/msys64/mingw32/bin"
    [[ -d "/c/tools/msys64/ucrt64/bin" ]] && pkg_path_prepend "/c/tools/msys64/ucrt64/bin"
    [[ -d "/c/tools/msys64/clang64/bin" ]] && pkg_path_prepend "/c/tools/msys64/clang64/bin"
    [[ -d "/c/tools/msys64/clang32/bin" ]] && pkg_path_prepend "/c/tools/msys64/clang32/bin"
    [[ -d "/c/tools/msys64/clangarm64/bin" ]] && pkg_path_prepend "/c/tools/msys64/clangarm64/bin"

    [[ -d "/cygdrive/c/Program Files/Git/bin" ]] && pkg_path_prepend "/cygdrive/c/Program Files/Git/bin"
    [[ -d "/cygdrive/c/Program Files/Git/usr/bin" ]] && pkg_path_prepend "/cygdrive/c/Program Files/Git/usr/bin"
    [[ -d "/cygdrive/c/Program Files/GitHub CLI" ]] && pkg_path_prepend "/cygdrive/c/Program Files/GitHub CLI"
    [[ -d "/cygdrive/c/Program Files/LLVM/bin" ]] && pkg_path_prepend "/cygdrive/c/Program Files/LLVM/bin"
    [[ -d "/cygdrive/c/Strawberry/perl/bin" ]] && pkg_path_prepend "/cygdrive/c/Strawberry/perl/bin"
    [[ -d "/cygdrive/c/Program Files/WinRAR" ]] && pkg_path_prepend "/cygdrive/c/Program Files/WinRAR"
    [[ -d "/cygdrive/c/Program Files/7-Zip" ]] && pkg_path_prepend "/cygdrive/c/Program Files/7-Zip"
    [[ -d "/cygdrive/c/ProgramData/chocolatey/bin" ]] && pkg_path_prepend "/cygdrive/c/ProgramData/chocolatey/bin"
    [[ -d "/cygdrive/c/msys64/usr/bin" ]] && pkg_path_prepend "/cygdrive/c/msys64/usr/bin"
    [[ -d "/cygdrive/c/msys64/mingw64/bin" ]] && pkg_path_prepend "/cygdrive/c/msys64/mingw64/bin"
    [[ -d "/cygdrive/c/msys64/mingw32/bin" ]] && pkg_path_prepend "/cygdrive/c/msys64/mingw32/bin"
    [[ -d "/cygdrive/c/msys64/ucrt64/bin" ]] && pkg_path_prepend "/cygdrive/c/msys64/ucrt64/bin"
    [[ -d "/cygdrive/c/msys64/clang64/bin" ]] && pkg_path_prepend "/cygdrive/c/msys64/clang64/bin"
    [[ -d "/cygdrive/c/msys64/clang32/bin" ]] && pkg_path_prepend "/cygdrive/c/msys64/clang32/bin"
    [[ -d "/cygdrive/c/msys64/clangarm64/bin" ]] && pkg_path_prepend "/cygdrive/c/msys64/clangarm64/bin"
    [[ -d "/cygdrive/c/tools/msys64/usr/bin" ]] && pkg_path_prepend "/cygdrive/c/tools/msys64/usr/bin"
    [[ -d "/cygdrive/c/tools/msys64/mingw64/bin" ]] && pkg_path_prepend "/cygdrive/c/tools/msys64/mingw64/bin"
    [[ -d "/cygdrive/c/tools/msys64/mingw32/bin" ]] && pkg_path_prepend "/cygdrive/c/tools/msys64/mingw32/bin"
    [[ -d "/cygdrive/c/tools/msys64/ucrt64/bin" ]] && pkg_path_prepend "/cygdrive/c/tools/msys64/ucrt64/bin"
    [[ -d "/cygdrive/c/tools/msys64/clang64/bin" ]] && pkg_path_prepend "/cygdrive/c/tools/msys64/clang64/bin"
    [[ -d "/cygdrive/c/tools/msys64/clang32/bin" ]] && pkg_path_prepend "/cygdrive/c/tools/msys64/clang32/bin"
    [[ -d "/cygdrive/c/tools/msys64/clangarm64/bin" ]] && pkg_path_prepend "/cygdrive/c/tools/msys64/clangarm64/bin"
    [[ -d "/cygdrive/c/cygwin64/bin" ]] && pkg_path_prepend "/cygdrive/c/cygwin64/bin"
    [[ -d "/cygdrive/c/cygwin/bin" ]] && pkg_path_prepend "/cygdrive/c/cygwin/bin"

    [[ -n "${localapp_u}" ]] && pkg_path_prepend_glob "${localapp_u}/Programs/Python/Python*"
    [[ -n "${localapp_u}" ]] && pkg_path_prepend_glob "${localapp_u}/Programs/Python/Python*/Scripts"

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
pkg_http_get () {

    local url="${1-}"

    [[ -n "${url}" ]] || return 1

    if has curl; then
        curl -fsSL "${url}"
        return $?
    fi
    if has wget; then
        wget -qO- "${url}"
        return $?
    fi

    return 1

}
pkg_fetch_url () {

    local url="${1-}" out="${2-}"

    [[ -n "${url}" && -n "${out}" ]] || return 1

    if has curl; then
        run curl -fsSL "${url}" -o "${out}"
        return $?
    fi
    if has wget; then
        run wget -qO "${out}" "${url}"
        return $?
    fi

    die "pkg: need curl or wget to download '${url}'."

}

pkg_github_release_json () {

    local repo="${1-}" api=""

    [[ -n "${repo}" ]] || return 1
    api="https://api.github.com/repos/${repo}/releases/latest"

    pkg_http_get "${api}"

}
pkg_github_latest_tag () {

    local repo="${1-}" tag=""

    [[ -n "${repo}" ]] || return 1

    tag="$(
        pkg_github_release_json "${repo}" 2>/dev/null \
            | grep -oE '"tag_name":[[:space:]]*"[^"]+"' \
            | head -n1 \
            | sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
    )"

    [[ -n "${tag}" ]] || return 1
    printf '%s\n' "${tag}"

}
pkg_github_release_asset_url () {

    local repo="${1-}" pattern="${2-}" url=""

    [[ -n "${repo}" && -n "${pattern}" ]] || return 1

    url="$(
        pkg_github_release_json "${repo}" 2>/dev/null \
            | grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' \
            | sed 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/' \
            | grep -E "/${pattern}$" \
            | head -n1
    )"

    [[ -n "${url}" ]] || return 1
    printf '%s\n' "${url}"

}
pkg_ensure_fetcher () {

    local target="${1-}" backend="${2-}" mapped=""

    if has curl || has wget; then
        return 0
    fi

    mapped="$(pkg_map "${target}" "${backend}" "" "curl")"
    [[ -n "${mapped}" ]] || return 1

    pkg_install "${target}" "${backend}" "${mapped}" || return 1
    pkg_refresh_path
    pkg_hash_clear

    has curl || has wget

}

pkg_cpu_arch () {

    local arch="$(uname -m 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    case "${arch}" in
        x86_64|amd64) printf '%s\n' "amd64" ;;
        aarch64|arm64) printf '%s\n' "arm64" ;;
        i386|i686|x86) printf '%s\n' "386" ;;
        armv7l|armv7) printf '%s\n' "armv7" ;;
        riscv64) printf '%s\n' "riscv64" ;;
        *) printf '%s\n' "${arch}" ;;
    esac

}
pkg_direct_bin_path () {

    local name="${1-}" target="${2-}" dir=""
    dir="$(pkg_user_bin_dir)"

    ensure_dir "${dir}"

    case "${target}" in
        msys|mingw|gitbash|cygwin) printf '%s\n' "${dir}/${name}.exe" ;;
        *)                         printf '%s\n' "${dir}/${name}" ;;
    esac

}
pkg_install_binary_file () {

    local target="${1-}" name="${2-}" src="${3-}" dest=""

    [[ -n "${target}" && -n "${name}" && -n "${src}" ]] || return 1
    [[ -f "${src}" ]] || return 1

    dest="$(pkg_direct_bin_path "${name}" "${target}")"

    run mv -f "${src}" "${dest}" || return 1
    run chmod +x "${dest}" || return 1

    case "${target}" in
        msys|mingw|gitbash|cygwin)
            pkg_write_exec_alias "${name}" "${dest}" || true
        ;;
    esac

    pkg_activate_user_bin
    return 0

}
pkg_unpack_zip_binary () {

    local archive="${1-}" name="${2-}" out="${3-}" archive_win="" out_win="" found=""

    [[ -n "${archive}" && -n "${name}" && -n "${out}" ]] || return 1

    if has unzip; then
        run unzip -o -qq "${archive}" -d "${out}" || return 1
    elif has powershell.exe; then
        archive_win="${archive}"
        out_win="${out}"

        if has cygpath; then
            archive_win="$(cygpath -w "${archive}" 2>/dev/null || printf '%s' "${archive}")"
            out_win="$(cygpath -w "${out}" 2>/dev/null || printf '%s' "${out}")"
        fi

        run powershell.exe -NoProfile -NonInteractive -Command \
            "Expand-Archive -Force -LiteralPath '${archive_win}' -DestinationPath '${out_win}'" || return 1
    else
        return 1
    fi

    if [[ -f "${out}/${name}.exe" ]]; then printf '%s\n' "${out}/${name}.exe"; return 0; fi
    if [[ -f "${out}/${name}" ]]; then printf '%s\n' "${out}/${name}"; return 0; fi

    found="$(find "${out}" -type f \( -name "${name}" -o -name "${name}.exe" \) 2>/dev/null | head -n1 || true)"
    [[ -n "${found}" && -f "${found}" ]] || return 1

    printf '%s\n' "${found}"
    return 0

}
pkg_unpack_tar_binary () {

    local archive="${1-}" name="${2-}" out="${3-}" found=""

    [[ -n "${archive}" && -n "${name}" && -n "${out}" ]] || return 1

    run tar -xzf "${archive}" -C "${out}" || return 1

    if [[ -f "${out}/${name}" ]]; then printf '%s\n' "${out}/${name}"; return 0; fi
    if [[ -f "${out}/${name}.exe" ]]; then printf '%s\n' "${out}/${name}.exe"; return 0; fi

    found="$(find "${out}" -type f \( -name "${name}" -o -name "${name}.exe" \) 2>/dev/null | head -n1 || true)"
    [[ -n "${found}" && -f "${found}" ]] || return 1

    printf '%s\n' "${found}"
    return 0

}
pkg_install_github_binary_release () {

    local target="${1-}" repo="${2-}" url="${3-}" name="${4-}" format="${5-}"
    local tmp="" archive="" bin=""

    [[ -n "${target}" && -n "${repo}" && -n "${url}" && -n "${name}" && -n "${format}" ]] || return 1

    tmp="$(mktemp -d 2>/dev/null || mktemp -d -t pkgbin)" || return 1
    archive="${tmp}/archive.${format}"

    pkg_fetch_url "${url}" "${archive}" || { run rm -rf "${tmp}" >/dev/null 2>&1 || true; return 1; }

    case "${format}" in
        zip)
            bin="$(pkg_unpack_zip_binary "${archive}" "${name}" "${tmp}" 2>/dev/null || true)"
        ;;
        tar.gz)
            bin="$(pkg_unpack_tar_binary "${archive}" "${name}" "${tmp}" 2>/dev/null || true)"
        ;;
        gz)
            bin="${tmp}/${name}"

            if has gzip; then
                run gzip -dc "${archive}" > "${bin}" || { run rm -rf "${tmp}" >/dev/null 2>&1 || true; return 1; }
            elif has gunzip; then
                run gunzip -c "${archive}" > "${bin}" || { run rm -rf "${tmp}" >/dev/null 2>&1 || true; return 1; }
            elif has python3; then
                run python3 -c 'import gzip,sys; sys.stdout.buffer.write(gzip.open(sys.argv[1], "rb").read())' "${archive}" > "${bin}" || { run rm -rf "${tmp}" >/dev/null 2>&1 || true; return 1; }
            else
                run rm -rf "${tmp}" >/dev/null 2>&1 || true
                return 1
            fi
        ;;
        *)
            run rm -rf "${tmp}" >/dev/null 2>&1 || true
            return 1
        ;;
    esac

    [[ -n "${bin}" && -f "${bin}" ]] || { run rm -rf "${tmp}" >/dev/null 2>&1 || true; return 1; }

    pkg_install_binary_file "${target}" "${name}" "${bin}" || { run rm -rf "${tmp}" >/dev/null 2>&1 || true; return 1; }

    run rm -rf "${tmp}" >/dev/null 2>&1 || true
    return 0

}

pkg_special_install_kill () {

    command -v kill >/dev/null 2>&1

}
pkg_special_install_trivy () {

    local target="${1-}" backend="${2-}" bin_dir="" url="" asset_re=""

    pkg_verify_one "${target}" "trivy" && return 0

    case "${target}" in
        macos)
            if [[ "${backend}" == "brew" ]]; then
                pkg_install_brew "trivy" || return 1
                return 0
            fi
        ;;
        linux)
            pkg_ensure_fetcher "${target}" "${backend}" || return 1
            bin_dir="$(pkg_user_bin_dir)"
            ensure_dir "${bin_dir}"

            if has curl; then
                run sh -c 'curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b "'"${bin_dir}"'"' || return 1
                return 0
            fi
            if has wget; then
                run sh -c 'wget -qO- https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b "'"${bin_dir}"'"' || return 1
                return 0
            fi
        ;;
        msys|mingw|gitbash|cygwin)
            if pkg_has_any winget winget.exe; then pkg_install_winget "AquaSecurity.Trivy" && return 0; fi
            if pkg_has_any choco choco.exe;   then pkg_install_choco "trivy" && return 0; fi

            pkg_ensure_fetcher "${target}" "${backend}" || return 1

            case "$(pkg_cpu_arch)" in
                amd64) asset_re='trivy_[^/]*_Windows-64bit\.zip' ;;
                arm64) asset_re='trivy_[^/]*_Windows-ARM64\.zip' ;;
                386)   asset_re='trivy_[^/]*_Windows-32bit\.zip' ;;
                *) return 1 ;;
            esac

            url="$(pkg_github_release_asset_url "aquasecurity/trivy" "${asset_re}")" || return 1
            pkg_install_github_binary_release "${target}" "aquasecurity/trivy" "${url}" "trivy" "zip" || return 1
            return 0
        ;;
    esac

    return 1

}
pkg_special_install_syft () {

    local target="${1-}" backend="${2-}" bin_dir="" os="" arch="" url="" format="" asset_re=""

    pkg_verify_one "${target}" "syft" && return 0

    case "${target}" in
        macos)
            if [[ "${backend}" == "brew" ]]; then
                pkg_install_brew "syft" || return 1
                return 0
            fi
        ;;
        linux)
            pkg_ensure_fetcher "${target}" "${backend}" || return 1
            bin_dir="$(pkg_user_bin_dir)"
            ensure_dir "${bin_dir}"

            if has curl; then
                run sh -c 'curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b "'"${bin_dir}"'"' || return 1
                return 0
            fi
            if has wget; then
                run sh -c 'wget -qO- https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b "'"${bin_dir}"'"' || return 1
                return 0
            fi
        ;;
        msys|mingw|gitbash|cygwin)
            if pkg_has_any winget winget.exe; then pkg_install_winget "Anchore.Syft" && return 0; fi
            if pkg_has_any choco choco.exe;   then pkg_install_choco "syft" && return 0; fi
            if pkg_has_any scoop scoop.cmd;   then pkg_install_scoop "syft" && return 0; fi
        ;;
    esac

    pkg_ensure_fetcher "${target}" "${backend}" || return 1
    arch="$(pkg_cpu_arch)"

    case "${target}" in
        linux) os="linux"; format="tar.gz" ;;
        macos) os="darwin"; format="tar.gz" ;;
        msys|mingw|gitbash|cygwin) os="windows"; format="zip" ;;
        *) return 1 ;;
    esac

    case "${arch}" in
        amd64|arm64) ;;
        *) return 1 ;;
    esac

    asset_re="syft_[^/]*_${os}_${arch}\\.${format//./\\.}"
    url="$(pkg_github_release_asset_url "anchore/syft" "${asset_re}")" || return 1
    pkg_install_github_binary_release "${target}" "anchore/syft" "${url}" "syft" "${format}" || return 1
    return 0

}
pkg_special_install_gitleaks () {

    local target="${1-}" backend="${2-}" os="" arch="" url="" format="" asset_re=""

    pkg_verify_one "${target}" "gitleaks" && return 0

    case "${target}" in
        macos)
            if [[ "${backend}" == "brew" ]]; then
                pkg_install_brew "gitleaks" || return 1
                return 0
            fi
        ;;
        msys|mingw|gitbash|cygwin)
            if pkg_has_any winget winget.exe; then pkg_install_winget "Gitleaks.Gitleaks" && return 0; fi
            if pkg_has_any choco choco.exe;   then pkg_install_choco "gitleaks" && return 0; fi
            if pkg_has_any scoop scoop.cmd;   then pkg_install_scoop "gitleaks" && return 0; fi
        ;;
    esac

    pkg_ensure_fetcher "${target}" "${backend}" || return 1

    case "${target}" in
        linux) os="linux"; format="tar.gz" ;;
        macos) os="darwin"; format="tar.gz" ;;
        msys|mingw|gitbash|cygwin) os="windows"; format="zip" ;;
        *) return 1 ;;
    esac

    case "$(pkg_cpu_arch)" in
        amd64) arch="x64" ;;
        arm64) arch="arm64" ;;
        386)   arch="x32" ;;
        *) return 1 ;;
    esac

    asset_re="gitleaks_[^/]*_${os}_${arch}\\.${format//./\\.}"
    url="$(pkg_github_release_asset_url "gitleaks/gitleaks" "${asset_re}")" || return 1
    pkg_install_github_binary_release "${target}" "gitleaks/gitleaks" "${url}" "gitleaks" "${format}" || return 1
    return 0

}
pkg_special_install_taplo () {

    local target="${1-}" backend="${2-}" os="" arch="" format="" url="" asset_re=""

    pkg_verify_one "${target}" "taplo" && return 0

    case "${target}" in
        macos)
            if [[ "${backend}" == "brew" ]]; then
                pkg_install_brew "taplo" || return 1
                return 0
            fi
        ;;
        msys|mingw|gitbash|cygwin)
            if pkg_has_any winget winget.exe; then pkg_install_winget "tamasfe.taplo" && return 0; fi
            if pkg_has_any choco choco.exe;   then pkg_install_choco "taplo" && return 0; fi
        ;;
    esac

    pkg_ensure_fetcher "${target}" "${backend}" || return 1

    case "${target}" in
        linux) os="linux"; format="gz" ;;
        macos) os="darwin"; format="gz" ;;
        msys|mingw|gitbash|cygwin) os="windows"; format="zip" ;;
        *) return 1 ;;
    esac

    case "$(pkg_cpu_arch)" in
        amd64)   arch="x86_64" ;;
        arm64)   arch="aarch64" ;;
        386)     arch="x86" ;;
        armv7)   arch="armv7" ;;
        riscv64) arch="riscv64" ;;
        *) return 1 ;;
    esac

    asset_re="taplo-${os}-${arch}\\.${format//./\\.}"
    url="$(pkg_github_release_asset_url "tamasfe/taplo" "${asset_re}")" || return 1
    pkg_install_github_binary_release "${target}" "tamasfe/taplo" "${url}" "taplo" "${format}" || return 1
    return 0

}
pkg_special_install_typos () {

    local target="${1-}" backend="${2-}" triple="" url="" format="" asset_re=""

    pkg_verify_one "${target}" "typos" && return 0

    case "${target}" in
        macos)
            if [[ "${backend}" == "brew" ]]; then
                pkg_install_brew "typos-cli" || return 1
                return 0
            fi
        ;;
        msys|mingw|gitbash|cygwin)
            if pkg_has_any winget winget.exe; then pkg_install_winget "Crate-CI.Typos" && return 0; fi
            if pkg_has_any choco choco.exe;   then pkg_install_choco "typos" && return 0; fi
        ;;
    esac

    pkg_ensure_fetcher "${target}" "${backend}" || return 1

    case "${target}" in
        linux)
            format="tar.gz"
            case "$(pkg_cpu_arch)" in
                amd64) triple="x86_64-unknown-linux-musl" ;;
                arm64) triple="aarch64-unknown-linux-musl" ;;
                *) return 1 ;;
            esac
        ;;
        macos)
            format="tar.gz"
            case "$(pkg_cpu_arch)" in
                amd64) triple="x86_64-apple-darwin" ;;
                arm64) triple="aarch64-apple-darwin" ;;
                *) return 1 ;;
            esac
        ;;
        msys|mingw|gitbash|cygwin)
            format="zip"
            case "$(pkg_cpu_arch)" in
                amd64) triple="x86_64-pc-windows-msvc" ;;
                arm64) triple="aarch64-pc-windows-msvc" ;;
                386)   triple="i686-pc-windows-msvc" ;;
                *) return 1 ;;
            esac
        ;;
        *) return 1 ;;
    esac

    asset_re="typos-v[^/]*-${triple}\\.${format//./\\.}"
    url="$(pkg_github_release_asset_url "crate-ci/typos" "${asset_re}")" || return 1
    pkg_install_github_binary_release "${target}" "crate-ci/typos" "${url}" "typos" "${format}" || return 1
    return 0

}
pkg_special_install_gh () {

    local target="${1-}" backend="${2-}" os="" arch="" format="" url="" asset_re=""

    pkg_verify_one "${target}" "gh" && return 0

    case "${target}" in
        macos)
            if [[ "${backend}" == "brew" ]]; then
                pkg_install_brew "gh" || return 1
                return 0
            fi
        ;;
        msys|mingw|gitbash|cygwin)
            if pkg_has_any winget winget.exe; then pkg_install_winget "GitHub.cli" && return 0; fi
            if pkg_has_any choco choco.exe;   then pkg_install_choco "gh" && return 0; fi
            if pkg_has_any scoop scoop.cmd;   then pkg_install_scoop "gh" && return 0; fi
        ;;
    esac

    pkg_ensure_fetcher "${target}" "${backend}" || return 1

    case "${target}" in
        linux) os="linux"; format="tar.gz" ;;
        macos) os="macOS"; format="zip" ;;
        msys|mingw|gitbash|cygwin) os="windows"; format="zip" ;;
        *) return 1 ;;
    esac

    case "$(pkg_cpu_arch)" in
        amd64) arch="amd64" ;;
        arm64) arch="arm64" ;;
        386)   arch="386" ;;
        *) return 1 ;;
    esac

    asset_re="gh_[^/]*_${os}_${arch}\\.${format//./\\.}"
    url="$(pkg_github_release_asset_url "cli/cli" "${asset_re}")" || return 1
    pkg_install_github_binary_release "${target}" "cli/cli" "${url}" "gh" "${format}" || return 1
    return 0

}
pkg_special_install_missing () {

    local target="${1-}" backend="${2-}" want=""
    shift 2 || true

    for want in "$@"; do

        [[ -n "${want}" ]] || continue

        case "${want}" in
            kill)      pkg_special_install_kill || true ;;
            gh)        pkg_special_install_gh "${target}" "${backend}" || true ;;
            trivy)     pkg_special_install_trivy "${target}" "${backend}" || true ;;
            syft)      pkg_special_install_syft "${target}" "${backend}" || true ;;
            gitleaks)  pkg_special_install_gitleaks "${target}" "${backend}" || true ;;
            taplo)     pkg_special_install_taplo "${target}" "${backend}" || true ;;
            typos)     pkg_special_install_typos "${target}" "${backend}" || true ;;
        esac

    done

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
            tar)
                prefix="$(pkg_brew_prefix gnu-tar)"
                [[ -x "${prefix}/bin/gtar" ]] && pkg_brew_link "tar" "${prefix}/bin/gtar"
            ;;
            diff)
                prefix="$(pkg_brew_prefix diffutils)"
                [[ -x "${prefix}/bin/gdiff" ]] && pkg_brew_link "diff" "${prefix}/bin/gdiff"
            ;;
            7z)
                prefix="$(pkg_brew_prefix sevenzip)"
                [[ -x "${prefix}/bin/7zz" ]] && pkg_brew_link "7z" "${prefix}/bin/7zz"
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

    pkg_refresh_path
    pkg_hash_clear

    pkg_post_install_windows_msys2 "${target}" "${backend}" "$@"

    pkg_refresh_path
    pkg_hash_clear

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

    pkg_refresh_path
    pkg_hash_clear
    pkg_collect_missing missing "${target}" "${wants[@]}"

    if (( ${#missing[@]} == 0 )); then
        return 0
    fi

    backend="$(pkg_backend "${target}")" || backend=""
    [[ "${target}" == "mingw" && "${backend}" == "pacman" ]] && aux="$(pkg_mingw_prefix)"

    if (( ${#missing[@]} )) && [[ -n "${backend}" ]]; then
        pkg_special_install_missing "${target}" "${backend}" "${missing[@]}"
        pkg_post_install "${target}" "${backend}" "${wants[@]}"
        pkg_collect_missing missing "${target}" "${wants[@]}"
    fi
    if (( ${#missing[@]} == 0 )); then
        pkg_hash_clear
        return 0
    fi

    [[ -n "${backend}" ]] || die "pkg: no usable backend for target '${target}'."

    pkg_build_plan plan "${target}" "${backend}" "${aux}" "${missing[@]}"
    pkg_install "${target}" "${backend}" "${plan[@]}"

    pkg_post_install "${target}" "${backend}" "${wants[@]}"
    pkg_collect_missing missing "${target}" "${wants[@]}"

    (( ${#missing[@]} == 0 )) || die "pkg: failed to ensure tools: ${missing[*]}"
    return 0

}

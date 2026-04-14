#!/usr/bin/env bash
set -Eeuo pipefail

YES="${YES:-0}"
VERBOSE="${VERBOSE:-0}"

APP_NAME="gun"
APP_VERSION="0.1.0"
APP_BASH_VERSION="5.2"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)"

TEMPLATE_KEY="__TEMPLATE_PAYLOAD_KEY__"
TEMPLATE_DIR="${ROOT_DIR}/template"
MODULE_DIR="${ROOT_DIR}/module"

WORKSPACE_DIR="${WORKSPACE_DIR:-/var/www}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/mnt/d/Archive}"
SYNC_DIR="${SYNC_DIR:-/mnt/d}"
OUT_DIR="${OUT_DIR:-out}"

GIT_HTTP_USER="${GIT_HTTP_USER:-x-access-token}"
GIT_HOST="${GIT_HOST:-github.com}"
GIT_AUTH="${GIT_AUTH:-ssh}"
GIT_TOKEN="${GIT_TOKEN:-}"
GIT_SSH_KEY="${GIT_SSH_KEY:-}"

GH_HOST="${GH_HOST:-}"
GH_PROFILE="${GH_PROFILE:-}"

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
        linux)
            bash_try_pkg_linux || bash_try_pkg_brew
        ;;
        macos)
            bash_try_pkg_brew
        ;;
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

    local req="$(bash_ver_norm "${APP_BASH_VERSION:-5.2}")"
    local cur_ver="$(bash_current_version)"
    local os="$(bash_os_kind)"

    local -a reexec_argv=()
    reexec_argv=( "$@" )

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

    local best_bin="$(bash_find_best_candidate "${req}" || true)"
    [[ -n "${best_bin}" ]] || bash_die "ensure-bash: no bash >= ${req} found after install/upgrade" 2

    local best_ver="$(bash_version_from_bin "${best_bin}")"
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

    local prompt="${1-}" def="${2-}" tries="${3:-3}" def_norm="" v="" i=0

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

    local root="" dir="" up=0 max_up=50

    command -v git >/dev/null 2>&1 && root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "${root}" && -d "${root}" ]] && { cd -P -- "${root}" || return 1; return 0; }

    dir="$(pwd -P 2>/dev/null || true)"
    [[ -n "${dir}" ]] || { eprint "cd_root: cannot resolve PWD"; return 2; }

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

    eprint "cd_root: cannot detect root"
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

parse_require_bash () {

    [[ -n "${BASH_VERSINFO[0]-}" ]] || die "parse: bash required" 2
    (( ${BASH_VERSINFO[0]:-0} >= 5 )) || die "parse: requires bash >= 5" 2
    return 0

}
parse_norm_key () {

    local k="${1-}"

    k="${k#--}"
    k="${k#-}"
    k="${k//-/_}"

    [[ -n "${k}" ]] || die "parse: empty key" 2
    [[ "${k}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die "parse: invalid key '${k}'" 2

    printf '%s' "${k}"
    return 0

}
parse_try_norm_key () {

    local k="${1-}"

    k="${k#--}"
    k="${k#-}"
    k="${k//-/_}"

    [[ -n "${k}" ]] || return 1
    [[ "${k}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    printf '%s' "${k}"
    return 0

}
parse_is_schema_token () {

    local s="${1-}"
    local re='^:?(--|-)?[a-zA-Z_][a-zA-Z0-9_-]*(\|(--|-)?[a-zA-Z_][a-zA-Z0-9_-]*)*(:(int|float|str|char|bool|list|any))?([=].*)?$'

    [[ "${s}" =~ ${re} ]]

}
parse_is_int () {

    [[ "${1-}" =~ ^[+-]?[0-9]+$ ]]

}
parse_is_float () {

    [[ "${1-}" =~ ^[+-]?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]

}
parse_is_neg_number_token () {

    local v="${1-}"

    [[ "${v}" =~ ^-[0-9]+$ ]] && return 0
    [[ "${v}" =~ ^-[0-9]+[.][0-9]+$ ]] && return 0
    [[ "${v}" =~ ^-[.][0-9]+$ ]] && return 0

    return 1

}
parse_is_option_like () {

    local v="${1-}"

    [[ "${v}" == "--" ]] && return 1
    [[ "${v}" == --* ]] && return 0
    [[ "${v}" == -* && "${v}" != "-" ]] && return 0

    return 1

}
parse_args__is_known_opt_token () {

    local tok="${1-}" key="" kn="" k=""
    local -n __alias_to="${2}"
    local -n __stype="${3}"

    case "${tok}" in
        --no-*|-no-*)
            key="${tok#--no-}"
            key="${key#-no-}"

            kn="$(parse_try_norm_key "${key}" || true)"
            [[ -n "${kn}" ]] || return 1

            k="${__alias_to[${kn}]-}"
            [[ -n "${k}" ]] || return 1
            [[ "${__stype[${k}]-}" == "bool" ]] || return 1

            return 0
        ;;
        --*=*|-*=*)
            key="${tok%%=*}"
            key="${key#--}"
            key="${key#-}"

            kn="$(parse_try_norm_key "${key}" || true)"
            [[ -n "${kn}" ]] || return 1

            k="${__alias_to[${kn}]-}"
            [[ -n "${k}" ]] || return 1

            return 0
        ;;
        --*|-*)
            [[ "${tok}" == "-" || "${tok}" == "--" ]] && return 1

            key="${tok#--}"
            key="${key#-}"

            kn="$(parse_try_norm_key "${key}" || true)"
            [[ -n "${kn}" ]] || return 1

            k="${__alias_to[${kn}]-}"
            [[ -n "${k}" ]] || return 1

            return 0
        ;;
    esac

    return 1

}
parse_int_norm () {

    local v="${1-}" label="${2-int}"

    [[ -n "${v}" ]] || die "parse: '${label}' must be an integer" 2
    parse_is_int "${v}" && { printf '%s' "${v}"; return 0; }

    if [[ "${v}" =~ ^([+-]?[0-9]+)[.](0+)$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    die "parse: '${label}' must be an integer" 2

}
parse_bool_norm () {

    local v="${1-}" label="${2-bool}"

    [[ -n "${v}" ]] || die "parse: '${label}' must be 'true' or 'false' (or 1/0)" 2
    v="${v,,}"

    case "${v}" in
        1|true|yes|y|on|t)  printf '1' ;;
        0|false|no|n|off|f) printf '0' ;;
        *) die "parse: '${label}' must be 'true' or 'false' (or 1/0)" 2 ;;
    esac

    return 0

}
parse_set_scalar () {

    local __p_key="${1-}" __p_val="${2-}"
    printf -v "${__p_key}" '%s' "${__p_val}"
    return 0

}
parse_set_array () {

    local __p_key="${1-}"
    shift || true

    local -n __p_ref="${__p_key}"
    __p_ref=()

    (( $# )) && __p_ref+=( "$@" )

    return 0

}
parse_array_append () {

    local __p_key="${1-}" __p_val="${2-}"

    local -n __p_ref="${__p_key}"
    __p_ref+=( "${__p_val}" )

    return 0

}
parse_args_split () {

    local -n out_argv="${1}"
    local -n out_schema="${2}"
    shift 2 || true

    out_argv=()
    out_schema=()

    local -a all=( "$@" )
    local sep=-1
    local i=0

    for (( i=${#all[@]}-1; i>=0; i-- )); do
        if [[ "${all[$i]}" == "--" ]]; then
            sep=$i
            break
        fi
    done

    (( sep >= 0 )) || die "parse: missing '--' separator" 2

    out_argv=( "${all[@]:0:$sep}" )
    out_schema=( "${all[@]:$(( sep + 1 ))}" )

    (( ${#out_schema[@]} )) || die "parse: missing schema" 2

    return 0

}
parse_emit_scalar () {

    local scope="${1-}" name="${2-}" value="${3-}"

    if [[ "${scope}" == "local" ]]; then
        printf 'local %s=%q\n' "${name}" "${value}"
        return 0
    fi

    printf '%s=%q\n' "${name}" "${value}"
    return 0

}
parse_emit_array () {

    local scope="${1-}" name="${2-}" x=""
    shift 2 || true

    if [[ "${scope}" == "local" ]]; then

        if (( $# == 0 )); then
            printf 'local -a %s=()\n' "${name}"
            return 0
        fi

        printf 'local -a %s=(' "${name}"
        for x in "$@"; do printf ' %q' "${x}"; done

        printf ' )\n'
        return 0

    fi
    if (( $# == 0 )); then
        printf '%s=()\n' "${name}"
        return 0
    fi

    printf '%s=(' "${name}"
    for x in "$@"; do printf ' %q' "${x}"; done

    printf ' )\n'
    return 0

}
parse_is_reserved_key () {

    local k="${1-}"

    case "${k}" in
        ""|kwargs|stype|sreq|sdef|sdef_has|set|alias_to|sdisp|order|pos_order|auto_order|auto_has_opt) return 0 ;;
    esac

    return 1

}
parse_args__schema_build () {

    local -n __schema="${1}"
    local -n __stype="${2}"
    local -n __sreq="${3}"
    local -n __sdef="${4}"
    local -n __sdef_has="${5}"
    local -n __alias_to="${6}"
    local -n __sdisp="${7}"
    local -n __order="${8}"
    local -n __pos_order="${9}"
    local -n __auto_order="${10}"
    local -n __auto_has_opt="${11}"
    local -n __kwargs_req="${12}"
    local -n __have_kwargs_schema="${13}"

    local spec="" raw="" names="" canon="" nk="" kind="" t=""
    local def_raw="" def_has=0
    local req=0

    local -a name_list=()
    local nm="" ak=""

    __kwargs_req=0
    __have_kwargs_schema=0

    for spec in "${__schema[@]}"; do

        parse_is_schema_token "${spec}" || die "parse: bad schema token '${spec}'" 2

        raw="${spec}"
        req=0
        def_has=0
        def_raw=""

        if [[ "${raw}" == :* ]]; then
            req=1
            raw="${raw#:}"
        fi
        if [[ "${raw}" == *"="* ]]; then
            def_raw="${raw#*=}"
            raw="${raw%%=*}"
            def_has=1
        fi

        if [[ "${raw}" == *:* ]]; then
            t="${raw##*:}"
            names="${raw%:*}"
        else
            t="__auto__"
            names="${raw}"
        fi

        name_list=()
        IFS='|' read -r -a name_list <<< "${names}"
        (( ${#name_list[@]} )) || die "parse: bad schema '${spec}'" 2

        canon="${name_list[0]}"
        [[ "${canon}" != --no-* && "${canon}" != -no-* ]] || die "parse: schema name '${canon}' is reserved (no- prefix)" 2

        nk="$(parse_norm_key "${canon}")"
        [[ "${nk}" != __* ]] || die "parse: key '${canon}' is reserved (internal prefix)" 2

        if [[ "${nk}" == "kwargs" ]]; then

            [[ "${canon}" != --* && "${canon}" != -* ]] || die "parse: kwargs must be positional (no -/-- prefix)" 2
            (( ${#name_list[@]} == 1 )) || die "parse: kwargs must not have aliases" 2
            (( def_has )) && die "parse: kwargs does not support default value" 2

            __have_kwargs_schema=1
            __kwargs_req="${req}"

            continue

        fi

        parse_is_reserved_key "${nk}" && die "parse: key '${canon}' is reserved" 2

        if [[ "${t}" == "__auto__" ]]; then

            local has_opt=0
            for nm in "${name_list[@]-}"; do
                if [[ "${nm}" == --* || "${nm}" == -* ]]; then
                    has_opt=1
                    break
                fi
            done

            __auto_order+=( "${nk}" )
            __auto_has_opt["${nk}"]="${has_opt}"

        fi

        case "${t}" in
            __auto__|int|float|str|char|bool|list|any) ;;
            *) die "parse: unknown type '${t}' for '${spec}'" 2 ;;
        esac

        [[ -z "${__stype[${nk}]-}" ]] || die "parse: duplicate name '${nk}'" 2

        __stype["${nk}"]="${t}"
        __sreq["${nk}"]="${req}"
        __sdisp["${nk}"]="${canon}"

        if (( def_has )); then
            __sdef["${nk}"]="${def_raw}"
            __sdef_has["${nk}"]=1
        fi

        __order+=( "${nk}" )

        kind="pos"
        if [[ "${canon}" == --* ]]; then kind="long"
        elif [[ "${canon}" == -* ]]; then kind="short"
        fi

        [[ "${kind}" == "pos" ]] && __pos_order+=( "${nk}" )

        for nm in "${name_list[@]-}"; do

            [[ "${nm}" != --no-* && "${nm}" != -no-* ]] || die "parse: schema alias '${nm}' is reserved (no- prefix)" 2

            ak="$(parse_norm_key "${nm}")"

            if [[ -n "${__alias_to[${ak}]-}" ]]; then
                [[ "${__alias_to[${ak}]}" == "${nk}" ]] || die "parse: duplicate alias '${nm}'" 2
                continue
            fi

            __alias_to["${ak}"]="${nk}"

        done

    done

    __stype["kwargs"]="list"
    __sdisp["kwargs"]="kwargs"
    __sreq["kwargs"]="${__kwargs_req}"

    return 0

}
parse_args__infer_auto_types () {

    local -n __argv="${1}"
    local -n __auto_order="${2}"
    local -n __auto_has_opt="${3}"
    local -n __alias_to="${4}"
    local -n __stype="${5}"

    (( ${#__auto_order[@]} )) || return 0

    local -A auto_has_value=()
    local -A auto_no_value=()
    local ai=0 arg2="" key2="" kn2="" kk="" nxt=""

    while (( ai < ${#__argv[@]} )); do

        arg2="${__argv[$ai]}"
        ai=$(( ai + 1 ))

        [[ "${arg2}" == "--" ]] && break

        case "${arg2}" in
            --no-*|-no-*)
                key2="${arg2#--no-}"
                key2="${key2#-no-}"

                kn2="$(parse_try_norm_key "${key2}" || true)"
                [[ -n "${kn2}" ]] || continue

                kk="${__alias_to[${kn2}]-}"
                [[ -n "${kk}" ]] || continue
                [[ "${__stype[${kk}]-}" == "__auto__" ]] || continue

                auto_no_value["${kk}"]=1
            ;;
            --*=*|-*=*)
                key2="${arg2%%=*}"

                if [[ "${key2}" == --* ]]; then key2="${key2#--}"
                else key2="${key2#-}"
                fi

                kn2="$(parse_try_norm_key "${key2}" || true)"
                [[ -n "${kn2}" ]] || continue

                kk="${__alias_to[${kn2}]-}"
                [[ -n "${kk}" ]] || continue
                [[ "${__stype[${kk}]-}" == "__auto__" ]] || continue

                auto_has_value["${kk}"]=1
            ;;
            --*|-*)
                key2="${arg2#--}"
                key2="${key2#-}"

                kn2="$(parse_try_norm_key "${key2}" || true)"
                [[ -n "${kn2}" ]] || continue

                kk="${__alias_to[${kn2}]-}"
                [[ -n "${kk}" ]] || continue
                [[ "${__stype[${kk}]-}" == "__auto__" ]] || continue

                if (( ai < ${#__argv[@]} )); then
                    nxt="${__argv[$ai]}"

                    if [[ "${nxt}" != "--" ]] && { ! parse_is_option_like "${nxt}" || parse_is_neg_number_token "${nxt}"; }; then auto_has_value["${kk}"]=1
                    else auto_no_value["${kk}"]=1
                    fi
                else
                    auto_no_value["${kk}"]=1
                fi
            ;;
        esac

    done

    local akey=""
    for akey in "${__auto_order[@]-}"; do

        if [[ -n "${auto_has_value[${akey}]-}" && -n "${auto_no_value[${akey}]-}" ]]; then
            __stype["${akey}"]="any"
            continue
        fi
        if [[ -n "${auto_has_value[${akey}]-}" ]]; then
            __stype["${akey}"]="str"
            continue
        fi
        if [[ -n "${auto_no_value[${akey}]-}" ]]; then
            __stype["${akey}"]="bool"
            continue
        fi

        if (( ${__auto_has_opt[${akey}]-0} )); then __stype["${akey}"]="bool"
        else __stype["${akey}"]="str"
        fi

    done

    return 0

}
parse_args__init_values () {

    local -n __order="${1}"
    local -n __stype="${2}"

    local n="" tv=""
    for n in "${__order[@]}"; do

        tv="${__stype[${n}]}"
        case "${tv}" in
            int)   parse_set_scalar "${n}" "0" ;;
            float) parse_set_scalar "${n}" "0.0" ;;
            bool)  parse_set_scalar "${n}" "0" ;;
            list)  parse_set_array  "${n}" ;;
            char|str|any) parse_set_scalar "${n}" "" ;;
        esac

    done

    parse_set_array kwargs
    return 0

}
parse_args__parse_argv () {

    local -n __argv="${1}"
    local -n __pos_order="${2}"
    local -n __stype="${3}"
    local -n __alias_to="${4}"
    local -n __sdisp="${5}"
    local -n __set="${6}"

    local raw_mode=0 pos_i=0 pos_list=""
    local i=0 arg="" key="" val="" next="" k="" knorm="" tv=""

    while (( i < ${#__argv[@]} )); do

        arg="${__argv[$i]}"
        i=$(( i + 1 ))

        if (( raw_mode )); then
            parse_array_append kwargs "${arg}"
            continue
        fi
        if [[ "${arg}" == "--" ]]; then

            parse_array_append kwargs "${arg}"

            while (( i < ${#__argv[@]} )); do
                parse_array_append kwargs "${__argv[$i]}"
                i=$(( i + 1 ))
            done

            raw_mode=1
            break

        fi
        if [[ -n "${pos_list}" ]]; then

            if [[ "${arg}" == "--" ]]; then

                parse_array_append kwargs "${arg}"

                while (( i < ${#__argv[@]} )); do
                    parse_array_append kwargs "${__argv[$i]}"
                    i=$(( i + 1 ))
                done

                raw_mode=1
                break
            fi
            if parse_is_neg_number_token "${arg}"; then
                parse_array_append "${pos_list}" "${arg}"
                __set["${pos_list}"]=1
                continue
            fi

            if parse_is_option_like "${arg}" && parse_args__is_known_opt_token "${arg}" "${!__alias_to}" "${!__stype}"; then
                :
            else
                parse_array_append "${pos_list}" "${arg}"
                __set["${pos_list}"]=1
                continue
            fi

        fi
        if [[ "${arg}" == "-" ]]; then

            parse_array_append kwargs "${arg}"
            continue

        fi
        if [[ "${arg}" =~ ^-[0-9] || "${arg}" =~ ^-\.[0-9] ]]; then

            local assigned=0
            while (( pos_i < ${#__pos_order[@]} )); do

                local pn="${__pos_order[$pos_i]}"
                [[ -n "${__set[${pn}]-}" ]] && { pos_i=$(( pos_i + 1 )); continue; }

                tv="${__stype[${pn}]}"
                if [[ "${tv}" == "list" ]]; then
                    pos_list="${pn}"
                    parse_array_append "${pn}" "${arg}"
                    __set["${pn}"]=1
                    assigned=1
                    break
                fi

                case "${tv}" in
                    int)   arg="$(parse_int_norm "${arg}" "${__sdisp[${pn}]}" )" ;;
                    float) parse_is_float "${arg}" || die "parse: '${__sdisp[${pn}]}' must be a float number" 2 ;;
                    bool)  arg="$(parse_bool_norm "${arg}" "${__sdisp[${pn}]}" )" ;;
                    char)  [[ "${#arg}" -eq 1 ]] || die "parse: '${__sdisp[${pn}]}' must be exactly 1 character" 2 ;;
                esac

                parse_set_scalar "${pn}" "${arg}"
                __set["${pn}"]=1
                pos_i=$(( pos_i + 1 ))
                assigned=1
                break

            done

            (( assigned )) || parse_array_append kwargs "${arg}"
            continue

        fi

        case "${arg}" in
            --no-*|-no-*)
                key="${arg#--no-}"
                key="${key#-no-}"

                knorm="$(parse_try_norm_key "${key}" || true)"
                k=""

                [[ -n "${knorm}" ]] && k="${__alias_to[${knorm}]-}"

                if [[ -n "${k}" && "${__stype[${k}]}" == "bool" ]]; then
                    parse_set_scalar "${k}" "0"
                    __set["${k}"]=1
                else
                    parse_array_append kwargs "${arg}"
                fi

                continue
            ;;
            --*=*|-*=*)
                key="${arg%%=*}"
                val="${arg#*=}"

                if [[ "${key}" == --* ]]; then key="${key#--}"
                else key="${key#-}"
                fi

                knorm="$(parse_try_norm_key "${key}" || true)"
                k=""

                [[ -n "${knorm}" ]] && k="${__alias_to[${knorm}]-}"

                if [[ -z "${k}" ]]; then
                    parse_array_append kwargs "${arg}"
                    continue
                fi

                tv="${__stype[${k}]}"
                if [[ "${tv}" == "bool" ]]; then
                    val="$(parse_bool_norm "${val}" "${__sdisp[${k}]}" )"
                    parse_set_scalar "${k}" "${val}"
                elif [[ "${tv}" == "int" ]]; then
                    val="$(parse_int_norm "${val}" "${__sdisp[${k}]}" )"
                    parse_set_scalar "${k}" "${val}"
                elif [[ "${tv}" == "float" ]]; then
                    parse_is_float "${val}" || die "parse: '${__sdisp[${k}]}' must be a float number" 2
                    parse_set_scalar "${k}" "${val}"
                elif [[ "${tv}" == "char" ]]; then
                    [[ "${#val}" -eq 1 ]] || die "parse: '${__sdisp[${k}]}' must be exactly 1 character" 2
                    parse_set_scalar "${k}" "${val}"
                elif [[ "${tv}" == "list" ]]; then
                    parse_array_append "${k}" "${val}"

                    while (( i < ${#__argv[@]} )); do

                        next="${__argv[$i]}"

                        [[ "${next}" == "--" ]] && break

                        if parse_is_neg_number_token "${next}"; then
                            parse_array_append "${k}" "${next}"
                            i=$(( i + 1 ))
                            continue
                        fi
                        if parse_is_option_like "${next}" && parse_args__is_known_opt_token "${next}" "${!__alias_to}" "${!__stype}"; then
                            break
                        fi

                        parse_array_append "${k}" "${next}"
                        i=$(( i + 1 ))

                    done

                else
                    parse_set_scalar "${k}" "${val}"
                fi

                __set["${k}"]=1
                continue
            ;;
            --*|-*)
                if [[ "${arg}" == --* ]]; then key="${arg#--}"
                else key="${arg#-}"
                fi

                knorm="$(parse_try_norm_key "${key}" || true)"
                k=""

                [[ -n "${knorm}" ]] && k="${__alias_to[${knorm}]-}"

                if [[ -z "${k}" ]]; then

                    parse_array_append kwargs "${arg}"

                    if (( i < ${#__argv[@]} )); then
                        next="${__argv[$i]}"

                        if [[ "${next}" != "--" ]] && { ! parse_is_option_like "${next}" || parse_is_neg_number_token "${next}"; }; then
                            parse_array_append kwargs "${next}"
                            i=$(( i + 1 ))
                        fi
                    fi

                    continue

                fi

                tv="${__stype[${k}]}"

                if [[ "${tv}" == "bool" ]]; then

                    if (( i < ${#__argv[@]} )) && [[ "${__argv[$i]}" != "--" ]] && { ! parse_is_option_like "${__argv[$i]}" || parse_is_neg_number_token "${__argv[$i]}"; }; then
                        val="$(parse_bool_norm "${__argv[$i]}" "${__sdisp[${k}]}" )"
                        parse_set_scalar "${k}" "${val}"
                        i=$(( i + 1 ))
                    else
                        parse_set_scalar "${k}" "1"
                    fi

                    __set["${k}"]=1
                    continue

                fi

                if [[ "${tv}" == "any" ]]; then

                    if (( i < ${#__argv[@]} )) && [[ "${__argv[$i]}" != "--" ]] && { ! parse_is_option_like "${__argv[$i]}" || parse_is_neg_number_token "${__argv[$i]}"; }; then
                        parse_set_scalar "${k}" "${__argv[$i]}"
                        i=$(( i + 1 ))
                    else
                        parse_set_scalar "${k}" "1"
                    fi

                    __set["${k}"]=1
                    continue

                fi

                if [[ "${tv}" == "list" ]]; then

                    local consumed=0

                    while (( i < ${#__argv[@]} )); do

                        next="${__argv[$i]}"

                        [[ "${next}" == "--" ]] && break

                        if parse_is_neg_number_token "${next}"; then
                            parse_array_append "${k}" "${next}"
                            i=$(( i + 1 ))
                            consumed=1
                            continue
                        fi
                        if parse_is_option_like "${next}" && parse_args__is_known_opt_token "${next}" "${!__alias_to}" "${!__stype}"; then
                            break
                        fi

                        parse_array_append "${k}" "${next}"
                        i=$(( i + 1 ))
                        consumed=1

                    done

                    (( consumed )) || die "parse: '${arg}' expects a value" 2

                    __set["${k}"]=1
                    continue

                fi

                (( i < ${#__argv[@]} )) || die "parse: '${arg}' expects a value" 2
                next="${__argv[$i]}"

                if [[ "${next}" == "--" ]]; then
                    die "parse: '${arg}' expects a value" 2
                fi
                if parse_is_option_like "${next}"; then

                    if [[ "${tv}" == "int" || "${tv}" == "float" ]] && parse_is_neg_number_token "${next}"; then :
                    else die "parse: '${arg}' expects a value (use ${arg}=VALUE for values starting with '-')" 2
                    fi

                fi

                i=$(( i + 1 ))

                if [[ "${tv}" == "int" ]]; then next="$(parse_int_norm "${next}" "${__sdisp[${k}]}" )"
                elif [[ "${tv}" == "float" ]]; then parse_is_float "${next}" || die "parse: '${__sdisp[${k}]}' must be a float number" 2
                elif [[ "${tv}" == "char" ]]; then [[ "${#next}" -eq 1 ]] || die "parse: '${__sdisp[${k}]}' must be exactly 1 character" 2
                fi

                if [[ "${tv}" == "list" ]]; then parse_array_append "${k}" "${next}"
                else parse_set_scalar "${k}" "${next}"
                fi

                __set["${k}"]=1
                continue
            ;;
        esac

        local assigned=0
        while (( pos_i < ${#__pos_order[@]} )); do

            local pn="${__pos_order[$pos_i]}"
            [[ -n "${__set[${pn}]-}" ]] && { pos_i=$(( pos_i + 1 )); continue; }

            tv="${__stype[${pn}]}"
            if [[ "${tv}" == "list" ]]; then
                pos_list="${pn}"
                parse_array_append "${pn}" "${arg}"
                __set["${pn}"]=1
                assigned=1
                break
            fi

            case "${tv}" in
                int)   arg="$(parse_int_norm "${arg}" "${__sdisp[${pn}]}" )" ;;
                float) parse_is_float "${arg}" || die "parse: '${__sdisp[${pn}]}' must be a float number" 2 ;;
                bool)  arg="$(parse_bool_norm "${arg}" "${__sdisp[${pn}]}" )" ;;
                char)  [[ "${#arg}" -eq 1 ]] || die "parse: '${__sdisp[${pn}]}' must be exactly 1 character" 2 ;;
            esac

            parse_set_scalar "${pn}" "${arg}"
            __set["${pn}"]=1
            pos_i=$(( pos_i + 1 ))
            assigned=1
            break

        done

        (( assigned )) || parse_array_append kwargs "${arg}"

    done

    return 0

}
parse_args__apply_defaults () {

    local -n __order="${1}"
    local -n __stype="${2}"
    local -n __sdef="${3}"
    local -n __sdef_has="${4}"
    local -n __sdisp="${5}"
    local -n __set="${6}"

    local n="" tv="" def_raw=""
    for n in "${__order[@]}"; do

        [[ -n "${__set[${n}]-}" ]] && continue
        [[ -n "${__sdef_has[${n}]-}" ]] || continue

        tv="${__stype[${n}]}"
        def_raw="${__sdef[${n}]-}"

        case "${tv}" in
            int)
                def_raw="$(parse_int_norm "${def_raw}" "${__sdisp[${n}]}" )"
                parse_set_scalar "${n}" "${def_raw}"
            ;;
            float)
                parse_is_float "${def_raw}" || die "parse: '${__sdisp[${n}]}' default must be a float number" 2
                parse_set_scalar "${n}" "${def_raw}"
            ;;
            bool)
                def_raw="$(parse_bool_norm "${def_raw}" "${__sdisp[${n}]}" )"
                parse_set_scalar "${n}" "${def_raw}"
            ;;
            char)
                [[ "${#def_raw}" -eq 1 ]] || die "parse: '${__sdisp[${n}]}' default must be exactly 1 character" 2
                parse_set_scalar "${n}" "${def_raw}"
            ;;
            list)
                if [[ -z "${def_raw}" ]]; then
                    parse_set_array "${n}"
                else
                    local -a parts=()
                    IFS=',' read -r -a parts <<< "${def_raw}"
                    parse_set_array "${n}" "${parts[@]-}"
                fi
            ;;
            str|any)
                parse_set_scalar "${n}" "${def_raw}"
            ;;
        esac

        __set["${n}"]=1

    done

    return 0

}
parse_args__validate_and_normalize () {

    local scope="${1-}"
    local -n __order="${2}"
    local -n __stype="${3}"
    local -n __sreq="${4}"
    local -n __sdisp="${5}"
    local -n __set="${6}"

    if (( __sreq[kwargs] )); then
        local -n __r_kwargs="kwargs"
        (( ${#__r_kwargs[@]} )) || die "parse: missing required 'kwargs'" 2
        __set["kwargs"]=1
    fi

    local n="" tv="" vv=""
    for n in "${__order[@]}"; do

        tv="${__stype[${n}]}"

        if (( __sreq[n] )); then
            [[ -n "${__set[${n}]-}" ]] || die "parse: missing required '${__sdisp[${n}]}'" 2
        fi

        [[ -n "${__set[${n}]-}" ]] || continue

        case "${tv}" in
            int)
                parse_set_scalar "${n}" "$(parse_int_norm "${!n-}" "${__sdisp[${n}]}" )"
            ;;
            float)
                parse_is_float "${!n-}" || die "parse: '${__sdisp[${n}]}' must be a float number" 2
            ;;
            bool)
                parse_set_scalar "${n}" "$(parse_bool_norm "${!n-}" "${__sdisp[${n}]}" )"
            ;;
            char)
                vv="${!n-}"
                if (( __sreq[n] )); then
                    [[ "${#vv}" -eq 1 ]] || die "parse: '${__sdisp[${n}]}' must be exactly 1 character" 2
                else
                    [[ -z "${vv}" || "${#vv}" -eq 1 ]] || die "parse: '${__sdisp[${n}]}' must be exactly 1 character" 2
                fi
            ;;
            str|any)
                if (( __sreq[n] )); then
                    [[ -n "${!n-}" ]] || die "parse: '${__sdisp[${n}]}' can't be empty" 2
                fi
            ;;
            list)
                if (( __sreq[n] )); then
                    local -n r="${n}"
                    (( ${#r[@]} )) || die "parse: missing required '${__sdisp[${n}]}'" 2
                fi
            ;;
        esac

    done

    if [[ "${scope}" == "assign" ]]; then
        return 0
    fi

    local emit_scope="local"
    [[ "${scope}" == "global" ]] && emit_scope="global"

    for n in "${__order[@]}"; do

        tv="${__stype[${n}]}"
        if [[ "${tv}" == "list" ]]; then
            local -n r="${n}"
            parse_emit_array "${emit_scope}" "${n}" "${r[@]}"
        else
            parse_emit_scalar "${emit_scope}" "${n}" "${!n-}"
        fi

    done

    local -n r_kwargs="kwargs"
    parse_emit_array "${emit_scope}" "kwargs" "${r_kwargs[@]}"

    return 0

}
parse_usage_extract () {

    local -n in_schema="${1}"
    local -n out_usage="${2}"

    out_usage=""

    local -a cleaned=()
    local i=0

    while (( i < ${#in_schema[@]} )); do
        case "${in_schema[$i]}" in
            --usage|--help|-h|--h)
                out_usage="${in_schema[$(( i + 1 ))]-}"
                [[ -n "${out_usage}" ]] || die "parse: help/usage flag requires function name" 2
                i=$(( i + 2 ))
                continue
            ;;
            --usage=*)
                out_usage="${in_schema[$i]#--usage=}"
                [[ -n "${out_usage}" ]] || die "parse: help/usage flag requires function name" 2
                i=$(( i + 1 ))
                continue
            ;;
            --help=*)
                out_usage="${in_schema[$i]#--help=}"
                [[ -n "${out_usage}" ]] || die "parse: help/usage flag requires function name" 2
                i=$(( i + 1 ))
                continue
            ;;
            -h=*)
                out_usage="${in_schema[$i]#-h=}"
                [[ -n "${out_usage}" ]] || die "parse: help/usage flag requires function name" 2
                i=$(( i + 1 ))
                continue
            ;;
            --h=*)
                out_usage="${in_schema[$i]#--h=}"
                [[ -n "${out_usage}" ]] || die "parse: help/usage flag requires function name" 2
                i=$(( i + 1 ))
                continue
            ;;
        esac

        cleaned+=( "${in_schema[$i]}" )
        i=$(( i + 1 ))
    done

    in_schema=( "${cleaned[@]}" )

    if [[ -n "${out_usage}" ]]; then
        [[ "${out_usage}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die "parse: invalid usage fn: ${out_usage}" 2
    fi

}
parse_args () {

    local IFS=$' \n\t' scope="assign" usage_fn="" a=""

    if [[ "${1-}" == "--local" ]]; then
        scope="local"
        shift || true
    elif [[ "${1-}" == "--global" ]]; then
        scope="global"
        shift || true
    fi

    parse_require_bash

    local -a argv=()
    local -a schema=()

    parse_args_split argv schema "$@"
    parse_usage_extract schema usage_fn

    for a in "${argv[@]}"; do
        case "${a}" in
            -h|--help)
                if [[ -n "${usage_fn}" ]]; then
                    printf '%s\n' "if declare -F ${usage_fn} >/dev/null; then"
                    printf '%s\n' "    ${usage_fn}"
                    printf '%s\n' '    if [[ $- == *i* ]]; then return 0 2>/dev/null || true; else exit 0; fi'
                    printf '%s\n' 'fi'
                    printf '%s\n' "printf '%s\n' \"No help available (missing ${usage_fn}()).\" >&2"
                    printf '%s\n' 'if [[ $- == *i* ]]; then return 2 2>/dev/null || true; else exit 2; fi'
                    return 0
                fi

                printf '%s\n' 'if declare -F usage >/dev/null; then'
                printf '%s\n' '    usage'
                printf '%s\n' '    if [[ $- == *i* ]]; then return 0 2>/dev/null || true; else exit 0; fi'
                printf '%s\n' 'elif declare -F help >/dev/null; then'
                printf '%s\n' '    help'
                printf '%s\n' '    if [[ $- == *i* ]]; then return 0 2>/dev/null || true; else exit 0; fi'
                printf '%s\n' 'fi'
                printf '%s\n' 'printf "%s\n" "No help available (define usage() or help())." >&2'
                printf '%s\n' 'if [[ $- == *i* ]]; then return 2 2>/dev/null || true; else exit 2; fi'
                return 0
            ;;
        esac
    done

    local -A stype=()
    local -A sreq=()
    local -A sdef=()
    local -A sdef_has=()
    local -A set=()
    local -A alias_to=()
    local -A sdisp=()

    local -a order=()
    local -a pos_order=()
    local -a auto_order=()
    local -A auto_has_opt=()

    local kwargs_req=0
    local have_kwargs_schema=0

    parse_args__schema_build schema stype sreq sdef sdef_has alias_to sdisp order pos_order auto_order auto_has_opt kwargs_req have_kwargs_schema
    parse_args__infer_auto_types argv auto_order auto_has_opt alias_to stype
    parse_args__init_values order stype
    parse_args__parse_argv argv pos_order stype alias_to sdisp set
    parse_args__apply_defaults order stype sdef sdef_has sdisp set
    parse_args__validate_and_normalize "${scope}" order stype sreq sdisp set

    return 0

}
parse () {

    local parse_old_die="$(declare -f die 2>/dev/null || true)"

    die () {

        local msg="${1:-}" code="${2:-2}"

        printf '❌ %s\n' "${msg}" >&2
        printf 'return %s 2>/dev/null || exit %s\n' "${code}" "${code}"

        exit 0

    }

    parse_args --local "$@"
    local rc=$?

    if [[ -n "${parse_old_die}" ]]; then eval "${parse_old_die}"
    else unset -f die 2>/dev/null || true
    fi

    return "${rc}"

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

ensure_tool () {

    ensure_pkg "$@" 1>&2

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

    case "$(tool_target)" in
        linux|macos) return 0 ;;
    esac

    return 1

}
tool_is_windows_target () {

    case "$(tool_target)" in
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

    ensure_tool sort 1>&2

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
    dirs+=( "/cygdrive/c/Program Files/Volta/bin" )
    dirs+=( "/cygdrive/c/Users/${USERNAME:-}/AppData/Local/Volta/bin" )

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

    dirs+=( "/c/Users/${USERNAME:-}/.bun/bin" )
    dirs+=( "/cygdrive/c/Users/${USERNAME:-}/.bun/bin" )

    for dir in "${dirs[@]}"; do
        tool_export_path_if_dir "${dir}"
    done

}
tool_node_major () {

    local v="${1-}" major=""
    [[ -n "${v}" ]] || return 1

    v="${v#v}"
    major="${v%%.*}"

    [[ "${major}" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${major}"

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

tool_node_ok () {

    local want="${1-}" v="" major=""

    has node || return 1
    has npm  || return 1
    has npx  || return 1

    [[ -n "${want}" ]] || return 0
    [[ "${want}" =~ ^[0-9]+$ ]] || return 0

    v="$(node --version 2>/dev/null || true)"
    major="$(tool_node_major "${v}")" || return 1

    (( major >= want ))

}
tool_bun_ok () {

    local want="${1-}" v="" major=""

    has bun || return 1

    [[ -n "${want}" ]] || return 0
    [[ "${want}" =~ ^[0-9]+$ ]] || return 0

    v="$(bun --version 2>/dev/null || true)"
    major="$(tool_node_major "${v}")" || return 1

    (( major >= want ))

}
tool_pnpm_ok () {

    has pnpm

}
tool_volta_ok () {

    tool_export_volta_bin
    has volta

}

tool_install_volta_unix () {

    ensure_tool curl

    export VOLTA_HOME="${VOLTA_HOME:-${HOME}/.volta}"
    tool_export_volta_bin

    has volta || run bash -c 'curl -fsSL https://get.volta.sh | bash' || die "Failed to install Volta."

    tool_export_volta_bin
    tool_hash_clear

    has volta || die "Volta installed but not found in PATH."
    run volta setup >/dev/null 2>&1 || true

    tool_export_volta_bin
    tool_hash_clear

}
tool_install_volta_windows () {

    local target="${1:-$(tool_target)}"
    local backend="$(tool_backend 2>/dev/null || true)"
    [[ -n "${backend}" ]] || die "No usable backend to install Volta on '${target}'."

    case "${backend}" in
        winget)
            run winget install --id Volta.Volta --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
                || run winget upgrade --id Volta.Volta --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
                || die "Failed to install Volta via winget."
        ;;
        choco)
            if tool_assume_yes; then run choco install -y volta || run choco upgrade -y volta || die "Failed to install Volta via choco."
            else run choco install volta || run choco upgrade volta || die "Failed to install Volta via choco."
            fi
        ;;
        scoop)
            run scoop install volta || run scoop update volta || die "Failed to install Volta via scoop."
        ;;
        *)
            die "Unsupported backend '${backend}' for Volta install on '${target}'."
        ;;
    esac

    tool_export_volta_bin
    tool_hash_clear

    has volta || die "Volta installed but not found in PATH."
    run volta setup >/dev/null 2>&1 || true

    tool_export_volta_bin
    tool_hash_clear

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
            die "tool_install_node_pacman: unsupported target '${target}'."
        ;;
    esac

}
tool_install_bun_unix () {

    ensure_tool curl

    export BUN_INSTALL="${BUN_INSTALL:-${HOME}/.bun}"
    tool_export_bun_bin

    run bash -c 'curl -fsSL https://bun.sh/install | bash' || return 1

    tool_export_bun_bin
    tool_hash_clear

    has bun

}
tool_install_bun_windows () {

    local target="${1:-$(tool_target)}"
    local backend="$(tool_backend 2>/dev/null || true)"

    if has powershell.exe; then

        run powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'irm bun.sh/install.ps1|iex' || true
        tool_export_bun_bin

        tool_hash_clear
        has bun && return 0

    fi

    case "${backend}" in
        scoop) run scoop install bun || run scoop update bun || return 1 ;;
        *) return 1 ;;
    esac

    tool_export_bun_bin
    tool_hash_clear

    has bun

}
tool_install_bun_via_npm () {

    has npm || return 1
    run npm install -g bun || return 1

    tool_export_npm_bin
    tool_hash_clear

    has bun

}

ensure_volta () {

    tool_export_volta_bin
    has volta && return 0

    local target="$(tool_target)"

    case "${target}" in
        linux|macos) tool_install_volta_unix ;;
        msys|mingw|gitbash|cygwin) tool_install_volta_windows "${target}" ;;
        *) die "Unsupported target for Volta install: ${target}." ;;
    esac

    tool_export_volta_bin
    tool_hash_clear

    has volta || die "Volta install failed."

}
ensure_node () {

    local want="${1:-${NODE_VERSION:-}}"

    tool_export_volta_bin
    tool_export_npm_bin
    tool_node_ok "${want}" && return 0

    local target="$(tool_target)"
    local backend="$(tool_backend 2>/dev/null || true)"

    case "${target}" in
        linux|macos)
            ensure_volta
            run volta install "$(tool_node_spec "${want}")" || die "Failed to install Node via Volta."
        ;;
        msys|mingw|gitbash)
            case "${backend}" in
                pacman)
                    if [[ -n "${want}" && "${want}" =~ ^[0-9]+$ ]]; then
                        ensure_volta
                        run volta install "$(tool_node_spec "${want}")" || die "Failed to install Node via Volta."
                    else
                        tool_install_node_pacman "${target}"
                    fi
                ;;
                winget|choco|scoop)
                    ensure_volta
                    run volta install "$(tool_node_spec "${want}")" || die "Failed to install Node via Volta."
                ;;
                *)
                    die "No supported backend for Node on '${target}'."
                ;;
            esac
        ;;
        cygwin)
            ensure_volta
            run volta install "$(tool_node_spec "${want}")" || die "Failed to install Node via Volta."
        ;;
        *)
            die "Unsupported target for Node install: ${target}."
        ;;
    esac

    tool_export_volta_bin
    tool_export_npm_bin
    tool_hash_clear

    tool_node_ok "${want}" || die "Node install did not satisfy requirement."

}
ensure_bun () {

    local want="${1:-${BUN_VERSION:-}}"

    tool_export_bun_bin
    tool_export_npm_bin
    tool_bun_ok "${want}" && return 0

    local target="$(tool_target)"

    case "${target}" in
        linux|macos) tool_install_bun_unix || tool_install_bun_via_npm || die "Failed to install Bun." ;;
        msys|mingw|gitbash|cygwin) tool_install_bun_windows "${target}" || tool_install_bun_via_npm || die "Failed to install Bun." ;;
        *) die "Unsupported target for Bun install: ${target}." ;;
    esac

    tool_export_bun_bin
    tool_export_npm_bin
    tool_hash_clear
    tool_bun_ok "${want}" || die "Bun install did not satisfy requirement."

}
ensure_pnpm () {

    ensure_node "${NODE_VERSION:-}"

    tool_export_volta_bin
    tool_export_npm_bin
    tool_pnpm_ok && return 0

    ensure_volta
    run volta install pnpm || die "Failed to install pnpm via Volta."

    tool_export_volta_bin
    tool_export_npm_bin
    tool_hash_clear
    tool_pnpm_ok || die "pnpm installed but not found in PATH."

}
ensure_package () {

    local pkg="${1-}" ver="${2-}"
    shift 2 || true

    [[ -n "${pkg}" ]] || die "ensure_package: requires <package>"
    [[ -n "${ver}" ]] && pkg="${pkg}@${ver}"

    if [[ -f "bun.lockb" || -f "bun.lock" ]]; then
        ensure_bun
        run bun add "$@" "${pkg}" || die "Failed to install package '${pkg}' via bun"
        return 0
    fi

    if has pnpm; then run pnpm add "$@" "${pkg}" || die "Failed to install package '${pkg}' via pnpm"
    elif has npm; then run npm install "$@" "${pkg}" || die "Failed to install package '${pkg}' via npm"
    else ensure_pnpm; run pnpm add "$@" "${pkg}" || die "Failed to install package '${pkg}' via pnpm"
    fi

}

tool_php_run () {

    if has php; then
        php "$@"
        return $?
    fi
    if has php.exe; then
        php.exe "$@"
        return $?
    fi

    return 127

}
tool_php_major () {

    local v="${1-}" major=""
    [[ -n "${v}" ]] || return 1

    v="${v#PHP }"
    major="${v%%.*}"

    [[ "${major}" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${major}"

}
tool_export_composer_bin () {

    local dir="" d=""
    local -a dirs=()

    [[ -n "${COMPOSER_HOME:-}" ]] && dirs+=( "$(tool_to_unix_path "${COMPOSER_HOME}")/vendor/bin" )
    [[ -n "${APPDATA:-}" ]]      && dirs+=( "$(tool_to_unix_path "${APPDATA}")/Composer/vendor/bin" )
    [[ -n "${LOCALAPPDATA:-}" ]] && dirs+=( "$(tool_to_unix_path "${LOCALAPPDATA}")/Composer/vendor/bin" )
    [[ -n "${USERPROFILE:-}" ]]  && dirs+=( "$(tool_to_unix_path "${USERPROFILE}")/AppData/Roaming/Composer/vendor/bin" )
    [[ -n "${USERPROFILE:-}" ]]  && dirs+=( "$(tool_to_unix_path "${USERPROFILE}")/AppData/Local/Composer/vendor/bin" )

    dirs+=( "${HOME}/.composer/vendor/bin" )
    dirs+=( "${HOME}/.config/composer/vendor/bin" )
    dirs+=( "${HOME}/.local/bin" )
    dirs+=( "${HOME}/bin" )

    for d in "${dirs[@]}"; do
        tool_export_path_if_dir "${d}"
    done

}
tool_composer_cmd () {

    tool_export_composer_bin

    if has composer; then
        composer "$@"
        return $?
    fi
    if [[ -x "${HOME}/.local/bin/composer" ]]; then
        "${HOME}/.local/bin/composer" "$@"
        return $?
    fi
    if [[ -x "${HOME}/bin/composer" ]]; then
        "${HOME}/bin/composer" "$@"
        return $?
    fi

    return 127

}

tool_php_ok () {

    local want="${1:-${PHP_VERSION:-8}}" v="" major=""

    tool_php_run -v >/dev/null 2>&1 || return 1

    [[ -n "${want}" ]] || return 0
    [[ "${want}" =~ ^[0-9]+$ ]] || return 0

    v="$(tool_php_run -r 'echo PHP_VERSION;' 2>/dev/null || true)"
    major="$(tool_php_major "${v}")" || return 1

    (( major >= want ))

}
tool_composer_ok () {

    tool_export_composer_bin

    if has composer; then
        composer --version >/dev/null 2>&1
        return $?
    fi
    if [[ -x "${HOME}/.local/bin/composer" ]]; then
        "${HOME}/.local/bin/composer" --version >/dev/null 2>&1
        return $?
    fi
    if [[ -x "${HOME}/bin/composer" ]]; then
        "${HOME}/bin/composer" --version >/dev/null 2>&1
        return $?
    fi

    return 1

}

tool_install_php_unix () {

    if has brew; then

        run brew install php || die "Failed to install PHP via brew."
        return 0

    fi
    if has apt-get; then

        run sudo apt-get update -y || die "Failed to update apt index."

        if tool_assume_yes; then run sudo apt-get install -y php-cli php-mbstring php-xml php-curl unzip ca-certificates
        else run sudo apt-get install php-cli php-mbstring php-xml php-curl unzip ca-certificates
        fi

        return 0

    fi
    if has apk; then

        if tool_assume_yes; then
            run sudo apk add php84-cli php84-phar php84-openssl php84-mbstring php84-xml php84-curl unzip ca-certificates \
                || run sudo apk add php83-cli php83-phar php83-openssl php83-mbstring php83-xml php83-curl unzip ca-certificates \
                || run sudo apk add php-cli php-phar php-openssl php-mbstring php-xml php-curl unzip ca-certificates \
                || die "Failed to install PHP via apk."
        else
            run sudo apk add php84-cli php84-phar php84-openssl php84-mbstring php84-xml php84-curl unzip ca-certificates \
                || run sudo apk add php83-cli php83-phar php83-openssl php83-mbstring php83-xml php83-curl unzip ca-certificates \
                || run sudo apk add php-cli php-phar php-openssl php-mbstring php-xml php-curl unzip ca-certificates \
                || die "Failed to install PHP via apk."
        fi

        return 0

    fi
    if has dnf; then

        if tool_assume_yes; then run sudo dnf install -y php-cli php-mbstring php-xml php-process php-curl unzip ca-certificates
        else run sudo dnf install php-cli php-mbstring php-xml php-process php-curl unzip ca-certificates
        fi

        return 0

    fi
    if has yum; then

        if tool_assume_yes; then run sudo yum install -y php-cli php-mbstring php-xml php-process php-curl unzip ca-certificates
        else run sudo yum install php-cli php-mbstring php-xml php-process php-curl unzip ca-certificates
        fi

        return 0

    fi
    if has zypper; then

        if tool_assume_yes; then
            run sudo zypper --non-interactive install php8 php8-cli php8-mbstring php8-xmlreader php8-xmlwriter php8-curl unzip ca-certificates \
                || run sudo zypper --non-interactive install php php-cli php-mbstring php-xmlreader php-xmlwriter php-curl unzip ca-certificates \
                || die "Failed to install PHP via zypper."
        else
            run sudo zypper install php8 php8-cli php8-mbstring php8-xmlreader php8-xmlwriter php8-curl unzip ca-certificates \
                || run sudo zypper install php php-cli php-mbstring php-xmlreader php-xmlwriter php-curl unzip ca-certificates \
                || die "Failed to install PHP via zypper."
        fi

        return 0

    fi
    if has pacman; then

        if tool_assume_yes; then run sudo pacman -S --needed --noconfirm php unzip ca-certificates
        else run sudo pacman -S --needed php unzip ca-certificates
        fi

        return 0

    fi

    die "No supported unix package manager found for PHP install."

}
tool_install_php_windows () {

    local target="${1:-$(tool_target)}"

    if has scoop; then

        run scoop install php || run scoop update php || die "Failed to install PHP via scoop."
        return 0

    fi
    if has choco; then

        if tool_assume_yes; then run choco install -y php || run choco upgrade -y php || die "Failed to install PHP via choco."
        else run choco install php || run choco upgrade php || die "Failed to install PHP via choco."
        fi
        return 0

    fi
    if has pacman; then

        case "${target}" in
            msys|gitbash)
                if tool_assume_yes; then run pacman -S --needed --noconfirm php
                else run pacman -S --needed php
                fi
            ;;
            mingw)
                local prefix="$(tool_mingw_prefix)"

                if tool_assume_yes; then
                    run pacman -S --needed --noconfirm "${prefix}-php" \
                        || run pacman -S --needed --noconfirm php \
                        || die "Failed to install PHP via pacman."
                else
                    run pacman -S --needed "${prefix}-php" \
                        || run pacman -S --needed php \
                        || die "Failed to install PHP via pacman."
                fi
            ;;
            cygwin)
                die "Cygwin PHP auto-install is not supported in this file. Use winget/choco/scoop from Windows side."
            ;;
            *)
                die "Unsupported pacman target for PHP: ${target}"
            ;;
        esac

        return 0

    fi
    if has winget; then

        run winget install --id PHP.PHP --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || run winget upgrade --id PHP.PHP --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || die "Failed to install PHP via winget."

        return 0

    fi

    die "No supported Windows package manager found for PHP install."

}
tool_install_composer_official () {

    ensure_tool curl
    ensure_php

    local setup="" expected="" actual="" install_dir=""

    if [[ -d "${HOME}/.local/bin" || ! -e "${HOME}/.local/bin" ]]; then install_dir="${HOME}/.local/bin"
    else install_dir="${HOME}/bin"
    fi

    mkdir -p "${install_dir}" || die "Failed to create Composer install dir: ${install_dir}"

    setup="$(mktemp "${TMPDIR:-/tmp}/composer-setup.XXXXXX.php" 2>/dev/null || true)"
    [[ -n "${setup}" ]] || setup="${TMPDIR:-/tmp}/composer-setup.$$.$RANDOM.php"

    expected="$(curl -fsSL https://composer.github.io/installer.sig 2>/dev/null || true)"
    [[ -n "${expected}" ]] || die "Failed to fetch Composer installer checksum."

    run curl -fsSL -o "${setup}" https://getcomposer.org/installer || {
        rm -f "${setup}" 2>/dev/null || true
        die "Failed to download Composer installer."
    }

    actual="$(tool_php_run -r 'echo hash_file("sha384", $argv[1]);' "${setup}" 2>/dev/null || true)"

    [[ -n "${actual}" && "${actual}" == "${expected}" ]] || {
        rm -f "${setup}" 2>/dev/null || true
        die "Composer installer checksum mismatch."
    }

    run tool_php_run "${setup}" --no-ansi --install-dir="${install_dir}" --filename=composer || {
        rm -f "${setup}" 2>/dev/null || true
        die "Failed to install Composer."
    }

    rm -f "${setup}" 2>/dev/null || true
    chmod +x "${install_dir}/composer" 2>/dev/null || true

    tool_export_path_if_dir "${install_dir}"
    tool_hash_clear

}
tool_install_composer_unix () {

    if has brew; then

        run brew install composer || tool_install_composer_official
        return 0

    fi
    if has apt-get; then

        run sudo apt-get update -y >/dev/null 2>&1 || true

        if tool_assume_yes; then run sudo apt-get install -y composer || tool_install_composer_official
        else run sudo apt-get install composer || tool_install_composer_official
        fi
        return 0

    fi
    if has apk; then

        if tool_assume_yes; then run sudo apk add composer || tool_install_composer_official
        else run sudo apk add composer || tool_install_composer_official
        fi
        return 0

    fi
    if has dnf; then

        if tool_assume_yes; then run sudo dnf install -y composer || tool_install_composer_official
        else run sudo dnf install composer || tool_install_composer_official
        fi
        return 0

    fi
    if has yum; then

        if tool_assume_yes; then run sudo yum install -y composer || tool_install_composer_official
        else run sudo yum install composer || tool_install_composer_official
        fi
        return 0

    fi
    if has zypper; then

        if tool_assume_yes; then run sudo zypper --non-interactive install composer || tool_install_composer_official
        else run sudo zypper install composer || tool_install_composer_official
        fi
        return 0

    fi
    if has pacman; then

        if tool_assume_yes; then run sudo pacman -S --needed --noconfirm composer || tool_install_composer_official
        else run sudo pacman -S --needed composer || tool_install_composer_official
        fi
        return 0

    fi

    tool_install_composer_official

}
tool_install_composer_windows () {

    if has scoop; then

        run scoop install composer || run scoop update composer || true

        tool_export_composer_bin
        tool_hash_clear
        tool_composer_ok && return 0

    fi
    if has choco; then

        if tool_assume_yes; then run choco install -y composer || run choco upgrade -y composer || true
        else run choco install composer || run choco upgrade composer || true
        fi

        tool_export_composer_bin
        tool_hash_clear
        tool_composer_ok && return 0

    fi
    if has winget; then

        run winget install --id Composer.Composer --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || run winget upgrade --id Composer.Composer --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || true

        tool_export_composer_bin
        tool_hash_clear
        tool_composer_ok && return 0

    fi

    tool_install_composer_official

}

ensure_php () {

    local want="${1:-${PHP_VERSION:-8}}"
    local target="$(tool_target)"

    tool_php_ok "${want}" && return 0

    case "${target}" in
        linux|macos) tool_install_php_unix ;;
        msys|mingw|gitbash|cygwin) tool_install_php_windows "${target}" ;;
        *) die "Unsupported target for PHP install: ${target}" ;;
    esac

    tool_hash_clear
    tool_php_ok "${want}" || die "PHP install did not satisfy requirement."

}
ensure_composer () {

    local target="$(tool_target)"

    tool_export_composer_bin
    tool_composer_ok && return 0

    case "${target}" in
        linux|macos) tool_install_composer_unix ;;
        msys|mingw|gitbash|cygwin) tool_install_composer_windows ;;
        *) die "Unsupported target for Composer install: ${target}" ;;
    esac

    tool_export_composer_bin
    tool_hash_clear

    tool_composer_ok || die "Composer install failed."

}
ensure_dependency () {

    local pkg="${1-}" ver="${2-}"
    local target="${pkg}"
    shift 2 || true

    [[ -n "${pkg}" ]] || die "ensure_dependency: requires <package>"
    [[ -n "${ver}" ]] && target="${pkg}:${ver}"

    ensure_composer

    if [[ -f "composer.json" ]]; then
        tool_composer_cmd require "$@" "${target}" || die "Failed to install dependency '${target}' via composer require."
    else
        tool_composer_cmd global require "$@" "${target}" || die "Failed to install dependency '${target}' via composer global require."
        tool_export_composer_bin
        tool_hash_clear
    fi

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

    ensure_tool python pip

    tool_export_python_bin
    tool_python_aliases_unix
    tool_hash_clear
    tool_python_ok "${want}" || die "Python install did not satisfy requirement."

    tool_python_run -m pip install --upgrade pip || die "Failed to upgrade pip."
    tool_pip_ok || die "pip is not available after Python install/upgrade."

}
ensure_pip () {

    ensure_python

}
ensure_lib () {

    local pkg="${1-}" ver="${2-}"
    local target="${pkg:-}"
    shift 2 || true

    [[ -n "${pkg}" ]] || die "ensure_lib: requires <package>"
    [[ -n "${ver}" ]] && target="${pkg}==${ver}"

    ensure_python

    tool_python_run -m pip show "${pkg}" >/dev/null 2>&1 && return 0
    tool_python_run -m pip install "$@" "${target}" || die "Failed to install Python package '${target}'."

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

forge_replace_all () {

    ensure_tool find mktemp rm perl xargs

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

    dir="${dir:-${WORKSPACE_DIR:-${PWD}}}"
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

forge_ensure_template () {

    ensure_pkg awk tail tar mkdir rm dirname

    local src="${0}"
    [[ -f "${src}" ]] || die "Source bundle not found: ${src}"
    [[ -d "${TEMPLATE_DIR:-}" ]] && return 0

    local key="${TEMPLATE_KEY:-__TEMPLATE_PAYLOAD_KEY__}"
    local line="$(awk -v key="${key}" '$0 == key { print NR + 1; exit }' "${src}" 2>/dev/null || true)"
    [[ -n "${line}" ]] || die "Template payload marker not found"

    local tmp="$(tmp_dir "gun-template")"
    local out="${tmp}/template"

    ensure_dir "${out}"

    tail -n +"${line}" -- "${src}" | tar -xzf - -C "${out}" --strip-components=1 || {
        rm -rf -- "${tmp}" >/dev/null 2>&1 || true
        die "Failed to extract template payload"
    }
    TEMPLATE_DIR="$(cd -- "${out}" 2>/dev/null && pwd -P)" || {
        rm -rf -- "${tmp}" >/dev/null 2>&1 || true
        die "Failed to resolve TEMPLATE_DIR"
    }
    [[ -d "${TEMPLATE_DIR}" ]] || {
        rm -rf -- "${tmp}" >/dev/null 2>&1 || true
        die "Extracted template dir not found"
    }

}
forge_copy_template () {

    ensure_tool mkdir find tar grep

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

cmd_forge_help () {

    info_ln "Scaffold :"

    printf '    %s\n' \
        "" \
        "new                        * Create a new project from template" \
        "new-project                * Create a new pure project from template" \
        "new-bin                    * Create a new pure binary project from template" \
        "new-lib                    * Create a new library project from template" \
        "new-ws                     * Create a new workspace project from template" \
        ''

}
cmd_new () {

    source <(parse "$@" -- :template name dest placeholders:bool=true git:bool=true)

    forge_ensure_template

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

    ensure_tool mkdir chmod
    source <(parse "$@" -- :src mode)

    run mkdir -p -- "${src}"
    [[ -n "${mode}" ]] && run chmod -- "${mode}" "${src}"

}
fs_new_file () {

    ensure_tool mkdir chmod touch dirname
    source <(parse "$@" -- :src mode)

    run mkdir -p -- "$(dirname -- "${src}")"
    run touch -- "${src}"

    [[ -n "${mode}" ]] && run chmod -- "${mode}" "${src}"

}
fs_path_type () {

    local p="${1:-}" type="unknown"

    [[ -e "${p}" ]] && type="other"
    [[ -d "${p}" ]] && type="dir"
    [[ -f "${p}" ]] && type="file"
    [[ -L "${p}" ]] && type="symlink"

    printf '%s\n' "${type}"
    return 0

}
fs_file_type () {

    ensure_tool file
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

fs_file_exists () {

    [[ -f "${1:-}" ]]

}
fs_dir_exists () {

    [[ -d "${1:-}" ]]

}
fs_path_exists () {

    [[ -e "${1:-}" || -L "${1:-}" ]]

}

fs_copy_path () {

    ensure_tool cp mkdir dirname
    source <(parse "$@" -- :src :dest)

    run mkdir -p -- "$(dirname -- "${dest}")"
    local -a cmd=( cp )

    if cp --version >/dev/null 2>&1; then cmd+=( -a )
    else cmd+=( -pPR )
    fi

    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" "${dest}"

}
fs_move_path () {

    ensure_tool mv mkdir dirname
    source <(parse "$@" -- :src :dest)

    run mkdir -p -- "$(dirname -- "${dest}")"
    run mv "${kwargs[@]}" -- "${src}" "${dest}"

}
fs_remove_path () {

    ensure_tool rm find
    source <(parse "$@" -- :src clear:bool)

    [[ "${src}" == "/" || "${src}" == "." || "${src}" == ".." ]] && die "Refuse to delete '/' '.' '..'"

    if (( clear )); then

        [[ -d "${src}" ]] || die "Not a directory: ${src}"
        find "${src}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
        return 0

    fi

    run rm -rf "${kwargs[@]}" -- "${src}"

}
fs_trash_path () {

    ensure_tool mkdir mv date basename
    source <(parse "$@" -- :src trash_dir)

    [[ "${src}" == "/" || "${src}" == "." || "${src}" == ".." ]] && die "Refuse to trash '/' '.' '..'"
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

    ensure_tool mkdir ln dirname
    source <(parse "$@" -- :src :dest)

    run mkdir -p -- "$(dirname -- "${dest}")"
    run ln -sfn "${kwargs[@]}" -- "${src}" "${dest}"

}

fs_stats_path () {

    ensure_tool stat
    source <(parse "$@" -- :src)

    if stat --version >/dev/null 2>&1; then stat -c $'path=%n\ntype=%F\nsize=%s\nperm=%a\nowner=%U\ngroup=%G\nmtime=%y' -- "${src}"
    else stat -f $'path=%N\ntype=%HT\nsize=%z\nperm=%Lp\nowner=%Su\ngroup=%Sg\nmtime=%Sm' -t "%Y-%m-%d %H:%M:%S" -- "${src}"
    fi

}
fs_diff_path () {

    ensure_tool diff
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

    ensure_tool diff
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

    ensure_tool mkdir dirname basename tar
    source <(parse "$@" -- src dest name type=zip exclude:list)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." || "${src}" == "/" ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    local base="${src%/}" kind="${type,,}" ext="" i=""
    local dir="$(dirname -- "${base}")"
    local entry="$(basename -- "${base}")"

    name="${name:-"${entry}"}"

    if [[ -z "${dest}" ]]; then

        case "${kind}" in
            zip)           dest="${PWD}/${name}.zip" ;;
            rar)           dest="${PWD}/${name}.rar" ;;
            7z)            dest="${PWD}/${name}.7z" ;;
            tar)           dest="${PWD}/${name}.tar" ;;
            tgz|gz)        dest="${PWD}/${name}.tar.gz" ;;
            txz|xz)        dest="${PWD}/${name}.tar.xz" ;;
            tbz2|bz2)      dest="${PWD}/${name}.tar.bz2" ;;
            tzst|zst|zstd) dest="${PWD}/${name}.tar.zst" ;;
            *)             dest="${PWD}/${name}.${type}" ;;
        esac

    fi

    [[ "${dest}" == /* ]] || dest="${PWD}/${dest#./}"
    run mkdir -p -- "$(dirname -- "${dest}")"

    ext="${dest,,}"

    local -a cmd=()
    local -a ignores=()

    mapfile -t ignores < <(ignore_list)
    ignores+=( "${exclude[@]-}" )

    if [[ "${kind}" == "zip" || "${ext}" == *.zip ]]; then

        ensure_tool zip

        cmd=( zip -rq )
        cmd+=( "${kwargs[@]}" )
        cmd+=( "${dest}" "${entry}" )

        for i in "${ignores[@]-}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( -x "*${i}*" )
        done

        ( cd -- "${dir}" && run "${cmd[@]}" )

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${kind}" == "rar" || "${ext}" == *.rar ]]; then

        ensure_tool rar

        cmd=( rar a -r -idq )
        cmd+=( "${kwargs[@]}" )
        cmd+=( "${dest}" "${entry}" )

        for i in "${ignores[@]-}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( "-x*${i}*" )
        done

        ( cd -- "${dir}" && run "${cmd[@]}" )

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${kind}" == "7z" || "${ext}" == *.7z ]]; then

        ensure_tool 7z

        cmd=( 7z a -y )
        cmd+=( "${kwargs[@]}" )
        cmd+=( "${dest}" "${entry}" )

        for i in "${ignores[@]-}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( "-xr!*${i}*" )
        done

        ( cd -- "${dir}" && run "${cmd[@]}" )

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${kind}" == "tzst" || "${kind}" == "zst" || "${kind}" == "zstd" || "${ext}" == *.tar.zst || "${ext}" == *.tzst ]]; then

        ensure_tool zstd

        if tar --help 2>/dev/null | grep -q -- '--zstd'; then

            cmd=( tar --zstd -cf "${dest}" )

            for i in "${ignores[@]-}"; do
                [[ -n "${i}" ]] || continue
                cmd+=( --exclude "${i}" )
            done

            run "${cmd[@]}" "${kwargs[@]}" -C "${dir}" -- "${entry}"

        else

            local -a tar_cmd=( tar -cf - )

            for i in "${ignores[@]-}"; do
                [[ -n "${i}" ]] || continue
                tar_cmd+=( --exclude "${i}" )
            done

            tar_cmd+=( "${kwargs[@]}" -C "${dir}" -- "${entry}" )
            ( "${tar_cmd[@]}" | zstd -T0 -q -o "${dest}" ) || die "Failed to create zstd archive: ${dest}"

        fi

        printf '%s\n' "${dest}"
        return 0

    fi

    if [[ "${kind}" == "tgz" || "${kind}" == "gz" || "${ext}" == *.tar.gz || "${ext}" == *.tgz ]]; then cmd=( tar -czf "${dest}" )
    elif [[ "${kind}" == "txz" || "${kind}" == "xz" || "${ext}" == *.tar.xz || "${ext}" == *.txz ]]; then cmd=( tar -cJf "${dest}" )
    elif [[ "${kind}" == "tbz2" || "${kind}" == "bz2" || "${ext}" == *.tar.bz2 || "${ext}" == *.tbz2 ]]; then cmd=( tar -cjf "${dest}" )
    elif [[ "${kind}" == "tar" || "${ext}" == *.tar ]]; then cmd=( tar -cf "${dest}" )
    else die "Unsupported archive type: ${dest}"
    fi

    for i in "${ignores[@]-}"; do
        [[ -n "${i}" ]] || continue
        cmd+=( --exclude "${i}" )
    done

    run "${cmd[@]}" "${kwargs[@]}" -C "${dir}" -- "${entry}"
    printf '%s\n' "${dest}"

}
fs_extract_path () {

    ensure_tool mkdir tar
    source <(parse "$@" -- :src dest strip:int)

    [[ -e "${src}" || -L "${src}" ]] || die "Archive not found: ${src}"
    [[ -n "${dest}" ]] || dest="."

    run mkdir -p -- "${dest}"

    local ext="${src,,}"
    local -a cmd=( tar )

    if [[ "${ext}" == *.zip ]]; then

        ensure_tool unzip
        run unzip -oq "${kwargs[@]}" -- "${src}" -d "${dest}"

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.rar ]]; then

        ensure_tool unrar
        run unrar x -o+ -y "${kwargs[@]}" "${src}" "${dest}/"

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.7z ]]; then

        ensure_tool 7z
        run 7z x -y "${kwargs[@]}" -o"${dest}" "${src}"

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.tar.zst || "${ext}" == *.tzst ]]; then

        ensure_tool zstd

        if tar --help 2>/dev/null | grep -q -- '--zstd'; then

            cmd+=( --zstd -xf )
            (( strip > 0 )) && cmd+=( --strip-components "${strip}" )

            run "${cmd[@]}" "${kwargs[@]}" -- "${src}" -C "${dest}"

        else

            local -a tar_cmd=( tar -xf - -C "${dest}" )

            (( strip > 0 )) && tar_cmd+=( --strip-components "${strip}" )
            tar_cmd+=( "${kwargs[@]}" )

            ( zstd -dc -- "${src}" | "${tar_cmd[@]}" ) || die "Failed to extract zstd archive: ${src}"

        fi

        printf '%s\n' "${dest}"
        return 0

    fi

    if [[ "${ext}" == *.tar.gz || "${ext}" == *.tgz ]]; then cmd+=( -xzf )
    elif [[ "${ext}" == *.tar.xz || "${ext}" == *.txz ]]; then cmd+=( -xJf )
    elif [[ "${ext}" == *.tar.bz2 || "${ext}" == *.tbz2 ]]; then cmd+=( -xjf )
    elif [[ "${ext}" == *.tar ]]; then cmd+=( -xf )
    else die "Unsupported archive type: ${src}"
    fi

    (( strip > 0 )) && cmd+=( --strip-components "${strip}" )

    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" -C "${dest}"
    printf '%s\n' "${dest}"

}
fs_backup_path () {

    ensure_tool date basename
    source <(parse "$@" -- src dest name type=zip archive_dir="${ARCHIVE_DIR:-}")

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." || "${src}" == "/" ]] && src="${PWD}"

    local base_name="$(basename -- "${src%/}")" ts="$(date +'%Y-%m-%d_%H-%M-%S')" _dest_=""

    [[ -n "${name}" ]] && _dest_="${dest:-${base_name}}/${name}" || _dest_="${dest:-"${base_name}/${ts}.${type:-zip}"}"
    [[ -n "${archive_dir}" && "${_dest_}" != /* && "${_dest_}" != *:* ]] && dest="${archive_dir%/}/${_dest_}" || dest="${_dest_}"

    fs_compress_path "${src}" "${dest}" "${name}" "${type}" "${kwargs[@]}"

    success "OK: ${src} archived at ${dest}"

}
fs_sync_path () {

    ensure_tool rsync mkdir
    source <(parse "$@" -- src dest src_dir="${WORKSPACE_DIR:-}" sync_dir="${SYNC_DIR:-}" force:bool=true ignore:bool=true exclude:list)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." || "${src}" == "/" ]] && src="${PWD}"

    local rel="${src#${src_dir%/}/}"
    [[ "${rel}" == "${src}" ]] && rel="${src#/}"

    if [[ -z "${dest}" && -n "${sync_dir}" ]]; then dest="${sync_dir%/}/${rel}"
    elif [[ -z "${dest}" ]]; then dest="${rel}"
    fi

    [[ -d "${src}" && "${src}" != */ ]] && src="${src}/"
    [[ -d "${src}" && "${dest}" != */ ]] && dest="${dest}/"
    [[ -d "${src}" ]] && run mkdir -p -- "${dest%/}" || run mkdir -p -- "$(dirname -- "${dest}")"

    local -a cmd=( rsync -a )
    (( force )) && cmd+=( --delete )

    if (( ignore )); then

        local i=""
        local -a ignores=()

        mapfile -t ignores < <(ignore_list)
        ignores+=( "${exclude[@]-}" )

        for i in "${ignores[@]}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( --exclude "${i}" )
        done

    fi

    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" "${dest}"

    success "OK: ${src} synced at ${dest}"

}

cmd_fs_help () {

    info_ln "Files :"

    printf '    %s\n' \
        "" \
        "new-dir                    * Create a new directory" \
        "new-file                   * Create a new file" \
        "" \
        "path-type                  * Print path type if the path exists" \
        "file-type                  * Print file type if the file exists" \
        "" \
        "copy                       * Copy file or directory to destination" \
        "move                       * Move file or directory to destination" \
        "link                       * Create symlink for file or directory" \
        "" \
        "remove                     * Remove file or directory" \
        "trash                      * Move file or directory to trash" \
        "clear                      * Clear directory contents or truncate file" \
        "" \
        "stats                      * Show file or directory statistics" \
        "diff                       * Show diff between source and destination" \
        "synced                     * Check whether source and destination are synced" \
        "" \
        "compress                   * Compress file or directory" \
        "extract                    * Extract archive to destination" \
        "backup                     * Create backup for file or directory" \
        "sync                       * Sync file or directory to target" \
        ''

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
cmd_link () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_link_path "${src}" "${dest}" "${kwargs[@]}"

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
cmd_extract () {

    source <(parse "$@" -- :src dest)
    fs_path_exists "${src}" && fs_extract_path "${src}" "${dest}" "${kwargs[@]}"

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

    ensure_tool git

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

    ensure_tool git
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository."

}
git_repo_root () {

    ensure_tool git
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

    if [[ "${v}" == *+* ]]; then main="${v%%+*}"; build="${v#*+}"
    else main="${v}"; build=""
    fi
    if [[ "${main}" == *-* ]]; then rest="${main%%-*}"; pre="${main#*-}"
    else rest="${main}"; pre=""
    fi
    if [[ "${rest}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then :
    else return 1
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

    (( ${#t} > 1 )) || { printf '\n'; return 0; }

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

    ensure_tool mkdir mktemp mv awk chmod
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

        if [[ -f "${key}" ]]; then
            printf -v ssh_cmd 'ssh -i %q -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=60 -o ServerAliveInterval=15 -o ServerAliveCountMax=2' "${key}"
        else
            ssh_cmd='ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=60 -o ServerAliveInterval=15 -o ServerAliveCountMax=2'
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

    ensure_tool ssh-keygen mkdir chmod rm
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

        ensure_tool touch awk mktemp mv

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

        ensure_tool ssh-add
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

    ensure_tool grep git
    ( git init -h 2>&1 || true ) | grep -q -- '--initial-branch'

}
git_set_default_branch () {

    local branch="${1:-main}"

    git branch -M "${branch}" >/dev/null 2>&1 && return 0
    git symbolic-ref HEAD "refs/heads/${branch}" >/dev/null 2>&1 && return 0

    return 0

}
git_guard_no_unborn () {

    ensure_tool find git

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

    ensure_tool awk git
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

        v="$(
            php -r '$j=@json_decode(@file_get_contents($argv[1]), true); echo is_array($j)&&isset($j["version"])?$j["version"]:"";' \
                "${root}/composer.json" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && -f "${root}/package.json" ]]; then

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

cmd_git_help () {

    info_ln "Git :"

    printf '    %s\n' \
        "" \
        "is-repo                    * Check whether current path is a git repository" \
        "repo-root                  * Print repository root path" \
        "root-tag                   * Build tag from current project version" \
        "" \
        "clone                      * Clone remote repository" \
        "pull                       * Pull latest changes with rebase" \
        "status                     * Print repository state (clean or dirty)" \
        "remote                     * Show remote URL and detected protocol" \
        "" \
        "ssh-key                    * Create SSH key and optionally upload it" \
        "changelog                  * Prepend release entry to CHANGELOG.md" \
        "" \
        "init                       * Initialize repository and configure remote" \
        "push                       * Commit and push current branch" \
        "release                    * Push release with tag and changelog" \
        "" \
        "new-tag                    * Create and push a new tag" \
        "remove-tag                 * Delete tag locally and remotely" \
        "new-branch                 * Create branch locally or track remote branch" \
        "remove-branch              * Delete branch locally and remotely" \
        "" \
        "default-branch             * Print default branch name" \
        "current-branch             * Print current branch name" \
        "switch-branch              * Switch to branch or create it" \
        "" \
        "all-tags                   * List all tags" \
        "all-branches               * List all branches" \
        ''

}

cmd_is_repo () {

    ensure_tool git

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        print yes
        return 0
    fi

    print no
    return 1

}
cmd_repo_root () {

    git_repo_root

}
cmd_root_tag () {

    local ver="v$(git_root_version)"
    local tag="$(git_norm_tag "${ver}")"

    [[ -n "${tag}" ]] && printf '%s\n' "${tag}"

}

cmd_clone () {

    ensure_tool git
    run git clone "$@"

}
cmd_pull () {

    ensure_tool git
    run git pull --rebase "$@"

}
cmd_status () {

    ensure_tool git
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

cmd_ssh_key () {

    source <(parse "$@" -- name host alias title upload:bool)

    [[ -n "${host}" ]] || host="${GIT_HOST:-github.com}"
    [[ -n "${name}" ]] || name="$(git_guess_ssh_key 2>/dev/null || true)"
    [[ -n "${name}" ]] || die "ssh: cannot guess key name. Use --name <key>"

    local base="$(git_new_ssh_key "${name}" "${host}" "${alias}" "${kwargs[@]}")"
    local pub="${base}.pub"

    if (( upload )) && [[ "${host}" == *github* ]]; then

        ensure_tool gh
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

    ensure_tool grep mktemp mv date tail git

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

    ensure_tool git
    source <(parse "$@" -- :repo branch=main remote=origin auth key host create:bool=true)

    local path="" url="" parsed=0 explicit=0 before_url="" after_url="" cur=""
    auth="${auth:-${GIT_AUTH:-ssh}}"
    host="${host:-${GIT_HOST:-github.com}}"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

        if git_initial_branch; then run git init -b "${branch}"
        else run git init; git_set_default_branch "${branch}"
        fi

    fi
    if [[ "${repo}" == *"://"* || "${repo}" == git@*:* || "${repo}" == ssh://* ]]; then
        explicit=1
    fi
    if [[ -n "${key}" && "${auth}" == "ssh" ]]; then

        local key_path="$(git_resolve_ssh_key "${key}")"
        [[ -f "${key_path}" ]] && git_keymap_set "${key_path}" >/dev/null 2>&1 || true
        [[ -f "${key_path}" ]] || cmd_ssh_key "${key}" "${host}" --upload

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

        [[ "${tag}" == "auto" ]] && tag="$(cmd_root_tag)"
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
    [[ -n "${kind}" && -n "${target}" ]] || die "Failed to resolve git auth for remote '${remote}'."

    ensure_tool awk
    run_git "${kind}" "${ssh_cmd}" ls-remote --tags --refs "${target}" | awk '{ sub("^refs/tags/","",$2); print $2 }'

}
cmd_all_branches () {

    git_repo_guard
    ensure_tool awk
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

    ensure_tool gh mkdir
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

    ensure_tool git
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

cmd_github_help () {

    info_ln "GitHub :"

    printf '    %s\n' \
        "" \
        "env-list                   * List GitHub environments" \
        "var-list                   * List GitHub variables" \
        "secret-list                * List GitHub secrets" \
        "" \
        "add-var                    * Add GitHub variable" \
        "add-secret                 * Add GitHub secret" \
        "remove-var                 * Remove GitHub variable" \
        "remove-secret              * Remove GitHub secret" \
        "" \
        "sync-vars                  * Sync GitHub variables from file" \
        "sync-secrets               * Sync GitHub secrets from file" \
        "clear-vars                 * Remove all GitHub variables" \
        "clear-secrets              * Remove all GitHub secrets" \
        "" \
        "new-repo                   * Create GitHub repository and sync vars/secrets" \
        "remove-repo                * Remove GitHub repository" \
        "new-env                    * Create GitHub environment" \
        "remove-env                 * Remove GitHub environment" \
        ''

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

    (( sync )) && {
        cmd_sync_vars "${kwargs[@]}"
        cmd_sync_secrets "${kwargs[@]}"
    }

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

notify_has_telegram () {

    local token="${1:-}" chat="${2:-}"

    [[ -n "${token}" ]] || token="${TELEGRAM_TOKEN:-${TOKEN:-}}"
    [[ -n "${chat}"  ]] || chat="${TELEGRAM_CHAT_ID:-${TELEGRAM_CHAT:-${CHAT_ID:-${CHAT:-}}}}"
    [[ -n "${token}" && -n "${chat}" ]]

}
notify_has_slack () {

    local webhook="${1:-}"

    [[ -n "${webhook}" ]] || webhook="${SLACK_WEBHOOK_URL:-${SLACK_WEBHOOK:-${SLACK_URL:-}}}"
    [[ -n "${webhook}" ]]

}
notify_has_discord () {

    local webhook="${1:-}"

    [[ -n "${webhook}" ]] || webhook="${DISCORD_WEBHOOK_URL:-${DISCORD_WEBHOOK:-${DISCORD_URL:-}}}"
    [[ -n "${webhook}" ]]

}
notify_has_webhook () {

    local webhook="${1:-}"

    [[ -n "${webhook}" ]] || webhook="${WEBHOOK_URL:-${WEBHOOK:-}}"
    [[ -n "${webhook}" ]]

}

notify_telegram () {

    ensure_tool curl

    local -n curl_args="${1}"
    local token="${2:-}" chat="${3:-}" msg="${4:-}"

    [[ -n "${token}" ]] || token="${TELEGRAM_TOKEN:-${TOKEN:-}}"
    [[ -n "${chat}"  ]] || chat="${TELEGRAM_CHAT_ID:-${TELEGRAM_CHAT:-${CHAT_ID:-${CHAT:-}}}}"

    [[ -n "${token}" ]] || die "notify: missing telegram token"
    [[ -n "${chat}"  ]] || die "notify: missing telegram chat"

    curl "${curl_args[@]}" -X POST \
        "https://api.telegram.org/bot${token}/sendMessage" \
        --data-urlencode "chat_id=${chat}" \
        --data-urlencode "text=${msg}" \
        --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || return 1

}
notify_slack () {

    ensure_tool curl jq

    local -n curl_args="${1}"
    local webhook="${2:-}" msg="${3:-}" payload=""

    [[ -n "${webhook}" ]] || webhook="${SLACK_WEBHOOK_URL:-${SLACK_WEBHOOK:-${SLACK_URL:-}}}"
    [[ -n "${webhook}" ]] || die "notify: missing slack webhook"

    payload="$(jq -cn --arg t "${msg}" '{text:$t}')" || return 1

    printf '%s' "${payload}" | curl "${curl_args[@]}" -X POST \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "${webhook}" >/dev/null 2>&1 || return 1

}
notify_discord () {

    ensure_tool curl jq

    local -n curl_args="${1}"
    local webhook="${2:-}" msg="${3:-}" payload=""

    [[ -n "${webhook}" ]] || webhook="${DISCORD_WEBHOOK_URL:-${DISCORD_WEBHOOK:-${DISCORD_URL:-}}}"
    [[ -n "${webhook}" ]] || die "notify: missing discord webhook"

    payload="$(jq -cn --arg t "${msg}" '{content:$t}')" || return 1

    printf '%s' "${payload}" | curl "${curl_args[@]}" -X POST \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "${webhook}" >/dev/null 2>&1 || return 1

}
notify_webhook () {

    ensure_tool curl jq

    local -n curl_args="${1}"
    local webhook="${2:-}" msg="${3:-}" payload=""

    [[ -n "${webhook}" ]] || webhook="${WEBHOOK_URL:-${WEBHOOK:-}}"
    [[ -n "${webhook}" ]] || die "notify: missing webhook url"

    payload="$(jq -cn --arg t "${msg}" '{text:$t}')" || return 1

    printf '%s' "${payload}" | curl "${curl_args[@]}" -X POST \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "${webhook}" >/dev/null 2>&1 || return 1

}

cmd_notify_help () {

    info_ln "Notify :"

    printf '    %s\n' \
        "" \
        "notify                     * Send notification to configured platforms" \
        "notify-telegram            * Send notification to Telegram" \
        "notify-slack               * Send notification to Slack" \
        "notify-discord             * Send notification to Discord" \
        "notify-webhook             * Send notification to generic webhook" \
        ''

}

cmd_notify () {

    source <(parse "$@" -- \
        platform:list platforms:list status title message \
        token chat telegram_token telegram_chat \
        webhook url slack_webhook discord_webhook webhook_url \
        retries:int=3 delay:int=1 timeout:float=10 max_time:float=20 retry_max_time:float=60 \
    )

    local p="" msg="${message:-"$(notify_message "${status}" "${title}")"}"

    local -a plats=() failed=()

    local -a args=(
        -fsS
        --connect-timeout "${timeout}"
        --max-time "${max_time}"
        --retry-max-time "${retry_max_time}"
        --retry "${retries}"
        --retry-delay "${delay}"
        --retry-connrefused
    )

    if (( ${#platform[@]} )); then plats=( "${platform[@]}" )
    elif (( ${#platforms[@]} )); then plats=( "${platforms[@]}" )
    else
        notify_has_telegram "${telegram_token:-${token}}" "${telegram_chat:-${chat}}" && plats+=( telegram )
        notify_has_slack    "${slack_webhook:-${webhook:-${url:-}}}"                  && plats+=( slack )
        notify_has_discord  "${discord_webhook:-${webhook:-${url:-}}}"                && plats+=( discord )
        notify_has_webhook  "${webhook_url:-${webhook:-${url:-}}}"                    && plats+=( webhook )
    fi

    (( ${#plats[@]} )) || die "notify: no configured notification platform found"

    for p in "${plats[@]}"; do

        case "${p,,}" in
            telegram) notify_telegram args "${telegram_token:-${token}}" "${telegram_chat:-${chat}}" "${msg}" || failed+=( telegram ) ;;
            slack)    notify_slack    args "${slack_webhook:-${webhook:-${url:-}}}" "${msg}"                  || failed+=( slack ) ;;
            discord)  notify_discord  args "${discord_webhook:-${webhook:-${url:-}}}" "${msg}"                || failed+=( discord ) ;;
            webhook)  notify_webhook  args "${webhook_url:-${webhook:-${url:-}}}" "${msg}"                    || failed+=( webhook ) ;;
            *) failed+=( "${p}" ) ;;
        esac

    done

    (( ${#failed[@]} )) && die "Failed to send ( ${failed[*]} ) notification"
    success "OK: notification sent successfully ( ${plats[*]} )"

}
cmd_notify_telegram () {

    source <(parse "$@" -- status title message token chat)
    cmd_notify --platform telegram --status "${status}" --title "${title}" --message "${message}" --token "${token}" --chat "${chat}" "${kwargs[@]}"

}
cmd_notify_slack () {

    source <(parse "$@" -- status title message webhook)
    cmd_notify --platform slack --status "${status}" --title "${title}" --message "${message}" --webhook "${webhook}" "${kwargs[@]}"

}
cmd_notify_discord () {

    source <(parse "$@" -- status title message webhook)
    cmd_notify --platform discord --status "${status}" --title "${title}" --message "${message}" --webhook "${webhook}" "${kwargs[@]}"

}
cmd_notify_webhook () {

    source <(parse "$@" -- status title message webhook)
    cmd_notify --platform webhook --status "${status}" --title "${title}" --message "${message}" --webhook "${webhook}" "${kwargs[@]}"

}

cmd_pretty_help () {

    info_ln "Pretty :"

    printf '    %s\n' \
        "" \
        "normalize                  * Remove trailing whitespace in git-tracked files" \
        "" \
        "typo-check                 * Typos check docs and text files" \
        "typo-fix                   * Typos fix docs and text files" \
        "" \
        "taplo-check                * Validate TOML formatting (no changes)" \
        "taplo-fix                  * Auto-format TOML files" \
        "" \
        "prettier-check             * Validate formatting for Markdown/YAML/etc. (no changes)" \
        "prettier-fix               * Auto-format Markdown/YAML/etc." \
        ''

}

cmd_normalize () {

    ensure_tool git perl

    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo"
    git diff --quiet -- || die "normalize: requires clean worktree"
    git diff --cached --quiet -- || die "normalize: requires clean worktree"

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
cmd_typo_check () {

    ensure_tool typos

    local -a cmd=()

    local config="$(config_file typos toml)"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    run typos --format brief "${cmd[@]}" "$@"

}
cmd_typo_fix () {

    ensure_tool typos

    local -a cmd=()

    local config="$(config_file typos toml)"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    run typos -w "${cmd[@]}" "$@"

}

cmd_taplo_check () {

    ensure_tool taplo
    run taplo fmt --check "$@"

}
cmd_taplo_fix () {

    ensure_tool taplo
    run taplo fmt "$@"

}

cmd_prettier_check () {

    ensure_node
    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --check "**/*.{md,mdx,yml,yaml,json,jsonc}" ".prettierrc.yml" "$@"

}
cmd_prettier_fix () {

    ensure_node
    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --write "**/*.{md,mdx,yml,yaml,json,jsonc}" ".prettierrc.yml" "$@"

}

cmd_safety_help () {

    info_ln "Safety :"

    printf '    %s\n' \
        "" \
        "leaks                      * Scan for secrets and credential leaks" \
        "trivy                      * Scan for vulnerabilities and secrets" \
        "sbom                       * Generate SBOM for the project" \
        ''

}

cmd_leaks () {

    ensure_tool gitleaks
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
cmd_trivy () {

    ensure_tool trivy
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
cmd_sbom () {

    ensure_tool syft
    source <(parse "$@" -- src format out config)

    format="${format:-cyclonedx-json}"
    out="${out:-${OUT_DIR:-out}/sbom.json}"

    local -a cmd=()

    config="${config:-"$(config_file syft yaml yml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )
    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"
    run syft scan -o "${format}=${out}" "${cmd[@]}" "${kwargs[@]}" -- "${src:-dir:.}"

}

load_norm_name () {

    local s="${1-}"

    [[ -n "${s}" ]] || return 0

    s="${s//[^[:alnum:]_]/_}"

    while [[ "${s}" == *"__"* ]]; do
        s="${s//__/_}"
    done

    s="${s##_}"
    s="${s%%_}"

    [[ -n "${s}" ]] || s="_"
    [[ "${s}" =~ ^[0-9] ]] && s="_${s}"

    printf '%s' "${s}"

}
load_path_names () {

    local path="${1-}" base="" name="" dir="" parent=""

    [[ -n "${path}" ]] || die "load_path_names: missing path"

    path="${path%/}"
    [[ -n "${path}" ]] || die "load_path_names: invalid path"

    base="${path##*/}"
    name="${base%.sh}"

    if [[ "${path}" == */* ]]; then
        dir="${path%/*}"
        parent="${dir##*/}"
    else
        parent=""
    fi

    printf '%s\n' "${name}" "${parent}"

}

load_walk_modules () {

    local dir="${1:-${MODULE_DIR:-}}" path="" ex="" skip=0
    shift || true

    [[ -n "${dir}" ]] || die "load_walk_modules: missing module dir"
    [[ -d "${dir}" ]] || die "load_walk_modules: invalid module dir: ${dir}"

    dir="${dir%/}"

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
            load_walk_modules "${path}" "$@"
            continue
        fi

        [[ -f "${path}" ]] || continue
        [[ "${path}" == *.sh ]] || continue

        printf '%s\n' "${path}"

    done

}
load_source_modules () {

    local dir="${1:-${MODULE_DIR:-}}" path=""
    local -a modules=()

    [[ -n "${dir}" ]] || die "load_source_modules: missing module dir"
    [[ -d "${dir}" ]] || die "load_source_modules: invalid module dir: ${dir}"

    mapfile -t modules < <( load_walk_modules "${dir}" )

    for path in "${modules[@]}"; do

        [[ -n "${path}" ]] || continue
        [[ -e "${path}" ]] || die "load_source_modules: path not found: ${path}"
        [[ -L "${path}" ]] && die "load_source_modules: refusing symlink: ${path}"
        [[ -f "${path}" ]] || die "load_source_modules: not a file: ${path}"
        [[ "${path}" == *.sh ]] || die "load_source_modules: not a .sh file: ${path}"

        source "${path}" || die "load_source_modules: failed to source: ${path}"

    done

}
load_doc_approved () {

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
load_module_docs () {

    local alias="${ALIAS:-${ALIAS_NAME:-${APP_NAME:-"--alias"}}}"
    local lang="$(which_lang)" line="" fn="" seen_any=0

    info_ln "Usage:"

    printf '%s\n' \
        "" \
        "    ${alias} [--yes] [--verbose] <cmd> [args...]" \
        ''

    info_ln "Global:"

    printf '%s\n' \
        "" \
        '    --yes,    -y     Non-interactive (assume yes)' \
        '    --verbose,-v     Print executed commands' \
        '    --help,   -h     Show help docs' \
        '    --version        Show version' \
        ''

    while IFS= read -r line; do

        fn="${line##declare -f }"
        load_doc_approved "${fn}" "${lang}" || continue

        "${fn}" || true
        seen_any=1

    done < <(declare -F)

    (( seen_any )) || printf '%s\n' '(no command docs found)' ''

}

load_dispatch () {

    local cmd="${1-}" sub="${2-}"

    case "${cmd}" in
        version|v|--version) printf '%s\n' "${APP_VERSION:-unknown}"; return 0 ;;
        ""|help|-h|--help|h) load_module_docs; return 0 ;;
    esac

    local lang="$(which_lang)"

    local fn="cmd_$(load_norm_name "${cmd}")"
    local fn_sub="${fn}_$(load_norm_name "${sub}")"

    local fn_lang="cmd_${lang}_$(load_norm_name "${cmd}")"
    local fn_sub_lang="${fn_lang}_$(load_norm_name "${sub}")"

    if declare -F "${fn_sub_lang}" >/dev/null 2>&1; then
        shift 2 || true
        "${fn_sub_lang}" "$@"
        return $?
    fi
    if declare -F "${fn_lang}" >/dev/null 2>&1; then
        shift || true
        "${fn_lang}" "$@"
        return $?
    fi
    if declare -F "${fn_sub}" >/dev/null 2>&1; then
        shift 2 || true
        "${fn_sub}" "$@"
        return $?
    fi
    if declare -F "${fn}" >/dev/null 2>&1; then
        shift || true
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
            --yes|-y)     YES=1; shift || true ;;
            --verbose|-v) VERBOSE=1; shift || true ;;
            -h|--help)    saw_help=1; shift || true ;;
            --version)    saw_version=1; shift || true ;;
            --)           shift || true; break ;;
            -*)           die "Unknown global flag: ${1}" ;;
            *)            break ;;
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

    CMD="${1-}"
    [[ $# -gt 0 ]] && shift || true
    ARGS=( "$@" )

}
load_run () {

    local ec=0
    load_parse "$@"

    if [[ ${#ARGS[@]} -gt 0 ]]; then load_dispatch "${CMD}" "${ARGS[@]}" || ec=$?
    else load_dispatch "${CMD}" || ec=$?
    fi

    return "${ec}"

}
load_run_entry () {

    cd_root
    load_source_modules
    load_run "$@"

}

ensure_bash "$@"
load_run "$@"
exit 0

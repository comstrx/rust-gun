#!/usr/bin/env bash
set -Eeuo pipefail

YES="${YES:-0}"
VERBOSE="${VERBOSE:-0}"

APP_NAME="gun"
APP_VERSION="0.1.0"

APP_BASH_VERSION="5.2"
TEMPLATE_PAYLOAD_KEY="__TEMPLATE_PAYLOAD_KEY__"

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

    message "ðŸ’¥" "$@";

}
success () {

    message "âœ…" "$@";

}
warn () {

    message "âš ï¸" "$@";

}
error () {

    message "âŒ" "$@";

}
info_ln () {

    messageln "ðŸ’¥" "$@";

}
success_ln () {

    messageln "âœ…" "$@";

}
warn_ln () {

    messageln "âš ï¸" "$@";

}
error_ln () {

    messageln "âŒ" "$@";

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

    local tag="${1:-tmp}" base="${2:-${TMPDIR:-/tmp}}"

    mkdir -p "${base}" 2>/dev/null || true
    local tmp="$(mktemp -d "${base%/}/${tag}.XXXXXX" 2>/dev/null || true)"

    if [[ -z "${tmp}" || ! -d "${tmp}" ]]; then
        tmp="${base%/}/${tag}.$$.$RANDOM"
        mkdir -p "${tmp}" 2>/dev/null || die "tmp_dir: failed (${base})"
    fi

    chmod 700 -- "${tmp}" 2>/dev/null || true
    printf '%s' "${tmp}"

}
tmp_file () {

    local tag="${1:-tmp}" base="${2:-${TMPDIR:-/tmp}}"

    local dir="$(tmp_dir "${tag}" "${base}")"
    local tmp="$(mktemp "${dir%/}/${tag}.XXXXXX" 2>/dev/null || true)"

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

        printf 'âŒ %s\n' "${msg}" >&2
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

forge_template_dir () {

    ensure_pkg awk tail tar mkdir rm dirname

    [[ -d "${TEMPLATE_DIR:-}" ]] && { printf '%s\n' "${TEMPLATE_DIR}"; return 0; }

    local src="${0}"
    [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]] && src="${BASH_SOURCE[0]}"
    [[ -f "${src}" ]] || die "Source bundle not found: ${src}"

    local key="${TEMPLATE_PAYLOAD_KEY:-}"
    local line="$(awk -v key="${key}" '$0 == key { print NR + 1; exit }' "${src}" 2>/dev/null || true)"
    [[ -n "${line}" ]] || die "Template payload marker not found"

    local tmp="$(tmp_dir "template-installer")"
    local out="${tmp}/template"

    ensure_dir "${out}"

    tail -n +"${line}" -- "${src}" | tar -xzf - -C "${out}" --strip-components=1 || {
        rm -rf -- "${tmp}" >/dev/null 2>&1 || true
        die "Failed to extract template payload"
    }

    local dir="$(cd -- "${out}" 2>/dev/null && pwd -P)" || {
        rm -rf -- "${tmp}" >/dev/null 2>&1 || true
        die "Failed to resolve template dir"
    }
    [[ -d "${dir}" ]] || {
        rm -rf -- "${tmp}" >/dev/null 2>&1 || true
        die "Extracted template dir not found"
    }

    printf '%s' "${dir}"

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
        "new-lib                    * Create a new library project from template" \
        "new-ws                     * Create a new workspace project from template" \
        ''

}
cmd_new () {

    source <(parse "$@" -- :template name dest placeholders:bool=true git:bool=true)

    local root="$(forge_template_dir)"
    local conf="${root}/conf"

    template="$(forge_resolve_name "${template}")"
    name="${name:-"$(forge_display_name "${template}")"}"
    dest="$(forge_resolve_dest "${dest}" "${name}")"

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
    local status_icon="ðŸ¤”" status_label="Unknown"
    local duration="0s" date_str="$(date -u +%F 2>/dev/null || date +%F)"

    [[ -n "${status}" ]] || status="${STATUS:-${GITHUB_STATUS:-}}"
    [[ -n "${title}" ]] || title="${WORKFLOW_NAME:-${GITHUB_WORKFLOW_NAME:-CI}} Workflow"
    [[ -z "${url}" && -n "${server_url}" && -n "${repo}" && -n "${run_id}" ]] && url="${server_url}/${repo}/actions/runs/${run_id}"

    case "${status,,}" in
        success|succeeded|ok|passed|pass)    status_icon="âœ…" ; status_label="Success" ;;
        warn|warning|warnings)     status_icon="âš ï¸" ; status_label="Warning" ;;
        fail|failed|failure|error)  status_icon="âŒ" ; status_label="Failed" ;;
        cancel|canceled|cancelled) status_icon="ðŸŸ¡" ; status_label="Cancelled" ;;
        skip|skipped)              status_icon="âšª" ; status_label="Skipped" ;;
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
        "ðŸ’¥ ${title} :" \
        "" \
        "      ( Status )      :  ${status_icon} ${status_label}" \
        "" \
        "      ( Duration )  :  ${duration}" \
        "" \
        "      ( Date )         :  ${date_str}" \
        "" \
        "      ( Repo )        :  ${repo}" \
        "" \
        "      ( Commit )   :  ${repo_name}@${ref} â€¢ ${sha}" \
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

install_confirm () {

    local bin="${1:-}" force="${2:-0}"

    [[ -n "${bin}" ]] || die "Missing install target"
    [[ -L "${bin}" ]] && die "Refusing to overwrite symlink ${bin}"
    [[ -e "${bin}" && ! -f "${bin}" ]] && die "Refusing non-file target ${bin}"
    [[ -e "${bin}" ]] && (( ! force )) && { confirm "Overwrite ${bin}?" || die "Canceled."; }

}
install_line_once () {

    ensure_tool grep rm mv dirname mktemp cat sleep kill tail

    local file="${1:-}" line="${2:-}" owner_pid="" max_tries=200 i=0

    [[ -n "${file}" ]] || die "Missing file"
    [[ -n "${line}" ]] || die "Missing line"
    [[ -L "${file}" ]] && die "Refusing to modify symlink: ${file}"

    ensure_file "${file}"

    LC_ALL=C grep -Fqx -- "${line}"      "${file}" 2>/dev/null && return 0
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
        (( i < max_tries )) || die "Lock timeout for ${file}"

        sleep 0.05 || true

    done

    LC_ALL=C grep -Fqx -- "${line}"      "${file}" 2>/dev/null && { rm -f -- "${lock_file}" 2>/dev/null || true; return 0; }
    LC_ALL=C grep -Fqx -- "${line}"$'\r' "${file}" 2>/dev/null && { rm -f -- "${lock_file}" 2>/dev/null || true; return 0; }

    local tmp="$(mktemp "${dir}/.tmp.install.XXXXXX")" || { rm -f -- "${lock_file}" 2>/dev/null || true; die "mktemp failed in ${dir}"; }

    {
        cat -- "${file}"
        [[ -s "${file}" && -n "$(tail -c 1 -- "${file}" 2>/dev/null)" ]] && printf '\n'
        printf '%s\n' "${line}"
    } > "${tmp}" || { rm -f -- "${tmp}" "${lock_file}" 2>/dev/null || true; die "Failed writing temp file"; }

    mv -f -- "${tmp}" "${file}" || { rm -f -- "${tmp}" "${lock_file}" 2>/dev/null || true; die "Failed replacing ${file}"; }
    rm -f -- "${lock_file}" 2>/dev/null || true

}
install_path_once () {

    local rc="${1:-}" alias="${2:-}"

    [[ -n "${rc}" ]] || die "Missing rc"
    [[ -L "${rc}" ]] && die "Refusing to modify symlink: ${rc}"

    ensure_file "${rc}"
    install_line_once "${rc}" "# ${alias}"

    if [[ "${rc}" == */.config/fish/config.fish ]]; then install_line_once "${rc}" 'set -gx PATH $HOME/.local/bin $PATH'
    else install_line_once "${rc}" 'export PATH="$HOME/.local/bin:$PATH"'
    fi

}

install_write_entry () {

    local out="${1:-}" entry="${2:-}"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        "exec /usr/bin/env bash ${entry} \"\$@\"" \
        > "${out}" || die "Failed writing ${out}"

}
install_write_src () {

    local out="${1:-}" src=""

    [[ -n "${0:-}" && -f "${0}" ]] && src="${0}"
    [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]] && src="${BASH_SOURCE[0]}"

    if [[ -n "${src}" ]]; then cat -- "${src}" > "${out}" || die "Failed to copy: ${src}"
    else cat > "${out}" || die "Failed reading script from stdin"
    fi

    [[ -s "${out}" ]] || die "Invalid source code"

}
install_bin () {

    ensure_tool chmod mkdir mv rm mktemp cat

    local alias="${1:-}"
    local force="${2:-0}"

    local rc="$(rc_path)"
    local bin_dir="$(home_path)/.local/bin"
    local bin="${bin_dir}/${alias}"

    validate_alias "${alias}"
    ensure_dir "${bin_dir}"
    install_confirm "${bin}" "${force}"

    local tmp="$(mktemp "${bin_dir}/.tmp.${alias}.XXXXXX")" || die "Creating mktemp failed in ${bin_dir}"

    if [[ -f "${ENTRY_POINT:-}" ]]; then install_write_entry "${tmp}" "${ENTRY_POINT}"
    else install_write_src "${tmp}"
    fi

    run chmod +x -- "${tmp}" || die "Failed to chmod: ${tmp}"
    mv -f -- "${tmp}" "${bin}" || die "Failed to replace: ${bin}"

    install_path_once "${rc}" "${alias}"
    printf '%s\n' "${bin}"

}

install () {

    source <(parse "$@" -- :alias="${APP_NAME:-}" force:bool)

    local bin="$(install_bin "${alias}" "${force}")"
    success "Installed: ( ${alias} ) at ${bin}"

}

run_version () {

    printf '%s\n' "${APP_VERSION:-unknown}"

}
run_norm_name () {

    local s="${1-}"
    [[ -n "${s}" ]] || return 0

    s="${s//[^[:alnum:]_]/_}"
    while [[ "${s}" == *"__"* ]]; do s="${s//__/_}"; done

    s="${s##_}"
    s="${s%%_}"

    [[ -n "${s}" ]] || s="_"
    [[ "${s}" =~ ^[0-9] ]] && s="_${s}"

    printf '%s' "${s}"

}
run_walk_modules () {

    local dir="${1:-}" path="" ex="" skip=0
    shift || true

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
            run_walk_modules "${path}" "$@"
            continue
        fi

        [[ -f "${path}" ]] || continue
        [[ "${path}" == *.sh ]] || continue

        printf '%s\n' "${path}"

    done

}
run_source_modules () {

    local dir="${1:-}" path=""
    local -a modules=()

    [[ -n "${dir}" ]] || die "Missing module dir"
    [[ -d "${dir}" ]] || die "Invalid module dir: ${dir}"

    mapfile -t modules < <( run_walk_modules "${dir%/}" )

    for path in "${modules[@]}"; do

        [[ "${path}" == *.sh ]] || die "Invalid .sh file: ${path}"
        [[ -f "${path}" ]] || die "Invalid file: ${path}"
        [[ -L "${path}" ]] && die "Refusing symlink: ${path}"

        source "${path}" || die "Failed to source: ${path}"

    done

}

run_validate_docs () {

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
run_docs () {

    local alias="${ALIAS:-${ALIAS_NAME:-${APP_NAME:-"--alias"}}}"
    local line="" fn="" seen_any=0
    local lang="$(which_lang)"

    info_ln "Usage:"

    printf '%s\n' \
        "" \
        "    ${alias} [--yes] [--verbose] <cmd> [args...]" \
        ''

    info_ln "Global:"

    printf '%s\n' \
        "" \
        '    --yes,     -y      * Non-interactive (assume yes)' \
        '    --verbose, -r      * Print executed commands' \
        '    --help,    -h      * Show help docs' \
        '    --version, -v      * Show version' \
        "    --install, -i      * Install ${alias} at ~/.local/bin/" \
        "    --upgrade, -u      * Upgrade ${alias} and update ~/.local/bin/" \
        ''

    while IFS= read -r line; do

        fn="${line##declare -f }"
        run_validate_docs "${fn}" "${lang}" || continue
        "${fn}" || true
        seen_any=1

    done < <(declare -F)

    (( seen_any )) || printf '%s\n' '(no command docs found)' ''

}
run_dispatch () {

    local cmd="${1:-}" sub="${2:-}"
    shift || true

    case "${cmd}" in
        help)    run_docs;    return 0 ;;
        version) run_version; return 0 ;;
        install) install "$@"; return 0 ;;
        upgrade) install "$@" --force; return 0 ;;
    esac

    local lang="$(which_lang)"
    local fn="cmd_$(run_norm_name "${cmd}")"
    local fn_sub="${fn}_$(run_norm_name "${sub}")"
    local fn_lang="cmd_${lang}_$(run_norm_name "${cmd}")"
    local fn_sub_lang="${fn_lang}_$(run_norm_name "${sub}")"

    if declare -F "${fn_sub_lang}" >/dev/null 2>&1; then
        shift || true
        "${fn_sub_lang}" "$@"
        return $?
    fi
    if declare -F "${fn_lang}" >/dev/null 2>&1; then
        "${fn_lang}" "$@"
        return $?
    fi
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
run_parse () {

    YES=0 VERBOSE=0 CMD="" ARGS=()
    local help=0 version=0 install=0 upgrade=0

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -y|--yes)     YES=1;     shift || true ;;
            -r|--verbose) VERBOSE=1; shift || true ;;
            -h|--help)    help=1;    shift || true ;;
            -v|--version) version=1; shift || true ;;
            -i|--install) install=1; shift || true ;;
            -u|--upgrade) upgrade=1; shift || true ;;
            --)           shift || true; break ;;
            -*)           die "Unknown global flag: ${1}" ;;
            *)            break ;;
        esac
    done

    (( help ))    && { CMD="help";    return 0; }
    (( version )) && { CMD="version"; return 0; }
    (( install )) && { CMD="install"; return 0; }
    (( upgrade )) && { CMD="upgrade"; return 0; }

    CMD="${1:-}"
    [[ $# -gt 0 ]] && shift || true
    ARGS=( "$@" )

}

run () {

    cd_root
    [[ -d "${MODULE_DIR:-}" ]] && run_source_modules "${MODULE_DIR}"

    run_parse "$@"
    run_dispatch "${CMD}" "${ARGS[@]}"

}

ensure_bash "$@"
run "$@"
exit 0

__TEMPLATE_PAYLOAD_KEY__
‹      ì=msÛ6Òý¬™þT9;­)‹Ô›­úî’:iëNÒd’´÷<“z$ˆ„$Ä$Á ¥Í¿]€¢HJŽe[Vªœ8‹ö}± !Å‚È§Š~qW®N«…Ÿv§UÏÎ®/ì–Ýn7ÛMÇ†r»Ù¶Û_Ö=Ž)»©hLÈ®ðx8
¨T,^Vïºç[z©ÿ}>¸/X•ÿ­N»ÓÀzv«Yoìø¿‰«ÀÿˆqBpsþ·›P´ãÿ®EþŸÒx$jJþºú@·›Í«øßht:†ÿŽcwÚÀÊ€ÿõuàc×ÿ8ÿßDÔ½ #vþe%¤#ÿ$Õ^ï—GÏžôzÕ/+—,–\„XZ¯Ùµ:1«´È©;6” ÔX¹šví+úÜe¡ÔŸ½&Ï_’GÐ×˜YŽ†3ê™þ^>yôøÙ“ZàA©Ç¤óhÖC¯÷øÉ«Ó—g/^Ÿ=ÿEÈY‰˜3	ÏßT=vÉ|,T–Â—U@ä‚M'"öLx@5ñ¬ü×WO^šò˜EBr%â©éôå“Ï{¿¾|ª{‹€E@¡%¾¬¼ñXÄB….Œè<-¹´J¥€HMFÈ£šmû<T²†ôƒJÃD%1ëñÐADøØåŸÄG±!À›VH€ Õ²Éà›A†CÆ^OªéªÍ°ÛžS·zÜã"«µJÂD2oÕº’YOD€T/ý2³_V.%(UÏ.v_¥¾/&P>¡qå2Wµ@-¨>oíÆ ==šRÚ
†t‰¡eLña€\äkbqÁÂTÈ:v}ES”"ß_-éŠ<LbÉ´ø­P9bwW«íq©éÊ¼jx·Ü£€º±¸êµñ®x¨¦Q¦žÈ}eï¸Ê3„†zÜ ÁÈt+KÂIL£^*gs@sU¹°U%"QËŠY sðv­E
]}‡¢$ÁhÁg¡	EbZÌdxà· #Aâ+€SQLmaA¤AŒ¢X¹Ïj1ó•hqE¤¬ÿ /Âc#Z0L…m0¢JSFy˜§ˆXAT`,±@NƒZ?´ ƒ¨§·• Y*Ïú’AÇ0Ä!Ì{lPI€õ‰5}¨?/\»5¤h²x8³¦ÇZMŸT³1C•¥x×	÷=‡s¯L†ú"œV{ŽV:¤u¡ö©Ýï'¿ã?nªä:§+ÇÿN½3ˆÿ;0ØÅÿ›¸®äÿ§×Äÿõ†]Ïâ˜Büo·:Í]ü¿‰+‹ÿ³ðßð¿ºû/„þ•(ø\Žgæ´Ry3d£Xy^Ñ` D¨G]üR=¯”‚æJZçOQ/ÂªÖjUòª½ðð¼40zN«â·Z£ýÔtÜÖëJýO)»Ž>®Õÿ¦ÖÿfŒ£ÝDý‡Ïþoâúú;í§j[Ò²ç˜®”‡ûÈŸ„ÔÝ.£ªÛø`9zñn+w»õÿ1ƒ€·ÓoßÛðà»
è±é"êªn–ôÃtï‡_íWYHa*Ü%–53.$ßø»ù¸ Ðt™”Ý.N:öÝû§¦ïßýZ¢ÿ`—ÇlàÊñŸÝétÿ«ïòÿ›¹®æ¿Öäµx€ëì»ÞÌì¿ãÔÑþ7ÎÎþoâJ$#Yz²Ûý3»ïb‘Dó‡=4ÐätöýÃwl<7þßUÐŒkñéiáÙw»äA¢æmfæÝgŠàœÑ»5Ý$ ñ…és¿j`êb4ðºÉÈTë“ÐÅ(t¿šs5Õò×à¯8^ƒö¸ÿW¾ìJÿµÜsÍš|Hï?ÌG2ä!„½ûÆ½•(öÕ~ª@yR@Õ"!³jðäSòQÿÙ;ŠI²5:€[ØÇvvö×Gø¿6pý·í,þ¯w0ÿãØíæÎþoäZfÂ‘ø<ÿó˜Ù«¢üOÇîºÝµ¨ÿ2v×¼dõü¯Ý±±>š»ý_¹–ó¾¬)÷ƒ×uöÌýÜþƒãGÿn`gÿ7p~¥m:ÑK—µ
æt!JŽW‘Ô#àš©©c<Â×oÜ: žãÜxháâ¾£àˆõ/ò= 0.VÐ\0^ý	+’ÿèèÝÄ×;/ò	®åúÀúÀµñ_£Ùÿ†^ÿ©7[;ýßÈ•éÿ÷Àq\®/„X”	¿\9&ü²òa·¼þ÷¿õ_1¹Þåÿ›ÏÿáicÿmäºŠÿëËþ®`ÿ›yü×Òó„ýßÄµ0ÿÿú
€^‘ËYôf9³ïªÇþøjYîô ÜíÒçkIü—D‘?µÜ1¸üõ¸›Ìÿ[uÿí þïìÿý_×ðæuC>ºã6°kì?ò¿Ñj4›m”§a·vû¿6rU¾&z›ºuÉ1Ü&¸[·Ry“•Ÿ—ö‚Õ«ð”‘ˆ•¬¦ŠáŽ]‹ú>§¡ËÎ+I¬7¤•Šd÷ð0¦“Úˆ«q2 gCŠ…ªæŠàpÖvÖôpBe xÀô´(‰4ñ8t‡’˜ï~$ÄÈ¿IŸ¦Avð‘¸ŒG7 ïñËKžD¨N¸ßŠåê¸â=÷}zƒÞÒ×có†½E×[¥kt,,WÄTr÷â¼À[»f×šÕÙJ%ÕËéY
ðHÂ8¡~Û¤¤±:ŒD	w8*ÃhávÃA¸>Ší›Ð¾µ: §7¥³øî€|öî¼¤0Zgu³Uâ2|ihu BÊ£å±?¶ª}P‰â¾\åÜdXIèŽ§eÎdnLýa±½ä]}\	ºD`WçÏ[iÉéµ£ÖÊ ¸ãx‹Õ™ùBA½%ÃX‘k@Ýzk%/Gw‚×Ò¯9K˜T_@$B-1LÍÕ-f£²"ƒutjÎÍ Xhàªh™,Í›XIJNCEŒËQíhu8ì¤‰ã¬Žx!õÞÊe`ìæñêp¦aY €½:—’ëØƒ{àï„Ò„ú_ÐÊ›8"^¬½[°Þˆïê|ÊC2ú°nxFt¬®Ó˜-˜‘dƒ;›×	iÄ-Þ>j[‘kÁWOL¤5
“E¼sTt‚e0`Vw@)œwGí^»¹Þñi0øúêÜÎ.´íX¿÷l¹ˆœýQ­±ºÝ›0&æ—Kâ˜›À
øÛ%Öêc>åSÏÍ6q]3ÿŸMMð×[÷ññù»Ù¶[åù£½{ÿc#WaþŸr› ·Q}Ò÷»X\£ñ€«˜ÆÓ²
5Ñ&LÆlöVXËªYèÁqª
~ŠÛÇmóÍ#®ë¹z.#­4{¿ë˜’ô£˜â®€ÂIQ¿ä5û[a ¶c¡Z¯{ ®[ÆÝÑ“Ã\ßm«n[Ø$…šÄ<+kÌ¾«Ëði8:t]_]+ô2ûkòÒ5ÇY,úš£ÅÛÛ÷8bÀX0úÁ¢×m–)[/±¶qìtŽK´}+$‹Æ~\"îÏ‚‘—Ü³i©ÿ·b õ.ËsoÄµQ È’w>€VËv¥dèZb²¸ÔØ9w‰ƒ<ª/Ò—;v5LÞƒ[æM›:VÄ®cÕëÜØbC^ì¾Ì]è½má<xÞ»íØN©ïÒÇA©ûÇô¼3Ê‹G¥þ!JäÑ’	ó->±üÇK„ºUKiÔgïÀo»c%ÊÄxðƒôYq(\]¡·ìÚ°«ÖbsÞƒî;ÍÃ-dIa(¾–×³Òy;‹%l%')÷‚â>& ÿµ<zñÌÈ§%I"_“2Àýàƒ
:A•"^×ˆƒê±Ð›Ó4mój}ÜÃ¡¡!1Gê1$jÌeº‹ìf˜Ï-û'ÅÛ>íÓ¶t	Þ7Á'“÷‚@’Ý‡yù½B6 S¸Ÿ‡Uä¤qÆõs²Z­¼FÖÁ%ß§ØA»”ÁÌ›mÄú7¢FAåÖG’Ûkå"…y
uf¦?£Ðë1[B —³¥
ðq
Í>drN‘T‘Ÿ@LÙ”œDc}ópÁ¦?]%·ÙÎýT„
yIBAÌñ5Gs€ßÏžëú®ÅòµMÌÂ,îx­<õ˜¯¨ÁÂºnÕwyfüÁdSŸ$‘Ä†ñ+$¡±H€‘ùóÀHyd,&¤oÐïkü‘{éˆy5òè7Å#vFùŠÃW‰îDŽi,–dÀ† «Qñ›oë²h9ÊØà«el=±Ï+ò3ò (“ášH@±F~`’žZ¤Æ iìGåÑèÂGÌ¨ú5ëy, Ú+qU‘t*	p	¢xØ…0= YÇ‘R%@h®5WSe½ƒÔHé¢'yº<M‡²¡kÉãd8ô‘õR ÃµÈTŽjä–a£œê ¼U¸Ú*1ß·æÇCixº7Ë `ý"ŒTÉDFÜå"Y\rl’ÖGªÒ:_žBÏCÐ€‡`ÇŠZ’ÊÌÒX¹¤>7˜n,žpÜ?”R™‚Ê˜µ×Ì’€y›cø#ñìlÿ¥$g¿‘“Ñ€_>LÛ\ŸNÕ”&.€b6¢è"†±ðÉl=ÕCO‚t<R$±«{Èžyœ‹½^®bªó"æl/yøíaÌ†¸?ŽzéÒn6Î/ºþìE@Õ?_?ù¿×!Ápdñáˆ°”Éõí¡ˆú›Sâ19óÉo,¾ ADN¼Ks÷04Pje‰Ðë6[E	‹‹12bøþŽW^k´œk5ÿ·ÉQA›YÚÚ²0ŽnyNg* ?
º¸ 19	tƒqŒoéXìF!|ø5Eå
õ(Að Ïï_ð<zq&kä™‰Ô#ÜC“Îð’B!„gž˜`´p'*ë——¾5D,“;«”Ò½ÇÅ•»²nGëÔ2Ž`|â¹ø¹ŠUZf…Qöì%Áì™9uÉš¬˜ËË&šVs¨dÏ2ê/9D®õp5òŸ1÷™®dzÃÄFG½‘Å"TÄ#ÏnÅ‚q´Ãž5³Ã¸|Ì|`;1GÈj!pŒ(î9(ÔWô&TÞ%°ÏT†ÑylH_œŸëà;@ÐŸ—?œ§^oUžè	êan›à|[cO…²wÔEñÊfp& ÇxU?:àv82t@âá~ý¾V©¼b€ÊLÔb Ÿ­ÃvÃiØí&™€±Å8åöÃ¸AÐý4¢ßb©}š\Pùž<
¡µ˜p÷=9ñu½­ì63Ùmåewïu&y j}óŽqæ
È¯	£h\àh€ó)3=ë/œO&•W}pÞ¯ímÍ—L~O±öüÕª®§ý[âƒBˆØTLáö^ý^·9^–ë¢[§!è÷P`x¨fFnz âè‚¬,PÓLô¶JŸEè²žËò!òÿ£ÍûI&äd
wc™Ü&6¶qmu[&hë-Ü·žK™„^,¸GžÂàÝéª8×1{º(ã&¼u›ñòö˜ãN1öø1fQÄ<íû'.À™ôÌ—x)_ö~åïƒ½ô>djþÅ¨~Ÿ.ÌúÿéHdŒG~kàÐ`nWÇ!ºJÌp«Š‡q„D|þžêiÁUà0	8ÿ„úàODÄBãøQ«Ã¹æ˜p€Ei®—_˜Ð¡8Ç¬F–Ó«‚#DÚu+ß3ð_CèVö¤ŠûÚéS¾O†ýùãÙY®Æ«Y™ÆìvÏ¢Ëæ#Ï‹û•JI§¡[æ	]ŠçªALn¨eQJ«Ñª·:C‡ìãBD%…A}) ðèÖŸoÜìù@  Þ Øÿ–rÝlÞ¯›ÅfÖ2t”8`@ êy†ö§©<ÁP*Ë†ÒpÚ­V³U#=þéS’ÿUwn¤q¯Â£•ýµh£y†@‘ú q<}@fÙUc­)&)9ÐÕMôO·.+iîcè˜ú3Ì8„Ë`Éaòð6Ð÷·Á´æšo¶™<éÅ[ ‰þ¼AŽfqêö6ä^äh2'“_üLÛÌ¬i»B£{q‘%²9s²5rd“‡øc20wÁOËCò-Q	þFº²ûÞ@xSkæÚ>2?ò0£C^Ó©.î„âDoï@äÆœÈwÍO~~Øœ§SÚµ ü±¢4á1"Ÿþ(Ò¡Ä½a0—c‘øøùK†Û@&!ŒÂ%¼þ,½äô·+1·	ªwæT?.ï¦™¥9 º×¿T6¤<† 4Ï¹Àin`(»”MûòŠüTëÈvìãæ¡S«µ@Ðõè‡Gg§¯1‚«Ìó|Æbp7n!(Gvö5<êáûyÌ½`^?3HÈ'Y)D„û³¡{ìÐðc6rS#>ÔV‹l{xvæì8“;ŸÛ}äã6dU¨£‹¼Mð`µ4ÿ3(Œ‰·™¨Oaæ†K4ôB\RPG~]´ësz6¶™*÷ÙÙsï‰«{¹Ti*Lï3“÷m¦ÞúÕž»Ö;/ ~vÐìÏ3·íRÜajôŠÌ¾¢¼×›m8ìƒy“”ît¹Pû¥CD¢ßt%2Ñx«#{Rèöœòùˆo¶û/¥5ªµÉt5ßjB®oiUSmNÀâÞÒLNE¢$÷Xq5j–ÒIÇ­Ì{1óKaYægŒ`ôï`¢,öÍï¨v»Ìçn9íù|ÈðÐóó¤Û8Õèeï§n,¿—ÏÄWS? UíÆõÎÌãÝPâÿ©*Ø[5OtƒÓÇL÷V-¤.'÷ÚR„­N.Ðe#™Â­§ÒÓ‚;­Ýå	?µd.O$ó÷T4üÝgz«ÅÓÜ¥ùÄÅÝÏVF7˜:ÜÛÛK—¡©!¡N åæMúý2
æM+$+•³=Ìé2$ÔØÇÝ°z9x´Ú"¾YÃïTúé
>êß|¿oÖxK|¯U—­çý.ñwzuù¿Œ¬y“¶gDvï€ìi	×7Zîñn(ñ?ùÞRCö|ã©Å™áRŸE–qÆ¡”lÌgurù³t±7;¥ë9¿~¯·14ý4YJêy÷§'õq7¥cóÎõÖ-
vxB"ŸºL‚Ç{¥8¨HólísHYl6U97ŸévÉÉ­1Wä(‹Fvßä(Ó·H"uæ2`A·‹/° QŠQOïÕÅj yè?Ø.ÊƒÊOgGÀ­}ÿ¸>ž`+öR›SË	ÅÖ«¿|^ÚòRoReWoÜµ;v½Ý¨T^àvV‘H¶±ÚxI¬(îxÕúnÁ7‘`Z8Â#¼€Hæ nÁ¦<X=;Å÷…KóO”:ÅÀžÂÇÃô\õ½Û«ßœ[ÞaùÅûÛt¸ÔÂdS{Õ®®ÖÈÏ"9yëÞ¶ß,'ÛØ8ÊÙ ye×³CÍ-<)ú¨/òøèjB/yéê5ÈLŒÆ !9Q<­Úkþ¤‘ô·zùEX}ŽÒ7ø"+è£Ç¾1ï¶Å,—P¡p´FíªQ/ygMœÂ×y«œˆç’þKlß—‡ÜåæW†CÆV„cÏDî¥€<Ê
nZCºyæUÐ>˜&´o=öÎxé¾~s@'Lú<äªOþËÞµ7·m+ûû·fòPw¦±oMY¤$ÊvÝ{â<šúLÒd’´çÞññÈ	IŒ(R‡Ëj›ï~w¾II”MËUJLëP|à±,~» vÃÈð‡¿±ý ä#£®Á|_8º!t j)ftÄú®ñ;«Z©Ëå‘CvÂ?Ösî‘Ñ"ïoŠu ¿ŸáŸ¦	ÊS[‰Ý+]tE­öµãÒ%ŸOpé5p× g0!GôneÇe/íæDðãà'[çu4ºåÖ¶™-Góž,çN«“`äê„ï5¹¶ƒ{F	áQ ~Ä‹G!¦1@ˆGší°£Üûè”»ëm¨£‡¢“. ã¨áˆï¶dÐë³Þ–r”À8(¬ª˜°ºïeŠ®ŠJØÅÔT\Ìfj(T‘n¥,…S´ÛÎ”nÉ¢ï†–”[™ueùý4ÛïÜþ\¤ƒÕ¯ªØ»’=Sþ#Ñ>kaØzÇ¨lÀˆl¶ÂŠ NÕ
Œù
Ù‘×þÀ	|ÆðLŠ#þ{s/‰âF`WÉbôÀsäÜv&¡³?À’/Ð€@þH8½Uc“OêÃí=è#7®IÔ[CCc‡¢è+'±ÎYp¦×_á/ŽÏú.[m$"‚Â _z*p¨‰áÀøQ÷#Ï˜­Œ+ö¨ÔW"ê¯Þ’ÿU4¶©4«-^ÝX;òäÊjIÐÞ	ùÀtc„íýìˆ«gá·åýƒÉè72¹4õ‘heËŸ €³„ÍCÂng€ÞôÇÃýîðµ?ÐŒÑ¿-?¥ÏÍZbaýÁàÊº¨Mzr]IÙõ1òF&£Öú`|KH›Îÿ´Ý1ùèàŠ.^<Â¢3}iuSZð9CõwßCÐaAd,H¢\xò‹1±É[ê¹tb¸*S2äy‹®~ÆÕ‰9›Ž¿Þ~6B•fc»}7_êã¯€¬ZŽðY3ž@{¡¦ÞKŒ,ij¼Ì¥¬öOðÐC» ~õ¼Í*_?ƒ³À÷ëgqNÙøª™œv˜ý–Þ’DègÌ0ŸMé­dàï¦¾µZíZë\JWÃÏGˆÿ´&þW¢zw/cMüoEÉÇÿ’{rÿk)ÿKp;Œÿ-~]á‚mˆXwÊ‘C•	Äq"á¡›L E¬g†Ð=Û´èbM-ªTù¸ ÈËÚròa¸Ê•×mŸäã‹('ÕwO"w×Õ&¬$™1ù–ÄA¾È~,\è$’¦¨
É `%)á¹ 
™\©Â;bKÉG{É„«´ÜcÐjm¹©xa[	íTT‘0bXÉD'ªFöE´°‚(KKúcÃ¿aÊÏÿØ*-'ùÎëÅó?&œÿÕ®‚·á=¹rû¿H·ÒZ,Ióù	ÿ¹)üž°/Jkð_«#ðð ï)rºAÿ¶.gT›Ð»j„ñ‘ÿ¹b8aK Bfƒ àÜRÓEÄäÕœ2êô¾!°%f	¯Áô‚o%mºW mMQaû½Äc^{ÍæùÒHÍ…¢"b&LSMa}1¨Lð5~ÔŽ†qðQAÐ J‹+Šá™¢èr<¼~lf<BZ2þSd¼oËr«–ÿÛHeø£;—±NþËÝ^VÿïÈµþ¿•ôí7—–ÝG£(ú¸	Þ>ÞÓÓDGø¡ÑHüúfÿÏ>ÊøSòÝ¥|õ'ù£A ™Ì#}¨ØgNO_ò¿ŽoíüÐøÿ?vsë”IÑøŸù«öG©´üï©½Ž¬ þïª-¥–ÿÛHiþó	 ò26ç?\öjþo#ð¿RÝÓºù¿×‰ô?E•{0ÿ·ºŠZÏÿÛHyý¯ßÿåüí«~¿”È­ž©ý,'\GKëx :6®*4f2êBiöÌ“LvÃL´7pËËˆY’oáúÃDn˜_ÆCÿ…¨ÜYji{t`;Ú´cÆ’‹éÀ6]\³Ãm{?’–¸’0ºœ#B~„ÊÆÀšö\â.Žãû†¥9Ü­5“ªlºÂÒzWð*¼ÆõÑàÁ^XSxa/ÿ]“ûº”°lÇÐ3ínåÚ­tÕ¨)zZEsVð¿`üã¶ûJûXiù/÷z=øhÿëÕö¿­¤%üG…à>*_*­“ÿ-UFþwÚ²Üë¨hÿƒ×kûßVÒ“ÆÐ"Èm²@þxÂu¸™cXži}³¿÷33M›üËvL}ïà‡'/OjîëJÑøŸßßÎ·,m‚ÿÛ=®ÿ)j·–ÿÛHIþ?Œöwþ«ŠZëÿ[I9þW®ý­ÿÛ]Yõ¿–Ú’qþ—ÕzþßJºäg @	ÝÄa®mÞˆíDí½Æ”áÔ,.÷@•{¤åKiŒ_²[
G\ãš¿àË‡Ü¥-wÓÂWçPŒÊi>„Æ‰§„-—çööây÷œC1c&)˜‰Ã¨.ŠúðêüåÛWÍ©Ž*c”Wâå«/>\¼ÿtñî¬õ½±4¿ßÿõã«p‰4³]Ã³…øêÃ«÷ïú¿~xƒŸŒí)Cïù'Éö§uãÈ7†h4?²¾tñ3·Xš¤ò!É‘|I•l®s›HÁ«ÆÐGÇ’}Pñx¶gLÆs•Ó=¨áò0hs×3?I†ü,PBƒÃ×}×[”üŠ{îa}Ü7tÃžº¥>ò-ßezÉWqRßžAƒúÁ¡}Ð˜.úpêc06nH@wô{9u,s<z±˜\ðÙU”§yŸ×(ÊO|„l‚:xÅg}q™xaàØf-ž/]x¢ºjàA«2„àîåé;.ã½xý»3¦SËã6˜õ/ë†ËÉËtáÑ?n^â‰_üˆÁÀÓ‹Ÿy‹Y2CÏÖíø»5¼3B£QÉ`$
oùÖÜ¡³~ÐÉ¢LfLó27¹FÔÇ~à{w™ã$sÅØWÜ“Ì7Ÿßb÷AèÓ)ñAèºôÝ&M4tê›žEçz²+×6¶¿¬í¯œrøOÌô•ª›Ùÿzhÿëvjýo+iÿ«TÖÙÿÔnKØÿ:]Uiµqÿ_§Û«ñÿ6R~ý'€ú¹í}ÁœÓŒJ¸£/€èùI¨^ð”ƒòüý Êç$ {Qn!,Ï?ayþI€ñó—çu@èœ R ½/aBžFZÍ’½ŒÙü‰ÍëÍç¼Áyf#c\N¼1ÚÁøPü_6þï»ç+™Öÿv'ÿªÜæöþ«Çÿ6Ò·—Úp´†H÷Âƒ«pq ×øÒ €ÝÓSÀ‹ÞééÀÉÑØ·ûÉ½^è8ÚîÏqÅ`ÿ 7}5¢Ëö–SP‹× ˜…ÎVN‰$…C’$?þ!®àB¹îé)*û
/ý±éûWOùñ/ì;UÀ;à?µWïÿÝJZÊÿ
àZü×éÅø÷)²Šû¿kùÿð© ÿÞ¿; ÌC»â·n¤%Ý¢×/9u—ž^‰àÞ˜:ÆkzpëÂÒñ_! \;þåþërü?êñ¿„[þ£{zúGtÝ9¶?;ŒòC‡äEøûËü¼@þð|€ExÿéãÝ}í”|7õ½ø“ƒÄ!|€&8­É¿˜Rg"ŠÜßYòÛˆïø'#ñZ?tò¼¿—Ã›{‡äÏAxÓ€» ßÿ3yo)ˆ-†¯á'_‚ë/q}††Òq_`ÜÙ¾Ù†Ña‚ðfš˜Ñ[x0"7þÃE½
àÆøO÷ëýß[IËù_ \'ÿ»Ýv„ÿ ùáù¿–\ïÿÞJÊã¿hU¿€e àe@¯õ˜î±Y]˜–ÿê àºñ/'ñ_§ÅÏÿwjýo+©Â¥,q±!î/€°–Yù»uº[Êÿ`GQ•eÜiý·Þÿ¹•´Œÿ(ªêwÀÿU­ù¿´’ÿ© kñ¿ÚÉøP:r§žÿ·‘òø_ ×GÇúÃùÌn_yˆ‡± à?Ê!á]¯¡Áß‘íÌÖûo˜iÏp»—ðÎ¸wÕ˜°” ‡/›øŽÍ«ÆZUâ±yžL+ÇE'AKËEî)nÿUêù;i-ÿMcp_-püWd5Öÿøü¯à2@-ÿ·ŽŽ¾á:~Í}ˆbKóH âvfñŽÐ¿½œân~·s¾ÐðT Ý1¥¢ïìïžº’ZÃLvøÔÑRaZ¯µÈGHkÇ'Á×ÚÚj$ÿÛ=Žÿºzÿ×VR4þŸ›Ÿ4žd×ôðVÂ$”= ¾Ü&Tß‰”ÿü ßcúÿàöŸŽÒ®ñß6ÒþoÕÿoWøëÿÉíÚÿÇvR^ÿ'yëÅ¿R‹H¬]ùiÉø¯rûÿzü§$×ÿÚÜÿO¯^ÿÛJÊ­ÿ}+ú4‚>¾‰«^üªSnü§Â?USÆ&ö?áÿ»¥Öþ_¶“Vó_³­¡1º/\#ÿUüYÿß­v}þs+)ÿK°;ŒÿÝ¿Êøeá>)ÆÁv›ƒ…Çðˆ½DMÓ ú‘ñîb}ä¿ðÛðÓ£9u§ž1eë£ †Ål{dnR¦ø ÷tEA}ƒìƒÐéh6G¿’ã–oK5pƒÒÂÐ‰k[sÉna sïM:¶%Ív¨kh“««t4b¹ÙY:“Åý¿d³€Ò.Ÿ‡ïÙÚp”Í£‹^{Jf¡™t–þ¾ßwË·3ès<ÜØ=3Q(S¦×ì•Ï#Ü!žÍ„;*‰íºF§’Îþã³|Vê²ò=ƒG¦Ëd¥lR-ßÒÆ‹lÊ}nLÍaú{È[¾
 "Ò‚[ž?ŸÝ 8[ª	íæq·tS6ÕÆN¾å™23mÞ+¨Fù†„yHªM@Õ­$/÷ft¯|[“¸“¥€I­òúo{‚©S¾£9l”È •¦²Y
¸)†BÊ¥³‰”Y¹Ë£9árÜ<.Ÿ€àã<q”òMá…?»EÙÈ“òù,¬ì0€äò\ò-ƒcC‡ñ^MšSs¢¹Q¹ÉD„àE–>b9é­@÷-Ï§dNb<TŸ„ˆ@G…ùºcê°œÙ0C6¸·x’¡«ÒL“à§nÏ]idùù1¸sE®8	f³¹P~
ò¹=Vûj§ÚúñlÐ¡\6Î§€ª¼ôû,·g¹Éþ¸Ù./÷ÂL¤(’ù=òšŸ¤Õª9å±u³m¤Õú¨™ 7º»—±ZÿW;j>þ·Ò­×ÿ·’RúÀn‚ìÆá˜nRg`xuÙ!ÔA™0³ÐC+x3x*@±øeÚ#ƒ¿Ä&^
O2!Œ÷Ò5øÓ53a»)Ÿ pKU@V$ÖUW€Ç>Oµ]áÊa¢l5d¼Q„îT)ùHà™¹æ8_"¶öî%&£}gfÝN–²­kyÜïmÃ¸ßâÆ¡Á3å'C}gÚÚÎV ƒ©·sÑ·3ÈDâÎ÷ÎNÇ­<]¸Ü³¨T<ï¬ÐÊ¶®'µÚÕwÜ0šw¢ø.07Wº*¡œ‰ë)_DôÎŸü)P¢1+Pè”ïñ‰„ä?)èÔÝT]2õ &»…y[{v–çð]ÏÒU1¼e½+7º€¬¬Zyf\/;°Ãå¬¤PSÉ«KÁI	;Ûl%g÷ŸÁ4d˜h üŸbôRyx•<´èÕÜ5ë¡SB-"–Ð‰=›éÅ.ÒÍZKöGm·ˆL²´ Ý›´'êïAsR’œa×}–ì¿5H†æ¤3ÜOæ•æ¤˜Œ[«9¹·×øƒx´Ê­Ìôpƒ0¾¿5RC®:’Ü}Tæ)ÔNR¨ŠþˆBŸÆ¬€0@/oÌ
Àj
…ÞbnL‘÷Ô#?C7er6ó‹gC ›æ¢-2Ó¦š¨ûÛò É»Ä²‰ð-M°6‡øûâÿ‡›¾›Ž»fØbƒ0›ÙÜ•Qu<Õ™éQÑ
€u]Ü>Î¯’ÌøÊ AMâÏt 6Ôß#SIE¨cûÀÈäæR:Ûsr-šÍÛÜ›R‹Ž˜Þ$¯€~ô‚=äkO_]œNÜ1‹]2`Cå(„íÁ[U-Aæ*A™+öÉüÖ°Œ)P&j«ïâÆ'ò›“À¥¸7†žÆn<¼¹ðÃ¨ks7‹MòÒ†Üæø’á5\ºp	p	âÖ)| êôu¬)õpïÔZ°œ*Õö¤F@n8IÒåMPmèU÷wì‡&²Þµá¼¸A?j’x?JìoÃ{
Tb¦)Å¾Ûy~üî ÁŽõ‹-z•ë»3C3l¿<¹Ü±XHªŽT™u¾$…ÞY0v¦†r,=J‚>34æ…ÜPÓ-…¶1gnàþ¡D—!™.“2bí5’$”ïZøšÙÎä¬]—\üFÎFãæYðÍòöqSMFqÆÑÑÈa#ŠSÄÐ±§ø$\OÕÆpÃð§A}\Ûw4^BôÄv€sŽÞŸÁT±à†‘~p0âû#‡Ý£1£z°´éÏÉE×€¼˜RïÇO¯þ÷Ó
G’1¬€…LníŒí@y1%^RË`&ù9:‘3ýF\=‹*”*Ý#øºÍNQB2ìš1L³&ÆRàU¡ä¬Õù{“#A;íîY˜ÓrL·½’×6VÝžP‡œMù-õßqb‘Û)øðkÍ åAõx6Áø:3¼~oXäüý…Û$oRŸa¸P:­
%Z Ït{Žhá^Tæ'¿DÌ’;z) {ß°—îÊº­ÉôbÌ Ågº†ÿ–‘J90+(Œ}O. ³"B’ÕHŽáN$™pZ!æP—že êo@®€zEvMò¯±a2þ’(iŠG½º1"/Ò"¼ˆ#¢§	0âh‡%sf‡qÿø˜™Àv"B:¥ÞpœQÜ:(¼ïÑ	(Tú°¥Aít6¤¾éÔÏ9øžbÖ¼=~zA”V«ÛxÅk@ætÁ«msñÔ·y={rÊn©†Ý+Òà G¼ÊŸ	pÛ	: ñ°¿>o64%ìjOt­#µ­´eµC O@ÝTùýPoèèf€èw¸×¾ñ'Ôýœ[ðµ=7´ßÉ™ÉoÑ»öÝNÔw»É¾ûôSÔó «]Ç× + ¿æŒNPhÀÑ)êSB=»ÎÅ'p=}ïàêºùt—h^ ü¾À2Ø»e§fTûwd² ±y…Ë‡øºÍI‘­‹Ô²ŽBßC0²1,/rsÐ5èkox‹¨ëíÔx¶-õ5–„Èÿ‡2ïg×'g¸»þ]°±Œk«»¢@¢¬—pßzÂdbéŽmèäT^[”ms­§»ÑdÜ„WµÏn9é¥±Çk‡ÍfLçsáµdÍ˜Ádr}(~8‹™gã§ÿÝž×óâbøáo˜saJ ±>Ç?‰Œ1FÏ¾Ð¶ËqÅa¸UEGábLãwÊ=:ÁTÕ$0ùûÔ„ùÄž1KLü8ª-‹i"²ä·[¯1Ð!]ET¤Fdã«‚#l:|wÚøoró×Šuû®ç\óéŒ{Iyî¯ãÇaYâá=ÞJhäééÅì¦s®ëÎu£ é ºE3¡FÑ¯:|ÆmÈª¥tÛÝV·×>RÈ>.D4‚<¨éÚðèvoÜì›@ Èüú Zÿ[Àu±y¿%3˜XËà(qÀ€ T×í_ý	ªÒ(ªJ[Q»ÝN·IÎø/Þ¤ó--Ò¸Wó£ý×¼k£x HÍCèŽ³8 ¡uUHkŠFJèªù<à¨hãÎ!°ÌÈ}	… Sÿ	º‘p$9(Ÿ§üúŽŒ\Áðòx—É£S‹N>Iø¿÷ ÈqH¥%ï2A¤¿ Mbò(ÉÅÏ`±MhM»dŠÌM‰ÉÖNÍ=ÂðÎ »à¿®ã‘ï‰çc_œ "D×ý­/¤pjû
È|®£E‡|¢¦¸3ŠŠ2^ÞƒÈí˜È÷µO~}=°§—ÙµàN1nx`ð@‚¢”¹¸7pwlû¦óüÃí Ð'FáÞuh^R®wË0·ª÷bªŸdwÓ„f@÷Üè€Ò$7Ü;tÆ¹P¶MûîûT÷XVä“Î‘Òlv tÿt~ñâ"¸FlçK1Á]n”#;û¾7<îãù<¦M˜~	$ä“ÛH!Âý°ê:;ük.nC¸”ÃÛ»Ï@œD}GNÚvÏMÜÆ‚¬²8ú×‘Èg+ö/‡AÂîƒ˜x—‰ú47\¢¡û†Âp4î3åVLÏö.SåaÏž¸º—ØI˜Âø.0¡¼ï2õª¨r<µÞ{ð«›Åþ<q©fp‡xsJ'pKì+JÎzá†Ãkoî{w°\Èç¥ "á']‰ë¨³ÓÈã´S>‰øÂÝ­qXK—æ;MÈê–VÿŸ½§ÿjãVöwÎéÿ rÏk Ï6Ø`Hhï9qÀIÝ&À1pózÚ<"{e£f?ÜÕnÀ}}ÿû›I»ÚIˆóÂeo/YÛ»Òh¾43’fk9‹{K3>ÒDIOW£l4Š‚Ž_5c~…X
Ë2?£–/ôÄ{;öål6ßÛ¾ôpËé¹/'“¾œã	õ5ºçÙùÔ¥ã¹‘øU#à¶JÓ8ÝPdï&
ÿ†"Y}›än˜ô1ÒýU-¤Ö£ûÎB„»_uˆ°‚—¥D
¿z,-1,ø µqÂ/Í™õáÂgþnXów`Áß5sš[bO}?Qú_\Ü½·<ºÄÐá£GÌ24×(¤ ã7Ñù2ÝøM·®¬aLW€!‘\ø¸––ƒ§·[Ä×køo+oÍ
>|I1¾|ÿ­^ã-Ñ½µ‚cùêiÿøûŒrõãZ]•öH³ì£{DN7Ä÷x7Qø˜üQ­"»_zhÑ*®ä^D— JÁF7ªãÄÏÌbnv2ë9gÏhó=Àé—‰RrÏS¸ÏØdê“cÜ@f`óÞÐÖ-zø’Í|>
f¼“D‚ø 7Û5´û²Xn¨2W÷uÁÉ¯F,ˆQ•ìšŽQšS	–*Š\"ØÛÃ,¨T"¸G»Dék05P=¼]ÿº0"?·)àî|ÿ8¥'ø*öRë¬Œå€baÔ·?|^Ú2¤MªbñÆÝön{sgkeå·³F©òíÆVxÇKcJ PÜñJò®“àI$p§˜Â¤Èð+Øt‰Õ³\(¾¹«Q1£Ô>& }
ÿ<5yÕ?èl/œ«ï°|ðþc:¬Õ0™+Ò¾m×?·ö[ìç(†ùññÇö›Åd·–>äÌØ^ØµMjÞÄLÑŸ0ô*/FtÍ¡«S°"š^€T„ìÇDÓÛöêf1Ü6Ëa)Ò÷xäÑßë³m±¢÷ð@!µFkÔ5ÇyîˆRxœG“ªs{Öô_"Ì}éd"ÇRW!˜L„¸=¶eU¸Û*än–Ü´†xóôQÐ· šP¿‹+=K¿¥“0y+C™¼e“4¤S“¯Do? ý(¸’"Æçu¢ÆG`A-¤ Ö
;Wò/q×úhg±>Šù<ròc=£ŒŒ!;–I€Œ:‚ÏOñOË‡ní‹ìÝ[w}GÌ¶kyíñ­{î¨ô¨+Ù0!_LùÇõý8ï{!›&„?¶²tZgÒÝÞ\6±ÛÙ¼×nWN«3#¹£½¡XßoCE1îe|ŠGèˆUa¾aÄq‹Êó+Ù)w• nxìÙ˜¤ŒqôˆPâ»›mðëËÙ–*˜À:(â®8°\*àzÞ+u}W”èXÔSS= ¥Í wc€C•ùV…¦Àçéº“ÇÎ:Ý[výq¶À‚þó(SgçÚþÏ‹dÿèñW*\ñ»êöcÑ^êÿá¾aX:ã.>€e–B
S§ê³‰ìØ‹täƒþQà'˜§ôùÃ³$j73v;eÝdŽ¤Š®6i$gTô˜Ò©N(~ëX˜$ŸžGEn)Þƒ9ÒqãZ“ƒ{+Ç"Ssåá$fíÏKaÎÔàú+üæølªÄõA¢‹i†0 €-òÕÄL1÷±ußHäìÚºb_ûû×oÉ¿ƒÝÊ\šë#^Ÿ{°Q–ÉÝê6a¼ïØPxrŠãý#ÖwOí»·ÏÖÆ¼‘îÒÔ	hÒ}²0FÐÁT„:¿fƒ‰«XoóñPÞZûÏóÛÒ)}
ké…AÌ#ÂUNQëfr½³7×È›ú‚‡7ã[€Ú’áüs¤.ØIŠ0*Þ<Äb2Ì¥Õ-xÁ=< †îï%¼CÀ„Y0p4gN¿ðË¡|±W<QüT_T§”Ðó
S+ü„«söcpñŸæé§Sti>8nßµòµóeÅ«d@Þµ¡Y3Ÿ@wÿõ“ÔÈ‚¡æË\ëó|nÑ®3Pï=mËÁý'pÙð½ÿ$®8÷šÈÅ„Ù¯ø å€yÆ¤ÿ4àWM‰Ÿ[ÞD«Û6®uSJé»¡ç¨ÿt}ý/ºOèã†úßNµþ×fwû¡þ×2®Bý/Mn[ÿ[zƒ"gŠmèX[•£R†ªTˆãIÝ”
qtôz¦ÀK"?äó p
Tí´×y¹±Ÿj®Ûõ×ÝzR­/Òyr·Ý}"’»7AãV»%š±ûË‹|±5[¬R\èI©$MnQ°[bËs¥’\…Î·±ÄV§Zí¥Ô¹)v§ý>¦‚V7ö[¨¶”ÒNu€ØŠa·,I„uÂ „r0¶¦«…ÕTYZ è_Zþ^•ù9pãnûÀI~çõúù/œÿwºüžkïvÀ\`Ý»£þú7ŸÿëéO‘ðO5û²ëûoswg§dÿJy¨ÿº”ë·¿ãSñfÅÖODX]1¶|1á¾6fÙ¢%x…éB¬½2Rý&Ä…¯Å‚{¨~Ëý¡ªùÁÉ!Z×Ú,R2‰âyõ·‹(¸¥§ú‹.Ý¦ª?¼søÎ«ùeÅâ«ˆ„{<á0K’ýŒhËŸrãÖo ö ªª3Ý×uõÛHbLÕ[ÂðäÂ’éXŒ5µA µ7‚.s¢aªìæV·÷9ýëå¿Ðø'óØë4(¶ôÿ2®[Ðß0×Ç÷q“þoww+õ¿wüÿ¥\ÿøö·0:Ç 8ú¸—i¥sÐJ{{'ü°²â|úvíïsÔ{ì»ßÒÇoþfÿ³ÂàòEÂÎAÏ ÓìíÐß8×ÖXù_øÿ—îÃUº2ùGáäŽí~{ÝVÿïtºÎöØÿÝîöîƒþ_ÆU¤?ØïD|×lp[úïÂ@{ôÿ6Û;ô_ÆUK2î® ÿÎÎ.Ègs³ó ÿK¹Óÿ€îq-àSû¸iýgŒ½vw³½Ùí¶Ûcÿwì¿e\Ï‡G¯Øìb¶÷¸µÕœÌ‚oV¾Yž2>Kš`åÙ’ß}—}ƒöqÛWsÎ~ÿ†l¾¿äŒ¥!þ§±Ï¦2A+rN›žx·Q(³û«ÀïØ{x…nM;w‡¶›X½E)ß>æÜÊqš5¤ü¤í¾0jþmÂxšâ*iZPg˜¸sõ§Ï‚‘JèD%B+®ä„ÍÆa0ã¡Iø7oj&Æ~6V\&W‹ûT;»ò”ÅØ¶ñ‹8`ÍxÂ6ÞóxF°À¿
|¬ïïûGÇ¿²&­-ÿMDJÄ{¶‘ªxc„\ÍwÕoðí×GÃ_CÝúåå¥i¯ÕÚ€ÿ|ó÷Âg-|²ø/v08é={Ù??îíÿÒ{Ñ?‡ÏûGÿêÿÙÖôÏúÊÈÝ#ÂvÈ“È@þ%š˜2Á¸ÑÏT¾…Ó!,ËGã‹ òXsÈvw»L%QŒUÿFQ” ølcÌÇÄ]ã‹è2Äç ò&ùöaÆ–”€v${¤þþoÄ™Àýs­ïÿÎî7[ô¿½' Rþ~¤q„§Jý‘Œ7TÀÞ-QÓBeGu€/XsÌV‰pi¨€b‹°ƒÒc¿±oYsÂZ"|ÏÞü3úÐWªÐ¿Ø§¡sÆãD*`?ÚV¡²<€9*Yû,‚)§{È?1ñdÍo•—ã(MDý»æ§…¯êŽy÷@gÏˆ+1f“«ß<8s÷àªÌÿwï+_·ÿ¡¡°öÿÎöÎÃúÏR®úïžÏÎN‡/Z÷é}Üÿ3ôßÞÜ‚ï·ÉþßÝÜy°ÿ–qÕÒÿ ~ôüøààlÿôÓYàÃé^ÀCüw)Wý‡ýÞÁ«þH¾¾>˜þ¸üó@ÿ¥\5ô?9;>>ÞÜÛë#ô»»õ@ÿe\uôïïŸ§¿Þ|ýqàþK¸Šô7»/¾Øþ/½¿¶w:öÿ2®zú¿ì÷OúÍÞqoÿ§þ§öq½üwºíî¶–ÿííÝMÿm·»ò¿Œ‹Ýtõf&z©9cåš'méNk³Á~æaÊã9‘Þ^øžžÙÛ ˆ§nèðŒaBµ±‚/žö‡¯NXïð€¡?28ž°çGCvvÒo°aÿxx„^
|Ý §'Æ{=:¤Ú-v &˜"
+€·V4«fD«L]`|3À-žõú:£&ˆ„ÞÜ¦K’§J4X,fqä¥:Ñ”iŠ²oJ,R]Žó´C—úÌî‰->Þ†öã(^°'ºÄ6æs7Y;ËpEq°q4›Çrz‘0ÚaŽ€áEÌ
¨7²É¿¨?ÓNÝ”ÖÀdL¨æVNY 1å>ëSÓ ÒÐ¤A ´cjÅBI|ß4amý“¤,
Ð5žúŠ#¿AîÍŸ€nPeöÛÇh2¦ñ‰BÓ’yP— §vt‡-ö<Š	ŽYc°ZåXÍni´jZY¥¡(¶&×õ«Ñ¥ˆ@¾X`mLŒwëû¦jsÜƒ•4u+ú'Â@ÌrûUéøÂ †	 4×ÐSÝÍØÅÌ¥Dn‚VÖ$@BäQr†-Mä°91žckÝÍÿX§î¢XÄÛ†Ò„ò Q†ÈÀž²-B“#
LÒ¤,´îÀ™“ü×(]ekX“îâÕu—êðâä½ôRl+f.˜Ä@+)K*ÀH¥ˆá‰Ï´Y*¬vBi'WQ¼‚2§Íb1q¬ó·$‡] Šah”èVYËpì§„
BÊ7àË@&:å†Š&É%²—Îsiò2æšfô+ÿ9McúNE9êãhô°BtÎõw@ŽÔ'ù Ã‚À¼u˜øÀ
( GéÜ˜†¡èŸÛD#œiôPsâ M¥aâ¢DŠ83L“‘A”R»ÚFjvêRÂv-»ð$gÉ|æûu¿«(Ü»JëµÀi¹ÈÐ# :3¬€{ HÞséÓš–G/Qf/dÀ17¬Ä3½`µ ÎÔ›Æ”Î¸Šj%Ipnñl…A„Ö4±°+6ð"¨v`sý">Ù›á.^yÂäG—ë9ç•ïC„¨Õ2`õ80£7-iXÀG¹€ú(Š&9qÖUØ‘eAç˜É•îÃ†9€û”/‚H‰\¨1rÂ`8Ší'hÂÙ•&ÓÎrB§ö9tù$ðšœÊz©Ò¼ª­žšÄ¿ÁÊè3Ø£¤öšv&5!&¸=ÑÊ§˜ñ˜8ñBÃD,ü9ÈAøŽ7nA>Á}Óë–è´49Áî NÃ™#3¤V€¢:Ñ$§ú>ªr3Ç×R¼,™È:ýe´Y@Ì\šÁhB<lY”Ò¨ 7ôü¾ø†#xàšÀÌ+™é(À4#$Öî î"È	<#
ÔéñŠYa©LÓÝµ³…k¨ V¦î‘ßG9T,6^n7Û³ÕlL«¦-=ßgj^>`2n FÜ'>²)WÐøHCƒ}†Rà"]äˆB<%*Â¿j\;eºËíþËabx^_¦wÊÊL!57$P®
‡978…ŒiŽ4OhòãÌ§­•ÌÖr‘ÞpÔHl#ÞpÉ:U4ËSéKcF¾&—OMâÊ"¡8VË05“ãT'¼xüU_œ[GÖäJNC®ÓZ±µœˆÊjõðÍ™+«˜éµ,Â%û:¶•ÀM¨ƒR§”Àv$€ŸÀd¤Éh·Ÿ\•ø3þñ±ÛqøÖÓ5¼ŽøiEÔi±hVa·ûÙð­eÅNR=¹^­uf1sµ²€Y’9b¨B f²âÈ. ãF	ÞL$€Ë~ ú|ïRê”Ma“(¯`Äø	ÄStœ¢9÷“ysø$1z4FE^™Íÿ§óõjoÞ Ã,¢UM—«s:³4,£Î|Œž}0ë©VÑ7Æ°pý6×ÌÏt1Ë•k¦sÒ-š@[Ž9*Ý{@5xMÌ0p9k"€J;Dël¦ÇêP07t<´ò,@äGcÚhJÉ¬„êWÿÅ‰&L¦Œ¡l¬BR3vdT¨‰hd{å³™î&%Þ&,£î2 }.ßúYgp€EjÄÅn¦7C^¥x,I:'¸yÌz4BÚ¹Ïü5µn°ÉÐE` IfÕÓkåì€´‡kf[ _yEàL—H
;×µØ`‚ôÏ|!š
y:#J"§›r•œqÜ×ò	+³­ãH©&!‡1ŽR´Ÿôg*ˆãóK•Ê‡ê‹©žx’ŸÛ%­x‚£9A®Œ«·3Î‰3·Ã²ôÈR…f´)VäDk2YgÔHŠu4r3Sžµªôì€"ŠÔ³¼Â•5Øh_¤a¾»RgÏð´*ØnQª<2Ô¢®>Ï5[Y”Ö¶)è£k¬<"	š“«54¡EÿFÙŒ\t›õ¾@“5rWˆ’³V „I×ÙŠÎ¹îÚ³óì_×#ÅvS„ÁÓþUÎ$•­qMßÌ;Ä«2PNóCÙ“ø¦QÛçÈéSnrSý(ôßuP'FÂ!ò‰ö•Ó=ª¸Œ¥±MrÞËòT«bÏc§çX$ `k7;.<y QypNÇY‡9C4PÂòÙ±a¸»jÑh75c‚X4ÉÅÍŒe‰³Kð”U*^¹å¦µ§mƒ€ó"2ha–ÁaR~’¸8É'.=’êT]Dš·ŽJ+£¿qüÔ«‡G§ƒýþ*ßU¢ó‚ƒØ™>Ðävúq¥ËQ5’RÁ,ÑËiÊºžËPir‡éD-ZQ)qŒó:Í¥FšA„é¬°·À«ÓL=†kñJÌmø‚+t§Ü(½y%—V]ÅlÏ‚É-Œ9®s¸J]Ã®2/0™+×Å Ãí×VÏà”9ÍgÀjûQÜ¨b™[[Ï‰rß K“’¤{p‰XTä¦IEn2Ú„ŸÃT¥`XNèé…öÂPUÑìÐ›ŒíJgA>ð!rç-”"8F¶HcÍ±ùlÚàž‡÷1ú;.G:­XÐ†n#	}¬)æŽ‰ü)oxž½4°fkc¬bÑþŸ%gY§‚mÐP+L­ŸIÛqZæ?˜Eëµ(Ê½
2[)X¯€RàË!6bÆá‚Œ!9‰VkÁÊ­±àóÐ^Í’‘nÆY+Š&5Ð4r±™³8_àŠ¸Ñ¹L”¨=ìÚ‰æå TV«
³pfuc,™Liä£BX&óTJž@ ]rvÌJ€öUs+PµØYHõˆ‘hNš`jÑY Éâó²é³œ0ÖÂÐUnécå@Ž6õFnôùC\3cf˜Ãè&´éêÙÕGýþa”àKÙêÍ/£H;e(¶Srïp!ÐT
ÓžÐA(ILGÚºÐÒDä.Ñ|:bü¹‘òÈp/¿£âIñfÁ4‡±^W*ûf-`T¡5@ªEÇŽö"Òœ‰6¹!“ý\oÛe`Ü,³h0ê%â÷Ó7&ÃÃúaË´bË)¹›‹?SiVLÝšÒ‰¤0ñG.O#4€e\ddH‘9©­Äg­4Yº™Ù f
Ð˜Úm±©ÈuÂEÛ	{M¥œqýÒAêh®Xò¼ÑÅÊÕ Q‘œ—<
ÖÈ	fd_å ®!¬4(»¨îÓ¾,wãZ òW{'lp²ÊžõN'¹¯§?²×½á°wx:èŸ°£¡»,ôœõe¿ÀÜ‘zø
££*‰$½â9aÒ\‚(NÊ­žšƒ“K¨"‡(®ªX@æéàôe¿X?lŸ‡/ú¯ú‡§öª?Üÿ	 ì=¼œþJ,ô|pzØ?ÑÛz¦ãÞvö²7dÇgÃã£“¾žmõj¡/¨€—šA§’VheF{…EvÊÅÑ,–hžÓ€'¦n$ñ_®qx©Ž6*6×ªk©H³«h,37Y+u³ÎJÑXw¡µêÌjÞ{Ü‚Ï¥øÒKÉGÒ§ÅóÎ¼ÌŸ0!8tð•OÁN€<m'ÔbW²€7dŠ©/Áú‹õF¶ÚÝ(„r³ÈÏü¾¦ªs/GdÐpSŒGdë¶Ëw (Z¯—­=Óe,É|I›ˆ ‘–|ZŒáãÛvK@¾9@Í®­;«Ï P`Øê¥4`tLäL£VCcÌàÆpu¬×ÌqÏæj\5.;º„Í4Ó1©þF††˜Ž^u#k×®‰[¨pØ~¤vEÞ¥ôÝØá;<µ7ÃJ²	R|Â¥eéiMÞÏ¯[¥n'ÕªÇ|èŽ…ÆA>D½ˆ3mdÁtî½—´H:1Û7@ìæÓ¼–€'-Öãœ€X°š{îåµ#¯/¤=È™‰ky±ðÚå6k…Ž/¢HGA)ÒYXl§˜+•&}ªŽ äáXèAÌtÔh¿9ñBÜZ’Ä4Z};‹F¾‰B‘Ý²j-_½ÔB§$ë_I«A3ã§è=!íJf#|:çã£-¡ï¬†d6·Y¡ ®ùi®F	^²tòU”\£ç‘"‡LL}&9Ñú^Ë;áf’áÆpWô`{5¡s¤‰¬qa1ç4ŽóÕ29^9:«:ˆÚ¨ÆGscläš#rœfÆü¥ÃŽÙ˜Á¢¸x€ójÝ68ú½w|þkIHÑÌßüì=]s"G’ï¡ÿP;¾8tBÂÆ1¶B#Â¡4s³ŠžÐ;M7×Ý 1¶Ãnì¾ÝGøå.öîžïžîÇÜ8ÿ„ËÌªêh@FØ;î²cDuUeÖgVfVU¦¼¾½º‡iT•Ûà,‰Ø% éúëZ¥©ëðã¢ò¢?"íò´ø„éFXå8š½è=@ö3Wív¾”P'ŠS@.©8UœiK„E 67FMFç†T%FL_£šmøªîDH–_9T_¡îªÔ}˜´EÛ¼v¤&f¨X™¿ç‚ªãh†ÇãÃ¦z±Åy¬"êä—¶8IZµã»í>>X¶goy…’sÈ¾yóÌ¦ï…aùýïõöGÀ±ÚþG!¼ÿ/áû£B.½ÿ½‰ #ÜíÖÂÍ 4Vm—¡\´+zÒž$“GNyÂ¬ôØ°9 (B›¶C"Úšbxƒ›šR4R2PLs,ÏrÄæÒ’%žì’.7,-ÐCK`J¾
ÌjÈÏ‹ŸT\°Oš`®÷¨ž{Rû²‡·Î°YÒNê^L›:sÉ Y1<àÖbg{Aí§Xˆ¨ú²‹<qþÛÈ– çÖöä…Æ.^n%ŒÑ‹çÚJÍ4wRx”Ç;á¨Ê¤@;½WiDšãÒßÒò®R[«:°í³k5NÛ°qÕ`[c—ÍÆËúIíDms{³[ÛëøVVûûË&Êï¦Vqy^¯Á·úEõüêä~vå.0ë0©h»Áat—<Sh1@‚6€x®‹ÆET» Âó|cµ—a­³Êù9¢Ò*WPû¦Ü/_7ëÏÏÚì¬q~RƒÇ5¨Z¨ QÕóJýÅ;©¼¨<{x 45Ì&•¯Îjø	ñUàzç€Í 7úÝƒV6ÛAÑWu|QiÖ[Ø!hÛgOÃî„å.j
v5‹dÁøU« d'µÊ9Àjaal¢ÊœîæŸFˆïÿÂ‰ÄÏeÿï°tT*ódÿ¯˜ÚÿÝHHÿŸÉþŸÿ"ÙÿKÇ3añøg?1¸ÿø£ùÏ<¾ÿ<8:LÇaõø£º¨Üä‡†zÈøçŠdÿ»XHí?m$<dü=_Y¼çÙéÃü‚¬²ÿP,æfì¿ÃLHí¿l$àiz™Žß¿×4Ç.kâÌÇ[Ç›U†ßàGÐ-^&M_ïÛe¶cy¶‹ÿmk 
¥¹Ý™b®¾ëŒGe†ã3óÝwLÌ¦¬‚Î~ø!úÙå=øÅ:¨ðµ2¦¹N5–eé]‚!`„(ªR9¤ffªŽ/épšR>ïËì;<öFÅA™Ù(ùZS:Ð‚ä[fS8ðÈd|sÈQpp”Ë±>y)ç!ëhºæC×>†XÿùÔþÛfBºþÓõßõ=´©õ_L÷ÿ„tý§ëùú·Œnq÷C¾+Öñèà`ÖÿÓ!úH×ÿã‡ÏØ±á™OÓÔêÁµ•Q/žÈk¹W–çû<ÂËô-ç=ÁâoZO‘ë¶=¿w‘< ­xñ
âc!ØÅ)¹½0ÍX˜ˆn¯.jÍÖ‚—Wççz³öÛ«Z«­·k/.Ï+m4ˆº {½ÕºªùDsÑ’âº%kŒ-öuww?9!°Û:_`QÒŒ©çù‚Ë3Ì[
N‚°"Ohnt¾ð²´]úªyvÓŸ®ÛÙ«—†YaL^×EúYíYJ°œÎ»„]T(Hå4—ã‹0¾v%Ï*Ïkç3$–ª¡ÿr “ëâ¾>&y–ú=qU,JÊ
Ó8ÂšSÂØª·HÜ›Mô‘•ØÓYÜ!{C?1­c™£Ñ4)©ËíÄïÞˆ[pXw+R»fg&‘¼¬b§C_›öÒÄ$ØÊ›éï=g¶°LÊàd’éíœUñ^6lè_tm*G@4L~MùÚ¸$˜DlÑ4M…Z¡‚“ˆ1–¨ÝXŽ±~o
(É“4ÅD¯ƒŠ<…&!
4¼ÊlM34ýÖ&	X‰hç2hš§ë"PÄÏX•ÞK@¢ w—‚"dáÿùÿwôGá!ç¿Gtþ[Ì¥ç?	KÇý£?
÷ÿ|©T* ýïBñ õÿ¸‘pÏñï¦5ýPÀÃõÅBjÿ3!Õÿ¥ú¿{¬¼
ÜûP°býŽòEáÿ¹”?ÈÑþt Ÿ®ÿM±þ/hx—R€à£;¶ÅòfG™½Ù®Ö·÷Ø6ÒüÛ’7E\Œ¼0]sûšŠ1aÈNo»¸Ï»×šyJ„p•q•2YáYDVÄ|ŒRzÈœÖ2kvïKS8Ñ,(éeºoÆ¶?Îàêðä2üQ„©H8¼ôöIDÒñÍäH²ˆþmq»+:YZø8nO¢b@«]i_µÊlyÃ°O¤j 
Í«½~²ª´êÐqèéyã½òXUÛ3ƒ´vÙhÕÛæëUe]>r<TÅL³½±eéó°ZµæËZS¿jžÇ`¡1îêè\²ÇpŸ®B:€Y¤ß¸03¸Î*÷*ëŒxÁÙÚ%ô‡VBuat›íÚ‰^i¯ìª±­#a‚%¢>ûþûe³ŠÌ«çiý¢Þ:»:áå÷¡¨"¸ÚµóÚófå…Þn|[»è<Ù}/O‹×1H«žUÚÁÜ+)Sgð¼RýVU;>k4¾çŒ*<—/M.]›'‹Ë'd˜Y7‹JÎ”Š åîf³ûÐµîtû¢‚üü,¼Æ=÷ÿÎ]ü‘aÅþX,åçÎÿSÿ/	bªÖ—ìýZÖõb›””6ñm4Ë®6v£OŸ&»ð
 }Ç'Ó°u.,¸`o_--ÊÅ‘µÇÃîF¨×$
˜7J´A·Ô>ïOÕ¦<4|×¼·hãÐ…AÇñ‚Ø­iwaÉÈøµ¶ž¨"ê—TÔ7 6wAÃ®Í:´z›Õ‘bÎ/³a‰2XðqUÓ†ž;ùe¶ko”ø²ªE£óî—Ù¢¤)ˆµ]Ý¦®ÓYSROÂPx:±yW G4€D¹!4#ôóJ,pô†þ£¨M†¾€o™öº’ú	Á
â\õPÀ‰1îšÑ‚+PLøc  ¨ü¸È¨Á•Ocá!\ÂãCù‡ ,gÚ31újëì{™™ö€»¦0ÆksÞ$þ7–ƒ¸ZÁ"úAŒÈeFˆØ„QIÂ´‚Ã(,·0‚k#Œ‰iÆiÊ…Q˜ a„3R	ìø0*úHÅcÿP=/ÉŸ0¢°rPq$Ê	®Óì•c,¡Ð(<{Æ¶‘aÝ~„zËš~:Šá{Êk]]uþS*Ìÿ¥ö_6„üw.†W	QÉJ÷Ñ~‹¤öJëŒ¸F^\®~yS cè¿è=Y<6ºS½ç¸:ú"ã·,êºÅ¢Þr%³hqF"@ãè@w""Íþ5µÃr¡rX‘Y¢8…RÌß °nHnaGJ`¯g(Iµô¡ãÏõÊ™c+ÖÿA¾Pš;ÿMïo&ˆõ·úæ4@Ã’“Þ´Gc?˜ÙRêÕšÒ2^™õ+â"‰î¢nhC“Œ3cËO\?,Øj`ÓìN-¿ª}{Íz‰]_.O®v{{åI—ÌKiÁ!›7à0
¤5Ö4yXT­4Ÿ7t´©Wç&ëÖ˜¢MÏæU«}z^yÞŒ™“[ƒ¬õÑ½VLÑ+ÕoÑnP’óÁ×VÍM—__´š/1[ö‹\6ä½@›Fç¯a0SÈŽ2¹<üÒË öµDŠ.fQVLŸ@1>C4Í.v‡çX“°gIoþ}„ìùgO"ƒA O¢§f½yÃ2ïäö;?<a××_’Hšvx©5
QÎ%„ÇÌÙÜ¢ÖØU;ª*‘n„ìË/Š D°Ö>èc,° ˆìãh9 P*±ÈîãÃž ÁFzbXfW-¡©™käööÕß¾ádÔÂ<`îÈ§žíd.ƒg²«¿ú
{ôy½}vu¬7®Ú—WíppîutË’¡»Ìh‰rßãþx”‰ßmþf’_¸­†kXœÒà„ËÊ9–¤ssh¶
t¯<scbEƒŸ>PÇoÈ1i[ÐÒ&Ìo2¹Œ=3”ìâ'½²gÎË¢)ñ'|KQm¼L*Kš)Eä¢Y{ŽžÑ_'NÈ±ðäJ]Í—gW‘	%©7–ü¹·µ4Ü3<DþóçþO>w8ÇÿSûŸ›	ùÏÅ¿„Ó>$uBë‚‚IdÇŽI(4E’ ïU,éøñCEÇ{œ ®É©î¼<ˆb×G¼,4³Û¸ÆûifhÜí÷"wF4(ˆ‡Ùƒlná~‡/Åû‚¤NóuÝi†û¬¸U£…£¸ÒõO0,¥ÿáCÙµp¬ÔÿÍÝÿÎ—ŽRù#a—%‡otýªUkêº¦Óaaõ´l1àuÝâÁk¸…9Ä{À%U/Ï–5&þH,9‡äo—tHøwšÝùÔY ôˆ{i]ñ…ó|†ùflq–Uã¿týwùˆÛ]ãÆñ×¸ýµšÿ+ÌÝÿ*¤üßfÂD8ë(³‚¦‰[ ò½¤zþË;Ž7…FÕQ[F²0ÄIwHŽ;-³}ÁôÄŠ0òÔçNx(Îßþbº”:0¹Gv&2¢Û¹ƒr.'Oîðl!ÓÌgÈB{™å÷ãrÔrd‚3Lˆ²R)ðV©³@Õô3CôéÝj9^Ñ¼+ãí‘÷´cîÈ¯@‘y-àP¡uÑ/â-*•NìBÒü•õUùþ‡Ù“ûT6ÝS¼¬î…ñ+	Kéÿ";(Ä±êýÏÁáÑÜùO®ÒÿM„Ï>cÿûÏÿÎZã!úÃÔ´:FCWÒ\O‡]6I:MášH9D'¡ÖîSÁ›)./àåˆÉé˜BoZP‘–Iö¥µÁ·I^æw»;Ù „™äí@5€>.Þq>BGœŽ¤VQgä‘Ø`èXÏâìí¼ü%xéõ¾‡Š "4ØÈ±„wh¸Zˆ“œµ¢WÔ÷èÊµ=é´;î¨OsÛôÝ=ûÓø¯ÿûï?°ötÄ±kß°kÀgí”‘›q_þâö µèâD~ªjà!£ãªbªetÄ]r1åUfé†QÖâ/ÿÉZ'¬ƒêJM3É8jÉ¨Äf *Hƒ¨Ú%†2h&ÎÕJ1+TKåÜP‰$:ÈÎ…8Â¨+ b†Ä"åßíâ²¡ú7|eÅ=¶ÏÎMû‡Ÿ;¸‡>‘óafàŸH÷°0“Ó¾ÉmÎžÊ)õw‘~ÙÁ	0D}”ð:80-ÇsFƒ)NœÚÝvrt‹2„ßìÓ)
9ÚLr]]è¿x'K%ªÐ›x0&¦¼oÜ9¶3œ²§˜7C+€fvÒ„VÂE s÷Æù|ª&q¦ëšnï¨¹ù—ÿa	ºÙå·èÆô°ÔxÔG/¼^¼OÄ<§	.L„A³/›ësŸÚ"USÝ{é\ö ºU…Æ cÞ•5q™²vTluF–¦ÇnÑß¸¨,ð¶tsŒ–/O=%„¥ûÿú¦ÿ(<Üþ_áð Ýÿ7Rû	Rû©ý¿ùaNíÿ¥öÿTJjÿ/µÿ—ÚÿKíÿ}ÚöÿÖºõ†U÷¿sù9þÿ }ÿ¿™òÿêþâ¶ÐYàúê8–ƒÏ{O«•\¿t¹Ø™éÈhû_e1mý–Rìƒ€nx^`êf;úfÜÂ=)TŠ•y¸-gÈý*M|Ä£,Ñ(¨ˆÂ,
²R¨Õj§IU½e=nøc—Kè®3¡ÒLÝo‰ W²Krþ¤ttr<ù•’säÒ÷¢€B©'ÖŸ§GÇG	 ž›þÙø&¢wJ‰ÌÚV¬&tâIÌcr ÅÏFå
¹Ã„‘yI;Ú™’BH•Ï ŸI>špKEP-ÔrÕ£yÄ¸²¡a›=Üõ÷²ÂÍsXÉÙÆº¡öy%Ÿ˜J[N_ÁÙSŠK†*ÒÙi%ù×XŸœžTNª	Ì'JëÂ–ŒëžT™ùªÇ›çžBœØâ(ÆÃƒüµRB[¨¤Ð­&u‹daâSí‹Ó|Bå%(*14Üw‰ðƒ[³Åêáéª"‰Õ#$V»/NrÕÂ"y¨kO „FÌÑi±PÍ/ƒÙ#ƒ[ž!
±PûüøpñÐÓZ/u9mX#pñu@åbóõ¸T)%¬41_=6¶»ÜeŠ÷Hb=f€[jŸVòImL›EXŽôÄõW–ò§WèYý‘õ¿¹\aöþO¡Kí?n$ˆ‘.³{_KÃ'–®ÿÅö‡âø ûß‡G©ý÷„‡Œ¿àd¾¬¼ÿ}4÷þ'µÿ°¡pcö;]¼sÑ¹¯Zƒ—ÍøòÆ7:¾ná]
¡Þ’,çO?þé?Ø‰éuÆâõŒÐÆ]ÒtMg^µZõÆE`êºH6nœ1>…þ-ŠÛXj™]ÄöXó´*E¦>·¹kX¬ÀÎÊÛ”3ÞVªc©8ÊúI­’ˆìÒuFH]Røwv"Ê”zjFœÞm¶xö3ƒ÷§ÿõ_Xø{Çõã¨å!Ur™Ÿ›®? ò¸Ã„w'ÜÍáùó?²˜ìÇ&Žò´ô÷¼ããíˆà/:Õ÷±iÒ¢l6Âë?dýßŒû:Š´®ÿ°;€«îççø¿ÃB1µÿ¿‘Éd´`æýñŸØñ¸ÏÄokjb5)ÎLpî¸c•À»kì©íØ¥Úyå›>¾;Û~p®á¯¦Œ“¼QjÅ=¡¼Ö³v)417ÜÎ ßŸ{¾Pû!=Â{D¤B™]¡Ìæ·ÈÅM¦àþÕÓq5íÞòÎØ‚åfŒ Ü×”µJïýÙœ"JÄ0ºF÷kVGûÚ]ŽÚXPÜu—ùüÎG‹ÆÄ0-¤“{_ùázVt3ŸeÙlV+ˆ?âf~aÚæT¥—=uH$7¬M{ûö-"ÐF8ÁØ0–¦®Oz\íÍp9f'€/Åõ}TºÒÝlÔ
È+ýû¾Ñ/³·“\ö.;}«áõ0Ì!ì^¿5n:]ÞË	(•n×5O ¡ÝŸ#}‡®8¾Pœ‘¢O Ø†=%õ¬á:c»›^±ú+¡ÿr1ÝwXùþ»4{þstKý?o$Dè?rV§òˆ$8	9™~>wÜž¡D˜(ötT<ÂÒµÚ±^ÀJÆv‰báî=Ø‘»Äñ,ýW'9Dˆö_ŸÃ
 Hb¯ŸÆXÃ"wÀ(ùJâ?1º™:uÆÌw§ˆ¯Œ¢…¯Uä"»ømL7¥“ö˜`ß¨\Ö$WÏë¡>v<w˜¶/ö‚J§ÃG>6•uðy9t€ºçŒÛEÒ/*fáƒàí&¨¦J‘Oû!-ö€‰îR“èv|—»_?ˆÚ‹AñCvÜÛÔ?¥ôŸDˆÓnO>–Ó¿H¸¯þ§„.€@ÈåŠ…Tÿ³‰0?þYøçãâX©ÿã_Ìä
¹ƒÿR®”îÿ	Iã¹.ùQp¬ÿbáÆ¿pTÈóhÿ!—ò›	®ãøì™ÃÙÒ¶´7»×[Zg`¸ÇÏc¿—ù|KãvWwz¨äðÑêaNÓî¢©ÏŸZøÑ~Åƒûg¬¸¥ùÆ~kvýˆniCãŽ é·ûôÙéõ° Ç]_ï™À–è ÞK\¢^Àuß¹†@¿ ·DøbqäziVRjÊ¼ßM‡Ö>øáz¶Ò…­_g“°þAø3û60ÜÇªû‡…­ÿb©TÊàú‡] =ÿÝHÀÝ~KÃ³»ðw+_þ¡¸´þÂ¯[Úo¨€G¢ŠIIGEÕÄÂ¸*P_"…Ô§hAªGXŠ¢‘"óoi»YËéoiöh˜éò›q£Pá©áÚóH­'?Œf‹X(QÅ¾d;FgÀ÷á‡?Áñ/¡ßGÌ”Œ]é¡Y~ÛÍúÞÍØ´`îô¬¡2`EíiGö'!†.ã ¿«<Xøe¡mA7@)Ç®‘½Zµ0·üít9ÀÛúPÖš3at4õŽ-ÈˆHQøÐ&âAÃ ®q«~vßØBSi½,þ¤	àPA*Ä?Ô@jÈ’ôw,þz¢iæI±‘á¢¶°Çîƒ?î†Æ;ú£ æWh;}dÞ™øã7â—<‚Ä—ø²‘8î…qkÜ‡í$ˆËë~á¯û.ŒHm©‡hu}4¥êé:éhúºôZüìbm¦x÷Nš0œŽ¦aÌ÷zaÌwîðÏiê–&ÿˆGæ(s;àÐCîØ©„Ž÷ûk,¿=øK¹ð¤ïîSìûô[ê[D×7ñ½¸'Sw4~SbïÍ~FŒžŒ¨
ãšÿoïéŸÛ¶‘½Ÿ5ãÿA×7IœP–dKjÕÉË¸¶›zÎ±ý,§½ž£j(’ó«ü¥T}ûÛ]€$H‘q”¨ÊÍ1‰EìX|ïb,ò~’áGÊAãt0€hˆ½|à¹¡…æiÕŸAXÀ­¯Ô
·³Èc¥…©ç”÷¡ëAo6Eqö0|Ç÷é7)áñ0~ý†›o~%%à]¿§ñ‚¿4BÜñ{üÑ(€‰I4BKá5,‹ªzAƒStøpúðæ³Eð{,œC0ÝÐø¯ãò_>ìƒÇhTc6÷cçˆJÑp}sJ™f6%É–äkµég² 9Ã'ú:ó1•“70~Ä3¯Âs‚mÑJÇA¢ÒPS÷pÐÚÅûb,Srn ¼púÂ“â¾qäPQÞÌ#+":ú#ÇÑ>nd…ñ¤vÀÀ<ÀÙ¿&c!~ bwN¿˜‚!æ.”ð@Ã;ÜœÐ±G¶‹o =èaý€Ê—zgnÈKê‚tyÐ0•1ˆ¬h¸Æ;à]f‡Ÿ\›ÑÖŸ>(öxQí‰¦5›¡†LD¥¡·_ &®î*F“ý‡¸¾6GßÌÈ‚oÆg¬ÿ{jý·WÐþÌ¬ÀY¶·xLþïvRý_·IëÿÃêüÏN\%ÿWò%ÿWò%ÿWò%ÿoCþ‡žN^^/—¦Ðì¥å.Á,ˆbáqê5Ø>‡î€ÿëS“Û ñ¨þ·Ë÷šGGV«ò_õþ×ŽÜ>k|‰WŽëÌµ^òÍ}|ÙE8:÷£p’‹Q9Ä‡$Já%I¥&²3D-ãÙ¹8¸gSˆÀi¥‘ÚÐÎ“_!8T1BŸLK0x
0 ŠcØ÷…¹â%)É°`òäËaiÕ‹bÄû2„”ÐL¡• PÔ-){0/©a/h•ô®qI½e	bê– `vŸ"@~
Ó ´$–“§¢ûñZëx1JOzkAbÚ©ž¸Õ5ƒ=kp‘CØ’Q„qŽB6@ÊÙJ Ð’ETm:¢“«†9™Ä ÞRæ‰ˆ†f iãÖndŠçÀ"(òË3ð0 -Hö÷ÒIH~­$dÆK¾aÌ—,iÈÒ€‰_.H]ÎÁþÒªæ“°÷ÞËûÙTöOÍIÿÀÆžì7uWÂ##³~7çp'“¼¿IñƒéeSDn(çñC=‹'@êïåð~&>ÑÔ[²w&ˆäàfS$Ù]òkõ,±²Ö¹ØÞa&„íeýî<ë¿Ïú´y¾˜	bf6­vÖ?YHþ¯Íô%—•ÿPs±ý€Ÿ|ÿ³×íu»tþ¯ƒú¿êüß_ï
ÚmYlµlÔþ=ÒÿWí¿#WÖþ²Ã/¥ñÈú¯×]{ÿ½Õ«ÎîÆá«´õ—u…?ó«OÕFu nÒ5Ò@g>f®e@ÀN èe‘ß6kø
2©1,|Lv™A·šÍšîNÑ\Ø¼<P§Æ:*_ ŒÃè>`&À!!Tñˆ_¨Žù=‡—øzÍ$Â+!*žâËfªõ]¯Õêx©Î5+aèA$h,“…ÊUuâú*ô¡¬­v¾×mwÛ­££šæûÚ²„$O62ÈîQ9‘YñMÍ	×c·ºÍZM³,÷A5Æ¨V¹Á'q‚Q <Æj)RsL½9¾æ•aÝ¦,ÃâQÉ¶H`™:þ–Ñ˜m¨ÎYA6È–)€±h!^&U±ÊùóŒùüâ=–d8‡FcLøØ£
BßäO)Z¢Ö(l´†/e«€†$ÕXèšo¨¦÷^“ì9fáï†Ù¹kêØgÚÃl¹xÙZÕ<3)áê*=È¬šÝ=‡¨J£¡kIêÂ€a. vDÂòˆÇPéln¶+&Qyšê˜aµ`
L)™†ò¢®¸÷ø—Óãf÷)¾gŒ“›ŠÁò‰Ã’*NŸÐ”ÃtBúc{išRX[Ó}—Óõ?è! œh‚Ðè÷©ó*x¡TÃu*€|`Ãp£ÍRD|Ïa’‰6| Är§<îƒüMk^©õ?_”R°œ¿”++ú­’(,Çg)¢ÓLž €þ«0ùúsnî“Ë¡»>ƒöÀ)O„€ŸÁî@áüHÇÉÜàW¯7¥º†›'…°„Ò§WO0rLäUÈ™‘O9ƒüÅ M‹0fÒ§I¥.a¥Ú"–ôÂ;1’ ïdÎ4Ü×áÕö‘,äÆ*g®Q4Xyæø5õ~ÿJüò	y½ší3¯èÑ”sR·X¸að-¨~ÿFünLvCzùbrÆ’§Ç¡[ï³ùÂþeÄ7háQä«Îõù±æÔŒ¨ÿïå~hƒL]£õ¥„žÒ1L>v¾¼ì4[…ù²™³Œ¯9…l-	æ{zùõ@›0¼l6 ëÓq6"‡ÐøŒ³”ÝMÙ‹23ös­×d¢óø@†mÐOˆ
HsýþÏøÇ)'OÆâ’OjÇõ—›åì.üüà.¾0íìÌ†«‘R!Dg–…}kr³®9ø´b}ìÂ˜z¨SÏ
’&MšÏ`¸£Ž-JÍH/5×¶i•³a3úPµ7Y6)Èû:¶œ†ÉØ0L’Ó4#¾ÃP,XË‹ùq’ôVy¢oØÖºkYL<xÙÇëáÌ¸0ƒ° žRdR9ÐGàÿ)ZØ.Ï¯íðwÀÐjQuP=¨èÃÀï–©}¥§­({c¦ÙÏêãØfñf-!gã†éÚrî\5œÕÿÐ|¸uð&ú¿N¯úßn¯UéÿváŠÚÛ
àÍÛ¿×ív«öß…+mÿFòXÍÓxDÿÛîŠóÿ­^ë¨Û¡ó?Nuþg'în
bòlXãGKSYIY|ÛuÔÈ¹wÜÒ›EuêD
g—Š†Û> 0Á­\ OWLÇpÕæz‹/f2ÕÐ|“'ÃQ¦&v…Î-¸I®¤»ÓŒ¹¸(ûkKdæØ×•ZäØšé„ðŸCñ ]WPålÚ‘­cÔ[Ìyƒ\6O•¿+“€% $N2æ/‘ù:±QÍÌéŒŽÓ’Xâ¨Pò4ƒ{Ó©cpI %îm#X·¸ V…!;Dà`¶%sòQÔ`lR»A¬©¶3òÓ5—Ÿ¦æM-qIÖ%î@ä¬>Ö¦SmÊÖé@¬„ˆ‚Ká`Öæå¨ñÚRCŸ±¢zŠ»/tšq'A‹Í"aèïcCz Ôá"ÛÄòßo%¹ŽÞ‚MwWÄòƒÚ¿AL†Ðû˜…¨¸‘»vÇß5…^ŸMA~ö—rgä˜)mR —¥ÀwÊ,½  L·5t×¦ù›ÎÆˆ'•¦Ë÷ÊP¤À…þ„v¾LVJ Q(µ"›#}¨sCMÔÒü%V© ÊB+a!LnõJ5Ø<Ñ¨ç¢‹À¢w»JNòCZzvó£Ùø®“v}ÞÀÇÖUÛf<¼9¿?œªmõÄÒ€^»<Çßo*«‡ilŒr˜‹r>8‰?ÿ*þnBØøûä¤©¶ÒTâ„O¨mYcøtÞÁàBá!®¥,	çÐÃt² éékÏÿYþOÏHo}°Ñþ‹Ûÿ9êUòß.\aûoy°qû·›Í£ÊþûN\yûgÞ¸ü"Èÿ-è\þï¢1hnÿ¿YÝÿÜ‰cÜ$2æ6¬»”teÁGÀïÑnSlÈ©Õn’a'ŽQ°9ªÍ@ž,Ý~¯	+N‰‰(ä˜, ÙÀâG3ùhðY'ÙèHH\ß`þ(·÷ƒÅ…¡dC›˜Ì2Fø
Ý¤?Ä=°8 âARZG@Š¶;g#<aÂŒ‘§ùÌI’µ,†F@5¸1Æ†#Ô¾#mœlëÓfÓhŒ§SÓSt/+Í'È®(ŽòËQÎ,ÃœÈÒè5¨zãI©M}7ò¤ºP¡q¶ kŸ–Rãcv„²TÂÈpu¢-ŽƒXæFØôrT4L‚öìGcèè%(*(óƒá¥r_ì²ó?î`„Ë¯&ÿµñ2—ÿ+ýïN\aû7‚å$üâg_÷˜þ¯Óëqþßé4ÈþC³{X½ÿ°g¹Óþ,\Löc‰õºÅæÌê×<§ `Îü± {ê×›dÈ€ñáqIÍóÔÈ3 õS‹œoPÒžÏBŒ–¤w“S€CÊSM—Ag,ÔÅÑ—ºå:ì“C-l«8Ð^-Ð]Š¡¿GxÝPðZ•Â
³ÌÀE'£Ø¨Ò›™^À‹(®^áÕ'Õ}p€G®/¬S–áU¼˜oiI8~ÕÙ2Ñ&8%k›AŸËƒL¾ë)2\(¨0¿a4V0æø¦>ë×ï†èJ$žI.ñ áGoÒ«› º3Íª¤±RñH‚…Iè4Tä€ âªx|}†rRZ
¡r%¢j]ACS3T$/¿<.Cðî¸ä—o‡K`¼ß%yIÉ&ù¹[ð›ç@²ð S—í:ÈðÔ¾ƒMí<ÈÐ5@jÞ#e‹¬?ÊúÉ*5¥¨uªFþ@
×âÔy rÖƒ$#@´‹Ê¯!Å½E¯uÙ½šP\u:bàÀô ˆ¥p(·+Ñ¯÷:4äñIsêžÂ¨…dxXço*HÈ@Š¢p
b˜ø¸@ "P]3­Ýé*2y‘ªwée`Uc‡ÆÔý:n6ixrU%…kSq_H7(­$“…D?«œ*Žr®e%<š§Õéx9)—-<Ùì›y~I‚ ®µ²òÜ£©:ó±)hÑ¯=ý—ðÿ)>Ö Ý;Úÿãï ÿo5ùýÿ.üTüŽžåÀ•åkÑäõ2±ùœÅÑP¸ƒ9fRè¯Ð·OÙD‹¬ŒÑè;RØ‡ƒ!’žÆ”Ï¹Â;½IKÓv=±XC<6œÑÞ#‹Ož<yúÛêàÙ;ìˆà{‘‡sRˆBNRˆ ëD…ˆ¨Á-a¸ùuŒÌ·
Ðt?yÌo#¯Ã…½ŸuçkÅˆyq…#d‹GEÑ2ŠHŠÐ’I¤ÂšO-`eÑ¯LÀ>}Õÿ`z+¨…U8ý°‚½+|ïá?¦Ï¾)Žä9ÓÕ{½š®¦æd…—ªWcÛ[™º»òŒÉ
ØãÊ°¬Uà®èjñ
øáŠ.F¿Z…!àÝ0NyøéÝÛÏM7
êt7³€¡*ÄEØâ–Ú‘Î–‘‘³Îr}0†L´{ÈbdÛË•°v¶âFÐVØ+‰ÄÊg††[’q½20­¸ç«%¸ç«àž¯pÎ}¾j{^k	<ôNÕ‡¯À£y&ÿ~öêž-W).tï™³â¦Û9'K…º
B×{pùV·(¨rsv}q|r6zs¦ÊÊÉOÇ—¯ àöêô*ñ_ŸþqökâœÜœÝf@äöêg—)äääl0È½z{Sº>~¹º9M gÿ<~s}‘ægõž¾}óæ×|àÑÏÇoóQr@Š˜ƒÝžns Ë«ÛÑñˆ—Sáu»ù¿ÿ‡¾9_nMð˜þÿ¨w$øÿQ¯×mUöwèÈÂa"©fµ ±D› ð84=ÖjÚM²˜gŒI<v\ÕóÝ)Þ¶KWÞýTÈÎÉñ 4ƒ%…0íx}C_*·î§:¢õcÉ\Åõ.GÅ >’°ÏP—b±ùÓùëŸø×ÉÍùíùÉñ„Áã¥¤‚8uq•cÈ
I:óÈB)elZqš|»Oý„QÀ…öAZyñL«ƒ9[¨øle^)‚+!žYUZ¢`^Ñú×>h\}GØñZdÈðb.Bò$há¯’FV3pU6¦¡óU‰Ì×bI%‹ HÉ¦”ÊfÉwlNx¹%8îÉzã0”ƒâoaò{¸Ä“dVŽã>IVIÉòILe’”Ê!	(ëK%‘Ä’'’<$þ,Þ¶à²ób*r«46Ñÿ7¹þÿ°]ÿÝ‰+iÿFlJv2Àcü¿Ýéò÷Ÿ€íwèüG«Ó©ôÿ;qb«XzòÚ½Oúb:8ÒÍQèŽÐ‚B_ìfó³†#~#
ƒ“qù{ãIÎ"û…Ýƒý}¥H%›ÓÚ_ˆÕ°ö¾R@l×+…ˆ¥²Jz¹D›¸¹xól~Ö!¤jÈ@„ERÄ•Ù”¸ö"#íD	Hb kÓó™nr­	Ï­öë†ûà OsP«ôšÆw/X	Á…X—Ç_ˆï…§Á59±·.¸o¿þmó¿SX|8„ŠŠfŠqƒ‡ÎË&‡hàG)|÷y¾öhùÏsÙùŸï‡}ÕýÿV‹öÿ;ÕùÏ¸Âöo„šg¹ÛQþÿíqýï0Ñÿ·Û´þou+þ¿'çt•€,¯c£+CùÚW@IùE
‰9`
Êóù3ë’pë”2ù–²ðlžËK(aÇ,áÇrÔ„!KÀ˜#Ë (â†è%@Nœá· 8+CSVÃôáL/´¿¬+x¼ÙNzÄ²Ù¬%g	³ïaÖ4„+ùŸd‰£±¥9÷ôÆ&âZ54 ›žÊ¼»ó¡i†É­¸å¹yYÑú÷lÉýÄÛ´ÃZZ„F|S„ú¬„Ó»U/¤‹V›ÙcFö+$ è‹a&â—ûÛ'ŸøÌ¦\ÐÜÛ¥Ë;¤Á<¼CïèdìAtRµšÖÅÇ±Å±ù°mìFNkq?¿Jø"ãk¤±_\')¼¸VŠðe)ÖLº þÖÎ'Íÿ%üé¹[ÚüÿÛãöÿ›G)ÿïrûÿ•ýÇ¸;:I3ÄC[¸Å¯J|oñïpþ½rÖ¿·Îû÷
˜ÿ^÷ß+bÿ{ëü¯@ Ø+’ öŠD€½B`¯@Ø+öÖÄ€½R9€¶ìÄ¾Õyr€B é!nšëk¡f¦SD=yÍZ€§–;Ö¬50]këòÛ×bI>¤Wu4ºD*âD'äÏ&„SpŠøÕÇÄe×ø)æ¨n{‹Þ$²áËýéé«ûÙoý§_<{÷.Ø<fYÜp“ß·>P~ù&©Ð’À"}l$ŠðîÓHÛåé«àYIDw2iì¿‚àˆ)ãÈ)Ažÿ^WK\ý¾-Å}“Ë8{}~Y¿~}]œ¿¾<¾}{sFpÈýž]ž`E/ÊV.Y}4'&ˆMÙŠ~÷n|{1Ý«ÿjªß†ÏŸŽ4Çu$À3¨q’9ø¾¸¦N†|ûâOZ£GÛùYJ¿a’Ã?Z/ÿL›ì7Lløü%9GÖ˜hœ¤ib¿M×4††¹.WÖ;Ó.MéÚ¦ƒ•`”¥Í@Á2ñêAPF-N59´Tœ¬ü:@’4 ’eÊR"b46â*NÛâ(§—ƒÑÙÍÍÕÍèüòçãó‹ÓÑÏç7·o/Îÿu|{~u	àÁíñåÉÙèòøÍ™‚pÃ(@„‡þñüâ!£³žœŽnðô%øtIä³OŽ-²H!ñûâüT)ªêrX! ý8îC H7ù•ÿŒ}¸¯åŠå?ú…^èëÛØ zDþköš½ÄþK¯G÷?›½êüçN\°[m$*|²7û.2úñ5Oák×j³M±¿ÃÍÿoäâ‚¼ƒ5àïø}í»xêC€Q3ƒµê«É0ì~Ýš M7`¿øx63ÎÝÇ	^£ì£Á44¶í>\ÓEM<hË Vû°rgáÀ#ã´‚jFÁ‰ˆÂñLÇ÷¯™/£Qõ Â•q!^•ù1Y^õé„F­†Û0>ÌÑßÖ"1®_¿{BïU=yQÂß§z2$ÈjñæG¦&sÑmƒÇ¶Eqäåd™ÏŸ“ñÿÀÆÛùƒ»OÕÿ÷à_³‹ö¿:GÍêþ_å*W¹ÊU®r•«\å*W¹ÊU®r•«\å*W¹ÊU®r•«\å*W¹ÊU®r•«\å*W¹ÊU®r•«\¡ûŒtÀ_ H 
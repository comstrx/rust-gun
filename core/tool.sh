
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

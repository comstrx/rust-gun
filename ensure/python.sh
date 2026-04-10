
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

    ensure_pkg python pip 1>&2

    tool_export_python_bin
    tool_python_aliases_unix
    tool_hash_clear

    tool_python_ok "${want}" || die "Python install did not satisfy requirement." 2
    tool_pip_ok || die "pip is not available after Python install." 2

}


install_line_once () (

    ensure_pkg grep rm mv dirname mktemp cat sleep kill tail 1>&2

    local file="${1:-}" line="${2:-}"
    local tmp="" owner_pid="" i=0 max_tries=200

    [[ -n "${file}" ]] || die "install_line_once: missing file"
    [[ -n "${line}" ]] || die "install_line_once: missing line"
    [[ -L "${file}" ]] && die "install_line_once: refusing to modify symlink: ${file}"

    ensure_file "${file}"

    LC_ALL=C grep -Fqx -- "${line}" "${file}" 2>/dev/null && return 0
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
        (( i < max_tries )) || die "install_line_once: lock timeout for ${file}"

        sleep 0.05 || true

    done

    trap 'rm -f -- "${tmp}" "${lock_file}" 2>/dev/null || true' EXIT INT TERM HUP

    LC_ALL=C grep -Fqx -- "${line}" "${file}" 2>/dev/null && return 0
    LC_ALL=C grep -Fqx -- "${line}"$'\r' "${file}" 2>/dev/null && return 0

    tmp="$(mktemp "${dir}/.tmp.install_line_once.XXXXXX")" || die "install_line_once: mktemp failed in ${dir}"

    {
        cat -- "${file}"
        [[ -s "${file}" && -n "$(tail -c 1 -- "${file}" 2>/dev/null)" ]] && printf '\n'
        printf '%s\n' "${line}"
    } > "${tmp}" || die "install_line_once: failed writing temp file for ${file}"

    mv -f -- "${tmp}" "${file}" || die "install_line_once: failed replacing ${file}"

)
install_path_once () {

    local rc="${1:-}" alias="${2:-}"

    [[ -n "${rc}" ]] || die "install_path_once: missing rc"
    [[ -n "${alias}" ]] || die "install_path_once: missing alias"
    [[ -L "${rc}" ]] && die "install_path_once: refusing to modify symlink: ${rc}"

    ensure_file "${rc}"
    install_line_once "${rc}" "# ${alias}"

    case "${rc}" in
        */.config/fish/config.fish) install_line_once "${rc}" 'set -gx PATH $HOME/.local/bin $PATH' ;;
        *)                          install_line_once "${rc}" 'export PATH="$HOME/.local/bin:$PATH"' ;;
    esac

}
install_launcher () (

    ensure_pkg chmod mkdir mv rm mktemp 1>&2

    local root="${1:-}" alias="${2:-}" root_q="" tmp=""
    local run_sh="${root}/entry/run.sh"
    local bin_dir="$(home_path)/.local/bin"
    local bin="${bin_dir}/${alias}"

    [[ -n "${root}" ]] || die "install_launcher: missing root"
    [[ -f "${run_sh}" ]] || die "install_launcher: missing ${run_sh}"

    validate_alias "${alias}"
    ensure_dir "${bin_dir}"

    [[ -e "${bin}" && ! -f "${bin}" ]] && die "install_launcher: refusing non-file target ${bin}"
    [[ -L "${bin}" ]] && die "install_launcher: refusing to overwrite symlink ${bin}"

    if [[ -e "${bin}" && ! (( YES )) ]]; then confirm "Overwrite ${bin}?" "N" || die "Canceled."; fi

    printf -v root_q '%q' "${root}"

    tmp="$(mktemp "${bin_dir}/.tmp.${alias}.XXXXXX")" || die "install_launcher: mktemp failed in ${bin_dir}"
    trap 'rm -f -- "${tmp}" 2>/dev/null || true' EXIT INT TERM HUP

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        '' \
        "ROOT=${root_q}" \
        '' \
        'exec /usr/bin/env bash "${ROOT}/entry/run.sh" "$@"' \
        > "${tmp}" || die "install_launcher: failed writing ${tmp}"

    run chmod +x -- "${tmp}" || die "install_launcher: chmod failed ${tmp}"
    mv -f -- "${tmp}" "${bin}" || die "install_launcher: failed replacing ${bin}"

    printf '%s\n' "${bin}"

)
install () {

    local alias="${1:-gun}"
    local rc="$(rc_path)"
    local bin_path="$(install_launcher "${ROOT_DIR:-}" "${alias}")"

    install_path_once "${rc}" "${alias}"

    success "Installed: ( ${alias} ) at ${bin_path}"
    success "Reload: source \"${rc}\""

}

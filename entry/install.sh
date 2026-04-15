
install_confirm () {

    local bin="${1:-}"

    [[ -n "${bin}" ]] || die "Missing install target"
    [[ -L "${bin}" ]] && die "Refusing to overwrite symlink ${bin}"
    [[ -e "${bin}" && ! -f "${bin}" ]] && die "Refusing non-file target ${bin}"

    [[ -e "${bin}" ]] && (( ! YES )) && { confirm "Overwrite ${bin} ?" || die "Canceled"; }

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

    local tmp="$(mktemp "${dir}/.tmp.install.XXXXXX")" || {
        rm -f -- "${lock_file}" 2>/dev/null || true
        die "mktemp failed in ${dir}"
    }

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

    [[ -n "${BASH_SOURCE[0]:-}" && -r "${BASH_SOURCE[0]}" ]] && src="${BASH_SOURCE[0]}"
    [[ -z "${src}" && -n "${0:-}" && -r "${0}" ]] && src="${0}"

    [[ -n "${src}" ]] || die "Cannot self-install from stdin. Use: bash <(curl -fsSL URL) --install --alias gun"

    cat -- "${src}" > "${out}" || die "Failed to copy: ${src}"
    [[ -s "${out}" ]] || die "Invalid source code"

}
install_bin () {

    ensure_tool chmod mkdir mv rm mktemp cat

    local alias="${1:-}"
    local rc="$(rc_path)"
    local bin_dir="$(home_path)/.local/bin"
    local bin="${bin_dir}/${alias}"

    validate_alias "${alias}"
    ensure_dir "${bin_dir}"
    install_confirm "${bin}"

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

    local alias="${1:-${APP_NAME:-}}"
    local bin="$(install_bin "${alias}")"
    [[ -n "${bin}" ]] && success "Installed: ( ${alias} ) at ${bin}"

}

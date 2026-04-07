
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/boot.sh"

ensure_line_once () {

    ensure_pkg grep 1>&2

    local file="${1:-}"
    local line="${2:-}"

    [[ -n "${file}" ]] || die "ensure_line_once: missing file" 2
    [[ -n "${line}" ]] || die "ensure_line_once: missing line" 2
    [[ -L "${file}" ]] && die "ensure_line_once: refusing to modify symlink: ${file}" 2

    ensure_file "${file}"

    LC_ALL=C grep -Fqx -- "${line}" "${file}" 2>/dev/null && return 0
    LC_ALL=C grep -Fqx -- "${line}"$'\r' "${file}" 2>/dev/null && return 0

    printf '%s\n' "${line}" >> "${file}" || die "ensure_line_once: failed writing ${file}" 2

}
ensure_path_once () {

    local rc="${1:-}"
    local alias_name="${2:-}"

    [[ -n "${rc}" ]] || die "ensure_path_once: missing rc" 2
    [[ -n "${alias_name}" ]] || die "ensure_path_once: missing alias" 2
    [[ -L "${rc}" ]] && die "ensure_path_once: refusing to modify symlink: ${rc}" 2

    ensure_file "${rc}"
    ensure_line_once "${rc}" "# ${alias_name}"

    case "${rc}" in
        */.config/fish/config.fish) ensure_line_once "${rc}" 'set -gx PATH $HOME/.local/bin $PATH' ;;
        *)                          ensure_line_once "${rc}" 'export PATH="$HOME/.local/bin:$PATH"' ;;
    esac

}
install_launcher () {

    ensure_pkg chmod mkdir 1>&2

    local root="${1:-}" alias_name="${2:-}" root_q=""
    local run_sh="${root}/scripts/run.sh"
    local bin_dir="$(home_path)/.local/bin"
    local bin="${bin_dir}/${alias_name}"

    [[ -n "${root}" ]] || die "install_launcher: missing root" 2
    [[ -f "${run_sh}" ]] || die "install_launcher: missing ${run_sh}" 2

    validate_alias "${alias_name}"
    ensure_dir "${bin_dir}"
    run chmod +x -- "${run_sh}" 2>/dev/null || true

    [[ -e "${bin}" && ! -f "${bin}" ]] && die "install_launcher: refusing non-file target ${bin}" 2
    [[ -L "${bin}" ]] && die "install_launcher: refusing to overwrite symlink ${bin}" 2

    if [[ -e "${bin}" && ! (( YES )) ]]; then confirm "Overwrite ${bin}?" "N" || die "Canceled." 2; fi

    printf -v root_q '%q' "${root}"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        '' \
        "ROOT=${root_q}" \
        '' \
        'exec /usr/bin/env bash "${ROOT}/scripts/run.sh" "$@"' \
        > "${bin}" || die "install_launcher: failed writing ${bin}" 2

    run chmod +x -- "${bin}" || die "install_launcher: chmod failed ${bin}" 2
    printf '%s\n' "${bin}"

}
install () {

    source <(parse "$@" -- :alias=gun)

    local rc="$(rc_path)"
    local bin_path="$(install_launcher "${ROOT_DIR:-}" "${alias}")"

    ensure_path_once "${rc}" "${alias}"

    success "Installed: ( ${alias} ) at ${bin_path}"
    success "Reload: source \"${rc}\""

}


cmd_new () {

    source <(parse "$@" -- :template name dir placeholders:bool=true git:bool=true)

    local root="${ROOT_DIR:-}/template"
    local cdir="${root}/config"
    local src="" template_key=""

    [[ -d "${root}" ]] || die "cmd_new: template root not found: ${root}"

    template_key="$(resolve_name "${template}")"
    src="$(resolve_path "${root}" "${template_key}")"
    [[ -d "${src}" ]] || die "cmd_new: template not found: ${template}"

    dir="${dir:-${PROJECTS_DIR:-${WORKSPACE_DIR:-${PWD}}}}"
    dir="${dir/#\~/${HOME}}"
    dir="${dir%/}"

    case "${template_key}" in
        empty)     [[ -n "${name}" ]] || name="rust-app" ;;
        lib)       [[ -n "${name}" ]] || name="rust-lib" ;;
        ws)        [[ -n "${name}" ]] || name="rust-workspace" ;;
        workspace) [[ -n "${name}" ]] || name="rust-workspace" ;;
        *)         [[ -n "${name}" ]] || name="${template_key}" ;;
    esac

    name="$(normalize_name "${name}")"

    [[ "${dir##*/}" == "${name}" ]] || dir="${dir}/${name}"

    copy_template "${src}" "${dir}"
    resolve_config config_dir="${cdir}" dest_dir="${dir}" "${kwargs[@]}"

    (( placeholders )) && set_placeholders root="${dir}" name="${name}" repo="${name}" "${kwargs[@]}"
    (( git ))          && set_git          root="${dir}" name="${name}" repo="${name}" "${kwargs[@]}"

    success "OK: ${name} was successfully set up at ${dir}"

}

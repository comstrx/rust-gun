
cmd_forge_help () {

    info_ln "Scaffold :"

    printf '    %s\n' \
        "" \
        "new                        * Create a new project from template (default: empty)" \
        "new-lib                    * Create a new library project from template" \
        "new-ws                     * Create a new workspace project from template" \
        "new-web                    * Create a new web project from template" \
        ''

}

cmd_new () {

    source <(parse "$@" -- :template dest name type config:bool git:bool=true placeholders:bool=true)

    template="$(forge_resolve_name "${template}")"

    local root="$(forge_template_dir)"
    local src="$(forge_resolve_path "${root}" "${template}" "${type}")"
    local conf="${root}/conf"

    dest="${dest%/}"
    [[ -n "${dest}" && "${dest}" != */* ]] && { name="${name:-${dest}}"; dest=""; }

    local base="${dest##*/}"
    name="${name:-${base:-"$(forge_display_name "${template}")"}}"
    dest="$(forge_resolve_dest "${dest}" "${name}")"

    forge_copy_template "${src}" "${dest}"

    if (( config )) || [[ "${src}" != */pure/* ]]; then
        forge_copy_config "${template}" "${conf}" "${dest}" "${kwargs[@]}"
    fi

    (( git ))          && forge_init_git     "${dest}" "${name}" "${kwargs[@]}"
    (( placeholders )) && forge_placeholders "${dest}" "${name}" "${kwargs[@]}"

    success "OK: ${name} was successfully set up at ${dest}"

}
cmd_new_lib () {

    cmd_new "$@" --type lib

}
cmd_new_ws () {

    cmd_new "$@" --type ws

}
cmd_new_web () {

    cmd_new "$@" --type web

}

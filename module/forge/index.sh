
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

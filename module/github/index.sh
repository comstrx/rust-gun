
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
    (( sync )) && { cmd_sync_vars "${kwargs[@]}"; cmd_sync_secrets "${kwargs[@]}"; }

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

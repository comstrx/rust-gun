
cmd_github_help () {

    info_ln "GitHub :"

    printf '    %s\n' \
        "" \
        "set-var                    * Add GitHub variable" \
        "set-secret                 * Add GitHub secret" \
        "del-var                    * Delete GitHub variable" \
        "del-secret                 * Delete GitHub secret" \
        "" \
        "sync-vars                  * Sync GitHub variables from file" \
        "sync-secrets               * Sync GitHub secrets from file" \
        "clear-vars                 * Remove all GitHub variables" \
        "clear-secrets              * Remove all GitHub secrets" \
        "" \
        "ssh-list                   * List GitHub ssh keys" \
        "repo-list                  * List GitHub repos" \
        "env-list                   * List GitHub environments" \
        "var-list                   * List GitHub variables" \
        "secret-list                * List GitHub secrets" \
        "" \
        "new-ssh                    * Create SSH key and optionally upload on GitHub" \
        "remove-ssh                 * Remove GitHub ssh key" \
        "new-repo                   * Create GitHub repository and sync vars/secrets" \
        "remove-repo                * Remove GitHub repository" \
        "new-env                    * Create GitHub environment" \
        "remove-env                 * Remove GitHub environment" \
        ''

}

cmd_set_var () {

    source <(parse "$@" -- :name value repo)
    gh_var_action add variable "${repo}" "${name}" "${value}" "${kwargs[@]}"

}
cmd_set_secret () {

    source <(parse "$@" -- :name value repo)
    gh_var_action add secret "${repo}" "${name}" "${value}" "${kwargs[@]}"

}
cmd_del_var () {

    source <(parse "$@" -- :name repo)
    gh_var_action remove variable "${repo}" "${name}" "${kwargs[@]}"

}
cmd_del_secret () {

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

cmd_ssh_list () {

    gh_ssh_list "$@"

}
cmd_repo_list () {

    gh_repo_list "$@"

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

cmd_new_ssh () {

    gh_new_ssh "$@"


}
cmd_remove_ssh () {

    gh_remove_ssh "$@"

}
cmd_new_repo () {

    source <(parse "$@" -- :name sync:bool=true)
    gh_new_repo "${name}" "${kwargs[@]}"

    (( sync )) && {
        cmd_sync_vars    --repo "${name}" "${kwargs[@]}"
        cmd_sync_secrets --repo "${name}" "${kwargs[@]}"
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

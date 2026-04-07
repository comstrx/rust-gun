
cmd_vet_help () {

    info_ln "Vet :\n"

    printf '    %s\n' \
        "vet-init                   * Initialize supply-chain auditing (cargo vet init)" \
        "vet-fmt                    * Format supply-chain files (cargo vet fmt)" \
        "vet-check                  * Verify audits and policies (cargo vet check)" \
        "vet-suggest                * Suggest policy imports / criteria (cargo vet suggest)" \
        "" \
        "vet-diff                   * Diff between dependency versions (cargo vet diff)" \
        "vet-certify                * Certify a crate version into audits (cargo vet certify)" \
        "vet-trust                  * Trust a crate/publisher (cargo vet trust)" \
        "vet-deny                   * Record a violation (cargo vet record-violation)" \
        "vet-prune                  * Prune unused audits (cargo vet prune)" \
        "vet-renew                  * Renew audit freshness (cargo vet renew)" \
        "vet-clean                  * Delete supply-chain directory (cleanup)" \
        "vet-import                 * Import audits from <name> (cargo vet import)" \
        "" \
        "vet-import-best            * Import best presets (mozilla/google/isrg/bytecode-alliance)" \
        "vet-trust-best             * Apply curated trust set (safe-to-deploy baseline)" \
        ''

}

cmd_vet_init () {

    [[ -f "${ROOT_DIR}/Cargo.lock" ]] || run_cargo generate-lockfile
    [[ -f "${ROOT_DIR}/supply-chain/config.toml" && -f "${ROOT_DIR}/supply-chain/audits.toml" ]] || run_cargo vet init

}
cmd_vet_fmt () {

    cmd_vet_init
    run_cargo vet fmt "$@"

}
cmd_vet_check () {

    cmd_vet_init
    run_cargo vet check "$@"

}
cmd_vet_suggest () {

    cmd_vet_init
    run_cargo vet suggest "$@"

}
cmd_vet_diff () {

    cmd_vet_init
    run_cargo vet diff "$@"

}
cmd_vet_certify () {

    source <(parse "$@" -- :name :version :criteria="safe-to-run")

    cmd_vet_init
    run_cargo vet certify "${name}" "${version}" --criteria "${criteria}" "${kwargs[@]}"

}
cmd_vet_trust () {

    cmd_vet_init
    run_cargo vet trust "$@"

}
cmd_vet_deny () {

    cmd_vet_init
    run_cargo vet record-violation "$@"

}

cmd_vet_prune () {

    cmd_vet_init
    run_cargo vet prune "$@"

}
cmd_vet_renew () {

    cmd_vet_init
    run_cargo vet renew "$@"

}
cmd_vet_clean () {

    confirm "Are you sure about deleting the supply chain?" && rm -rf supply-chain

}
cmd_vet_import () {

    source <(parse "$@" -- :name)

    cmd_vet_init
    run_cargo vet import "${name}" "${kwargs[@]}"

}

cmd_vet_import_best () {

    cmd_vet_import mozilla
    cmd_vet_import google
    cmd_vet_import isrg
    cmd_vet_import bytecode-alliance

}
cmd_vet_trust_best () {

    cmd_vet_trust dtolnay                                 --criteria safe-to-deploy
    cmd_vet_trust r-efi dvdhrm                            --criteria safe-to-deploy
    cmd_vet_trust libfuzzer-sys fitzgen                   --criteria safe-to-deploy
    cmd_vet_trust getrandom josephlr                      --criteria safe-to-deploy
    cmd_vet_trust find-msvc-tools cuviper                 --criteria safe-to-deploy
    cmd_vet_trust libc rust-lang-owner                    --criteria safe-to-deploy
    cmd_vet_trust jobserver rust-lang-owner               --criteria safe-to-deploy
    cmd_vet_trust cc github:rust-lang/cc-rs               --criteria safe-to-deploy
    cmd_vet_trust find-msvc-tools github:rust-lang/cc-rs  --criteria safe-to-deploy

}

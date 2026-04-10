
cmd_safety_help () {

    info_ln "Safety :\n"

    printf '    %s\n' \
        "audit-check                * Security advisories gate (cargo deny advisories/bans/licenses/sources)" \
        "audit-fix                  * Auto-fix advisories by upgrading dependencies (cargo audit fix)" \
        "" \
        "fmt-check                  * Verify formatting --nightly (no changes)" \
        "fmt-fix                    * Auto-format code --nightly" \
        "fmt-stable-check           * Verify formatting checks (no changes)" \
        "fmt-stable-fix             * Auto-format code" \
        "" \
        "lint-check                 * Clippy check lint for publishable crates only (workspace gate)" \
        "lint-fix                   * Clippy fix lint / update depds with cargo update for publishable crates only (workspace gate)" \
        "lint-strict-check          * Clippy check lint for full workspace (including non-publishable crates)" \
        "lint-strict-fix            * Clippy fix lint or update depds with cargo update (including non-publishable crates)" \
        ''

}

cmd_audit_check () {

    if [[ -f deny.toml ]] || [[ -f .deny.toml ]]; then run_cargo deny check advisories bans licenses sources "$@"
    else run_cargo audit "$@"
    fi

}
cmd_audit_fix () {

    # run_cargo audit fix "$@"
    run_cargo update "$@"

}

cmd_fmt_check () {

    run_cargo fmt --nightly --all -- --check "$@"

}
cmd_fmt_fix () {

    run_cargo fmt --nightly --all "$@"

}

cmd_fmt_stable_check () {

    run_cargo fmt --all -- --check "$@"

}
cmd_fmt_stable_fix () {

    run_cargo fmt --all "$@"

}

cmd_lint_check () {

    run_workspace_publishable clippy --workspace --all-targets --all-features "$@"

}
cmd_lint_fix () {

    run_workspace_publishable clippy --fix --allow-dirty --allow-staged --workspace --all-targets --all-features "$@"

}

cmd_lint_strict_check () {

    run_workspace clippy --workspace --all-targets --all-features "$@"

}
cmd_lint_strict_fix () {

    run_workspace clippy --fix --allow-dirty --allow-staged --workspace --all-targets --all-features "$@"

}

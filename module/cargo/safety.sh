
cmd_safety_help () {

    info_ln "Safety :\n"

    printf '    %s\n' \
        "typo-check                 * Typos check docs and text files" \
        "typo-fix                   * Typos fix docs and text files" \
        "" \
        "taplo-check                * Validate TOML formatting (no changes)" \
        "taplo-fix                  * Auto-format TOML files" \
        "" \
        "prettier-check             * Validate formatting for Markdown/YAML/etc. (no changes)" \
        "prettier-fix               * Auto-format Markdown/YAML/etc." \
        "" \
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
        "" \
        "normalize                  * Remove trailing whitespace in git-tracked files" \
        "leaks                      * Remove trailing whitespace in git-tracked files" \
        "sbom                       * Remove trailing whitespace in git-tracked files" \
        "trivy                      * Remove trailing whitespace in git-tracked files" \
        "" \
        ''

}

cmd_typo_check () {

    ensure typos

    local -a cmd=()

    local config="$(config_file typos toml)"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    run typos --format brief "${cmd[@]}" "$@"

}
cmd_typo_fix () {

    ensure typos

    local -a cmd=()

    local config="$(config_file typos toml)"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    run typos -w "${cmd[@]}" "$@"

}

cmd_taplo_check () {

    ensure taplo
    run taplo fmt --check "$@"

}
cmd_taplo_fix () {

    ensure taplo
    run taplo fmt "$@"

}

cmd_prettier_check () {

    ensure node
    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --check "**/*.{md,mdx,yml,yaml,json,jsonc}" ".prettierrc.yml" "$@"

}
cmd_prettier_fix () {

    ensure node
    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --write "**/*.{md,mdx,yml,yaml,json,jsonc}" ".prettierrc.yml" "$@"

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

cmd_normalize () {

    ensure git perl

    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo"
    git diff --quiet -- && { git diff --cached --quiet -- || die "normalize: requires clean worktree"; }

    git ls-files -z | perl -e '
        use strict;
        use warnings;
        use File::Basename qw(dirname);
        use File::Temp qw(tempfile);

        binmode(STDIN);
        local $/ = "\0";
        my $ec = 0;

        while (defined(my $path = <STDIN>)) {

            chomp($path);
            next if $path eq "";
            next if -l $path;
            next if !-f $path;
            open my $in, "<:raw", $path or do { $ec = 1; next; };
            local $/;

            my $data = <$in>;
            close $in;
            next if !defined $data;
            next if index($data, "\0") != -1;

            my $changed = ($data =~ s/[ \t]+(?=\r?$)//mg);
            next if !$changed;
            my $dir = dirname($path);
            my ($tmpfh, $tmp) = tempfile(".wsfix.XXXXXX", DIR => $dir, UNLINK => 0) or do { $ec = 1; next; };
            binmode($tmpfh);

            print $tmpfh $data or do { close $tmpfh; unlink($tmp); $ec = 1; next; };
            close $tmpfh or do { unlink($tmp); $ec = 1; next; };
            my @st = stat($path);

            if (@st) {

                chmod($st[2] & 07777, $tmp);
                eval { chown($st[4], $st[5], $tmp); 1; };

            }

            if (rename($tmp, $path)) { next; }
            my $bak = $path . ".wsfix.bak.$$";

            if (!rename($path, $bak)) {

                unlink($tmp);
                $ec = 1;
                next;

            }
            if (!rename($tmp, $path)) {

                rename($bak, $path);
                unlink($tmp);
                $ec = 1;
                next;

            }

            unlink($bak);

        }

        exit($ec);
    '

    run git add --renormalize .
    run git restore .

}
cmd_leaks () {

    ensure gitleaks
    source <(parse "$@" -- mode format target out config baseline redact=100 fail:bool=true)

    out="${out:-/dev/stdout}"

    local exit_code="0"; (( fail )) && exit_code="1"
    local -a cmd=()

    config="${config:-"$(config_file gitleaks toml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    [[ -n "${baseline}" ]] && cmd+=( --baseline-path "${baseline}" )
    [[ -n "${redact}" ]] && cmd+=( --redact="${redact}" )

    [[ -n "${mode}" ]] || { is_ci && mode="git" || mode="dir"; }
    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"

    run gitleaks "${mode}" --no-banner --report-path "${out}" --report-format "${format:-json}" \
        --exit-code "${exit_code}" "${cmd[@]}" "${kwargs[@]}" -- "${target:-.}"

}
cmd_sbom () {

    ensure syft
    source <(parse "$@" -- src format out config)

    format="${format:-cyclonedx-json}"
    out="${out:-${OUT_DIR:-out}/sbom.json}"

    local -a cmd=()

    config="${config:-"$(config_file syft yaml yml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"
    run syft scan -o "${format}=${out}" "${cmd[@]}" "${kwargs[@]}" -- "${src:-dir:.}"

}
cmd_trivy () {

    ensure trivy
    source <(parse "$@" -- mode format target out scanners severity config no_progress:bool=true ignore_unfixed:bool=true fail:bool=true)

    out="${out:-/dev/stdout}"
    scanners="${scanners:-vuln,secret,misconfig,license}"
    severity="${severity:-CRITICAL,HIGH}"

    local exit_code="0"; (( fail )) && exit_code="1"
    local -a cmd=()

    config="${config:-"$(config_file trivy yaml yml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    [[ -n "${severity}" ]] && cmd+=( --severity "${severity}" )
    [[ -n "${scanners}" ]] && cmd+=( --scanners "${scanners}" )

    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"

    (( no_progress )) && cmd+=( --no-progress )
    (( ignore_unfixed )) && [[ "${scanners}" == *vuln* ]] && cmd+=( --ignore-unfixed )

    run trivy "${mode:-fs}" --output "${out}" --format "${format:-table}" \
        --exit-code "${exit_code}" "${cmd[@]}" "${kwargs[@]}" "${target:-.}"

}

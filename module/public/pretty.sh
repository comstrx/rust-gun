
cmd_pretty_help () {

    info_ln "Pretty :"

    printf '    %s\n' \
        "" \
        "normalize                  * Remove trailing whitespace in git-tracked files" \
        "" \
        "typo-check                 * Typos check docs and text files" \
        "typo-fix                   * Typos fix docs and text files" \
        "" \
        "taplo-check                * Validate TOML formatting (no changes)" \
        "taplo-fix                  * Auto-format TOML files" \
        "" \
        "prettier-check             * Validate formatting for Markdown/YAML/etc. (no changes)" \
        "prettier-fix               * Auto-format Markdown/YAML/etc." \
        ''

}

cmd_normalize () {

    ensure_tool git perl

    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo"
    git diff --quiet -- || die "normalize: requires clean worktree"
    git diff --cached --quiet -- || die "normalize: requires clean worktree"

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
cmd_typo_check () {

    ensure_tool typos

    local -a cmd=()

    local config="$(config_file typos toml)"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    run typos --format brief "${cmd[@]}" "$@"

}
cmd_typo_fix () {

    ensure_tool typos

    local -a cmd=()

    local config="$(config_file typos toml)"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    run typos -w "${cmd[@]}" "$@"

}

cmd_taplo_check () {

    ensure_tool taplo
    run taplo fmt --check "$@"

}
cmd_taplo_fix () {

    ensure_tool taplo
    run taplo fmt "$@"

}

cmd_prettier_check () {

    ensure_node
    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --check "**/*.{md,mdx,yml,yaml,json,jsonc}" ".prettierrc.yml" "$@"

}
cmd_prettier_fix () {

    ensure_node
    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --write "**/*.{md,mdx,yml,yaml,json,jsonc}" ".prettierrc.yml" "$@"

}

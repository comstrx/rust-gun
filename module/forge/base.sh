
forge_replace_all () {

    ensure_tool find mktemp rm perl xargs

    local root="${1:-}" map_name="${2:-}" ig="" f="" any=0 k=""

    [[ -n "${root}" && -d "${root}" ]] || die "replace: root dir not found: ${root}"
    [[ -n "${map_name}" ]] || die "replace: missing map name"

    local -n map="${map_name}"
    ((${#map[@]})) || return 0

    local -a ignore_list=( .git target node_modules dist build vendor .next .nuxt .venv venv .vscode __pycache__ )
    local -a find_cmd=( find "${root}" -type d "(" )

    local kv="$(mktemp "${TMPDIR:-/tmp}/replace.map.XXXXXX")" || die "replace: mktemp failed"
    trap 'rm -rf -- "${kv}" 2>/dev/null || true; trap - RETURN' RETURN
    : > "${kv}" || { rm -f "${kv}" 2>/dev/null || true; die "replace: cannot write tmp file"; }

    for k in "${!map[@]}"; do
        [[ "${k}" != *$'\0'* && "${map["${k}"]}" != *$'\0'* ]] || die "replace: NUL not allowed in map"
        printf '%s\0%s\0' "${k}" "${map["${k}"]}" >> "${kv}"
    done

    for ig in "${ignore_list[@]}"; do find_cmd+=( -name "${ig}" -o ); done
    find_cmd+=( -false ")" -prune -o -type f ! -lname '*' -print0 )

    while IFS= read -r -d '' f; do any=1; break; done < <("${find_cmd[@]}")
    (( any )) || { rm -f "${kv}" 2>/dev/null || true; return 0; }

    "${find_cmd[@]}" | KV_FILE="${kv}" xargs -0 perl -0777 -i -pe '
        BEGIN {
            our %map = ();
            our $re  = "";

            my $kv = $ENV{KV_FILE} // "";
            open my $fh, "<", $kv or die "kv open failed: $kv";
            local $/;
            my $buf = <$fh>;
            close $fh;

            my @p = split(/\0/, $buf, -1);
            pop @p if @p && $p[-1] eq "";
            die "kv pairs mismatch\n" if @p % 2;

            for (my $i = 0; $i < @p; $i += 2) {
                $map{$p[$i]} = $p[$i + 1];
            }

            my @keys = sort { length($b) <=> length($a) } keys %map;
            $re = @keys ? join("|", map { quotemeta($_) } @keys) : "";
        }
        if ( $re ne "" && index($_, "\0") == -1 ) {
            s/($re)/$map{$1}/g;
        }
    ' || { rm -f "${kv}" 2>/dev/null || true; die "replace failed"; }

}
forge_placeholders () {

    source <(parse "$@" -- :root :name alias user repo branch description discord_url docs_url site_url host)

    [[ -n "${repo}"   ]] || repo="${name}"
    [[ -n "${alias}"  ]] || alias="${name}"
    [[ -n "${host}"   ]] || host="https://github.com"
    [[ "${host}" == *"://"* ]] || host="https://${host}"
    [[ -n "${branch}" ]] || branch="$(git_default_branch "${root}")"

    cd -- "${root}" || die "set_placeholders: cannot cd to ${root}"

    local -A ph_map=()

    append () {

        local k="${1-}" v="${2-}"
        [[ -n "${k}" && -n "${v}" ]] || return 0

        ph_map["__${k,,}__"]="${v}"
        ph_map["__${k^^}__"]="${v}"

        ph_map["--${k,,}--"]="${v}"
        ph_map["--${k^^}--"]="${v}"

        ph_map["{{${k,,}}}"]="${v}"
        ph_map["{{${k^^}}}"]="${v}"

    }
    blob_gh_url () {

        local repo_url="${1:-}" branch="${2:-}" rel="${3:-}"
        printf '%s/blob/%s/%s' "${repo_url}" "${branch}" "${rel#/}"

    }
    tree_gh_url () {

        local repo_url="${1:-}" branch="${2:-}" rel="${3:-}"
        printf '%s/tree/%s/%s' "${repo_url}" "${branch}" "${rel#/}"

    }

    append "year"         "$(date +%Y)"
    append "name"         "${name}"
    append "alias"        "${alias}"
    append "user"         "${user}"
    append "repo"         "${repo}"
    append "branch"       "${branch}"
    append "description"  "${description}"
    append "docs_url"     "${docs_url}"
    append "site_url"     "${site_url}"
    append "discord_url"  "${discord_url}"
    append "crate_name"   "${name}"
    append "package_name" "${name}"
    append "project_name" "${name}"

    if [[ -n "${user}" && -n "${repo}" ]]; then

        local repo_url="${host}/${user}/${repo}"
        local issues_url="${repo_url}/issues"
        local new_issue_url="${repo_url}/issues/new/choose"
        local discussions_url="${repo_url}/discussions"
        local community_url="${repo_url}/graphs/community"
        local categories_url="${repo_url}/discussions/categories"
        local announcements_url="${repo_url}/discussions/categories/announcements"
        local general_url="${repo_url}/discussions/categories/general"
        local ideas_url="${repo_url}/discussions/categories/ideas"
        local polls_url="${repo_url}/discussions/categories/polls"
        local qa_url="${repo_url}/discussions/categories/q-a"
        local show_and_tell_url="${repo_url}/discussions/categories/show-and-tell"

        append "repo_url"             "${repo_url}"
        append "issues_url"           "${issues_url}"
        append "new_issue_url"        "${new_issue_url}"
        append "discussions_url"      "${discussions_url}"
        append "community_url"        "${community_url}"
        append "categories_url"       "${categories_url}"
        append "announcements_url"    "${announcements_url}"
        append "general_url"          "${general_url}"
        append "ideas_url"            "${ideas_url}"
        append "polls_url"            "${polls_url}"
        append "qa_url"               "${qa_url}"
        append "show_and_tell_url"    "${show_and_tell_url}"
        append "bug_report_url"       "${new_issue_url}"
        append "feature_request_url"  "${new_issue_url}"

        [[ -f "${root}/SECURITY.md"          ]] && append "security_url"             "$(blob_gh_url "${repo_url}" "${branch}" "SECURITY.md")"
        [[ -f "${root}/SUPPORT.md"           ]] && append "support_url"              "$(blob_gh_url "${repo_url}" "${branch}" "SUPPORT.md")"
        [[ -f "${root}/CONTRIBUTING.md"      ]] && append "contributing_url"         "$(blob_gh_url "${repo_url}" "${branch}" "CONTRIBUTING.md")"
        [[ -f "${root}/CODE_OF_CONDUCT.md"   ]] && append "code_of_conduct_url"      "$(blob_gh_url "${repo_url}" "${branch}" "CODE_OF_CONDUCT.md")"
        [[ -f "${root}/README.md"            ]] && append "readme_url"               "$(blob_gh_url "${repo_url}" "${branch}" "README.md")"
        [[ -f "${root}/CHANGELOG.md"         ]] && append "changelog_url"            "$(blob_gh_url "${repo_url}" "${branch}" "CHANGELOG.md")"

        [[ -z "${ph_map["__security_url__"]:-}"          ]] && append "security_url"              "${repo_url}/security"
        [[ -z "${ph_map["__support_url__"]:-}"           ]] && append "support_url"               "${discussions_url}"
        [[ -z "${ph_map["__contributing_url__"]:-}"      ]] && append "contributing_url"          "${repo_url}"
        [[ -z "${ph_map["__code_of_conduct_url__"]:-}"   ]] && append "code_of_conduct_url"       "${repo_url}"
        [[ -d "${root}/.github/ISSUE_TEMPLATE"           ]] && append "issue_templates_url"       "$(tree_gh_url "${repo_url}" "${branch}" ".github/ISSUE_TEMPLATE")"
        [[ -f "${root}/.github/PULL_REQUEST_TEMPLATE.md" ]] && append "pull_request_template_url" "$(blob_gh_url "${repo_url}" "${branch}" ".github/PULL_REQUEST_TEMPLATE.md")"

    fi

    forge_replace_all  "${root}" ph_map

}
forge_init_git () {

    source <(parse "$@" -- :root :name repo branch)

    cd -- "${root}" || die "set_git: cannot cd to ${root}"
    cmd_init "${repo:-${name}}" "${kwargs[@]}"

}

forge_resolve_name () {

    local name="${1:-}"

    name="${name%%[[:space:]]*}"
    name="${name##*/}"
    name="${name//_/-}"
    name="${name,,}"

    name="${name//-app/-pure}"
    name="${name//-project/-pure}"
    name="${name//-framework/-web}"
    name="${name//-package/-lib}"
    name="${name//-crate/-lib}"
    name="${name//-workspace/-ws}"
    name="${name//-monorepo/-ws}"

    printf '%s\n' "${name}"

}
forge_display_name () {

    local name="${1:-}"
    local first="${name%%-*}"

    [[ "${name}" == *-pure ]] || { printf '%s\n' "${name}"; return 0; }
    printf '%s\n' "${first}"

}
forge_resolve_dest () {

    local dir="${1:-}" name="${2:-}"

    dir="${dir:-${WORKSPACE_DIR:-}}"
    dir="${dir/#\~/${HOME}}"
    dir="${dir%/}"

    ensure_dir "${dir}"
    dir="${dir}/${name}"

    printf '%s\n' "${dir}"

}
forge_resolve_path () {

    local root="${1:-}" name="${2:-}" base="" try=""

    for base in "pure" "web" "lib" "ws"; do

        try="${base}/${name}"
        [[ -d "${root}/${try}" ]] && { printf '%s\n' "${root}/${try}" ; return 0 ; }
        [[ "${name}" == *-"${base}" ]] || continue

        try="${base}/${name%-${base}}"
        [[ -d "${root}/${try}" ]] && { printf '%s\n' "${root}/${try}" ; return 0 ; }

    done

    printf '%s\n' ""
    return 1

}

forge_template_dir () {

    ensure_tool awk tail tar mkdir rm dirname

    [[ -d "${TEMPLATE_DIR:-}" ]] && { printf '%s\n' "${TEMPLATE_DIR}"; return 0; }

    local src="${0}"
    [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]] && src="${BASH_SOURCE[0]}"
    [[ -f "${src}" ]] || die "Source bundle not found: ${src}"

    local key="${TEMPLATE_PAYLOAD_KEY:-}"
    local line="$(awk -v key="${key}" '$0 == key { print NR + 1; exit }' "${src}" 2>/dev/null || true)"
    [[ -n "${line}" ]] || die "Template payload marker not found"

    local tmp="$(tmp_dir "template-installer")"
    local out="${tmp}/template"

    ensure_dir "${out}"

    tail -n +"${line}" -- "${src}" | tar -xzf - -C "${out}" --strip-components=1 || {
        rm -rf -- "${tmp}" >/dev/null 2>&1 || true
        die "Failed to extract template payload"
    }

    local dir="$(cd -- "${out}" 2>/dev/null && pwd -P)" || {
        rm -rf -- "${tmp}" >/dev/null 2>&1 || true
        die "Failed to resolve template dir"
    }
    [[ -d "${dir}" ]] || {
        rm -rf -- "${tmp}" >/dev/null 2>&1 || true
        die "Extracted template dir not found"
    }

    printf '%s' "${dir}"

}
forge_copy_template () {

    ensure_tool mkdir find tar grep

    local src="${1:-}" dest="${2:-}"
    local -a tar_out=()

    [[ -e "${src}" ]] || die "cannot resolve template src: ${src}"
    [[ -e "${dest}" ]] && die "dest path already exists: ${dest}"

    mkdir -p -- "${dest}" 2>/dev/null || die "cannot create dir: ${dest}"
    [[ -n "$(find "${dest}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]] && die "dest dir not empty: ${dest}"

    tar_out=( tar -C "${dest}" -xf - )
    ( tar --help 2>/dev/null || true ) | grep -q -- '--no-same-owner' && tar_out=( tar --no-same-owner -C "${dest}" -xf - )

    tar -C "${src}" -cf - . | "${tar_out[@]}" || die "copy failed: ${src} -> ${dest}"

}

forge_copy_global_config () {

    local src_dir="${1:-}" dest_dir="${2:-}" path="" base="" out=""
    [[ -d "${src_dir}" ]] || return 0

    for path in "${src_dir}"/* "${src_dir}"/.[!.]* "${src_dir}"/..?*; do

        [[ -e "${path}" ]] || continue

        base="${path##*/}"
        out="${dest_dir}/${base}"

        if [[ -f "${path}" ]]; then

            [[ -e "${out}" ]] && continue

            mkdir -p -- "${out%/*}" || die "Failed mkdir ${out}" 2
            cp -f -- "${path}" "${out}" || die "Failed copying ${path}" 2

        elif [[ -d "${path}" ]]; then

            [[ "${base}" == .* ]] || continue
            [[ -e "${out}" ]] && continue

            mkdir -p -- "${out}" || die "Failed mkdir ${out}" 2
            cp -R -- "${path}/." "${out}" || die "Failed copying dir ${path}" 2

        fi

    done

}
forge_copy_custom_config () {

    local src_dir="${1:-}" dest_dir="${2:-}" rel="" out="" f=""
    [[ -d "${src_dir}" ]] || return 0

    while IFS= read -r -d '' f; do

        rel="${f#${src_dir}/}"
        out="${dest_dir}/${rel}"
        [[ -e "${out}" ]] && continue

        mkdir -p -- "${out%/*}" || die "Failed mkdir ${out}" 2
        cp -p -- "${f}" "${out}" || die "Failed copying ${f}" 2

    done < <(find "${src_dir}" -type f -print0)

}
forge_copy_config () {

    source <(parse "$@" -- \
        :name :config_dir :dest_dir \
        env:bool=true docs:bool=true license:bool=true pretty:bool=true safety:bool=true \
        format:bool=true lint:bool=true audit:bool=true coverage:bool=true github:bool=true docker:bool=false \
    )

    [[ -e "${config_dir}" ]] || die "cannot resolve config src: ${config_dir}"

    local path="" base="" cfg=""
    local -a configs=()

    for path in "${config_dir}"/* "${config_dir}"/.[!.]* "${config_dir}"/..?*; do

        base="${path##*/}"

        [[ -d "${path}" ]] || continue
        [[ "${base}" == "." || "${base}" == ".." ]] && continue

        configs+=( "${base}" )

    done
    for cfg in "${configs[@]}"; do

        declare -n _flag="${cfg}" 2>/dev/null && (( ! _flag )) && continue

        forge_copy_custom_config "${config_dir}/${cfg}/${name%%-*}" "${dest_dir}"
        forge_copy_global_config "${config_dir}/${cfg}" "${dest_dir}"

    done

}


replace_all () {

    ensure_pkg find mktemp rm perl xargs

    local root="${1:-}" map_name="${2:-}" ig="" f="" any=0 kv="" k=""

    [[ -n "${root}" && -d "${root}" ]] || die "replace: root dir not found: ${root}"
    [[ -n "${map_name}" ]] || die "replace: missing map name"

    local -n map="${map_name}"
    ((${#map[@]})) || return 0

    local -a ignore_list=( .git target node_modules dist build vendor .next .nuxt .venv venv .vscode __pycache__ )
    local -a find_cmd=( find "${root}" -type d "(" )

    kv="$(mktemp "${TMPDIR:-/tmp}/replace.map.XXXXXX")" || die "replace: mktemp failed"
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
default_branch () {

    ensure_pkg git
    local root="${1:-}" b=""

    if has git && [[ -e "${root}/.git" ]]; then

        b="$(cd -- "${root}" && git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
        b="${b#origin/}"

        [[ -n "${b}" ]] || b="$(cd -- "${root}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        [[ "${b}" == "HEAD" ]] && b=""

    fi

    [[ -n "${b}" ]] || b="main"
    printf '%s' "${b}"

}

set_placeholders () {

    source <(parse "$@" -- :root name alias user repo branch description discord_url docs_url site_url host)
    cd -- "${root}"

    [[ -n "${branch}" ]] || branch="$(default_branch "${root}")"
    [[ -n "${host}" ]] || host="https://github.com"
    [[ "${host}" == *"://"* ]] || host="https://${host}"

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

    append "year" "$(date +%Y)"
    append "alias" "${alias}"
    append "branch" "${branch}"
    append "user" "${user}"
    append "repo" "${repo}"
    append "name" "${name}"
    append "description" "${description}"
    append "docs_url" "${docs_url}"
    append "site_url" "${site_url}"
    append "discord_url" "${discord_url}"

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

        append "repo_url" "${repo_url}"
        append "issues_url" "${issues_url}"
        append "new_issue_url" "${new_issue_url}"
        append "discussions_url" "${discussions_url}"
        append "community_url" "${community_url}"
        append "categories_url" "${categories_url}"
        append "announcements_url" "${announcements_url}"
        append "general_url" "${general_url}"
        append "ideas_url" "${ideas_url}"
        append "polls_url" "${polls_url}"
        append "qa_url" "${qa_url}"
        append "show_and_tell_url" "${show_and_tell_url}"
        append "bug_report_url" "${new_issue_url}"
        append "feature_request_url" "${new_issue_url}"

        if [[ -f "${root}/SECURITY.md" ]]; then append "security_url" "$(blob_gh_url "${repo_url}" "${branch}" "SECURITY.md")"
        else append "security_url" "${repo_url}/security"
        fi

        if [[ -f "${root}/.github/SUPPORT.md" ]]; then append "support_url" "$(blob_gh_url "${repo_url}" "${branch}" ".github/SUPPORT.md")"
        elif [[ -f "${root}/SUPPORT.md" ]]; then append "support_url" "$(blob_gh_url "${repo_url}" "${branch}" "SUPPORT.md")"
        else append "support_url" "${discussions_url}"
        fi

        if [[ -f "${root}/CONTRIBUTING.md" ]]; then append "contributing_url" "$(blob_gh_url "${repo_url}" "${branch}" "CONTRIBUTING.md")"
        elif [[ -f "${root}/.github/CONTRIBUTING.md" ]]; then append "contributing_url" "$(blob_gh_url "${repo_url}" "${branch}" ".github/CONTRIBUTING.md")"
        fi

        if [[ -f "${root}/CODE_OF_CONDUCT.md" ]]; then append "code_of_conduct_url" "$(blob_gh_url "${repo_url}" "${branch}" "CODE_OF_CONDUCT.md")"
        elif [[ -f "${root}/.github/CODE_OF_CONDUCT.md" ]]; then append "code_of_conduct_url" "$(blob_gh_url "${repo_url}" "${branch}" ".github/CODE_OF_CONDUCT.md")"
        fi

        [[ -f "${root}/README.md" ]] && append "readme_url" "$(blob_gh_url "${repo_url}" "${branch}" "README.md")"
        [[ -f "${root}/CHANGELOG.md" ]] && append "changelog_url" "$(blob_gh_url "${repo_url}" "${branch}" "CHANGELOG.md")"
        [[ -f "${root}/.github/PULL_REQUEST_TEMPLATE.md" ]] && append "pull_request_template_url" "$(blob_gh_url "${repo_url}" "${branch}" ".github/PULL_REQUEST_TEMPLATE.md")"
        [[ -d "${root}/.github/ISSUE_TEMPLATE" ]] && append "issue_templates_url" "$(tree_gh_url "${repo_url}" "${branch}" ".github/ISSUE_TEMPLATE")"

    fi

    replace_all "${root}" ph_map

}
set_git () {

    source <(parse "$@" -- root name repo branch)
    cd -- "${root}"

    cmd_init "${repo:-${name}}" "${kwargs[@]}"

}

copy_template () {

    ensure_pkg mkdir find tar grep

    local src="${1:-}" dest="${2:-}"
    local -a tar_out=()

    mkdir -p -- "${dest}" 2>/dev/null || die "cannot create dir: ${dest}"
    [[ -n "$(find "${dest}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]] && die "dest dir not empty: ${dest}"

    tar_out=( tar -C "${dest}" -xf - )
    ( tar --help 2>/dev/null || true ) | grep -q -- '--no-same-owner' && tar_out=( tar --no-same-owner -C "${dest}" -xf - )

    tar -C "${src}" -cf - . | "${tar_out[@]}" || die "copy failed: ${src} -> ${dest}"

}
copy_config () {

    local src_dir="${1:-}" dest_dir="${2:-}" cfg="${3:-}" rel="" out="" f=""
    [[ -d "${src_dir}" ]] || return 0

    while IFS= read -r -d '' f; do

        rel="${f#${src_dir}/}"
        out="${dest_dir}/${rel}"

        (( ! github )) && [[ "${cfg}" == "infra" && "${rel}" == *github* ]] && continue
        (( ! gitlab )) && [[ "${cfg}" == "infra" && "${rel}" == *gitlab* ]] && continue
        (( ! docker )) && [[ "${cfg}" == "infra" && "${rel}" == *docker* ]] && continue
        (( ! k8s ))    && [[ "${cfg}" == "infra" && "${rel}" == k8s/* ]]    && continue

        [[ -e "${out}" ]] && continue
        mkdir -p "${out%/*}" && cp -p "${f}" "${out}"

    done < <(find "${src_dir}" -type f -print0)

}

resolve_name () {

    local name="${1:-}"

    name="${name%%[[:space:]]*}"
    name="${name##*/}"
    name="${name//_/-}"
    name="${name,,}"

    name="${name%js}"
    name="${name//c++/cpp}"
    name="${name//c#/csharp}"
    name="${name//dotnet/csharp}"
    name="${name//workspace/ws}"
    name="${name//monorepo/ws}"
    name="${name//crate/lib}"
    name="${name//golang/go}"

    [[ "${name}" == "py" ]] && name="python"
    [[ "${name}" == py-* ]] && name="python-${name#py-}"

    printf '%s\n' "${name}"

}
resolve_path () {

    local pure="pure" lib="lib" ws="mono" web="web" base="" try=""
    local root="${1:-}" name="$(resolve_name "${2:-}")"

    if [[ "${name}" == *-pure ]]; then
        try="${pure}/${name%-pure}"
        [[ -d "${root}/${try}" ]] && { printf '%s\n' "${root}/${try}" ; return 0 ; }
    fi
    if [[ "${name}" == *-lib ]]; then
        try="${lib}/${name%-lib}"
        [[ -d "${root}/${try}" ]] && { printf '%s\n' "${root}/${try}" ; return 0 ; }
    fi
    if [[ "${name}" == *-ws ]]; then
        try="${ws}/${name%-ws}"
        [[ -d "${root}/${try}" ]] && { printf '%s\n' "${root}/${try}" ; return 0 ; }
    fi
    if [[ "${name}" == *-web ]]; then
        try="${web}/${name%-web}"
        [[ -d "${root}/${try}" ]] && { printf '%s\n' "${root}/${try}" ; return 0 ; }
    fi

    for base in "${pure}" "${web}" "${lib}" "${ws}"; do
        try="${base}/${name}"
        [[ -d "${root}/${try}" ]] && { printf '%s\n' "${root}/${try}" ; return 0 ; }
    done

    printf '%s\n' ""
    return 1

}
resolve_config () {

    source <(parse "$@" -- \
        :name :config_dir :dest_dir \
        env:bool=true docs:bool=true license:bool=true quality:bool=true security:bool=true \
        fmt:bool=true lint:bool=true audit:bool=true coverage:bool=true semver:bool=true \
        infra:bool=true github:bool=true gitlab:bool=false docker:bool=false k8s:bool=false \
    )

    local -a configs=( env docs license infra quality security coverage semver fmt lint audit )

    name="$(resolve_name "${name}")"
    name="${name%%-*}"

    for cfg in "${configs[@]}"; do

        declare -n _flag="${cfg}" 2>/dev/null && (( ! _flag )) && continue

        copy_config "${config_dir}/${cfg}/${name}" "${dest_dir}" "${cfg}"
        copy_config "${config_dir}/${cfg}/_global" "${dest_dir}" "${cfg}"

    done

}

cmd_new () {

    source <(parse "$@" -- :template name dir placeholders:bool=true git:bool=true)

    local root="${ROOT_DIR:-}/template"
    local cdir="${root}/config"

    local src="$(resolve_path "${root}" "${template}")"
    [[ -d "${src}" ]] || die "template not found: ${src}"

    dir="${dir:-${PROJECTS_DIR:-${WORKSPACE_DIR:-${PWD}}}}"
    dir="${dir/#\~/${HOME}}"
    dir="${dir%/}"

    name="${name:-${template##*/}}"
    [[ "${dir##*/}" == "${name}" ]] || dir+="/${name}"

    copy_template "${src}" "${dir}"
    resolve_config "${name}" "${cdir}" "${dir}" "${kwargs[@]}"

    (( placeholders )) && set_placeholders "${dir}" "${name}" "${kwargs[@]}"

    (( git )) && set_git "${dir}" "${name}" "${kwargs[@]}"

    success "OK: ${name} was successfully set up at ${dir}"

}

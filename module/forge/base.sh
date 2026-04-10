
replace_all () {

    ensure_pkg find mktemp rm perl xargs

    local root="${1:-}" map_name="${2:-}" ig="" f="" any=0 kv="" k=""

    [[ -n "${root}" && -d "${root}" ]] || die "replace_all: root dir not found: ${root}"
    [[ -n "${map_name}" ]] || die "replace_all: missing map name"

    local -n map="${map_name}"
    ((${#map[@]})) || return 0

    local -a ignore_list=( .git target .idea .vscode node_modules dist build vendor .next .nuxt .venv venv __pycache__ )
    local -a find_cmd=( find "${root}" -type d "(" )

    kv="$(mktemp "${TMPDIR:-/tmp}/gun.replace.XXXXXX")" || die "replace_all: mktemp failed"
    trap 'rm -f -- "${kv}" 2>/dev/null || true; trap - RETURN' RETURN

    : > "${kv}" || die "replace_all: cannot write tmp file: ${kv}"

    for k in "${!map[@]}"; do
        [[ "${k}" != *$'\0'* ]] || die "replace_all: key contains NUL"
        [[ "${map["${k}"]}" != *$'\0'* ]] || die "replace_all: value contains NUL"
        printf '%s\0%s\0' "${k}" "${map["${k}"]}" >> "${kv}"
    done

    for ig in "${ignore_list[@]}"; do
        find_cmd+=( -name "${ig}" -o )
    done

    find_cmd+=( -false ")" -prune -o -type f ! -lname '*' -print0 )

    while IFS= read -r -d '' f; do
        any=1
        break
    done < <("${find_cmd[@]}")

    (( any )) || return 0

    "${find_cmd[@]}" | KV_FILE="${kv}" xargs -0 perl -0777 -i -pe '
        BEGIN {
            our %map = ();
            our $re  = "";

            my $kv = $ENV{KV_FILE} // "";
            open my $fh, "<", $kv or die "replace_all: cannot open kv file: $kv\n";
            local $/;
            my $buf = <$fh>;
            close $fh;

            my @pairs = split(/\0/, $buf, -1);
            pop @pairs if @pairs && $pairs[-1] eq "";
            die "replace_all: kv mismatch\n" if @pairs % 2;

            for ( my $i = 0; $i < @pairs; $i += 2 ) {
                $map{$pairs[$i]} = $pairs[$i + 1];
            }

            my @keys = sort { length($b) <=> length($a) } keys %map;
            $re = @keys ? join("|", map { quotemeta($_) } @keys) : "";
        }

        if ( $re ne "" && index($_, "\0") == -1 ) {
            s/($re)/$map{$1}/g;
        }
    ' || die "replace_all: replacement failed"

}
rename_paths () {

    ensure_pkg find mv

    local root="${1:-}" map_name="${2:-}" old="" new="" path="" rel="" out="" changed=1
    [[ -n "${root}" && -d "${root}" ]] || die "rename_paths: root dir not found: ${root}"
    [[ -n "${map_name}" ]] || die "rename_paths: missing map name"

    local -n map="${map_name}"
    ((${#map[@]})) || return 0

    while (( changed )); do

        changed=0

        while IFS= read -r -d '' path; do

            rel="${path#${root}/}"
            [[ "${rel}" != "${path}" ]] || continue

            out="${rel}"

            for old in "${!map[@]}"; do
                new="${map["${old}"]}"
                [[ -n "${old}" ]] || continue
                out="${out//${old}/${new}}"
            done

            [[ "${out}" == "${rel}" ]] && continue

            mkdir -p -- "${root}/${out%/*}" || die "rename_paths: mkdir failed: ${root}/${out%/*}"

            [[ -e "${root}/${out}" ]] && die "rename_paths: target already exists: ${root}/${out}"
            mv -- "${path}" "${root}/${out}" || die "rename_paths: move failed: ${path} -> ${root}/${out}"

            changed=1

        done < <(find "${root}" -depth -mindepth 1 -print0)

    done

}
default_branch () {

    ensure_pkg git

    local root="${1:-}" b=""
    [[ -n "${root}" ]] || root="${PWD}"

    if has git && [[ -e "${root}/.git" ]]; then

        b="$(cd -- "${root}" && git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
        b="${b#origin/}"

        [[ -n "${b}" ]] || b="$(cd -- "${root}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        [[ "${b}" == "HEAD" ]] && b=""

    fi

    [[ -n "${b}" ]] || b="main"
    printf '%s\n' "${b}"

}
set_placeholders () {

    source <(parse "$@" -- :root name alias user repo branch description discord_url docs_url site_url host)

    [[ -n "${root}" && -d "${root}" ]] || die "set_placeholders: invalid root: ${root}"
    cd -- "${root}" || die "set_placeholders: cannot cd to ${root}"

    [[ -n "${name}" ]] || die "set_placeholders: missing name"

    [[ -n "${repo}"   ]] || repo="${name}"
    [[ -n "${alias}"  ]] || alias="${name}"
    [[ -n "${branch}" ]] || branch="$(default_branch "${root}")"
    [[ -n "${host}"   ]] || host="https://github.com"
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

    rename_paths "${root}" ph_map
    replace_all  "${root}" ph_map

}
set_git () {

    source <(parse "$@" -- :root name repo branch)

    [[ -n "${root}" && -d "${root}" ]] || die "set_git: invalid root: ${root}"
    cd -- "${root}" || die "set_git: cannot cd to ${root}"

    cmd_init "${repo:-${name}}" "${kwargs[@]}"

}

copy_template () {

    ensure_pkg mkdir find tar grep

    local src="${1:-}" dest="${2:-}"
    local -a tar_out=()

    [[ -n "${src}"  && -d "${src}"  ]] || die "copy_template: source dir not found: ${src}"
    [[ -n "${dest}" ]] || die "copy_template: missing dest"

    mkdir -p -- "${dest}" || die "copy_template: cannot create dir: ${dest}"

    [[ -n "$(find "${dest}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]] && die "copy_template: dest dir not empty: ${dest}"

    tar_out=( tar -C "${dest}" -xf - )
    ( tar --help 2>/dev/null || true ) | grep -q -- '--no-same-owner' && tar_out=( tar --no-same-owner -C "${dest}" -xf - )

    tar -C "${src}" -cf - . | "${tar_out[@]}" || die "copy_template: copy failed: ${src} -> ${dest}"

}
config_target_dir () {

    local group="${1:-}"

    case "${group}" in
        env|docs|license|format|lint|prettier|audit|coverage|safety) printf '%s\n' "" ;;
        github)                                                      printf '%s\n' ".github" ;;
        *)                                                           printf '%s\n' "" ;;
    esac

}
copy_config_group () {

    ensure_pkg mkdir find cp

    local src_dir="${1:-}" dest_dir="${2:-}" group="${3:-}" sub="" f="" rel="" out="" target=""
    [[ -d "${src_dir}" ]] || return 0
    [[ -n "${dest_dir}" ]] || die "copy_config_group: missing dest dir"

    sub="$(config_target_dir "${group}")"
    target="${dest_dir}"
    [[ -n "${sub}" ]] && target="${dest_dir}/${sub}"

    while IFS= read -r -d '' f; do

        rel="${f#${src_dir}/}"
        out="${target}/${rel}"

        [[ -e "${out}" ]] && continue

        mkdir -p -- "${out%/*}" || die "copy_config_group: mkdir failed: ${out%/*}"
        cp -p -- "${f}" "${out}" || die "copy_config_group: copy failed: ${f} -> ${out}"

    done < <(find "${src_dir}" -type f -print0)

}

normalize_name () {

    local name="${1:-}"

    [[ -n "${name}" ]] || die "normalize_name: missing name"

    name="${name##*/}"
    name="${name// /-}"
    name="${name//_/-}"
    name="${name,,}"

    printf '%s\n' "${name}"

}
resolve_name () {

    local name="${1:-}"

    name="${name%%[[:space:]]*}"
    name="${name##*/}"
    name="${name//_/-}"
    name="${name,,}"

    name="${name//workspace/ws}"
    name="${name//monorepo/ws}"
    name="${name//workspaces/ws}"
    name="${name//crate/lib}"
    name="${name//library/lib}"
    name="${name//binary/empty}"
    name="${name//bin/empty}"

    [[ "${name}" == "app"        ]] && name="empty"
    [[ "${name}" == "exe"        ]] && name="empty"
    [[ "${name}" == "cli"        ]] && name="empty"
    [[ "${name}" == "basic"      ]] && name="empty"
    [[ "${name}" == "minimal"    ]] && name="empty"
    [[ "${name}" == "workspace"  ]] && name="workspace"

    printf '%s\n' "${name}"

}
resolve_path () {

    local root="${1:-}" raw="${2:-}" name=""
    [[ -n "${root}" && -d "${root}" ]] || die "resolve_path: invalid root: ${root}"

    name="$(resolve_name "${raw}")"

    [[ -d "${root}/${name}" ]] && {
        printf '%s\n' "${root}/${name}"
        return 0
    }

    case "${name}" in
        empty|bin|app|exe|cli|minimal|basic)
            [[ -d "${root}/empty" ]] && { printf '%s\n' "${root}/empty" ; return 0 ; }
            ;;
        lib|crate|library)
            [[ -d "${root}/lib" ]] && { printf '%s\n' "${root}/lib" ; return 0 ; }
            ;;
        ws|workspace|monorepo|workspaces)
            [[ -d "${root}/workspace" ]] && { printf '%s\n' "${root}/workspace" ; return 0 ; }
            ;;
    esac

    return 1

}
resolve_config () {

    source <(parse "$@" -- \
        :config_dir :dest_dir \
        env:bool=true docs:bool=true license:bool=true github:bool=true \
        format:bool=true lint:bool=true prettier:bool=true \
        audit:bool=true coverage:bool=true safety:bool=true \
    )

    [[ -n "${config_dir}" && -d "${config_dir}" ]] || return 0
    [[ -n "${dest_dir}"   && -d "${dest_dir}"   ]] || die "resolve_config: invalid dest dir: ${dest_dir}"

    local group=""
    local -a groups=( env docs license github format lint prettier audit coverage safety )

    for group in "${groups[@]}"; do

        declare -n _flag="${group}" || continue
        (( _flag )) || continue

        copy_config_group "${config_dir}/${group}" "${dest_dir}" "${group}"

    done

}


run_git () {

    ensure_pkg git

    local kind="${1:-ssh}" ssh_cmd="${2:-}"
    shift 2 || true

    if [[ "${kind}" == http* ]]; then
        local old="${VERBOSE:-0}"
        VERBOSE=0
        GIT_TERMINAL_PROMPT=0 run git "$@"
        VERBOSE="${old}"
        return $?
    fi
    if [[ -n "${ssh_cmd}" ]]; then
        GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${ssh_cmd}" run git "$@"
        return $?
    fi

    GIT_TERMINAL_PROMPT=0 run git "$@"

}
git_repo_guard () {

    ensure_pkg git
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository."

}
git_repo_root () {

    ensure_pkg git
    git rev-parse --show-toplevel 2>/dev/null || pwd -P

}
git_has_switch () {

    git switch -h >/dev/null 2>&1

}
git_switch () {

    if git_has_switch; then

        git switch "$@"
        return $?

    fi
    if [[ "${1:-}" == "-c" ]]; then

        shift || true
        local b="${1:-}"
        shift || true

        if [[ "${1:-}" == "--track" ]]; then

            shift || true
            local upstream="${1:-}"
            shift || true

            git checkout -b "${b}" --track "${upstream}" "$@"
            return $?

        fi

        git checkout -b "${b}" "$@"
        return $?

    fi

    git checkout "$@"

}
git_has_commit () {

    git rev-parse --verify HEAD >/dev/null 2>&1

}
git_require_remote () {

    local remote="${1:-origin}"
    git remote get-url "${remote}" >/dev/null 2>&1 || die "Remote not found: ${remote}. Run: init <user/repo>"

}
git_require_identity () {

    local n="$(git config user.name  2>/dev/null || true)"
    local e="$(git config user.email 2>/dev/null || true)"

    [[ -n "${n}" && -n "${e}" ]] && return 0
    die "Missing git identity. Set: git config user.name \"Your Name\" && git config user.email \"you@example.com\""

}

git_is_semver () {

    local v="${1:-}" main="" rest="" pre="" build=""
    [[ -n "${v}" ]] || return 1

    if [[ "${v}" == *+* ]]; then
        main="${v%%+*}"
        build="${v#*+}"
    else
        main="${v}"
        build=""
    fi
    if [[ "${main}" == *-* ]]; then
        rest="${main%%-*}"
        pre="${main#*-}"
    else
        rest="${main}"
        pre=""
    fi
    if [[ "${rest}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        :
    else
        return 1
    fi

    if [[ -n "${pre}" ]]; then

        local -a ids=()
        IFS='.' read -r -a ids <<< "${pre}"
        ((${#ids[@]})) || return 1

        local id=""
        for id in "${ids[@]}"; do

            [[ -n "${id}" ]] || return 1
            [[ "${id}" =~ ^[0-9A-Za-z-]+$ ]] || return 1

            if [[ "${id}" =~ ^[0-9]+$ ]]; then
                [[ "${id}" == "0" || "${id}" =~ ^[1-9][0-9]*$ ]] || return 1
            fi

        done

    fi
    if [[ -n "${build}" ]]; then

        local -a ids=()
        IFS='.' read -r -a ids <<< "${build}"
        ((${#ids[@]})) || return 1

        local id=""
        for id in "${ids[@]}"; do
            [[ -n "${id}" ]] || return 1
            [[ "${id}" =~ ^[0-9A-Za-z-]+$ ]] || return 1
        done

    fi

    return 0

}
git_norm_tag () {

    local t="${1:-}"
    local core="${t}"
    [[ -n "${t}" ]] || { printf '%s\n' ""; return 0; }

    if [[ "${t}" == v* ]]; then

        core="${t#v}"
        git_is_semver "${core}" && { printf 'v%s\n' "${core}"; return 0; }
        printf '%s\n' "${t}"
        return 0

    fi

    git_is_semver "${t}" && { printf 'v%s\n' "${t}"; return 0; }
    printf '%s\n' "${t}"

}
git_redact_url () {

    local url="${1:-}" proto="" rest=""
    [[ -n "${url}" ]] || { printf ''; return 0; }

    if [[ "${url}" == http://* || "${url}" == https://* ]]; then

        proto="${url%%://*}://"
        rest="${url#*://}"

        if [[ "${rest}" == *@* ]]; then
            printf '%s***@%s\n' "${proto}" "${rest#*@}"
            return 0
        fi

    fi

    printf '%s\n' "${url}"

}
git_remote_url () {

    local remote="${1:-origin}"
    git remote get-url "${remote}" 2>/dev/null || true

}
git_remote_has_tag () {

    local kind="${1:-ssh}" ssh_cmd="${2:-}" target="${3:-origin}" tag="${4:-}"
    [[ -n "${tag}" ]] || return 1
    run_git "${kind}" "${ssh_cmd}" ls-remote --exit-code --tags --refs "${target}" "refs/tags/${tag}" >/dev/null 2>&1

}
git_remote_has_branch () {

    local kind="${1:-ssh}" ssh_cmd="${2:-}" target="${3:-origin}" b="${4:-}"
    [[ -n "${b}" ]] || return 1
    run_git "${kind}" "${ssh_cmd}" ls-remote --exit-code --heads "${target}" "${b}" >/dev/null 2>&1

}
git_parse_remote () {

    local url="${1:-}" rest="" left="" host="" path=""
    [[ -n "${url}" ]] || return 1

    if [[ "${url}" != *"://"* && "${url}" == *:* ]]; then

        left="${url%%:*}"
        path="${url#*:}"
        host="${left#*@}"
        host="${host%%:*}"
        [[ -n "${host}" && -n "${path}" && "${path}" == */* ]] || return 1

        printf '%s %s\n' "${host}" "${path}"
        return 0

    fi
    if [[ "${url}" == ssh://* || "${url}" == git+ssh://* ]]; then

        rest="${url#*://}"
        [[ "${rest}" == */* ]] || return 1

        left="${rest%%/*}"
        path="${rest#*/}"
        host="${left#*@}"
        host="${host%%:*}"

        printf '%s %s\n' "${host}" "${path}"
        return 0

    fi
    if [[ "${url}" == http://* || "${url}" == https://* ]]; then

        rest="${url#*://}"
        [[ "${rest}" == *@* ]] && rest="${rest#*@}"
        [[ "${rest}" == */* ]] || return 1

        host="${rest%%/*}"
        path="${rest#*/}"

        printf '%s %s\n' "${host}" "${path}"
        return 0

    fi

    return 1

}
git_build_https_token_url () {

    local token="${1:-}" host="${2:-}" path="${3:-}"
    [[ -n "${token}" && -n "${host}" && -n "${path}" ]] || return 1
    printf 'https://%s:%s@%s/%s\n' "${GIT_HTTP_USER:-x-access-token}" "${token}" "${host}" "${path}"

}
git_upstream_exists_for () {

    local b="${1:-}"
    [[ -n "${b}" ]] || return 1
    git rev-parse --abbrev-ref --symbolic-full-name "${b}@{u}" >/dev/null 2>&1

}

git_keymap_set () {

    ensure_pkg mkdir mktemp mv awk chmod
    source <(parse "$@" -- :key repo)

    local file="${HOME}/.ssh/git-keymap.tsv"
    local dir="$(dirname -- "${file}")"

    local repo_root="${repo:-"$(git_repo_root)"}"
    repo_root="$(cd -- "${repo_root}" 2>/dev/null && pwd -P || printf '%s' "${repo_root}")"

    [[ -n "${repo_root}" ]] || die "keymap: cannot detect repo root"
    [[ -z "${key}" || "${key}" == *$'\t'* || "${key}" == *$'\n'* || "${key}" == *$'\r'* ]] && die "keymap: invalid key"

    local tmp="$(mktemp "${TMPDIR:-/tmp}/vx.keymap.XXXXXX")" || die "mktemp failed"
    run mkdir -p -- "${dir}"
    chmod 700 "${dir}" 2>/dev/null || true
    [[ -f "${file}" ]] || : > "${file}" || die "keymap: create failed: ${file}"

    awk -F $'\t' -v p="${repo_root}" '$1 != p' "${file}" > "${tmp}"
    printf '%s\t%s\n' "${repo_root}" "${key}" >> "${tmp}"

    run mv -f -- "${tmp}" "${file}"
    chmod 600 "${file}" 2>/dev/null || true

    printf '%s\n' "${file}"

}
git_keymap_get () {

    source <(parse "$@" -- repo)

    local file="${HOME}/.ssh/git-keymap.tsv"
    local repo_root="${repo:-"$(git_repo_root)"}"
    repo_root="$(cd -- "${repo_root}" 2>/dev/null && pwd -P || printf '%s' "${repo_root}")"

    [[ -n "${repo_root}" ]] || return 1
    [[ -f "${file}" ]] || return 1

    awk -F $'\t' -v p="${repo_root}" '
        $1 == p { print $2; found=1; exit }
        END { if (!found) exit 1 }
    ' "${file}"

}
git_guess_ssh_key () {

    local p="$(pwd -P)" key="$(git_keymap_get 2>/dev/null || true)"

    [[ -n "${key}" ]] && { printf '%s\n' "${key}"; return 0; }
    [[ "${p}" == */private/* || "${p}" == */private ]] && { printf '%s\n' "private"; return 0; }
    [[ "${p}" == */public/*  || "${p}" == */public  ]] && { printf '%s\n' "public"; return 0; }

    if [[ -n "${WORKSPACE_DIR:-}" && "${p}" == "${WORKSPACE_DIR%/}/"* ]]; then

        local scope="${p#${WORKSPACE_DIR%/}/}"
        scope="${scope%%/*}"
        [[ -n "${scope}" ]] && { printf '%s\n' "${scope}"; return 0; }

    fi

    return 1

}
git_resolve_ssh_key () {

    local hint="${1:-${GIT_SSH_KEY:-"$(git_guess_ssh_key 2>/dev/null || true)"}}"
    hint="${hint/#\~/${HOME}}"

    local key="${hint}"
    [[ -f "${key}" ]] || key="${HOME}/.ssh/${hint}"
    [[ -f "${key}" ]] || key="${HOME}/.ssh/id_ed25519${hint:+_${hint}}"
    [[ -f "${key}" ]] || key="${HOME}/.ssh/id_ed25519_private"
    [[ -f "${key}" ]] || key="${HOME}/.ssh/id_ed25519"

    printf '%s\n' "${key}"
    return 0

}
git_auth_resolve () {

    local auth="${1:-ssh}" remote="${2:-origin}" key="${3:-}" token="${4:-}" token_env="${5:-GIT_TOKEN}"
    local kind="" target="" safe="" ssh_cmd=""

    if [[ -z "${auth}" ]]; then

        local env_auth="${GIT_AUTH:-}"
        [[ -n "${env_auth}" ]] && auth="${env_auth}" || auth="ssh"

    fi
    if [[ "${auth}" == "ssh" ]]; then

        kind="ssh" target="${remote}" safe="${remote}" key="$(git_resolve_ssh_key "${key}")"

        if [[ -f "${key}" ]]; then printf -v ssh_cmd 'ssh -i %q -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=60 -o ServerAliveInterval=15 -o ServerAliveCountMax=2' "${key}"
        else ssh_cmd='ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=60 -o ServerAliveInterval=15 -o ServerAliveCountMax=2'
        fi

        printf '%s\t%s\t%s\t%s\n' "${kind}" "${target}" "${safe}" "${ssh_cmd}"
        return 0

    fi
    if [[ "${auth}" == "http" ]]; then

        local cur="" host="" path="" url=""
        kind="http"

        [[ -n "${token}" ]] || token="$(get_env "${token_env}")"
        [[ -n "${token}" ]] || die "Missing token. Use --token or --token-env <VAR> (default: ${token_env})."

        cur="$(git_remote_url "${remote}")"
        [[ -n "${cur}" ]] || die "Remote not found: ${remote}"

        read -r host path < <(git_parse_remote "${cur}") || die "Can't parse remote url: $(git_redact_url "${cur}")"
        url="$(git_build_https_token_url "${token}" "${host}" "${path}")" || die "Can't build token url"

        target="${url}"
        safe="https://***@${host}/${path}"

        printf '%s\t%s\t%s\t%s\n' "${kind}" "${target}" "${safe}" ""
        return 0

    fi

    die "Unknown auth: ${auth} (use ssh|http)"

}
git_new_ssh_key () {

    ensure_pkg ssh-keygen mkdir chmod rm
    source <(parse "$@" -- name host alias type=ed25519 bits=4096 comment passphrase file config:bool=true add_agent:bool force:bool)

    local ssh_dir="${HOME}/.ssh" pub="" n="${name}" c="${comment}" base="${file}"
    base="${base/#\~/${HOME}}"

    [[ -n "${host}" ]] || host="${GIT_HOST:-github.com}"
    [[ -n "${passphrase}" ]] || passphrase=""
    [[ -n "${c}" ]] || c="$(git config user.email 2>/dev/null || true)"
    [[ -n "${c}" ]] || c="${USER:-user}@${HOSTNAME:-host}"
    [[ -n "${base}" ]] || base="id_${type}${n:+_${n}}"
    [[ "${base}" == */* ]] || base="${ssh_dir}/${base}"

    pub="${base}.pub"
    (( force )) || [[ ! -e "${base}" && ! -e "${pub}" ]] || die "Key exists: ${base} (use --force to override)"

    mkdir -p "${ssh_dir}"
    chmod 700 "${ssh_dir}" 2>/dev/null || true
    rm -f "${base}" "${pub}" 2>/dev/null || true

    if [[ "${type}" == "rsa" ]]; then run ssh-keygen -t rsa -b "${bits}" -f "${base}" -C "${c}" -N "${passphrase}"
    else run ssh-keygen -t ed25519 -a 64 -f "${base}" -C "${c}" -N "${passphrase}"
    fi

    chmod 600 "${base}" 2>/dev/null || true
    chmod 644 "${pub}" 2>/dev/null || true

    if (( config )); then

        ensure_pkg touch awk mktemp mv

        local cfg="${ssh_dir}/config"
        local a="${alias:-}"
        [[ -n "${a}" ]] || a="${host}${n:+-${n}}"

        run touch -- "${cfg}"
        chmod 600 "${cfg}" 2>/dev/null || true

        local tmp="$(mktemp "${TMPDIR:-/tmp}/vx.sshcfg.XXXXXX")" || die "mktemp failed"

        awk -v a="${a}" '
            BEGIN { drop=0; seen_host=0 }
            $0 == "### vx-key:" a { drop=1; seen_host=0; next }
            drop && $0 ~ /^Host[[:space:]]+/ {
                if (seen_host == 0) { seen_host=1; next }
                drop=0
            }
            drop && $0 ~ /^### vx-key:/ { drop=0 }
            drop { next }
            { print }
        ' "${cfg}" > "${tmp}"

        {
            printf '\n### vx-key:%s\n' "${a}"
            printf 'Host %s\n' "${a}"
            printf '    HostName %s\n' "${host}"
            printf '    User git\n'
            printf '    IdentityFile %s\n' "${base}"
            printf '    IdentitiesOnly yes\n'
        } >> "${tmp}"

        run mv -f -- "${tmp}" "${cfg}"
        chmod 600 "${cfg}" 2>/dev/null || true

    fi
    if (( add_agent )); then

        ensure_pkg ssh-add
        [[ -n "${SSH_AUTH_SOCK:-}" ]] && run ssh-add "${base}"

    fi

    printf '%s\n' "${base}"

}

git_build_ssh_url () {

    local host="${1:-}" path="${2:-}"
    [[ -n "${host}" && -n "${path}" ]] || return 1

    printf 'git@%s:%s\n' "${host}" "${path}"

}
git_build_https_url () {

    local host="${1:-}" path="${2:-}"
    [[ -n "${host}" && -n "${path}" ]] || return 1

    printf 'https://%s/%s\n' "${host}" "${path}"

}
git_norm_path_git () {

    local p="${1:-}"
    [[ -n "${p}" ]] || { printf ''; return 0; }

    p="${p%/}"
    p="${p#/}"
    p="${p%.git}"

    printf '%s.git\n' "${p}"

}
git_initial_branch () {

    ensure_pkg grep git
    ( git init -h 2>&1 || true ) | grep -q -- '--initial-branch'

}
git_set_default_branch () {

    local branch="${1:-main}"

    git branch -M "${branch}" >/dev/null 2>&1 && return 0
    git symbolic-ref HEAD "refs/heads/${branch}" >/dev/null 2>&1 && return 0

    return 0

}
git_guard_no_unborn () {

    ensure_pkg find git

    local root="${1:-.}" d="" repo=""
    local root_abs="$(cd -- "${root}" && pwd -P)" || die "Invalid root: ${root}"

    while IFS= read -r -d '' d; do

        repo="${d%/.git}"

        local repo_abs="$(cd -- "${repo}" && pwd -P 2>/dev/null || true)"
        [[ -n "${repo_abs}" && "${repo_abs}" == "${root_abs}" ]] && continue

        git -C "${repo}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
        git -C "${repo}" rev-parse --verify HEAD >/dev/null 2>&1 && continue

        die "Nested git repo with no commit checked out: ${repo}. Remove its .git or initialize/commit it."

    done < <(find "${root}" -mindepth 2 \( -name .git -type d -o -name .git -type f \) -print0 2>/dev/null)

}
git_root_version () {

    ensure_pkg awk git
    local v="" root="$(git_repo_root)"

    if [[ -f "${root}/Cargo.toml" ]]; then

        v="$(
            awk '
                BEGIN { sect=""; ws=""; pkg="" }

                /^\[workspace\.package\][[:space:]]*$/ { sect="ws"; next }
                /^\[package\][[:space:]]*$/            { sect="pkg"; next }
                /^\[[^]]+\][[:space:]]*$/              { sect=""; next }

                sect=="ws"  && ws==""  && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { ws=m[1]; next }
                sect=="pkg" && pkg=="" && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { pkg=m[1]; next }

                END {
                    if (ws  != "") { print ws;  exit 0 }
                    if (pkg != "") { print pkg; exit 0 }
                    exit 1
                }
            ' "${root}/Cargo.toml" 2>/dev/null
        )" || die "Can't detect version from ${root}/Cargo.toml."

    fi
    if [[ -z "${v}" && -f "${root}/composer.json" ]]; then

        ensure_pkg php
        v="$(
            php -r '$j=@json_decode(@file_get_contents($argv[1]), true); echo is_array($j)&&isset($j["version"])?$j["version"]:"";' \
                "${root}/composer.json" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && -f "${root}/package.json" ]]; then

        ensure_pkg node
        v="$(
            node -e '
                const fs = require("fs");
                const p = process.argv[2];
                try {
                    const j = JSON.parse(fs.readFileSync(p, "utf8"));
                    process.stdout.write(j.version || "");
                } catch (e) {}
            ' "${root}/package.json" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && -f "${root}/pyproject.toml" ]]; then

        v="$(
            awk '
                BEGIN { sect=""; v="" }

                /^\[project\][[:space:]]*$/      { sect="proj"; next }
                /^\[tool\.poetry\][[:space:]]*$/ { sect="poetry"; next }
                /^\[[^]]+\][[:space:]]*$/        { sect=""; next }

                sect=="proj"   && v=="" && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { v=m[1]; print v; exit 0 }
                sect=="poetry" && v=="" && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { v=m[1]; print v; exit 0 }

                END { exit 1 }
            ' "${root}/pyproject.toml" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && -f "${root}/setup.cfg" ]]; then

        v="$(
            awk '
                BEGIN { sect=""; v="" }

                /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
                    s=$0
                    gsub(/^[[:space:]]*\[/,"",s); gsub(/\][[:space:]]*$/,"",s)
                    sect=tolower(s)
                    next
                }

                sect=="metadata" && v=="" && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*([^#;[:space:]]+)/, m) {
                    v=m[1]
                    gsub(/^[[:space:]]+|[[:space:]]+$/,"",v)
                    print v
                    exit 0
                }

                END { exit 1 }
            ' "${root}/setup.cfg" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && -f "${root}/setup.py" ]]; then

        v="$(
            awk '
                match($0, /version[[:space:]]*=[[:space:]]*["'\'']([^"'\'']+)["'\'']/, m) { print m[1]; exit 0 }
                END { exit 1 }
            ' "${root}/setup.py" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" && ( -f "${root}/go.mod" || -f "${root}/go.work" ) ]]; then

        v="$(
            git -C "${root}" tag --list |
            awk '
                /^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/ {
                    raw = $0
                    tag = raw
                    sub(/^v/, "", tag)

                    split(tag, a, /[-+]/)
                    split(a[1], n, ".")

                    major = n[1] + 0
                    minor = n[2] + 0
                    patch = n[3] + 0

                    pre = (tag ~ /-/) ? 0 : 1

                    printf "%020d %020d %020d %d %s\n", major, minor, patch, pre, raw
                }
            ' |
            sort |
            tail -n 1 |
            awk '{ print $5 }'
        )" || true

        [[ -n "${v}" ]] && v="${v#v}"

    fi
    if [[ -z "${v}" && -f "${root}/xmake.lua" ]]; then

        v="$(
            awk '
                match($0, /^[[:space:]]*set_version[[:space:]]*\([[:space:]]*"([^"]+)"/, m) {
                    print m[1]
                    exit 0
                }
                END { exit 1 }
            ' "${root}/xmake.lua" 2>/dev/null
        )" || true

    fi
    if [[ -z "${v}" ]]; then

        local proj=""
        local -a proj_globs=(
            "${root}"/*.csproj
            "${root}"/*.fsproj
            "${root}"/*.vbproj
            "${root}"/src/*.csproj
            "${root}"/src/*.fsproj
            "${root}"/src/*.vbproj
            "${root}"/src/*/*.csproj
            "${root}"/src/*/*.fsproj
            "${root}"/src/*/*.vbproj
            "${root}"/app/*.csproj
            "${root}"/app/*.fsproj
            "${root}"/app/*.vbproj
            "${root}"/app/*/*.csproj
            "${root}"/app/*/*.fsproj
            "${root}"/app/*/*.vbproj
            "${root}"/apps/*.csproj
            "${root}"/apps/*.fsproj
            "${root}"/apps/*.vbproj
            "${root}"/apps/*/*.csproj
            "${root}"/apps/*/*.fsproj
            "${root}"/apps/*/*.vbproj
        )

        for proj in "${proj_globs[@]}"; do

            [[ -f "${proj}" ]] || continue

            v="$(
                awk '
                    match($0, /<Version>[[:space:]]*([^<[:space:]]+)[[:space:]]*<\/Version>/, m) {
                        print m[1]
                        exit 0
                    }
                    match($0, /<VersionPrefix>[[:space:]]*([^<[:space:]]+)[[:space:]]*<\/VersionPrefix>/, m) {
                        vp=m[1]
                    }
                    match($0, /<VersionSuffix>[[:space:]]*([^<[:space:]]+)[[:space:]]*<\/VersionSuffix>/, m) {
                        vs=m[1]
                    }
                    END {
                        if (vp != "" && vs != "") {
                            print vp "-" vs
                            exit 0
                        }
                        if (vp != "") {
                            print vp
                            exit 0
                        }
                        exit 1
                    }
                ' "${proj}" 2>/dev/null
            )" || true

            [[ -n "${v}" ]] && break

        done

    fi
    if [[ -z "${v}" ]]; then

        local f=""
        for f in "${root}/VERSION" "${root}/version" "${root}/.version"; do

            [[ -f "${f}" ]] || continue
            v="$(awk 'NR==1{ gsub(/\r/,""); print $1; exit }' "${f}" 2>/dev/null)" || true
            [[ -n "${v}" ]] && break

        done

    fi

    [[ -n "${v}" ]] || die "Can't detect version from ${root}."
    printf '%s\n' "${v}"

}
git_default_branch () {

    local remote="${1:-origin}" auth="${2:-ssh}" key="${3:-}" token="${4:-}" token_env="${5:-GIT_TOKEN}"

    git_repo_guard
    git_require_remote "${remote}"

    local b="$(git symbolic-ref -q --short "refs/remotes/${remote}/HEAD" 2>/dev/null || true)"
    [[ -n "${b}" ]] && { printf '%s\n' "${b#${remote}/}"; return 0; }

    local kind="" target="" safe="" ssh_cmd="" line="" sym=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    while IFS= read -r line; do
        case "${line}" in
            "ref: refs/heads/"*" HEAD")
                sym="${line#ref: }"
                sym="${sym% HEAD}"
                break
            ;;
        esac
    done < <(run_git "${kind}" "${ssh_cmd}" ls-remote --symref "${target}" HEAD 2>/dev/null || true)

    if [[ -n "${sym}" ]]; then
        printf '%s\n' "${sym#refs/heads/}"
        return 0
    fi

    local def="$(git config --get init.defaultBranch 2>/dev/null || true)"

    if [[ -n "${def}" ]] && git show-ref --verify --quiet "refs/heads/${def}"; then
        printf '%s\n' "${def}"
        return 0
    fi

    for def in main master trunk production prod; do
        git show-ref --verify --quiet "refs/heads/${def}" && { printf '%s\n' "${def}"; return 0; }
    done

    def="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "${def}" ]] && { printf '%s\n' "${def}"; return 0; }

    return 1

}

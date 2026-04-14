
year () {

    LC_ALL=C command date '+%Y'

}
month () {

    LC_ALL=C command date '+%m'

}
day () {

    LC_ALL=C command date '+%d'

}
date_only () {

    LC_ALL=C command date '+%Y-%m-%d'

}
time_only () {

    LC_ALL=C command date '+%H:%M:%S'

}
datetime () {

    LC_ALL=C command date '+%Y-%m-%d %H:%M:%S'

}

os_name () {

    local u="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    case "${u}" in
        linux*) printf '%s' linux ;;
        darwin*) printf '%s' macos ;;
        msys*|mingw*|cygwin*) printf '%s' windows ;;
        *) printf '%s' unknown ;;
    esac

}
is_linux () {

    [[ "$(os_name)" == "linux" ]]

}
is_macos () {

    [[ "$(os_name)" == "macos" ]]

}
is_mac () {

    is_macos

}
is_windows () {

    [[ "$(os_name)" == "windows" ]]

}
is_wsl () {

    [[ -n "${WSL_INTEROP:-}" || -n "${WSL_DISTRO_NAME:-}" ]] && return 0
    [[ -r /proc/version ]] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && return 0
    [[ -r /proc/sys/kernel/osrelease ]] && grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null && return 0

    return 1

}
is_ci () {

    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${GITLAB_CI:-}" || -n "${BUILDKITE:-}" || -n "${TF_BUILD:-}" ]]

}
is_ci_pull () {

    is_ci && [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" || -n "${CI_MERGE_REQUEST_IID:-}" ]]

}
is_ci_push () {

    is_ci && [[ "${GITHUB_EVENT_NAME:-}" == "push" || "${CI_PIPELINE_SOURCE:-}" == "push" ]]

}
is_ci_tag_push () {

    is_ci_push && [[ "${GITHUB_REF:-}" == refs/tags/* || -n "${CI_COMMIT_TAG:-}" ]]

}

slugify () {

    local s="${1-}"
    [[ -n "${s}" ]] || { printf '%s' ""; return 0; }

    s="$(LC_ALL=C printf '%s' "${s}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-')"
    s="${s#-}"
    s="${s%-}"

    printf '%s' "${s}"

}
uc_first () {

    local s="${1:-}"
    [[ -n "${s}" ]] || { printf '%s' ""; return 0; }
    printf '%s%s' "$(printf '%s' "${s:0:1}" | tr '[:lower:]' '[:upper:]')" "${s:1}"

}
unique_list () {

    local -n in="${1}"
    local -a out=()
    local -A seen=()
    local x=""

    for x in "${in[@]-}"; do

        [[ -n "${x}" ]] || continue
        [[ -n "${seen["$x"]+x}" ]] && continue

        seen["$x"]=1
        out+=( "$x" )

    done

    in=( "${out[@]}" )

}
is_danger_path () {

    local p="${1:-}"

    case "${p}" in
        ""|"-"*|"/"|"."|".."|"~"|"/."|"/.."|"/c"|"/c/"|"/d"|"/d/"|"/e"|"/e/"|"/f"|"/f/"|[A-Za-z]:|[A-Za-z]:/|[A-Za-z]:\\)
            return 0
        ;;
    esac

    return 1

}
assert_safe_path () {

    local p="${1:-}" label="${2:-path}"
    [[ -n "${p}" ]] || die "${label}: empty path"
    is_danger_path "${p}" && die "${label}: refused dangerous path '${p}'"

}
validate_alias () {

    local a="${1:-}"

    [[ -n "${a}" ]] || die "validate_alias: empty alias"
    [[ "${a}" != *"/"* && "${a}" != *"\\"* ]] || die "validate_alias: invalid alias '${a}'"
    [[ "${a}" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || die "validate_alias: invalid alias '${a}'"

}
ignore_list () {

    printf '%s\n' \
        ".git" \
        ".vscode" \
        ".idea" \
        ".DS_Store" \
        "Thumbs.db" \
        "out" \
        "dist" \
        "build" \
        "coverage" \
        "target" \
        "vendor" \
        "venv" \
        "node_modules" \
        ".nyc_output" \
        ".next" \
        ".nuxt" \
        ".turbo" \
        "__pycache__" \
        ".venv" \
        ".pytest_cache" \
        ".mypy_cache" \
        ".ruff_cache" \
        ".cache" \
        ".dart_tool" \
        ".flutter-plugins" \
        ".flutter-plugins-dependencies" \
        "pubspec.lock" \
        "obj" \
        ".vs" \
        ".xmake" \
        ".build" \
        ".ccls-cache" \
        "compile_commands.json" \
        ".zig-cache" \
        "zig-out" \
        "gradlew" \
        "mvnw" \
        ".mojo" \
        ".modular"

}
which_lang () {

    local dir="${1:-${PWD}}" hit=""

    [[ -d "${dir}" ]] || dir="$(dirname -- "${dir}")"
    [[ -d "${dir}" ]] || { printf '%s' "null"; return 0; }

    while :; do

        if [[ -f "${dir}/Cargo.toml" ]]; then printf '%s' "rust"; return 0; fi
        if [[ -f "${dir}/build.zig" || -f "${dir}/build.zig.zon" ]]; then printf '%s' "zig"; return 0; fi
        if [[ -f "${dir}/go.mod" || -f "${dir}/go.work" ]]; then printf '%s' "go"; return 0; fi

        if compgen -G "${dir}/*.sln" >/dev/null || compgen -G "${dir}/*.csproj" >/dev/null || compgen -G "${dir}/*.fsproj" >/dev/null || [[ -f "${dir}/Directory.Build.props" || -f "${dir}/Directory.Build.targets" || -f "${dir}/global.json" ]]; then
            printf '%s' "csharp"
            return 0
        fi
        if [[ -f "${dir}/settings.gradle" || -f "${dir}/settings.gradle.kts" || -f "${dir}/build.gradle" || -f "${dir}/build.gradle.kts" || -f "${dir}/pom.xml" || -f "${dir}/gradlew" || -f "${dir}/mvnw" ]]; then
            printf '%s' "java"
            return 0
        fi

        if [[ -f "${dir}/pubspec.yaml" ]]; then printf '%s' "dart"; return 0; fi
        if [[ -f "${dir}/composer.json" || -f "${dir}/artisan" ]]; then printf '%s' "php"; return 0; fi

        if [[ -f "${dir}/pyproject.toml" || -f "${dir}/uv.toml" || -f "${dir}/uv.lock" || -f "${dir}/requirements.txt" || -f "${dir}/Pipfile" || -f "${dir}/poetry.lock" ]]; then
            printf '%s' "python"
            return 0
        fi
        if [[ -f "${dir}/mojoproject.toml" || -f "${dir}/mod.toml" ]]; then
            printf '%s' "mojo"
            return 0
        fi

        hit="$(find "${dir}" -maxdepth 3 -type f -name '*.mojo' -print -quit 2>/dev/null || true)"
        [[ -n "${hit}" ]] && { printf '%s' "mojo"; return 0; }

        if [[ -f "${dir}/bun.lockb" || -f "${dir}/bun.lock" || -f "${dir}/bunfig.toml" ]]; then printf '%s' "bun"; return 0; fi
        if [[ -f "${dir}/package.json" ]]; then printf '%s' "node"; return 0; fi

        if [[ -f "${dir}/xmake.lua" || -f "${dir}/CMakeLists.txt" || -f "${dir}/meson.build" || -f "${dir}/Makefile" || -f "${dir}/conanfile.txt" || -f "${dir}/conanfile.py" ]]; then
            hit="$(find "${dir}" -maxdepth 6 -type f \( \
                -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' -o -name '*.C' -o \
                -name '*.hpp' -o -name '*.hh' -o -name '*.hxx' -o \
                -name '*.ipp' -o -name '*.inl' -o \
                -name '*.ixx' -o -name '*.cppm' -o -name '*.cxxm' \
            \) -print -quit 2>/dev/null || true)"

            [[ -n "${hit}" ]] && { printf '%s' "cpp"; return 0; }
            printf '%s' "c"
            return 0
        fi
        if [[ -f "${dir}/rocks.toml" ]] || compgen -G "${dir}/*.rockspec" >/dev/null; then
            printf '%s' "lua"
            return 0
        fi

        hit="$(find "${dir}" -maxdepth 2 -type f -name '*.lua' -print -quit 2>/dev/null || true)"
        [[ -n "${hit}" ]] && { printf '%s' "lua"; return 0; }

        hit="$(find "${dir}" -maxdepth 2 -type f -name '*.sh' -print -quit 2>/dev/null || true)"
        [[ -n "${hit}" ]] && { printf '%s' "bash"; return 0; }

        [[ "$(dirname -- "${dir}")" != "${dir}" ]] || break
        dir="$(dirname -- "${dir}")"

    done

    printf '%s' "null"

}

tmp_dir () {

    local tag="${1:-tmp}" base="${2:-${TMPDIR:-/tmp}}"

    mkdir -p "${base}" 2>/dev/null || true
    local tmp="$(mktemp -d "${base%/}/${tag}.XXXXXX" 2>/dev/null || true)"

    if [[ -z "${tmp}" || ! -d "${tmp}" ]]; then
        tmp="${base%/}/${tag}.$$.$RANDOM"
        mkdir -p "${tmp}" 2>/dev/null || die "tmp_dir: failed (${base})"
    fi

    chmod 700 -- "${tmp}" 2>/dev/null || true
    printf '%s' "${tmp}"

}
tmp_file () {

    local tag="${1:-tmp}" base="${2:-${TMPDIR:-/tmp}}"

    local dir="$(tmp_dir "${tag}" "${base}")"
    local tmp="$(mktemp "${dir%/}/${tag}.XXXXXX" 2>/dev/null || true)"

    if [[ -z "${tmp}" || ! -f "${tmp}" ]]; then
        tmp="${dir%/}/${tag}"
        : > "${tmp}" 2>/dev/null || die "tmp_file: failed (${dir})"
    fi

    chmod 600 -- "${tmp}" 2>/dev/null || true
    printf '%s' "${tmp}"

}
abs_dir () {

    local p="${1:-}" d=""

    if [[ -z "${p}" ]]; then
        pwd -P
        return 0
    fi

    if [[ -d "${p}" ]]; then d="${p}"
    else d="$(dirname -- "${p}")"
    fi

    ( cd -- "${d}" 2>/dev/null && pwd -P ) || return 1

}
config_file () {

    local name="${1:-}" ext1="${2:-}" ext2="${3:-}" base=""
    [[ -n "${name}" ]] || { printf '\n'; return 0; }
    base="${name%%-*}"

    if [[ -n "${ext1}" && -f "${name}.${ext1}" ]]; then printf '%s\n' "${name}.${ext1}"; return 0; fi
    if [[ -n "${ext1}" && -f ".${name}.${ext1}" ]]; then printf '%s\n' ".${name}.${ext1}"; return 0; fi
    if [[ -n "${ext2}" && -f "${name}.${ext2}" ]]; then printf '%s\n' "${name}.${ext2}"; return 0; fi
    if [[ -n "${ext2}" && -f ".${name}.${ext2}" ]]; then printf '%s\n' ".${name}.${ext2}"; return 0; fi

    if [[ "${base}" != "${name}" ]]; then
        if [[ -n "${ext1}" && -f "${base}.${ext1}" ]]; then printf '%s\n' "${base}.${ext1}"; return 0; fi
        if [[ -n "${ext1}" && -f ".${base}.${ext1}" ]]; then printf '%s\n' ".${base}.${ext1}"; return 0; fi
        if [[ -n "${ext2}" && -f "${base}.${ext2}" ]]; then printf '%s\n' "${base}.${ext2}"; return 0; fi
        if [[ -n "${ext2}" && -f ".${base}.${ext2}" ]]; then printf '%s\n' ".${base}.${ext2}"; return 0; fi
    fi

    printf '\n'

}
home_path () {

    local h="${HOME:-}"

    if [[ -n "${h}" ]]; then
        printf '%s' "${h}"
        return 0
    fi

    h="$(cd ~ 2>/dev/null && pwd)" || h=""
    [[ -n "${h}" ]] || die "home_path: HOME not set and cannot resolve"

    printf '%s' "${h}"

}
rc_path () {

    local shell_name="${SHELL##*/}"

    case "${shell_name}" in
        zsh)  printf '%s' "$(home_path)/.zshrc" ;;
        fish) printf '%s' "$(home_path)/.config/fish/config.fish" ;;
        *)    printf '%s' "$(home_path)/.bashrc" ;;
    esac

}
remove_path () {

    local p="${1:-}" label="${2:-remove_path}"

    assert_safe_path "${p}" "${label}"
    [[ -e "${p}" || -L "${p}" ]] || return 0

    run rm -rf "${p}"

}
ln_sf () {

    local src="${1:-}" dst="${2:-}"

    [[ -n "${src}" && -n "${dst}" ]] || die "ln_sf: usage: ln_sf <src> <dst>"
    [[ -e "${src}" || -L "${src}" ]] || die "ln_sf: missing source '${src}'"

    assert_safe_path "${dst}" "ln_sf"
    ensure_dir "$(dirname -- "${dst}")"
    remove_path "${dst}" "ln_sf"

    run ln -s "${src}" "${dst}" && return 0

    if [[ -d "${src}" ]]; then run cp -R "${src}" "${dst}"
    else run cp "${src}" "${dst}"
    fi

}

ensure_dir () {

    local dir="${1:-}"

    [[ -n "${dir}" ]] || die "ensure_dir: missing dir"
    [[ -d "${dir}" ]] && return 0

    run mkdir -p "${dir}"

}
ensure_file () {

    local file="${1:-}"

    [[ -n "${file}" ]] || die "ensure_file: missing file"
    [[ -f "${file}" ]] && return 0

    ensure_dir "$(dirname -- "${file}")"
    run touch "${file}"

}
ensure_symlink () {

    local src="${1:-}" dst="${2:-}"

    [[ -n "${src}" && -n "${dst}" ]] || die "ensure_symlink: usage: ensure_symlink <src> <dst>"
    [[ -e "${src}" || -L "${src}" ]] || die "ensure_symlink: missing source '${src}'"

    assert_safe_path "${dst}" "ensure_symlink"
    ensure_dir "$(dirname -- "${dst}")"
    remove_path "${dst}" "ensure_symlink"

    run ln -s "${src}" "${dst}"

}
ensure_bin_link () {

    local alias_name="${1:-}" target="${2:-}" prefix="${3:-$(home_path)/.local}"
    local bin_dir="${prefix}/bin" bin_path="${bin_dir}/${alias_name}"

    [[ -n "${target}" ]] || die "ensure_bin_link: missing target"

    validate_alias "${alias_name}"
    ensure_dir "${bin_dir}"
    ensure_symlink "${target}" "${bin_path}"

}

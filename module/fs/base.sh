
fs_new_dir () {

    ensure_pkg mkdir chmod
    source <(parse "$@" -- :src mode)

    run mkdir -p -- "${src}"
    [[ -n "${mode}" ]] && run chmod -- "${mode}" "${src}"

}
fs_new_file () {

    ensure_pkg mkdir chmod touch dirname
    source <(parse "$@" -- :src mode)

    run mkdir -p -- "$(dirname -- "${src}")"
    run touch -- "${src}"

    [[ -n "${mode}" ]] && run chmod -- "${mode}" "${src}"

}
fs_path_type () {

    local p="${1:-}" type="unknown"

    [[ -e "${p}" ]] && type="other"
    [[ -d "${p}" ]] && type="dir"
    [[ -f "${p}" ]] && type="file"
    [[ -L "${p}" ]] && type="symlink"

    printf '%s\n' "${type}"
    return 0

}
fs_file_type () {

    ensure_pkg file
    local p="${1:-}" mime="" enc=""

    [[ -L "${p}" ]] && { printf '%s\n' "symlink"; return 0; }
    [[ -d "${p}" ]] && { printf '%s\n' "dir"; return 0; }
    [[ -e "${p}" ]] || { printf '%s\n' "missing"; return 1; }

    mime="$(file -b --mime-type -- "${p}" 2>/dev/null || true)"
    enc="$(file -b --mime-encoding -- "${p}" 2>/dev/null || true)"

    case "${mime}" in
        text/*) printf '%s\n' "text"; return 0 ;;
        image/*) printf '%s\n' "image"; return 0 ;;
        video/*) printf '%s\n' "video"; return 0 ;;
        audio/*) printf '%s\n' "audio"; return 0 ;;
        application/pdf) printf '%s\n' "pdf"; return 0 ;;
    esac
    case "${p,,}" in
        *.pdf) printf '%s\n' "pdf"; return 0 ;;
        *.doc|*.docx|*.dot|*.dotx|*.docm|*.dotm) printf '%s\n' "word"; return 0 ;;
        *.xls|*.xlsx|*.xlsm|*.xlt|*.xltx|*.xltm) printf '%s\n' "excel"; return 0 ;;
    esac

    [[ "${enc}" == "binary" ]] && { printf '%s\n' "binary"; return 0; }

    printf '%s\n' "other"
    return 0

}

fs_file_exists () {

    [[ -f "${1:-}" ]]

}
fs_dir_exists () {

    [[ -d "${1:-}" ]]

}
fs_path_exists () {

    [[ -e "${1:-}" || -L "${1:-}" ]]

}

fs_copy_path () {

    ensure_pkg cp mkdir dirname
    source <(parse "$@" -- :src :dest)

    run mkdir -p -- "$(dirname -- "${dest}")"
    local -a cmd=( cp )

    if cp --version >/dev/null 2>&1; then cmd+=( -a )
    else cmd+=( -pPR )
    fi

    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" "${dest}"

}
fs_move_path () {

    ensure_pkg mv mkdir dirname
    source <(parse "$@" -- :src :dest)

    run mkdir -p -- "$(dirname -- "${dest}")"
    run mv "${kwargs[@]}" -- "${src}" "${dest}"

}
fs_remove_path () {

    ensure_pkg rm find
    source <(parse "$@" -- :src clear:bool)

    [[ "${src}" == "/" || "${src}" == "." || "${src}" == ".." ]] && die "Refuse to delete '/' '.' '..'"

    if (( clear )); then

        [[ -d "${src}" ]] || die "Not a directory: ${src}"
        find "${src}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
        return 0

    fi

    run rm -rf "${kwargs[@]}" -- "${src}"

}
fs_trash_path () {

    ensure_pkg mkdir mv date basename
    source <(parse "$@" -- :src trash_dir)

    [[ "${src}" == "/" || "${src}" == "." || "${src}" == ".." ]] && die "Refuse to trash '/' '.' '..'"
    local dir=""

    if [[ -n "${trash_dir}" ]]; then dir="${trash_dir%/}"
    elif [[ "${OSTYPE:-}" == darwin* ]]; then dir="${HOME}/.Trash"
    else dir="${XDG_DATA_HOME:-"${HOME}/.local/share"}/Trash/files"
    fi

    run mkdir -p -- "${dir}"

    local base="$(basename -- "${src%/}")"
    local ts="$(date +'%Y-%m-%d_%H-%M-%S')"
    local dest="${dir}/${base}__${ts}__$$"

    run mv "${kwargs[@]}" -- "${src}" "${dest}"
    printf '%s\n' "${dest}"

}
fs_link_path () {

    ensure_pkg mkdir ln dirname
    source <(parse "$@" -- :src :dest)

    run mkdir -p -- "$(dirname -- "${dest}")"
    run ln -sfn "${kwargs[@]}" -- "${src}" "${dest}"

}

fs_stats_path () {

    ensure_pkg stat
    source <(parse "$@" -- :src)

    if stat --version >/dev/null 2>&1; then stat -c $'path=%n\ntype=%F\nsize=%s\nperm=%a\nowner=%U\ngroup=%G\nmtime=%y' -- "${src}"
    else stat -f $'path=%N\ntype=%HT\nsize=%z\nperm=%Lp\nowner=%Su\ngroup=%Sg\nmtime=%Sm' -t "%Y-%m-%d %H:%M:%S" -- "${src}"
    fi

}
fs_diff_path () {

    ensure_pkg diff
    source <(parse "$@" -- :src :dest recursive:bool=true brief:bool=true)

    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"
    [[ -e "${dest}" || -L "${dest}" ]] || die "Path not found: ${dest}"

    local -a cmd=( diff )

    (( brief )) && cmd+=( -q )
    [[ -d "${src}" && -d "${dest}" ]] && (( recursive )) && cmd+=( -r )

    cmd+=( "${kwargs[@]}" -- "${src}" "${dest}" )
    "${cmd[@]}"

}
fs_synced_path () {

    ensure_pkg diff
    source <(parse "$@" -- :src :dest recursive:bool=true)

    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"
    [[ -e "${dest}" || -L "${dest}" ]] || die "Path not found: ${dest}"

    local -a cmd=( diff -q )

    [[ -d "${src}" && -d "${dest}" ]] && (( recursive )) && cmd+=( -r )
    cmd+=( "${kwargs[@]}" -- "${src}" "${dest}" )

    if "${cmd[@]}" >/dev/null 2>&1; then printf '%s\n' "yes"
    else printf '%s\n' "no"
    fi

}

fs_compress_path () {

    ensure_pkg mkdir dirname basename tar
    source <(parse "$@" -- src dest name type=zip exclude:list)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." || "${src}" == "/" ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    local base="${src%/}" kind="${type,,}" ext="" i=""
    local dir="$(dirname -- "${base}")"
    local entry="$(basename -- "${base}")"

    name="${name:-"${entry}"}"

    if [[ -z "${dest}" ]]; then

        case "${kind}" in
            zip)           dest="${PWD}/${name}.zip" ;;
            rar)           dest="${PWD}/${name}.rar" ;;
            7z)            dest="${PWD}/${name}.7z" ;;
            tar)           dest="${PWD}/${name}.tar" ;;
            tgz|gz)        dest="${PWD}/${name}.tar.gz" ;;
            txz|xz)        dest="${PWD}/${name}.tar.xz" ;;
            tbz2|bz2)      dest="${PWD}/${name}.tar.bz2" ;;
            tzst|zst|zstd) dest="${PWD}/${name}.tar.zst" ;;
            *)             dest="${PWD}/${name}.${type}" ;;
        esac

    fi

    [[ "${dest}" == /* ]] || dest="${PWD}/${dest#./}"
    run mkdir -p -- "$(dirname -- "${dest}")"

    ext="${dest,,}"

    local -a cmd=()
    local -a ignores=()

    mapfile -t ignores < <(ignore_list)
    ignores+=( "${exclude[@]-}" )

    if [[ "${kind}" == "zip" || "${ext}" == *.zip ]]; then

        ensure_pkg zip

        cmd=( zip -rq )
        cmd+=( "${kwargs[@]}" )
        cmd+=( "${dest}" "${entry}" )

        for i in "${ignores[@]-}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( -x "*${i}*" )
        done

        ( cd -- "${dir}" && run "${cmd[@]}" )

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${kind}" == "rar" || "${ext}" == *.rar ]]; then

        ensure_pkg rar

        cmd=( rar a -r -idq )
        cmd+=( "${kwargs[@]}" )
        cmd+=( "${dest}" "${entry}" )

        for i in "${ignores[@]-}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( "-x*${i}*" )
        done

        ( cd -- "${dir}" && run "${cmd[@]}" )

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${kind}" == "7z" || "${ext}" == *.7z ]]; then

        ensure_pkg 7z

        cmd=( 7z a -y )
        cmd+=( "${kwargs[@]}" )
        cmd+=( "${dest}" "${entry}" )

        for i in "${ignores[@]-}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( "-xr!*${i}*" )
        done

        ( cd -- "${dir}" && run "${cmd[@]}" )

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${kind}" == "tzst" || "${kind}" == "zst" || "${kind}" == "zstd" || "${ext}" == *.tar.zst || "${ext}" == *.tzst ]]; then

        ensure_pkg zstd

        if tar --help 2>/dev/null | grep -q -- '--zstd'; then

            cmd=( tar --zstd -cf "${dest}" )

            for i in "${ignores[@]-}"; do
                [[ -n "${i}" ]] || continue
                cmd+=( --exclude "${i}" )
            done

            run "${cmd[@]}" "${kwargs[@]}" -C "${dir}" -- "${entry}"

        else

            local -a tar_cmd=( tar -cf - )

            for i in "${ignores[@]-}"; do
                [[ -n "${i}" ]] || continue
                tar_cmd+=( --exclude "${i}" )
            done

            tar_cmd+=( "${kwargs[@]}" -C "${dir}" -- "${entry}" )
            ( "${tar_cmd[@]}" | zstd -T0 -q -o "${dest}" ) || die "Failed to create zstd archive: ${dest}"

        fi

        printf '%s\n' "${dest}"
        return 0

    fi

    if [[ "${kind}" == "tgz" || "${kind}" == "gz" || "${ext}" == *.tar.gz || "${ext}" == *.tgz ]]; then cmd=( tar -czf "${dest}" )
    elif [[ "${kind}" == "txz" || "${kind}" == "xz" || "${ext}" == *.tar.xz || "${ext}" == *.txz ]]; then cmd=( tar -cJf "${dest}" )
    elif [[ "${kind}" == "tbz2" || "${kind}" == "bz2" || "${ext}" == *.tar.bz2 || "${ext}" == *.tbz2 ]]; then cmd=( tar -cjf "${dest}" )
    elif [[ "${kind}" == "tar" || "${ext}" == *.tar ]]; then cmd=( tar -cf "${dest}" )
    else die "Unsupported archive type: ${dest}"
    fi

    for i in "${ignores[@]-}"; do
        [[ -n "${i}" ]] || continue
        cmd+=( --exclude "${i}" )
    done

    run "${cmd[@]}" "${kwargs[@]}" -C "${dir}" -- "${entry}"
    printf '%s\n' "${dest}"

}
fs_extract_path () {

    ensure_pkg mkdir tar
    source <(parse "$@" -- :src dest strip:int)

    [[ -e "${src}" || -L "${src}" ]] || die "Archive not found: ${src}"
    [[ -n "${dest}" ]] || dest="."

    run mkdir -p -- "${dest}"

    local ext="${src,,}"
    local -a cmd=( tar )

    if [[ "${ext}" == *.zip ]]; then

        ensure_pkg unzip
        run unzip -oq "${kwargs[@]}" -- "${src}" -d "${dest}"

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.rar ]]; then

        ensure_pkg unrar
        run unrar x -o+ -y "${kwargs[@]}" "${src}" "${dest}/"

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.7z ]]; then

        ensure_pkg 7z
        run 7z x -y "${kwargs[@]}" -o"${dest}" "${src}"

        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.tar.zst || "${ext}" == *.tzst ]]; then

        ensure_pkg zstd

        if tar --help 2>/dev/null | grep -q -- '--zstd'; then

            cmd+=( --zstd -xf )
            (( strip > 0 )) && cmd+=( --strip-components "${strip}" )

            run "${cmd[@]}" "${kwargs[@]}" -- "${src}" -C "${dest}"

        else

            local -a tar_cmd=( tar -xf - -C "${dest}" )

            (( strip > 0 )) && tar_cmd+=( --strip-components "${strip}" )
            tar_cmd+=( "${kwargs[@]}" )

            ( zstd -dc -- "${src}" | "${tar_cmd[@]}" ) || die "Failed to extract zstd archive: ${src}"

        fi

        printf '%s\n' "${dest}"
        return 0

    fi

    if [[ "${ext}" == *.tar.gz || "${ext}" == *.tgz ]]; then cmd+=( -xzf )
    elif [[ "${ext}" == *.tar.xz || "${ext}" == *.txz ]]; then cmd+=( -xJf )
    elif [[ "${ext}" == *.tar.bz2 || "${ext}" == *.tbz2 ]]; then cmd+=( -xjf )
    elif [[ "${ext}" == *.tar ]]; then cmd+=( -xf )
    else die "Unsupported archive type: ${src}"
    fi

    (( strip > 0 )) && cmd+=( --strip-components "${strip}" )

    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" -C "${dest}"
    printf '%s\n' "${dest}"

}
fs_backup_path () {

    ensure_pkg date basename
    source <(parse "$@" -- src dest name type=zip archive_dir="${ARCHIVE_DIR:-}")

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." || "${src}" == "/" ]] && src="${PWD}"

    local base_name="$(basename -- "${src%/}")" ts="$(date +'%Y-%m-%d_%H-%M-%S')" _dest_=""

    [[ -n "${name}" ]] && _dest_="${dest:-${base_name}}/${name}" || _dest_="${dest:-"${base_name}/${ts}.${type:-zip}"}"
    [[ -n "${archive_dir}" && "${_dest_}" != /* && "${_dest_}" != *:* ]] && dest="${archive_dir%/}/${_dest_}" || dest="${_dest_}"

    fs_compress_path "${src}" "${dest}" "${name}" "${type}" "${kwargs[@]}"

    success "OK: ${src} archived at ${dest}"

}
fs_sync_path () {

    ensure_pkg rsync mkdir
    source <(parse "$@" -- src dest src_dir="${WORKSPACE_DIR:-}" sync_dir="${SYNC_DIR:-}" force:bool=true ignore:bool=true exclude:list)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." || "${src}" == "/" ]] && src="${PWD}"

    local rel="${src#${src_dir%/}/}"
    [[ "${rel}" == "${src}" ]] && rel="${src#/}"

    if [[ -z "${dest}" && -n "${sync_dir}" ]]; then dest="${sync_dir%/}/${rel}"
    elif [[ -z "${dest}" ]]; then dest="${rel}"
    fi

    [[ -d "${src}" && "${src}" != */ ]] && src="${src}/"
    [[ -d "${src}" && "${dest}" != */ ]] && dest="${dest}/"
    [[ -d "${src}" ]] && run mkdir -p -- "${dest%/}" || run mkdir -p -- "$(dirname -- "${dest}")"

    local -a cmd=( rsync -a )
    (( force )) && cmd+=( --delete )

    if (( ignore )); then

        local i=""
        local -a ignores=()

        mapfile -t ignores < <(ignore_list)
        ignores+=( "${exclude[@]-}" )

        for i in "${ignores[@]}"; do
            [[ -n "${i}" ]] || continue
            cmd+=( --exclude "${i}" )
        done

    fi

    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" "${dest}"

    success "OK: ${src} synced at ${dest}"

}

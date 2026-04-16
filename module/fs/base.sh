
fs_file_exists () {

    [[ -f "${1:-}" ]]

}
fs_dir_exists () {

    [[ -d "${1:-}" ]]

}
fs_path_exists () {

    [[ -e "${1:-}" || -L "${1:-}" ]]

}
fs_new_dir () {

    ensure_tool mkdir chmod
    source <(parse "$@" -- :name mode)

    run mkdir -p -- "${name}"
    [[ -n "${mode}" ]] && run chmod -- "${mode}" "${name}"

}
fs_new_file () {

    ensure_tool mkdir chmod touch dirname
    source <(parse "$@" -- :name mode)

    run mkdir -p -- "$(dirname -- "${name}")"
    run touch -- "${name}"

    [[ -n "${mode}" ]] && run chmod -- "${mode}" "${name}"

}
fs_path_type () {

    source <(parse "$@" -- :src)
    local type="unknown"

    [[ -e "${src}" ]] && type="other"
    [[ -d "${src}" ]] && type="dir"
    [[ -f "${src}" ]] && type="file"
    [[ -L "${src}" ]] && type="symlink"

    printf '%s\n' "${type}"
    return 0

}
fs_file_type () {

    ensure_tool file
    source <(parse "$@" -- :src)

    [[ -L "${src}" ]] && { printf '%s\n' "symlink"; return 0; }
    [[ -d "${src}" ]] && { printf '%s\n' "dir"; return 0; }
    [[ -e "${src}" ]] || { printf '%s\n' "missing"; return 1; }

    local mime="$(file -b --mime-type -- "${src}" 2>/dev/null || true)"
    local enc="$(file -b --mime-encoding -- "${src}" 2>/dev/null || true)"

    case "${mime}" in
        text/*) printf '%s\n' "text"; return 0 ;;
        image/*) printf '%s\n' "image"; return 0 ;;
        video/*) printf '%s\n' "video"; return 0 ;;
        audio/*) printf '%s\n' "audio"; return 0 ;;
        application/pdf) printf '%s\n' "pdf"; return 0 ;;
    esac
    case "${src,,}" in
        *.pdf) printf '%s\n' "pdf"; return 0 ;;
        *.doc|*.docx|*.dot|*.dotx|*.docm|*.dotm) printf '%s\n' "word"; return 0 ;;
        *.xls|*.xlsx|*.xlsm|*.xlt|*.xltx|*.xltm) printf '%s\n' "excel"; return 0 ;;
    esac

    [[ "${enc}" == "binary" ]] && { printf '%s\n' "binary"; return 0; }

    printf '%s\n' "other"
    return 0

}

fs_copy_path () {

    ensure_tool cp mkdir dirname
    source <(parse "$@" -- src :dest)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    run mkdir -p -- "$(dirname -- "${dest}")"
    local -a cmd=( cp )

    if cp --version >/dev/null 2>&1; then cmd+=( -a )
    else cmd+=( -pPR )
    fi

    run "${cmd[@]}" "${kwargs[@]}" -- "${src}" "${dest}"

}
fs_move_path () {

    ensure_tool mv mkdir dirname
    source <(parse "$@" -- src :dest)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ "${src}" == "/" ]] && die "Refuse to move '/'"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    run mkdir -p -- "$(dirname -- "${dest}")"
    run mv "${kwargs[@]}" -- "${src}" "${dest}"

}
fs_trash_path () {

    ensure_tool mkdir mv date basename
    source <(parse "$@" -- src trash_dir)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ "${src}" == "/" ]] && die "Refuse to trash '/'"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    local dir="${XDG_DATA_HOME:-"${HOME}/.local/share"}/Trash/files"

    if [[ -n "${trash_dir}" ]]; then dir="${trash_dir%/}"
    elif [[ "${OSTYPE:-}" == darwin* ]]; then dir="${HOME}/.Trash"
    fi

    run mkdir -p -- "${dir}"

    local base="$(basename -- "${src%/}")"
    local ts="$(date +'%Y-%m-%d_%H-%M-%S')"
    local dest="${dir}/${base}__${ts}__$$"

    run mv "${kwargs[@]}" -- "${src}" "${dest}"
    printf '%s\n' "${dest}"

}
fs_remove_path () {

    ensure_tool rm find
    source <(parse "$@" -- src clear:bool)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ "${src}" == "/" ]] && die "Refuse to remove '/'"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    if (( clear )); then

        if [[ -f "${src}" ]]; then : > "${src}" || die "Cannot clear file: ${src}"
        else find "${src}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || die "Cannot clear dir: ${src}"
        fi

        return 0

    fi

    run rm -rf "${kwargs[@]}" -- "${src}"

}
fs_link_path () {

    ensure_tool mkdir ln dirname
    source <(parse "$@" -- src :dest)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    run mkdir -p -- "$(dirname -- "${dest}")"
    run ln -sfn "${kwargs[@]}" -- "${src}" "${dest}"

}
fs_stats_path () {

    ensure_tool stat
    source <(parse "$@" -- src)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    if stat --version >/dev/null 2>&1; then stat -c $'path=%n\ntype=%F\nsize=%s\nperm=%a\nowner=%U\ngroup=%G\nmtime=%y' -- "${src}"
    else stat -f $'path=%N\ntype=%HT\nsize=%z\nperm=%Lp\nowner=%Su\ngroup=%Sg\nmtime=%Sm' -t "%Y-%m-%d %H:%M:%S" -- "${src}"
    fi

}
fs_diff_path () {

    ensure_tool diff
    source <(parse "$@" -- src :dest recursive:bool=true brief:bool=true)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"
    [[ -e "${dest}" || -L "${dest}" ]] || die "Path not found: ${dest}"

    local -a cmd=( diff )

    (( brief )) && cmd+=( -q )
    [[ -d "${src}" && -d "${dest}" ]] && (( recursive )) && cmd+=( -r )

    cmd+=( "${kwargs[@]}" -- "${src}" "${dest}" )
    "${cmd[@]}"

}
fs_synced_path () {

    ensure_tool diff
    source <(parse "$@" -- src :dest recursive:bool=true)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"
    [[ -e "${dest}" || -L "${dest}" ]] || die "Path not found: ${dest}"

    local -a cmd=( diff -q )

    [[ -d "${src}" && -d "${dest}" ]] && (( recursive )) && cmd+=( -r )
    cmd+=( "${kwargs[@]}" -- "${src}" "${dest}" )

    if "${cmd[@]}" >/dev/null 2>&1; then printf '%s\n' "yes"
    else printf '%s\n' "no"
    fi

}

fs_ucfirst_path () {

    local p="${1:-}" base_dir="${2:-}" rest="" out="" seg="" trailing=0
    local -a parts=()

    if [[ -n "${base_dir}" ]]; then

        base_dir="${base_dir%/}"
        rest="${p#${base_dir}}"

        [[ "${p}" == "${base_dir}" || "${p}" == "${base_dir}/"* ]] || { printf '%s\n' "${p}"; return 0; }
        [[ -z "${rest}" ]] && { printf '%s\n' "${base_dir}"; return 0; }
        [[ "${rest}" == */ && "${rest}" != "/" ]] && trailing=1

        rest="${rest#/}"
        rest="${rest%/}"

        IFS='/' read -r -a parts <<< "${rest}"

        for seg in "${parts[@]}"; do

            seg="${seg^}"
            [[ -n "${seg}" ]] || continue
            [[ -n "${out}" ]] && out+="/${seg}" || out="${seg}"

        done

        [[ -n "${out}" ]] && out="/${out}"
        (( trailing )) && out+="/"

        printf '%s\n' "${base_dir}${out}"
        return 0

    fi

    [[ "${p}" == /mnt/* || "${p}" == "/mnt" ]] || { printf '%s\n' "${p}"; return 0; }
    [[ "${p}" == */ && "${p}" != "/" ]] && trailing=1

    p="${p#/}"
    p="${p%/}"

    IFS='/' read -r -a parts <<< "${p}"

    for seg in "${parts[@]}"; do

        seg="${seg^}"
        [[ -n "${seg}" ]] || continue
        [[ -n "${out}" ]] && out+="/${seg}" || out="${seg}"

    done

    [[ -n "${out}" ]] && out="/${out}"
    (( trailing )) && out+="/"

    printf '%s\n' "${out:-/}"

}
fs_compress_type () {

    local type="${1:-}" name="${2:-}"

    case "${type,,}" in
        zip|rar|tar|7z) ;;
        tgz|gz|tar.gz)     type="tar.gz" ;;
        txz|xz|tar.xz)     type="tar.xz" ;;
        tbz2|bz2|tar.bz2)  type="tar.bz2" ;;
        tzst|zst|tar.zst)  type="tar.zst" ;;
        "")
            case "${name,,}" in
                *.tar.zst) type="tar.zst" ;;
                *.tar.gz|*.tgz) type="tar.gz" ;;
                *.tar.xz|*.txz) type="tar.xz" ;;
                *.tar.bz2|*.tbz2) type="tar.bz2" ;;
                *.tar) type="tar" ;;
                *.zip) type="zip" ;;
                *.rar) type="rar" ;;
                *.7z) type="7z" ;;
                *) type="zip" ;;
            esac
        ;;
        *) die "Unsupported archive type: ${type}" ;;
    esac

    printf '%s\n' "${type}"

}
fs_compress_name () {

    local name="${1:-}"

    name="${name%.tar.zst}"
    name="${name%.tar.gz}"
    name="${name%.tar.xz}"
    name="${name%.tar.bz2}"
    name="${name%.tgz}"
    name="${name%.txz}"
    name="${name%.tbz2}"
    name="${name%.tzst}"
    name="${name%.tar}"
    name="${name%.zip}"
    name="${name%.rar}"
    name="${name%.7z}"

    printf '%s\n' "${name}"

}
fs_compress_dest () {

    local dest="${1:-}" type="${2:-}" name="${3:-}"

    [[ -n "${dest}" ]] || dest="${PWD}/${name}.${type}"
    [[ "${dest}" == /* ]] || dest="${PWD}/${dest#./}"

    dest="${dest%.tar.zst}"
    dest="${dest%.tar.gz}"
    dest="${dest%.tar.xz}"
    dest="${dest%.tar.bz2}"
    dest="${dest%.tgz}"
    dest="${dest%.txz}"
    dest="${dest%.tbz2}"
    dest="${dest%.tzst}"
    dest="${dest%.tar}"
    dest="${dest%.zip}"
    dest="${dest%.rar}"
    dest="${dest%.7z}"
    dest="${dest}.${type}"

    run mkdir -p -- "$(dirname -- "${dest}")"
    printf '%s\n' "${dest}"

}

fs_compress_path () {

    ensure_tool mkdir dirname basename tar
    source <(parse "$@" -- src dest name type exclude:list)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"

    local -a cmd=()
    local -a ignores=()

    local dir="$(dirname -- "${src%/}")"
    local entry="$(basename -- "${src%/}")"

    name="${name:-"${entry}"}"
    type="$(fs_compress_type "${type}" "${name}")"
    name="$(fs_compress_name "${name}")"
    dest="$(fs_compress_dest "${dest}" "${type}" "${name}")"

    mapfile -t ignores < <(ignore_list)
    ignores+=( "${exclude[@]-}" )

    if [[ "${type}" == "zip" ]]; then

        ensure_tool zip

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
    if [[ "${type}" == "rar" ]]; then

        ensure_tool rar

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
    if [[ "${type}" == "7z" ]]; then

        ensure_tool 7z

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
    if [[ "${type}" == "tar.zst" ]]; then

        ensure_tool zstd

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

    if [[ "${type}" == "tar.gz" ]]; then cmd=( tar -czf "${dest}" )
    elif [[ "${type}" == "tar.xz" ]]; then cmd=( tar -cJf "${dest}" )
    elif [[ "${type}" == "tar.bz2" ]]; then cmd=( tar -cjf "${dest}" )
    elif [[ "${type}" == "tar" ]]; then cmd=( tar -cf "${dest}" )
    else die "Unsupported archive type: ${type}"
    fi

    for i in "${ignores[@]-}"; do
        [[ -n "${i}" ]] || continue
        cmd+=( --exclude "${i}" )
    done

    run "${cmd[@]}" "${kwargs[@]}" -C "${dir}" -- "${entry}"
    printf '%s\n' "${dest}"

}
fs_extract_path () {

    ensure_tool mkdir tar
    source <(parse "$@" -- :src dest strip:int)

    [[ -e "${src}" || -L "${src}" ]] || die "File not found: ${src}"
    [[ -n "${dest}" ]] || dest="${PWD}"
    [[ "${dest}" == /* ]] || dest="${PWD}/${dest#./}"

    local ext="${src,,}"
    local -a cmd=( tar )

    run mkdir -p -- "${dest}"

    if [[ "${ext}" == *.zip ]]; then

        ensure_tool unzip
        run unzip -oq "${kwargs[@]}" -- "${src}" -d "${dest}"
        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.rar ]]; then

        ensure_tool unrar
        run unrar x -o+ -y "${kwargs[@]}" "${src}" "${dest}/"
        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.7z ]]; then

        ensure_tool 7z
        run 7z x -y "${kwargs[@]}" -o"${dest}" "${src}"
        printf '%s\n' "${dest}"
        return 0

    fi
    if [[ "${ext}" == *.tar.zst || "${ext}" == *.tzst ]]; then

        ensure_tool zstd

        if tar --help 2>/dev/null | grep -q -- '--zstd'; then

            cmd+=( --zstd -xf )

            (( strip > 0 )) && cmd+=( --strip-components "${strip}" )
            run "${cmd[@]}" "${kwargs[@]}" -- "${src}" -C "${dest}"

        else

            local -a tar_cmd=( tar )

            (( strip > 0 )) && tar_cmd+=( --strip-components "${strip}" )
            tar_cmd+=( -xf - -C "${dest}" )
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

    run "${cmd[@]}" "${kwargs[@]}" "${src}" -C "${dest}"
    printf '%s\n' "${dest}"

}
fs_backup_path () {

    ensure_tool date basename
    source <(parse "$@" -- src dest name archive_dir semantic:bool=true)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"
    [[ -n "${archive_dir}" ]]  || archive_dir="${ARCHIVE_DIR:-}"

    local base_name="$(basename -- "${src%/}")" ts="$(date +'%Y-%m-%d_%H-%M-%S')"
    local dest_dir="${dest:-${base_name}}"

    [[ -n "${archive_dir}" && "${dest_dir}" != /* && "${dest_dir}" != *:* ]] && dest_dir="${archive_dir%/}/${dest_dir}"
    (( semantic )) && dest_dir="$(fs_ucfirst_path "${dest_dir}" "${archive_dir}")"

    dest="${dest_dir%/}/${name:-${ts}}"
    while [[ "${dest}" == *"//"* ]]; do dest="${dest//\/\//\/}"; done

    dest="$(fs_compress_path "${src}" "${dest}" "${name}" "${kwargs[@]}")"
    success "OK: ${src} archived at ${dest}"

}
fs_sync_path () {

    ensure_tool rsync mkdir basename
    source <(parse "$@" -- src dest sync_dir force:bool=true ignore:bool=true semantic:bool=true exclude:list)

    [[ -z "${src}" || "${src}" == "." || "${src}" == ".." ]] && src="${PWD}"
    [[ -e "${src}" || -L "${src}" ]] || die "Path not found: ${src}"
    [[ -n "${sync_dir}" ]] || sync_dir="${SYNC_DIR:-}"

    local rel="$(basename -- "${src%/}")"

    if [[ -z "${dest}" && -n "${sync_dir}" ]]; then dest="${sync_dir%/}/${rel}"
    elif [[ -z "${dest}" ]]; then dest="${rel}"
    fi

    (( semantic )) && dest="$(fs_ucfirst_path "${dest}" "${sync_dir}")"
    while [[ "${dest}" == *"//"* ]]; do dest="${dest//\/\//\/}"; done

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

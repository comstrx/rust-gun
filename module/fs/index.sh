
cmd_new_dir () {

    source <(parse "$@" -- :src mode)
    fs_new_dir "${src}" "${mode}" "${kwargs[@]}"

}
cmd_new_file () {

    source <(parse "$@" -- :src mode)
    fs_new_file "${src}" "${mode}" "${kwargs[@]}"

}
cmd_path_type () {

    source <(parse "$@" -- :src)
    fs_path_exists "${src}" && fs_path_type "${src}" "${kwargs[@]}"

}
cmd_file_type () {

    source <(parse "$@" -- :src)
    fs_file_exists "${src}" && fs_file_type "${src}" "${kwargs[@]}"

}
cmd_copy () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_copy_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_move () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_move_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_remove () {

    source <(parse "$@" -- :src)
    fs_path_exists "${src}" && fs_remove_path "${src}" "${kwargs[@]}"

}
cmd_trash () {

    source <(parse "$@" -- :src trash_dir)
    fs_path_exists "${src}" && fs_trash_path "${src}" "${trash_dir}" "${kwargs[@]}"

}
cmd_clear () {

    source <(parse "$@" -- :src)

    fs_dir_exists "${src}" && fs_remove_path "${src}" true "${kwargs[@]}"
    fs_file_exists "${src}" && : > "${src}"

}
cmd_link () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_link_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_stats () {

    source <(parse "$@" -- :src)
    fs_path_exists "${src}" && fs_stats_path "${src}" "${kwargs[@]}"

}
cmd_diff () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_diff_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_synced () {

    source <(parse "$@" -- :src :dest)
    fs_path_exists "${src}" && fs_synced_path "${src}" "${dest}" "${kwargs[@]}"

}
cmd_compress () {

    source <(parse "$@" -- src)
    fs_path_exists "${src:-${PWD}}" && fs_compress_path "${src}" "${kwargs[@]}"

}
cmd_backup () {

    source <(parse "$@" -- src)
    fs_path_exists "${src:-${PWD}}" && fs_backup_path "${src}" "${kwargs[@]}"

}
cmd_sync () {

    source <(parse "$@" -- src)
    fs_path_exists "${src:-${PWD}}" && fs_sync_path "${src}" "${kwargs[@]}"

}

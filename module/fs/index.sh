
cmd_fs_help () {

    info_ln "Files :"

    printf '    %s\n' \
        "" \
        "is-dir                     * Check if path is directory" \
        "is-file                    * Check if path is file" \
        "new-dir                    * Create a new directory" \
        "new-file                   * Create a new file" \
        "" \
        "path-exists                * Check if path is exists" \
        "path-type                  * Print path type if the path exists" \
        "file-type                  * Print file type if the file exists" \
        "" \
        "copy-path                  * Copy file or directory to destination" \
        "move-path                  * Move file or directory to destination" \
        "clear-path                 * Clear directory contents or truncate file" \
        "trash-path                 * Move file or directory to trash" \
        "remove-path                * Remove file or directory" \
        "link-path                  * Create symlink for file or directory" \
        "" \
        "path-stats                 * Show file or directory statistics" \
        "path-diff                  * Show diff between source and destination" \
        "path-synced                * Check whether source and destination are synced" \
        "" \
        "compress                   * Compress file or directory" \
        "extract                    * Extract archive to destination" \
        "backup                     * Create backup for file or directory" \
        "sync                       * Sync file or directory to target" \
        ''

}

cmd_is_dir () {

    fs_dir_exists "$@"

}
cmd_is_file () {

    fs_file_exists "$@"

}
cmd_new_dir () {

    fs_new_dir "$@"

}
cmd_new_file () {

    fs_new_file "$@"

}

cmd_path_exists () {

    fs_path_exists "$@"

}
cmd_path_type () {

    fs_path_type "$@"

}
cmd_file_type () {

    fs_file_type "$@"

}

cmd_copy_path () {

    fs_copy_path "$@"

}
cmd_move_path () {

    fs_move_path "$@"

}
cmd_clear_path () {

    fs_remove_path "$@" --clear

}
cmd_trash_path () {

    fs_trash_path "$@"

}
cmd_remove_path () {

    fs_remove_path "$@"

}
cmd_link_path () {

    fs_link_path "$@"

}

cmd_path_stats () {

    fs_stats_path "$@"

}
cmd_path_diff () {

    fs_diff_path "$@"

}
cmd_path_synced () {

    fs_synced_path "$@"

}

cmd_compress () {

    fs_compress_path "$@"

}
cmd_extract () {

    fs_extract_path "$@"

}
cmd_backup () {

    fs_backup_path "$@"

}
cmd_sync () {

    fs_sync_path "$@"

}

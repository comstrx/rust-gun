
build_header () {

    local file="${1:-}"

    mkdir -p -- "$(dirname -- "${file}")" || return 1
    rm -f -- "${file}"

    {
        printf '#!/usr/bin/env bash\n'
        printf 'set -Eeuo pipefail\n\n'

        printf '# ===== ENV: =====\n'
        cat -- "entry/env.sh"
    } > "${file}" || return 1

}
build_content () {

    local file="${1:-}"

    {
        find core ensure module \
            -type f -name '*.sh' \
            ! -path '*/arch.sh' \
            ! -path '*/stack/*' \
            ! -path '*/play/*' \
            -print0 |
        sort -z |
        while IFS= read -r -d '' f; do
            printf '\n# ===== FILE: %s =====\n' "${f#./}"
            cat -- "${f}"
        done
    } >> "${file}"

}
build_footer () {

    local file="${1:-}"

    {
        printf '\n# ===== ENTRY: =====\n'
        cat -- "entry/load.sh"
        printf '\nensure_bash "$@"\n'
        printf 'load_run "$@"\n'
        printf 'exit 0\n'
    } >> "${file}"

}
build_template () {

    local file="${1:-}"

    {
        printf '\n# ===== TEMPLATE: =====\n'
        printf '\n%s\n' "${TEMPLATE_KEY}"
        tar -czf - -C "$(dirname -- "${TEMPLATE_DIR}")" "$(basename -- "${TEMPLATE_DIR}")"
    } >> "${file}"

}
build () {

    local out="${1:-run}"
    [[ "${out}" == *.sh ]] || out="${out}.sh"

    build_header   "${out}"
    build_content  "${out}"
    build_footer   "${out}"
    build_template "${out}"

    chmod +x "${out}"
    printf '%s\n' "✅ Successfully built at -> ${out}"

}


build_content () {

    local file="${1:-}"

    {
        printf '#!/usr/bin/env bash\n'
        printf 'set -Eeuo pipefail\n'

        cat -- "entry/base.sh"

        find core ensure module -type f -name '*.sh' ! -path '*/arch.sh' -print0 | sort -z | while IFS= read -r -d '' f; do cat -- "${f}"; done

        cat -- "entry/install.sh"
        cat -- "entry/load.sh"

        printf '\nensure_bash "$@"\n'
        printf 'load "$@"\n'
        printf 'exit 0\n'

        printf '\n%s\n' "${TEMPLATE_PAYLOAD_KEY}"
        tar -czf - -C "$(dirname -- "${TEMPLATE_DIR}")" "$(basename -- "${TEMPLATE_DIR}")"
    } > "${file}"

}
build () {

    local out="${1:-}"

    [[ -n "${out}" ]] || out="release/${APP_NAME:-run}.sh"
    [[ "${out}" == *.sh ]] || out="${out}.sh"

    mkdir -p -- "$(dirname -- "${out}")"
    build_content "${out}"

    chmod +x "${out}"
    printf '%s\n' "✅ Successfully built at -> ${out}"

}


cmd_safety_help () {

    info_ln "Safety :\n"

    printf '    %s\n' \
        "leaks                      * Remove trailing whitespace in git-tracked files" \
        "sbom                       * Remove trailing whitespace in git-tracked files" \
        "trivy                      * Remove trailing whitespace in git-tracked files" \
        ''

}

cmd_leaks () {

    ensure gitleaks
    source <(parse "$@" -- mode format target out config baseline redact=100 fail:bool=true)

    out="${out:-/dev/stdout}"

    local exit_code="0"; (( fail )) && exit_code="1"
    local -a cmd=()

    config="${config:-"$(config_file gitleaks toml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    [[ -n "${baseline}" ]] && cmd+=( --baseline-path "${baseline}" )
    [[ -n "${redact}" ]] && cmd+=( --redact="${redact}" )

    [[ -n "${mode}" ]] || { is_ci && mode="git" || mode="dir"; }
    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"

    run gitleaks "${mode}" --no-banner --report-path "${out}" --report-format "${format:-json}" \
        --exit-code "${exit_code}" "${cmd[@]}" "${kwargs[@]}" -- "${target:-.}"

}
cmd_sbom () {

    ensure syft
    source <(parse "$@" -- src format out config)

    format="${format:-cyclonedx-json}"
    out="${out:-${OUT_DIR:-out}/sbom.json}"

    local -a cmd=()

    config="${config:-"$(config_file syft yaml yml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )
    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"
    run syft scan -o "${format}=${out}" "${cmd[@]}" "${kwargs[@]}" -- "${src:-dir:.}"

}
cmd_trivy () {

    ensure trivy
    source <(parse "$@" -- mode format target out scanners severity config no_progress:bool=true ignore_unfixed:bool=true fail:bool=true)

    out="${out:-/dev/stdout}"
    scanners="${scanners:-vuln,secret,misconfig,license}"
    severity="${severity:-CRITICAL,HIGH}"

    local exit_code="0"; (( fail )) && exit_code="1"
    local -a cmd=()

    config="${config:-"$(config_file trivy yaml yml)"}"
    [[ -f "${config}" ]] && cmd+=( --config "${config}" )

    [[ -n "${severity}" ]] && cmd+=( --severity "${severity}" )
    [[ -n "${scanners}" ]] && cmd+=( --scanners "${scanners}" )

    [[ "${out}" != "/dev/stdout" && "${out}" == */* ]] && ensure_dir "${out%/*}"

    (( no_progress )) && cmd+=( --no-progress )
    (( ignore_unfixed )) && [[ "${scanners}" == *vuln* ]] && cmd+=( --ignore-unfixed )

    run trivy "${mode:-fs}" --output "${out}" --format "${format:-table}" \
        --exit-code "${exit_code}" "${cmd[@]}" "${kwargs[@]}" "${target:-.}"

}

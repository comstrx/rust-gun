
cmd_perf_help () {

    info_ln "Safety :\n"

    printf '    %s\n' \
        "semver                     * Semver via cargo llvm-cov (lcov/codecov)" \
        "coverage                   * Coverage via cargo llvm-cov (lcov/codecov)" \
        "" \
        "bloat                      * Check bloat for (binary size)" \
        "udeps                      * Detect unused dependencies (cargo udeps)" \
        "hack                       * Feature-matrix checks (cargo hack)" \
        "" \
        "fuzz                       * Fuzz targets (cargo fuzz) with sane defaults" \
        "miri                       * Miri interpreter checks (UB / unsafe issues)" \
        "sanitizer                  * Sanitizers pipeline (asan/tsan/msan/lsan) for UB detection" \
        "" \
        "samply                     * CPU profiling via samply (Firefox Profiler UI) for one target" \
        "samply-load                * Load saved samply profile (default: profiles/samply.json)" \
        "" \
        "flame                      * CPU flamegraph via cargo flamegraph (output: SVG)" \
        "flame-open                 * Open saved flamegraph SVG (default: profiles/flamegraph.svg)" \
        ''

}

semver_baseline () {

    local baseline="${1:-}" remote="${2:-origin}" def="" base=""

    [[ -n "${baseline}" ]] && { printf '%s' "${baseline}"; return 0; }
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

    if is_ci_pull; then

        base="${GITHUB_BASE_REF:-}"
        [[ -n "${base}" ]] || die "semver: missing GITHUB_BASE_REF (or pass --base <rev>)"

        git show-ref --verify --quiet "refs/remotes/${remote}/${base}" 2>/dev/null || \
            run git fetch --no-tags "${remote}" "${base}:refs/remotes/${remote}/${base}" >/dev/null 2>&1 || \
                die "semver: git fetch failed"

        printf '%s' "${remote}/${base}"
        return 0

    fi

    def="$(git symbolic-ref -q "refs/remotes/${remote}/HEAD" 2>/dev/null || true)"
    def="${def#refs/remotes/"${remote}"/}"
    [[ -n "${def}" ]] || def="main"

    git show-ref --verify --quiet "refs/remotes/${remote}/${def}" 2>/dev/null || \
        run git fetch --no-tags "${remote}" "${def}:refs/remotes/${remote}/${def}" >/dev/null 2>&1 || true

    git show-ref --verify --quiet "refs/remotes/${remote}/${def}" 2>/dev/null || return 0
    printf '%s' "${remote}/${def}"

}
cmd_semver () {

    ensure cargo cargo-semver-checks
    source <(parse "$@" -- base remote)

    local baseline="$(semver_baseline "${base}" "${remote}")"
    [[ -n "${baseline}" ]] || die "semver: cannot detect baseline"

    run cargo semver-checks check-release --baseline-rev "${base}" "${kwargs[@]}"

}

cov_upload_out () {

    ensure curl chmod mv mkdir
    source <(parse "$@" -- mode name version token flags out)

    [[ -n "${flags}" ]] || flags="${name}"
    [[ -n "${name}"  ]] || name="coverage-rust-${GITHUB_RUN_ID:-local}"

    [[ -n "${version}" ]] || version="latest"
    [[ -n "${version}" && "${version}" != "latest" && "${version}" != v* ]] && version="v${version}"
    [[ -n "${out}" ]] || out="lcov.info"

    [[ -n "${token}" ]] || token="${CODECOV_TOKEN:-}"
    [[ -n "${token}" ]] || die "codecov: CODECOV_TOKEN is missing."

    [[ -f "${out}" ]] || die "codecov: file not found: ${out}"

    local os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    local arch="$(uname -m)" dist="linux"

    if [[ "${os}" == "darwin" ]]; then dist="macos"; fi
    if [[ "${dist}" == "linux" && ( "${arch}" == "aarch64" || "${arch}" == "arm64" ) ]]; then dist="linux-arm64"; fi

    local cache_dir="${TMPDIR:-/tmp}/.codecov/cache" resolved="${version}"
    local bin="${cache_dir}/codecov-${dist}-${resolved}"

    mkdir -p -- "${cache_dir}"

    if [[ "${version}" == "latest" ]]; then

        local latest_page="$(curl -fsSL "https://cli.codecov.io/${dist}/latest" 2>/dev/null || true)"
        local v="$(printf '%s\n' "${latest_page}" | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"

        [[ -n "${v}" ]] && resolved="${v}"
        bin="${cache_dir}/codecov-${dist}-${resolved}"

    fi
    if [[ ! -x "${bin}" ]]; then

        local url_a="https://cli.codecov.io/${dist}/${resolved}/codecov"
        local url_b="https://cli.codecov.io/${resolved}/${dist}/codecov"
        local sha_a="https://cli.codecov.io/${dist}/${resolved}/codecov.SHA256SUM"
        local sha_b="https://cli.codecov.io/${resolved}/${dist}/codecov.SHA256SUM"
        local sig_a="https://cli.codecov.io/${dist}/${resolved}/codecov.SHA256SUM.sig"
        local sig_b="https://cli.codecov.io/${resolved}/${dist}/codecov.SHA256SUM.sig"

        local tmp_dir="$(mktemp -d "${cache_dir}/codecov.tmp.XXXXXX" 2>/dev/null || true)"

        if [[ -z "${tmp_dir}" || ! -d "${tmp_dir}" ]]; then
            tmp_dir="${cache_dir}/codecov.tmp.$$"
            mkdir -p -- "${tmp_dir}" || die "Codecov: failed to create temp dir."
        fi

        local tmp_bin="${tmp_dir}/codecov"
        local tmp_sha="${tmp_dir}/codecov.SHA256SUM"
        local tmp_sig="${tmp_dir}/codecov.SHA256SUM.sig"

        trap 'rm -rf -- "${tmp_dir:-}" 2>/dev/null || true; trap - RETURN' RETURN
        rm -f -- "${tmp_bin}" "${tmp_sha}" "${tmp_sig}" 2>/dev/null || true

        run curl -fsSL -o "${tmp_bin}" "${url_a}" || run curl -fsSL -o "${tmp_bin}" "${url_b}"
        run curl -fsSL -o "${tmp_sha}" "${sha_a}" || run curl -fsSL -o "${tmp_sha}" "${sha_b}"

        curl -fsSL -o "${tmp_sig}" "${sig_a}" 2>/dev/null || curl -fsSL -o "${tmp_sig}" "${sig_b}" 2>/dev/null || rm -f -- "${tmp_sig}" 2>/dev/null || true

        if [[ -f "${tmp_sig}" ]] && has gpg; then

            local keyring="${tmp_dir}/trustedkeys.gpg"
            local keyfile="${tmp_dir}/codecov.pgp.asc"
            local want_fp="27034E7FDB850E0BBC2C62FF806BB28AED779869"

            run curl -fsSL -o "${keyfile}" "https://keybase.io/codecovsecurity/pgp_keys.asc"
            gpg --no-default-keyring --keyring "${keyring}" --import "${keyfile}" >/dev/null 2>&1 || true

            local got_fp="$(gpg --no-default-keyring --keyring "${keyring}" --fingerprint --with-colons 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}' || true)"

            [[ -n "${got_fp}" ]] || die "Codecov: cannot read PGP fingerprint."
            [[ "${got_fp}" == "${want_fp}" ]] || die "Codecov: PGP fingerprint mismatch."

            gpg --no-default-keyring --keyring "${keyring}" --verify "${tmp_sig}" "${tmp_sha}" >/dev/null 2>&1 || die "Codecov: SHA256SUM signature verification failed."

        fi

        local got="" want="$(awk '$2 ~ /(^|\/)codecov$/ { print $1; exit }' "${tmp_sha}" 2>/dev/null || true)"
        [[ -n "${want}" ]] || die "Codecov: invalid SHA256SUM file."

        if has sha256sum; then got="$(sha256sum "${tmp_bin}" 2>/dev/null | awk '{print $1}' || true)"
        elif has shasum; then got="$(shasum -a 256 "${tmp_bin}" 2>/dev/null | awk '{print $1}' || true)"
        elif has openssl; then got="$(openssl dgst -sha256 "${tmp_bin}" 2>/dev/null | awk '{print $NF}' || true)"
        else die "Codecov: no SHA256 tool found (need sha256sum or shasum or openssl)."
        fi

        [[ -n "${got}" ]] || die "Codecov: failed to compute checksum."
        [[ "${got}" == "${want}" ]] || die "Codecov: checksum mismatch."

        run chmod +x "${tmp_bin}"
        run mv -f -- "${tmp_bin}" "${bin}"
        run "${bin}" --version >/dev/null 2>&1

    fi

    export CODECOV_TOKEN="${token}"
    local -a args=( --verbose upload-process --disable-search --fail-on-error -f "${out}" )

    [[ -n "${flags}" ]] && args+=( -F "${flags}" )
    [[ -n "${name}"  ]] && args+=( -n "${name}" )

    run "${bin}" "${args[@]}"
    success "Ok: Codecov file uploaded."

}
cmd_coverage () {

    ensure cargo cargo-llvm-cov
    source <(parse "$@" -- name version flags token out mode=lcov upload:bool)

    local -a args=( --exclude bloats --exclude fuzz --"${mode}" )

    out="${out:-"${OUT_DIR:-out}/lcov.info"}"
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"
    [[ -f "${out}" ]] || : > "${out}"

    run cargo llvm-cov clean --workspace
    run cargo llvm-cov --workspace --all-targets --all-features "${args[@]}" --output-path "${out}" --remap-path-prefix "${kwargs[@]}"

    success "Ok: coverage processed -> ${out}"
    (( upload )) && cov_upload_out "${mode}" "${name}" "${version}" "${token}" "${flags}" "${out}"

}

cmd_bloat () {

    source <(parse "$@" -- package:list out="profiles/bloat.info" max_size=10MB all:bool release:bool=true)

    local -a pkgs=()

    if [[ ${#package[@]} -gt 0 ]]; then pkgs=( "${package[@]}" ); ensure_workspace_pkg "${pkgs[@]}"
    elif (( all )); then mapfile -t pkgs < <(workspace_pkgs)
    else mapfile -t pkgs < <(publishable_pkgs)
    fi

    [[ ${#pkgs[@]} -gt 0 ]] || die "bloat: no packages selected" 2
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"
    : > "${out}"

    printf '\n%s\n' "---------------------------------------" >> "${out}"
    printf '%s' "- Bloats Report: " >> "${out}"

    [[ -n "${max_size}" ]] && printf '%s' " Max-Size ( ${max_size} )" >> "${out}"

    printf '\n%s\n' "- Version: $(cmd_version)" >> "${out}"
    printf '%s\n\n' "---------------------------------------" >> "${out}"

    local meta="$(run_cargo metadata --no-deps --format-version 1 2>/dev/null)" || die "bloat: failed to get metadata" 2
    local target_dir="$(jq -r '.target_directory' <<<"${meta}" 2>/dev/null || true)"
    [[ -n "${target_dir}" ]] || die "bloat: failed to read target_directory" 2

    local mod="debug" flag="--dev"
    (( release )) && { mod="release"; flag="--release"; }

    local exe="" pkg="" out_text="" i=1
    [[ "$(os_name)" == "windows" ]] && exe=".exe"

    for pkg in "${pkgs[@]}"; do

        printf '%s\n' "Analysing : ${pkg} ..."

        printf '%d) %s:\n\n' "${i}" "${pkg}" >> "${out}"
        (( i++ ))

        local -a bins=()
        mapfile -t bins < <(jq -r --arg n "${pkg}" '.packages[] | select(.name == $n) | .targets[] | select(.kind | index("bin")) | .name' <<<"${meta}")

        if (( ${#bins[@]} > 0 )); then

            local x="" bin_name="${bins[0]}"
            for x in "${bins[@]}"; do [[ "${x}" == "${pkg}" ]] && { bin_name="${x}"; break; }; done

            local bin_path="${target_dir}/${mod}/${bin_name}${exe}"

            if out_text="$(NO_COLOR=1 CARGO_TERM_COLOR=never run_cargo bloat -p "${pkg}" --bin "${bin_name}" "${flag}" "${kwargs[@]}" 2>&1)"; then

                awk '{ sub(/\r$/, "") } !on && /^[[:space:]]*File[[:space:]]/ { on=1 } on { print }' <<<"${out_text}" >> "${out}"
                printf '\n' >> "${out}"

                [[ -n "${max_size}" ]] && check_max_size "${bin_path}" "${max_size}" || true

            else

                printf 'ERROR: %s\n\n' "can't resolve ${bin_path}" >> "${out}"

            fi

        else

            local bin_name="bloat-${pkg}"

            if out_text="$(NO_COLOR=1 CARGO_TERM_COLOR=never run_cargo bloat -p bloats --bin "${bin_name}" --features "bloat-${pkg}" "${flag}" "${kwargs[@]}" 2>&1)"; then

                local bin_path="${target_dir}/${mod}/${bin_name}${exe}"

                awk '{ sub(/\r$/, "") } !on && /^[[:space:]]*File[[:space:]]/ { on=1 } on { print }' <<<"${out_text}" >> "${out}"
                printf '\n' >> "${out}"

                [[ -n "${max_size}" ]] && check_max_size "${bin_path}" "${max_size}" || true

            elif out_text="$(NO_COLOR=1 CARGO_TERM_COLOR=never run_cargo bloat -p bloats --bin "${pkg}" --features "bloat-${pkg}" "${flag}" "${kwargs[@]}" 2>&1)"; then

                bin_name="${pkg}"
                local bin_path="${target_dir}/${mod}/${bin_name}${exe}"

                awk '{ sub(/\r$/, "") } !on && /^[[:space:]]*File[[:space:]]/ { on=1 } on { print }' <<<"${out_text}" >> "${out}"
                printf '\n' >> "${out}"

                [[ -n "${max_size}" ]] && check_max_size "${bin_path}" "${max_size}" || true

            else

                printf 'ERROR: cargo bloat failed for %s (via bloats)\n%s\n\n' "${pkg}" "${out_text}" >> "${out}"

            fi


        fi

    done

    success "Analysed: out file -> ${out}"

}
cmd_udeps () {

    run_cargo udeps --nightly --all-targets "$@"

}
cmd_hack () {

    source <(parse "$@" -- depth:int=2 each_feature:bool)

    if (( each_feature )); then
        run_cargo hack check --keep-going --each-feature "${kwargs[@]}"
        return 0
    fi

    run_cargo hack check --keep-going --feature-powerset --depth "${depth}" "${kwargs[@]}"

}

cmd_fuzz () {

    source <(parse "$@" -- timeout:int=10 len:int=4096 have_max_total_time:bool have_max_len:bool in_post:bool)

    local -a pre=() post=()

    while [[ $# -gt 0 ]]; do

        if [[ "$1" == "--" ]]; then
            in_post=1
            shift || true
            continue
        fi
        if (( in_post )); then
            case "$1" in
                -max_total_time|-max_total_time=*) have_max_total_time=1 ;;
                -max_len|-max_len=*) have_max_len=1 ;;
            esac
            post+=( "$1" )
            shift || true
            continue
        fi
        case "$1" in
            --timeout) shift || true; [[ $# -gt 0 ]] || die "Missing value for --timeout" 2; timeout="$1"; shift || true ;;
            --timeout=*) timeout="${1#*=}"; shift || true ;;
            --len) shift || true; [[ $# -gt 0 ]] || die "Missing value for --len" 2; len="$1"; shift || true ;;
            --len=*) len="${1#*=}"; shift || true ;;
            -max_total_time|-max_total_time=*) have_max_total_time=1; post+=( "$1" ); shift || true ;;
            -max_len|-max_len=*) have_max_len=1; post+=( "$1" ); shift || true ;;
            *) pre+=( "$1" ); shift || true ;;
        esac

    done

    if [[ -z "${CARGO_BUILD_TARGET:-}" ]] || [[ "${CARGO_BUILD_TARGET:-}" == *-musl ]]; then

        pre+=( "--target" "x86_64-unknown-linux-gnu" )

    fi
    if [[ "${#pre[@]}" -eq 0 ]] || [[ "${pre[0]-}" == -* ]]; then

        (( have_max_total_time )) || [[ "${timeout}" == "0" ]] || post+=( "-max_total_time=${timeout}" )
        (( have_max_len )) || [[ "${len}" == "0" ]] || post+=( "-max_len=${len}" )

        local -a targets=()
        local t=""

        while IFS= read -r line; do
            [[ -n "${line}" ]] || continue
            targets+=( "${line}" )
        done < <(run_cargo fuzz --nightly list 2>/dev/null || true)

        [[ "${#targets[@]}" -gt 0 ]] || die "No fuzz targets found. Run: cargo fuzz init && cargo fuzz add <name>" 2

        for t in "${targets[@]}"; do

            if [[ "${#post[@]}" -gt 0 ]]; then run_cargo fuzz --nightly run "${t}" "${pre[@]}" -- "${post[@]}" || die "Fuzzing failed: ${t}" 2
            else run_cargo fuzz --nightly run "${t}" "${pre[@]}" || die "Fuzzing failed: ${t}" 2
            fi

        done

        return 0

    fi
    if [[ "${#pre[@]}" -gt 0 ]]; then

        case "${pre[0]}" in
            run|list|init|add|clean|cmin|tmin|coverage|fmt) ;;
            *) pre=( "run" "${pre[@]}" ) ;;
        esac

    fi
    if [[ "${pre[0]}" == "run" ]]; then

        (( have_max_total_time )) || [[ "${timeout}" == "0" ]] || post+=( "-max_total_time=${timeout}" )
        (( have_max_len )) || [[ "${len}" == "0" ]] || post+=( "-max_len=${len}" )

    fi
    if [[ "${#post[@]}" -gt 0 ]]; then

        run_cargo fuzz --nightly "${pre[@]}" -- "${post[@]}"
        return $?

    fi

    run_cargo fuzz --nightly "${pre[@]}"

}
cmd_miri () {

    source <(parse "$@" -- command=test :target=auto clean:bool setup:bool=1)

    local target="${target}" tc="$(nightly_version)"
    local target_dir="target/miri"

    if [[ -z "${target}" || "${target}" == "auto" ]]; then

        local vv="$(rustc +"${tc}" -vV 2>/dev/null)" || die "miri: failed to read rustc -vV for ${tc}" 2
        target="$(awk '/^host: / { print $2; exit }' <<< "${vv}")"
        [[ -n "${target}" ]] || die "miri: failed to detect host target." 2

    fi

    (( clean )) && { CARGO_TARGET_DIR="${target_dir}" run_cargo clean --nightly --target "${target}" >/dev/null 2>&1 || true; }
    (( setup )) && { CARGO_TARGET_DIR="${target_dir}" run_cargo miri --nightly setup >/dev/null 2>&1 || true; }

    CARGO_TARGET_DIR="${target_dir}" CARGO_INCREMENTAL=0 run_cargo miri --nightly "${command}" --target "${target}" "${kwargs[@]}"

}
cmd_sanitizer () {

    source <(parse "$@" -- :sanitizer=asan command=test :target=auto clean:bool=0 track_origins:bool=1)

    local target="${target}" san="${sanitizer}" zsan="" opt="" tc="$(nightly_version)"
    local -a extra=()

    case "${san}" in
        asan|address)      san="asan"  ; zsan="address" ;;
        tsan|thread)       san="tsan"  ; zsan="thread" ;;
        lsan|leak)         san="lsan"  ; zsan="leak" ;;
        msan|memory)
            san="msan"
            zsan="memory"
            (( track_origins )) && extra+=( "-Zsanitizer-memory-track-origins" )
        ;;
        *) die "sanitizer: unknown sanitizer '${sanitizer}' (use: asan|tsan|msan|lsan)" 2 ;;
    esac

    if [[ -z "${target}" || "${target}" == "auto" ]]; then

        local vv="$(rustc +"${tc}" -vV 2>/dev/null)" || die "sanitizer: failed to read rustc -vV for ${tc}" 2
        target="$(awk '/^host: / { print $2; exit }' <<< "${vv}")"
        [[ -n "${target}" ]] || die "sanitizer: failed to detect host target." 2

    fi

    local target_dir="target/sanitizers/${san}"
    local rf="${RUSTFLAGS:-}"
    local rdf="${RUSTDOCFLAGS:-}"

    [[ -n "${rf}" ]] && rf+=" "
    [[ -n "${rdf}" ]] && rdf+=" "

    rf+="-Zsanitizer=${zsan} -Cforce-frame-pointers=yes -Cdebuginfo=1"
    rdf+="-Zsanitizer=${zsan} -Cforce-frame-pointers=yes -Cdebuginfo=1"

    for opt in "${extra[@]}"; do
        rf+=" ${opt}"
        rdf+=" ${opt}"
    done

    (( clean )) && { CARGO_TARGET_DIR="${target_dir}" run_cargo clean --nightly --target "${target}" >/dev/null 2>&1 || true; }
    log "=> sanitizer: ${san} (-Zsanitizer=${zsan}) target=${target} command=${command} \n"

    CARGO_TARGET_DIR="${target_dir}" \
        CARGO_INCREMENTAL=0 \
        RUSTFLAGS="${rf}" \
        RUSTDOCFLAGS="${rdf}" \
        run_cargo "${command}" --nightly -Zbuild-std=std --target "${target}" "${kwargs[@]}"

}

cmd_samply () {

    ensure samply
    set_perf_paranoid

    source <(parse "$@" -- \
        bin test bench example toolchain out="profiles/samply.json" nightly:bool stable:bool msrv:bool save_only:bool \
        rate address duration package:list \
    )

    [[ -z "${bin}"  || -z "${example}" ]] || die "samply: use only one of --bin or --example" 2
    [[ -z "${bench}" || -z "${test}"   ]] || die "samply: use only one of --bench or --test" 2
    [[ -z "${bench}${example}"         ]] || die "samply: use only one of --bench or --example" 2

    local -a args=( samply record )
    local -a cargo=( cargo )
    local -a pkgs=()
    local -A seen=()
    local p=""

    (( stable  )) && toolchain="stable"
    (( nightly )) && toolchain="nightly"
    (( msrv    )) && toolchain="msrv"

    if [[ "${toolchain}" == "stable" ]]; then cargo+=( +"$(stable_version)" )
    elif [[ "${toolchain}" == "nightly" ]]; then cargo+=( +"$(nightly_version)" )
    elif [[ "${toolchain}" == "msrv" ]]; then cargo+=( +"$(msrv_version)" )
    elif [[ -n "${toolchain}" ]]; then cargo+=( +"${toolchain}" )
    fi

    if [[ -n "${bench}" ]]; then cargo+=( bench --bench "${bench}" )
    elif [[ -n "${example}" ]]; then cargo+=( run --example "${example}" )
    elif [[ -n "${test}" ]]; then cargo+=( test --test "${test}" )
    else cargo+=( run ); [[ -n "${bin}" ]] && cargo+=( --bin "${bin}" )
    fi

    for p in "${package[@]-}"; do

        [[ -n "${p}" ]] || continue
        [[ -n "${seen[${p}]-}" ]] && continue

        seen["${p}"]=1
        pkgs+=( -p "${p}" )

    done

    (( ${#seen[@]} <= 1 )) || die "samply: --package supports at most one package" 2

    (( save_only )) && args+=( --save-only )

    [[ -n "${rate}"  ]] && args+=( --rate "${rate}" )
    [[ -n "${address}"  ]] && args+=( --address "${address}" )
    [[ -n "${duration}"  ]] && args+=( --duration "${duration}" )

    [[ -n "${out}"  ]] && args+=( -o "${out}" )
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"
    : > "${out}"

    CARGO_PROFILE_RELEASE_DEBUG=true \
        RUSTFLAGS="${RUSTFLAGS:-} -C force-frame-pointers=yes -g" \
        run "${args[@]}" -- "${cargo[@]}" "${pkgs[@]}" "${kwargs[@]}"

}
cmd_samply_load () {

    ensure samply
    source <(parse "$@" -- :file="profiles/samply.json")

    [[ -f "${file}" ]] || die "file not found: ${file}" 2
    run samply load "${file}"

}

cmd_flame () {

    ensure flamegraph
    set_perf_flame

    source <(parse "$@" -- \
        bin test bench example toolchain out="profiles/flamegraph.svg" nightly:bool stable:bool msrv:bool package:list \
    )

    [[ -z "${bin}"  || -z "${example}" ]] || die "flame: use only one of --bin or --example" 2
    [[ -z "${bench}" || -z "${test}"   ]] || die "flame: use only one of --bench or --test" 2
    [[ -z "${bench}${example}"         ]] || die "flame: use only one of --bench or --example" 2

    local -a cargo=( cargo )
    local -a args=( flamegraph )
    local -a pkgs=()
    local -A seen=()
    local p=""

    (( stable  )) && toolchain="stable"
    (( nightly )) && toolchain="nightly"
    (( msrv    )) && toolchain="msrv"

    if [[ "${toolchain}" == "stable" ]]; then cargo+=( +"$(stable_version)" )
    elif [[ "${toolchain}" == "nightly" ]]; then cargo+=( +"$(nightly_version)" )
    elif [[ "${toolchain}" == "msrv" ]]; then cargo+=( +"$(msrv_version)" )
    elif [[ -n "${toolchain}" ]]; then cargo+=( +"${toolchain}" )
    fi

    if [[ -n "${bench}" ]]; then args+=( --bench "${bench}" )
    elif [[ -n "${example}" ]]; then args+=( --example "${example}" )
    elif [[ -n "${test}" ]]; then args+=( --test "${test}" )
    else [[ -n "${bin}" ]] && args+=( --bin "${bin}" )
    fi

    for p in "${package[@]-}"; do

        [[ -n "${p}" ]] || continue
        [[ -n "${seen[${p}]-}" ]] && continue

        seen["${p}"]=1
        pkgs+=( -p "${p}" )

    done

    (( ${#seen[@]} <= 1 )) || die "flame: --package supports at most one package" 2

    [[ -n "${out}"  ]] && args+=( -o "${out}" )
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"
    : > "${out}"

    CARGO_PROFILE_RELEASE_DEBUG=true \
        RUSTFLAGS="${RUSTFLAGS:-} -C force-frame-pointers=yes -g" \
        run "${cargo[@]}" "${args[@]}" "${pkgs[@]}" "${kwargs[@]}"

}
cmd_flame_open () {

    ensure flamegraph
    source <(parse "$@" -- :file="profiles/flamegraph.svg")

    [[ -f "${file}" ]] || die "file not found: ${file}" 2
    open_path "${file}"

}

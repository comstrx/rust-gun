
cmd_cinema_help () {

    info_ln "Guide :"

    printf '    %s\n' \
        "" \
        "play                       * Guided tour: boot a demo workspace and showcase commands" \
        "extract-gif                * Extract GIF(s) from video in high quality with support for start/duration/fps/width/loop." \
        ''

}
cmd_extract_gif () {

    ensure_tool ffmpeg
    source <(parse "$@" -- :path out :start="00:00:00" :duration:float=60 :fps:float=20 :width:int=720 :speed:float=1 :quality=normal loop:bool)

    [[ -f "${path}" ]] || die "extract-gif: file not found: ${path}" 2
    [[ -n "${out}" ]] || out="${path%.*}.gif"

    local inv="$(awk -v s="${speed}" 'BEGIN{ if (s <= 0) s = 1; printf "%.10f", 1/s }')"
    local vf="" ff_loop="-1"

    (( loop )) && ff_loop="0"

    case "${quality}" in
        high) vf="setpts=${inv}*PTS,fps=${fps},scale=${width}:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=full[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" ;;
        *) vf="setpts=${inv}*PTS,fps=${fps},scale=${width}:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" ;;
    esac

    ffmpeg -hide_banner -loglevel error -nostdin -y -ss "${start}" -t "${duration}" -i "${path}" -vf "${vf}" -loop "${ff_loop}" "${out}"

}
cmd_cinema_show () {

    sound_traps

    source <(parse "$@" -- \
        :tmp_dir="/tmp/rust-gun" \
        :dir_name="Gun" \
        :user="codingmstr" \
        :repo="demo" \
        :src_repo="git@github.com:codingmstr/rust-gun.git" \
        :installer="install.sh" \
    )

    rm -rf -- "${tmp_dir}/${dir_name}" 2>/dev/null || true
    cd -- "${tmp_dir}" || return 1
    run_clear
    sleep 1
    set_prompt ""
    run_typed "mkdir -p ${tmp_dir}"
    run_typed "cd ${tmp_dir}"
    set_prompt "${tmp_dir}"

    run_clear
    run_say "Hi, Rustaceans 🫡"
    run_say "Prepare your coffee and enjoy the show ☕" 0
    run_say "Let's get started and see the amazing rust-gun commands 😎" 0
    sleep 1

    cd -- "${tmp_dir}/${dir_name}" || return 1
    run_clear
    run_say "Boot a clean workspace."
    run_typed "mkdir -p ${dir_name}"
    run_typed "cd ${dir_name}"
    set_prompt "${tmp_dir}/${dir_name}"

    run_clear
    run_say "clone the template into this folder."
    run_typed "git clone ${src_repo} ."

    run_clear
    run_say "Install + stamp template placeholders (alias/name/repo metadata) so this becomes YOUR project."
    run_typed "bash ${installer} --alias gun --name demo --description \"this is my demo crate\" --user \"${user}\" --repo \"${repo}\""
    run_typed "which gun"

    run_clear
    run_say "Create the GitHub repo and wire this workspace for real pushes/releases."
    run_typed "gun init ${user}/${repo}"
    run_say "Check current remote status, atuh ..."
    run_typed "gun remote"
    run_say "Creating secrets and environmental variables."
    run_typed "mv .secrets.example .secrets"
    run_say "Fill in the secret values in the .secrets file."
    run_say "Now sync secrets from your local file into GitHub."
    run_typed "gun sync-secrets"

    run_clear
    run_say "Show the command surface: one CLI to rule the whole workspace."
    run_typed "gun --help"

    run_clear
    run_say "Help pages for the main pillars: lint/ci/doctor (fast discovery without reading docs)."
    run_typed "gun cinema-help"
    run_typed "gun notify-help"
    run_typed "gun git-help"
    run_typed "gun github-help"
    run_typed "gun crate-help"
    run_typed "gun lint-help"
    run_typed "gun perf-help"
    run_typed "gun safety-help"
    run_typed "gun doctor-help"
    run_typed "gun meta-help"
    run_typed "gun ci-help"

    run_clear
    run_say "Auto help for any command: (args/options/flags)."
    run_typed "gun help sync-secrets"
    run_typed "gun help cinema-show"
    run_typed "gun help publish"
    run_typed "gun help yank"
    run_typed "gun help notify"
    run_typed "gun help push"
    run_typed "gun help samply"
    run_typed "gun help fuzz"
    run_typed "gun help doctor"

    run_clear
    run_say "See source code + file path (and line numbers) for any command."
    run_typed "gun source help"
    run_typed "gun source add-var"
    run_typed "gun source add-secret"
    run_typed "gun source ensure"
    run_typed "gun source ci-local"

    run_clear
    run_say "Diagnose environment: OS + Bash + Rust + Git + required tools (catch problems before CI screams)."
    run_typed "gun doctor"
    run_clear
    run_say "Ensure tooling: installs/validates cargo tools and utilities (autopilot mode)."
    run_typed "gun ensure"

    run_clear
    run_say "Toolchain matrix: show and run stable/nightly/MSRV and inspect active toolchain."
    run_typed "gun version"
    run_typed "gun stable"
    run_typed "gun nightly"
    run_typed "gun msrv"
    run_typed "gun active"

    run_clear
    run_say "Create a new crate named 'hi', a publishable crate and a private/internal one, then inspect manifests."
    run_typed "gun new hi"
    run_typed "cat crates/hi/Cargo.toml"
    run_typed $'cat > crates/hi/src/lib.rs <<\'RS\'\n//! Hi crate Doc.\n\npub struct Hi;\n\nimpl Hi {\n    #[must_use]\n    pub const fn run() -> &\'static str {\n        "Iam Hi Crate"\n    }\n}\nRS\n'

    run_clear
    run_say "Workspace metadata: list package names, then only publishable crates (release safety)."
    run_typed "gun meta --names"
    run_typed "gun meta --names --only-publishable"
    run_typed "gun can-publish"
    run_typed "gun tree"
    run_typed "gun tree-files"

    run_clear
    run_say "Read-only quality gates (checks): verify formatting, audits, TOML, and prettier without changing files."
    run_typed "gun fmt-check"
    run_typed "gun audit-check"
    run_typed "gun taplo-check"
    run_typed "gun prettier-check"

    run_clear
    run_say "Auto-fix gates: apply consistent formatting + repair common policy issues (make it green fast)."
    run_typed "gun ws-fix"
    run_typed "gun fmt-fix"
    run_typed "gun audit-fix"
    run_typed "gun taplo-fix"
    run_typed "gun prettier-fix"

    run_clear
    run_say "Spellcheck: keep docs clean (small typos become big embarrassment)."
    gun spell-remove SLA || true
    run_typed "gun spell-check"
    run_say "Add a word to dictionary, then re-run spellcheck (show the workflow)."
    run_typed "gun spell-add SLA"
    run_typed "gun spell-check"

    run_clear
    run_say "Supply-chain verification: vet policy check (dependency trust gate)."
    run_typed "gun vet-check"
    run_say 'Trust the "best" baseline set (project-defined trust presets).'
    run_typed "gun vet-trust-best"
    run_say 'Import the "best" audit set (project-defined import presets).'
    run_typed "gun vet-import-best"
    run_say "Supply-chain verification: vet policy check (dependency trust gate)."
    run_typed "gun vet-check"

    run_clear
    run_say "Core build/run suite: check, test, docs checks, benches, and examples."
    run_typed "gun check"
    run_typed "gun test"
    run_typed "gun doc-check"
    run_typed "gun doc-test"
    run_typed "gun doc-clean"
    run_typed "gun bench demo"
    run_typed "gun example demo"

    run_clear
    run_say "UB & chaos testing: fuzz quickly, then sanitizer + miri (catch dragons)."
    run_typed "gun fuzz --timeout 5"
    run_typed "gun sanitizer"
    run_typed "gun miri"

    run_clear
    run_say "Clippy gate: strict linting to keep the codebase honest."
    run_typed "gun clippy"
    run_clear
    run_say "Coverage output: produce lcov report artifact for CI/codecov."
    run_typed "gun coverage --out profiles/lcov.info"
    run_clear
    run_say "Size gate: produce bloat report artifact (binary weight accountability)."
    run_typed "gun bloat --out profiles/bloat.info"

    run_clear
    run_say "Full local CI simulation: run the whole pipeline before pushing (gatekeeper mode)."
    run_typed "gun ci-local"
    run_clear
    run_say "Release flow: tag + changelog + push (force only for demo purposes)."
    run_typed "gun push --release --changelog --force"
    run_typed "cat CHANGELOG.md"

    run_clear
    run_say "Goodbye, Rustaceans 😎"

    sleep 5

}

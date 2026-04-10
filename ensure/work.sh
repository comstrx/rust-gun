
ensure () {

    local -a wants=()
    local want=""

    for want in "$@"; do
        [[ -n "${want}" ]] || continue
        wants+=( "${want}" )
    done

    unique_list wants
    (( ${#wants[@]} )) || return 0

    for want in "${wants[@]}"; do

        case "${want}" in
            node|nodejs|npm|npx)       ensure_node ;;
            bun)                       ensure_bun ;;
            pnpm)                      ensure_pnpm ;;
            volta)                     ensure_volta ;;

            python|pip)                ensure_python ;;

            cargo|rust|rustc|rustup)   ensure_rust ;;

            rustfmt|rust-src)          ensure_component "${want}" stable; ensure_component "${want}" nightly ;;
            miri)                      ensure_component miri nightly ;;
            clippy|llvm-tools-preview) ensure_component "${want}" stable ;;

            taplo)                     ensure_crate taplo-cli taplo ;;
            cargo-audit)               ensure_crate cargo-audit cargo-audit --features fix ;;
            cargo-edit|cargo-upgrade)  ensure_cargo_edit ;;
            cargo-add|cargo-rm)        ensure_cargo_edit ;;
            cargo-set-version)         ensure_cargo_edit ;;

            cargo-*)                   ensure_crate "${want}" "${want}" ;;

            *)                         ensure_tool "${want}" 1>&2 ;;
        esac

    done

}


cmd_notify () {

    source <(parse "$@" -- \
        platform:list platforms:list \
        status title message \
        token chat telegram_token telegram_chat \
        webhook url slack_webhook discord_webhook webhook_url \
        retries:int=3 delay:int=1 timeout:float=10 max_time:float=20 retry_max_time:float=60 \
    )

    local msg="${message:-"$(notify_message "${status}" "${title}")"}"

    local p=""
    local -a plats=() failed=()

    local -a args=(
        -fsS
        --connect-timeout "${timeout}"
        --max-time "${max_time}"
        --retry-max-time "${retry_max_time}"
        --retry "${retries}"
        --retry-delay "${delay}"
        --retry-connrefused
    )

    if (( ${#platform[@]} )); then plats=( "${platform[@]}" )
    elif (( ${#platforms[@]} )); then plats=( "${platforms[@]}" )
    else
        notify_has_telegram "${telegram_token:-${token}}" "${telegram_chat:-${chat}}" && plats+=( telegram )
        notify_has_slack    "${slack_webhook:-${webhook:-${url:-}}}"                  && plats+=( slack )
        notify_has_discord  "${discord_webhook:-${webhook:-${url:-}}}"                && plats+=( discord )
        notify_has_webhook  "${webhook_url:-${webhook:-${url:-}}}"                    && plats+=( webhook )
    fi

    (( ${#plats[@]} )) || die "notify: no configured notification platform found"

    for p in "${plats[@]}"; do

        case "${p,,}" in
            telegram) notify_telegram args "${telegram_token:-${token}}" "${telegram_chat:-${chat}}" "${msg}" || failed+=( telegram ) ;;
            slack)    notify_slack    args "${slack_webhook:-${webhook:-${url:-}}}" "${msg}"                  || failed+=( slack ) ;;
            discord)  notify_discord  args "${discord_webhook:-${webhook:-${url:-}}}" "${msg}"                || failed+=( discord ) ;;
            webhook)  notify_webhook  args "${webhook_url:-${webhook:-${url:-}}}" "${msg}"                    || failed+=( webhook ) ;;
            *) failed+=( "${p}" ) ;;
        esac

    done

    (( ${#failed[@]} )) && die "Failed to send ( ${failed[*]} ) notification"
    success "OK: notification sent successfully ( ${plats[*]} )"

}
cmd_notify_telegram () {

    source <(parse "$@" -- status title message token chat)

    cmd_notify --platform telegram \
        --status "${status}" --title "${title}" --message "${message}" \
        --token "${token}" --chat "${chat}" "${kwargs[@]}"

}
cmd_notify_slack () {

    source <(parse "$@" -- status title message webhook)

    cmd_notify --platform slack \
        --status "${status}" --title "${title}" --message "${message}" \
        --webhook "${webhook}" "${kwargs[@]}"

}
cmd_notify_discord () {

    source <(parse "$@" -- status title message webhook)

    cmd_notify --platform discord \
        --status "${status}" --title "${title}" --message "${message}" \
        --webhook "${webhook}" "${kwargs[@]}"

}
cmd_notify_webhook () {

    source <(parse "$@" -- status title message webhook)

    cmd_notify --platform webhook \
        --status "${status}" --title "${title}" --message "${message}" \
        --webhook "${webhook}" "${kwargs[@]}"

}

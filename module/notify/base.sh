
notify_message () {

    local status="${1:-}" title="${2:-}"

    local ref="${REF:-${GITHUB_REF:-}}"
    local sha="${SHA:-${GITHUB_SHA:-}}"
    local url="${URL:-${GITHUB_URL:-${GITHUB_WORKFLOW_URL:-${WORKFLOW_URL:-}}}}"
    local started_at="${STARTED_AT:-${RUN_STARTED_AT:-${GITHUB_RUN_STARTED_AT:-}}}"
    local finished_at="${FINISHED_AT:-${RUN_FINISHED_AT:-${GITHUB_RUN_FINISHED_AT:-}}}"
    local run_id="${RUN_ID:-${GITHUB_RUN_ID:-}}"
    local server_url="${SERVER_URL:-${GITHUB_SERVER_URL:-}}"
    local repo="${REPOSITORY:-${GITHUB_REPOSITORY:-}}"
    local repo_name="${repo##*/}"
    local status_icon="🤔" status_label="Unknown"
    local duration="0s" date_str="$(date -u +%F 2>/dev/null || date +%F)"

    [[ -n "${status}" ]] || status="${STATUS:-${GITHUB_STATUS:-}}"
    [[ -n "${title}" ]] || title="${WORKFLOW_NAME:-${GITHUB_WORKFLOW_NAME:-CI}} Workflow"
    [[ -z "${url}" && -n "${server_url}" && -n "${repo}" && -n "${run_id}" ]] && url="${server_url}/${repo}/actions/runs/${run_id}"

    case "${status,,}" in
        success|succeeded|ok|passed|pass)    status_icon="✅" ; status_label="Success" ;;
        warn|warning|warnings)     status_icon="⚠️" ; status_label="Warning" ;;
        fail|failed|failure|error)  status_icon="❌" ; status_label="Failed" ;;
        cancel|canceled|cancelled) status_icon="🟡" ; status_label="Cancelled" ;;
        skip|skipped)              status_icon="⚪" ; status_label="Skipped" ;;
    esac
    case "${ref}" in
        refs/heads/*) ref="${ref#refs/heads/}" ;;
        refs/tags/*)  ref="${ref#refs/tags/}"  ;;
    esac

    if [[ -n "${started_at}" ]]; then

        local st="${started_at}"
        local ft="${finished_at}"

        [[ "${st}" == *.*Z ]] && st="${st%%.*}Z"
        [[ "${ft}" == *.*Z ]] && ft="${ft%%.*}Z"

        local start_s="$(date -u -d "${st}" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${st}" +%s 2>/dev/null || true)"
        local end_s="$(date -u -d "${ft}" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${ft}" +%s 2>/dev/null || true)"

        [[ -n "${end_s}" ]] || end_s="$(date -u +%s 2>/dev/null || date +%s)"

        if [[ -n "${start_s}" ]]; then

            local delta=$(( end_s - start_s ))
            (( delta < 0 )) && delta=0

            local h=$(( delta / 3600 ))
            local m=$(( (delta % 3600) / 60 ))
            local s=$(( delta % 60 ))

            if (( h > 0 )); then duration="${h}h ${m}m ${s}s"
            elif (( m > 0 )); then duration="${m}m ${s}s"
            else duration="${s}s"
            fi

        fi

    fi

    [[ -n "${url}" ]] || url="--"
    [[ -n "${ref}" ]] || ref="--"
    [[ -n "${repo}" ]] || repo="--"
    [[ -n "${repo_name}" ]] || repo_name="--"
    [[ -n "${sha}" ]] && sha="${sha:0:7}" || sha="--"

    printf '%s\n' \
        "==>" \
        "" \
        "💥 ${title} :" \
        "" \
        "      ( Status )      :  ${status_icon} ${status_label}" \
        "" \
        "      ( Duration )  :  ${duration}" \
        "" \
        "      ( Date )         :  ${date_str}" \
        "" \
        "      ( Repo )        :  ${repo}" \
        "" \
        "      ( Commit )   :  ${repo_name}@${ref} • ${sha}" \
        "" \
        "      ( URL )          :  ${url}" \
        "" \
        "==>"

}

notify_has_telegram () {

    local token="${1:-}" chat="${2:-}"

    [[ -n "${token}" ]] || token="${TELEGRAM_TOKEN:-${TOKEN:-}}"
    [[ -n "${chat}"  ]] || chat="${TELEGRAM_CHAT_ID:-${TELEGRAM_CHAT:-${CHAT_ID:-${CHAT:-}}}}"
    [[ -n "${token}" && -n "${chat}" ]]

}
notify_has_slack () {

    local webhook="${1:-}"

    [[ -n "${webhook}" ]] || webhook="${SLACK_WEBHOOK_URL:-${SLACK_WEBHOOK:-${SLACK_URL:-}}}"
    [[ -n "${webhook}" ]]

}
notify_has_discord () {

    local webhook="${1:-}"

    [[ -n "${webhook}" ]] || webhook="${DISCORD_WEBHOOK_URL:-${DISCORD_WEBHOOK:-${DISCORD_URL:-}}}"
    [[ -n "${webhook}" ]]

}
notify_has_webhook () {

    local webhook="${1:-}"

    [[ -n "${webhook}" ]] || webhook="${WEBHOOK_URL:-${WEBHOOK:-}}"
    [[ -n "${webhook}" ]]

}

notify_telegram () {

    ensure_tool curl

    local -n curl_args="${1}"
    local token="${2:-}" chat="${3:-}" msg="${4:-}"

    [[ -n "${token}" ]] || token="${TELEGRAM_TOKEN:-${TOKEN:-}}"
    [[ -n "${chat}"  ]] || chat="${TELEGRAM_CHAT_ID:-${TELEGRAM_CHAT:-${CHAT_ID:-${CHAT:-}}}}"

    [[ -n "${token}" ]] || die "notify: missing telegram token"
    [[ -n "${chat}"  ]] || die "notify: missing telegram chat"

    curl "${curl_args[@]}" -X POST \
        "https://api.telegram.org/bot${token}/sendMessage" \
        --data-urlencode "chat_id=${chat}" \
        --data-urlencode "text=${msg}" \
        --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || return 1

}
notify_slack () {

    ensure_tool curl jq

    local -n curl_args="${1}"
    local webhook="${2:-}" msg="${3:-}" payload=""

    [[ -n "${webhook}" ]] || webhook="${SLACK_WEBHOOK_URL:-${SLACK_WEBHOOK:-${SLACK_URL:-}}}"
    [[ -n "${webhook}" ]] || die "notify: missing slack webhook"

    payload="$(jq -cn --arg t "${msg}" '{text:$t}')" || return 1

    printf '%s' "${payload}" | curl "${curl_args[@]}" -X POST \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "${webhook}" >/dev/null 2>&1 || return 1

}
notify_discord () {

    ensure_tool curl jq

    local -n curl_args="${1}"
    local webhook="${2:-}" msg="${3:-}" payload=""

    [[ -n "${webhook}" ]] || webhook="${DISCORD_WEBHOOK_URL:-${DISCORD_WEBHOOK:-${DISCORD_URL:-}}}"
    [[ -n "${webhook}" ]] || die "notify: missing discord webhook"

    payload="$(jq -cn --arg t "${msg}" '{content:$t}')" || return 1

    printf '%s' "${payload}" | curl "${curl_args[@]}" -X POST \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "${webhook}" >/dev/null 2>&1 || return 1

}
notify_webhook () {

    ensure_tool curl jq

    local -n curl_args="${1}"
    local webhook="${2:-}" msg="${3:-}" payload=""

    [[ -n "${webhook}" ]] || webhook="${WEBHOOK_URL:-${WEBHOOK:-}}"
    [[ -n "${webhook}" ]] || die "notify: missing webhook url"

    payload="$(jq -cn --arg t "${msg}" '{text:$t}')" || return 1

    printf '%s' "${payload}" | curl "${curl_args[@]}" -X POST \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "${webhook}" >/dev/null 2>&1 || return 1

}

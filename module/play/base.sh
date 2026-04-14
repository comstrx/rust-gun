
CURRENT_DIR=""
PLAY_SOUND_PID=""
PLAY_SOUND_PG=0

userhost_short () {

    local u="$(id -un 2>/dev/null || printf '%s' "${USER-unknown}")"
    local h="$(hostname 2>/dev/null || printf '%s' "${HOSTNAME-localhost}")"

    h="${h%%.*}"
    printf '%s@%s' "${u}" "${h}"

}
set_prompt () {

    local path="${1-}"

    if [[ -t 1 && -n "${TERM-}" && "${TERM}" != "dumb" && -z "${NO_COLOR-}" ]]; then
        CURRENT_DIR="\e[32m$(userhost_short)\e[0m:\e[34m${path}\e[0m\e[37m$ \e[0m"
    else
        CURRENT_DIR="$(userhost_short):${path}$ "
    fi

}

play_sound () {

    local file="${1-}" mode="${2-}" win_path="" cmd=""

    stop_sound

    [[ -n "${file}" ]] || return 0
    [[ -f "${file}" ]] || return 0

    [[ -n "${NO_SOUND-}" || "${SOUND-1}" == "0" ]] && return 0
    [[ -t 1 && -n "${TERM-}" && "${TERM}" != "dumb" ]] || return 0

    [[ "${mode}" == "loop" ]] || mode="once"

    if command -v afplay >/dev/null 2>&1; then

        if [[ "${mode}" == "loop" ]]; then

            if command -v setsid >/dev/null 2>&1; then
                setsid bash -c 'while :; do afplay "$1" >/dev/null 2>&1 || exit 0; done' _ "${file}" & PLAY_SOUND_PID=$!
                PLAY_SOUND_PG=1
            else
                ( while :; do afplay "${file}" >/dev/null 2>&1 || exit 0; done ) & PLAY_SOUND_PID=$!
                PLAY_SOUND_PG=0
            fi

        else

            afplay "${file}" >/dev/null 2>&1 & PLAY_SOUND_PID=$!
            PLAY_SOUND_PG=0

        fi

        return 0

    fi
    if command -v ffplay >/dev/null 2>&1; then

        if [[ "${mode}" == "loop" ]]; then

            if command -v setsid >/dev/null 2>&1; then
                setsid ffplay -nodisp -loglevel error -loop -1 "${file}" >/dev/null 2>&1 & PLAY_SOUND_PID=$!
                PLAY_SOUND_PG=1
            else
                ffplay -nodisp -loglevel error -loop -1 "${file}" >/dev/null 2>&1 & PLAY_SOUND_PID=$!
                PLAY_SOUND_PG=0
            fi

        else

            ffplay -nodisp -autoexit -loglevel error "${file}" >/dev/null 2>&1 & PLAY_SOUND_PID=$!
            PLAY_SOUND_PG=0

        fi

        return 0

    fi
    if command -v paplay >/dev/null 2>&1; then

        if [[ "${mode}" == "loop" ]]; then

            if command -v setsid >/dev/null 2>&1; then
                setsid bash -c 'while :; do paplay "$1" >/dev/null 2>&1 || exit 0; done' _ "${file}" & PLAY_SOUND_PID=$!
                PLAY_SOUND_PG=1
            else
                ( while :; do paplay "${file}" >/dev/null 2>&1 || exit 0; done ) & PLAY_SOUND_PID=$!
                PLAY_SOUND_PG=0
            fi

        else

            paplay "${file}" >/dev/null 2>&1 & PLAY_SOUND_PID=$!
            PLAY_SOUND_PG=0

        fi

        return 0

    fi
    if command -v aplay >/dev/null 2>&1; then

        if [[ "${mode}" == "loop" ]]; then

            if command -v setsid >/dev/null 2>&1; then
                setsid bash -c 'while :; do aplay -q "$1" >/dev/null 2>&1 || exit 0; done' _ "${file}" & PLAY_SOUND_PID=$!
                PLAY_SOUND_PG=1
            else
                ( while :; do aplay -q "${file}" >/dev/null 2>&1 || exit 0; done ) & PLAY_SOUND_PID=$!
                PLAY_SOUND_PG=0
            fi

        else

            aplay -q "${file}" >/dev/null 2>&1 & PLAY_SOUND_PID=$!
            PLAY_SOUND_PG=0

        fi

        return 0

    fi
    if command -v powershell.exe >/dev/null 2>&1; then

        win_path="${file}"
        command -v wslpath >/dev/null 2>&1 && win_path="$(wslpath -w "${file}" 2>/dev/null || printf '%s' "${file}")"
        win_path="${win_path//\'/\'\'}"

        if [[ "${mode}" == "loop" ]]; then cmd="\$p='${win_path}'; \$sp=New-Object Media.SoundPlayer \$p; while(\$true){ \$sp.PlaySync() }"
        else cmd="(New-Object Media.SoundPlayer '${win_path}').PlaySync()"
        fi

        powershell.exe -NoProfile -NonInteractive -Command "${cmd}" >/dev/null 2>&1 & PLAY_SOUND_PID=$!
        PLAY_SOUND_PG=0

        return 0

    fi

    return 0

}
stop_sound () {

    local pid="${PLAY_SOUND_PID-}"

    [[ -n "${pid}" ]] || return 0

    if command -v taskkill.exe >/dev/null 2>&1; then
        taskkill.exe //T //F //PID "${pid}" >/dev/null 2>&1 || true
    fi

    kill -TERM "${pid}" >/dev/null 2>&1 || true
    kill -TERM -- "-${pid}" >/dev/null 2>&1 || true

    if command -v pkill >/dev/null 2>&1; then
        pkill -TERM -P "${pid}" >/dev/null 2>&1 || true
    fi

    for _ in 1 2 3 4 5 6 7 8; do
        kill -0 "${pid}" >/dev/null 2>&1 || break
        sleep 0.03
    done

    kill -KILL "${pid}" >/dev/null 2>&1 || true
    kill -KILL -- "-${pid}" >/dev/null 2>&1 || true

    if command -v pkill >/dev/null 2>&1; then
        pkill -KILL -P "${pid}" >/dev/null 2>&1 || true
    fi

    wait "${pid}" 2>/dev/null || true

    PLAY_SOUND_PID=""
    PLAY_SOUND_PG=0

}
sound_traps () {

    trap 'stop_sound; exit 130' INT
    trap 'stop_sound' TERM
    trap 'stop_sound' EXIT

}
type_line () {

    local s="${1-}" type="${2-cmd}" sound="${3:-cmd}" mode="${4-loop}" delay="" i=0

    [[ "${type}" != "say" ]] && printf '%b' "${CURRENT_DIR}"

    sleep 1
    delay="$(awk -v r=22 'BEGIN{print 1/r}')"

    play_sound "${ROOT_DIR}/scripts/assets/${sound}" "${mode}"

    while (( i < ${#s} )); do
        printf '%s' "${s:i:1}"
        sleep "${delay}"
        i=$(( i + 1 ))
    done

    stop_sound
    printf '\n'

}

run_typed () {

    local rc=0 shown=""
    (( $# )) || return 0

    if (( $# == 1 )); then
        shown="${1}"
    else
        shown="$(printf '%q ' "$@")"
        shown="${shown% }"
    fi

    type_line "${shown}" cmd cmd.wav

    if (( $# == 1 )); then
        if bash -lc "${1}"; then :
        else rc=$?
        fi
    else
        if "$@"; then :
        else rc=$?
        fi
    fi

}
run_clear () {

    type_line clear cmd cmd.wav
    clear

}
run_say () {

    local new_line="${2:-1}"
    (( new_line )) && type_line && printf '\n'

    type_line "          👉  $1" say say.wav
    printf '\n'

}

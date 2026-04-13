
tool_php_run () {

    if has php; then
        php "$@"
        return $?
    fi
    if has php.exe; then
        php.exe "$@"
        return $?
    fi

    return 127

}
tool_php_major () {

    local v="${1-}" major=""
    [[ -n "${v}" ]] || return 1

    v="${v#PHP }"
    major="${v%%.*}"

    [[ "${major}" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${major}"

}
tool_export_composer_bin () {

    local dir="" d=""
    local -a dirs=()

    [[ -n "${COMPOSER_HOME:-}" ]] && dirs+=( "$(tool_to_unix_path "${COMPOSER_HOME}")/vendor/bin" )
    [[ -n "${APPDATA:-}" ]]      && dirs+=( "$(tool_to_unix_path "${APPDATA}")/Composer/vendor/bin" )
    [[ -n "${LOCALAPPDATA:-}" ]] && dirs+=( "$(tool_to_unix_path "${LOCALAPPDATA}")/Composer/vendor/bin" )
    [[ -n "${USERPROFILE:-}" ]]  && dirs+=( "$(tool_to_unix_path "${USERPROFILE}")/AppData/Roaming/Composer/vendor/bin" )
    [[ -n "${USERPROFILE:-}" ]]  && dirs+=( "$(tool_to_unix_path "${USERPROFILE}")/AppData/Local/Composer/vendor/bin" )

    dirs+=( "${HOME}/.composer/vendor/bin" )
    dirs+=( "${HOME}/.config/composer/vendor/bin" )
    dirs+=( "${HOME}/.local/bin" )
    dirs+=( "${HOME}/bin" )

    for d in "${dirs[@]}"; do
        tool_export_path_if_dir "${d}"
    done

}
tool_composer_cmd () {

    tool_export_composer_bin

    if has composer; then
        composer "$@"
        return $?
    fi
    if [[ -x "${HOME}/.local/bin/composer" ]]; then
        "${HOME}/.local/bin/composer" "$@"
        return $?
    fi
    if [[ -x "${HOME}/bin/composer" ]]; then
        "${HOME}/bin/composer" "$@"
        return $?
    fi

    return 127

}

tool_php_ok () {

    local want="${1:-${PHP_VERSION:-8}}" v="" major=""

    tool_php_run -v >/dev/null 2>&1 || return 1

    [[ -n "${want}" ]] || return 0
    [[ "${want}" =~ ^[0-9]+$ ]] || return 0

    v="$(tool_php_run -r 'echo PHP_VERSION;' 2>/dev/null || true)"
    major="$(tool_php_major "${v}")" || return 1

    (( major >= want ))

}
tool_composer_ok () {

    tool_export_composer_bin

    if has composer; then
        composer --version >/dev/null 2>&1
        return $?
    fi
    if [[ -x "${HOME}/.local/bin/composer" ]]; then
        "${HOME}/.local/bin/composer" --version >/dev/null 2>&1
        return $?
    fi
    if [[ -x "${HOME}/bin/composer" ]]; then
        "${HOME}/bin/composer" --version >/dev/null 2>&1
        return $?
    fi

    return 1

}

tool_install_php_unix () {

    if has brew; then

        run brew install php || die "Failed to install PHP via brew."
        return 0

    fi
    if has apt-get; then

        run sudo apt-get update -y || die "Failed to update apt index."

        if tool_assume_yes; then run sudo apt-get install -y php-cli php-mbstring php-xml php-curl unzip ca-certificates
        else run sudo apt-get install php-cli php-mbstring php-xml php-curl unzip ca-certificates
        fi

        return 0

    fi
    if has apk; then

        if tool_assume_yes; then
            run sudo apk add php84-cli php84-phar php84-openssl php84-mbstring php84-xml php84-curl unzip ca-certificates \
                || run sudo apk add php83-cli php83-phar php83-openssl php83-mbstring php83-xml php83-curl unzip ca-certificates \
                || run sudo apk add php-cli php-phar php-openssl php-mbstring php-xml php-curl unzip ca-certificates \
                || die "Failed to install PHP via apk."
        else
            run sudo apk add php84-cli php84-phar php84-openssl php84-mbstring php84-xml php84-curl unzip ca-certificates \
                || run sudo apk add php83-cli php83-phar php83-openssl php83-mbstring php83-xml php83-curl unzip ca-certificates \
                || run sudo apk add php-cli php-phar php-openssl php-mbstring php-xml php-curl unzip ca-certificates \
                || die "Failed to install PHP via apk."
        fi

        return 0

    fi
    if has dnf; then

        if tool_assume_yes; then run sudo dnf install -y php-cli php-mbstring php-xml php-process php-curl unzip ca-certificates
        else run sudo dnf install php-cli php-mbstring php-xml php-process php-curl unzip ca-certificates
        fi

        return 0

    fi
    if has yum; then

        if tool_assume_yes; then run sudo yum install -y php-cli php-mbstring php-xml php-process php-curl unzip ca-certificates
        else run sudo yum install php-cli php-mbstring php-xml php-process php-curl unzip ca-certificates
        fi

        return 0

    fi
    if has zypper; then

        if tool_assume_yes; then
            run sudo zypper --non-interactive install php8 php8-cli php8-mbstring php8-xmlreader php8-xmlwriter php8-curl unzip ca-certificates \
                || run sudo zypper --non-interactive install php php-cli php-mbstring php-xmlreader php-xmlwriter php-curl unzip ca-certificates \
                || die "Failed to install PHP via zypper."
        else
            run sudo zypper install php8 php8-cli php8-mbstring php8-xmlreader php8-xmlwriter php8-curl unzip ca-certificates \
                || run sudo zypper install php php-cli php-mbstring php-xmlreader php-xmlwriter php-curl unzip ca-certificates \
                || die "Failed to install PHP via zypper."
        fi

        return 0

    fi
    if has pacman; then

        if tool_assume_yes; then run sudo pacman -S --needed --noconfirm php unzip ca-certificates
        else run sudo pacman -S --needed php unzip ca-certificates
        fi

        return 0

    fi

    die "No supported unix package manager found for PHP install."

}
tool_install_php_windows () {

    local target="${1:-$(tool_target)}"

    if has scoop; then

        run scoop install php || run scoop update php || die "Failed to install PHP via scoop."
        return 0

    fi
    if has choco; then

        if tool_assume_yes; then run choco install -y php || run choco upgrade -y php || die "Failed to install PHP via choco."
        else run choco install php || run choco upgrade php || die "Failed to install PHP via choco."
        fi
        return 0

    fi
    if has pacman; then

        case "${target}" in
            msys|gitbash)
                if tool_assume_yes; then run pacman -S --needed --noconfirm php
                else run pacman -S --needed php
                fi
            ;;
            mingw)
                local prefix="$(tool_mingw_prefix)"

                if tool_assume_yes; then
                    run pacman -S --needed --noconfirm "${prefix}-php" \
                        || run pacman -S --needed --noconfirm php \
                        || die "Failed to install PHP via pacman."
                else
                    run pacman -S --needed "${prefix}-php" \
                        || run pacman -S --needed php \
                        || die "Failed to install PHP via pacman."
                fi
            ;;
            cygwin)
                die "Cygwin PHP auto-install is not supported in this file. Use winget/choco/scoop from Windows side."
            ;;
            *)
                die "Unsupported pacman target for PHP: ${target}"
            ;;
        esac

        return 0

    fi
    if has winget; then

        run winget install --id PHP.PHP --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || run winget upgrade --id PHP.PHP --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || die "Failed to install PHP via winget."

        return 0

    fi

    die "No supported Windows package manager found for PHP install."

}
tool_install_composer_official () {

    ensure_tool curl
    ensure_php

    local setup="" expected="" actual="" install_dir=""

    if [[ -d "${HOME}/.local/bin" || ! -e "${HOME}/.local/bin" ]]; then install_dir="${HOME}/.local/bin"
    else install_dir="${HOME}/bin"
    fi

    mkdir -p "${install_dir}" || die "Failed to create Composer install dir: ${install_dir}"

    setup="$(mktemp "${TMPDIR:-/tmp}/composer-setup.XXXXXX.php" 2>/dev/null || true)"
    [[ -n "${setup}" ]] || setup="${TMPDIR:-/tmp}/composer-setup.$$.$RANDOM.php"

    expected="$(curl -fsSL https://composer.github.io/installer.sig 2>/dev/null || true)"
    [[ -n "${expected}" ]] || die "Failed to fetch Composer installer checksum."

    run curl -fsSL -o "${setup}" https://getcomposer.org/installer || {
        rm -f "${setup}" 2>/dev/null || true
        die "Failed to download Composer installer."
    }

    actual="$(tool_php_run -r 'echo hash_file("sha384", $argv[1]);' "${setup}" 2>/dev/null || true)"

    [[ -n "${actual}" && "${actual}" == "${expected}" ]] || {
        rm -f "${setup}" 2>/dev/null || true
        die "Composer installer checksum mismatch."
    }

    run tool_php_run "${setup}" --no-ansi --install-dir="${install_dir}" --filename=composer || {
        rm -f "${setup}" 2>/dev/null || true
        die "Failed to install Composer."
    }

    rm -f "${setup}" 2>/dev/null || true
    chmod +x "${install_dir}/composer" 2>/dev/null || true

    tool_export_path_if_dir "${install_dir}"
    tool_hash_clear

}
tool_install_composer_unix () {

    if has brew; then

        run brew install composer || tool_install_composer_official
        return 0

    fi
    if has apt-get; then

        run sudo apt-get update -y >/dev/null 2>&1 || true

        if tool_assume_yes; then run sudo apt-get install -y composer || tool_install_composer_official
        else run sudo apt-get install composer || tool_install_composer_official
        fi
        return 0

    fi
    if has apk; then

        if tool_assume_yes; then run sudo apk add composer || tool_install_composer_official
        else run sudo apk add composer || tool_install_composer_official
        fi
        return 0

    fi
    if has dnf; then

        if tool_assume_yes; then run sudo dnf install -y composer || tool_install_composer_official
        else run sudo dnf install composer || tool_install_composer_official
        fi
        return 0

    fi
    if has yum; then

        if tool_assume_yes; then run sudo yum install -y composer || tool_install_composer_official
        else run sudo yum install composer || tool_install_composer_official
        fi
        return 0

    fi
    if has zypper; then

        if tool_assume_yes; then run sudo zypper --non-interactive install composer || tool_install_composer_official
        else run sudo zypper install composer || tool_install_composer_official
        fi
        return 0

    fi
    if has pacman; then

        if tool_assume_yes; then run sudo pacman -S --needed --noconfirm composer || tool_install_composer_official
        else run sudo pacman -S --needed composer || tool_install_composer_official
        fi
        return 0

    fi

    tool_install_composer_official

}
tool_install_composer_windows () {

    if has scoop; then

        run scoop install composer || run scoop update composer || true

        tool_export_composer_bin
        tool_hash_clear
        tool_composer_ok && return 0

    fi
    if has choco; then

        if tool_assume_yes; then run choco install -y composer || run choco upgrade -y composer || true
        else run choco install composer || run choco upgrade composer || true
        fi

        tool_export_composer_bin
        tool_hash_clear
        tool_composer_ok && return 0

    fi
    if has winget; then

        run winget install --id Composer.Composer --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || run winget upgrade --id Composer.Composer --exact --accept-source-agreements --accept-package-agreements --disable-interactivity \
            || true

        tool_export_composer_bin
        tool_hash_clear
        tool_composer_ok && return 0

    fi

    tool_install_composer_official

}

ensure_php () {

    local want="${1:-${PHP_VERSION:-8}}"
    local target="$(tool_target)"

    tool_php_ok "${want}" && return 0

    case "${target}" in
        linux|macos) tool_install_php_unix ;;
        msys|mingw|gitbash|cygwin) tool_install_php_windows "${target}" ;;
        *) die "Unsupported target for PHP install: ${target}" ;;
    esac

    tool_hash_clear
    tool_php_ok "${want}" || die "PHP install did not satisfy requirement."

}
ensure_composer () {

    local target="$(tool_target)"

    tool_export_composer_bin
    tool_composer_ok && return 0

    case "${target}" in
        linux|macos) tool_install_composer_unix ;;
        msys|mingw|gitbash|cygwin) tool_install_composer_windows ;;
        *) die "Unsupported target for Composer install: ${target}" ;;
    esac

    tool_export_composer_bin
    tool_hash_clear

    tool_composer_ok || die "Composer install failed."

}
ensure_dependency () {

    local pkg="${1-}" ver="${2-}"
    local target="${pkg}"
    shift 2 || true

    [[ -n "${pkg}" ]] || die "ensure_dependency: requires <package>"
    [[ -n "${ver}" ]] && target="${pkg}:${ver}"

    ensure_composer

    if [[ -f "composer.json" ]]; then
        tool_composer_cmd require "$@" "${target}" || die "Failed to install dependency '${target}' via composer require."
    else
        tool_composer_cmd global require "$@" "${target}" || die "Failed to install dependency '${target}' via composer global require."
        tool_export_composer_bin
        tool_hash_clear
    fi

}


[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "boot.sh: this file should not be run externally." >&2; exit 2; }
[[ -n "${BOOT_LOADED:-}" ]] && return 0
BOOT_LOADED=1

readonly BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly CORE_DIR="${BASE_DIR}/../core"
readonly MODULE_DIR="${BASE_DIR}/../module"

readonly APP_VERSION="1.0.0"
readonly BASH_MIN_VERSION="5.2"

readonly SORTED_LIST=( cargo ops git github file )

source "${CORE_DIR}/bash.sh"
source "${CORE_DIR}/tool.sh"

ensure_bash "${BASH_MIN_VERSION}" "$@"

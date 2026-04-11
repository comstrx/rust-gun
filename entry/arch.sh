[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "entry files should not be run directly." >&2; exit 2; }
[[ -n "${ENTRY_LOADED:-}" ]] && return 0

readonly ENTRY_LOADED=1

readonly ENTRY_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
readonly TEMPLATE_DIR="${ENTRY_DIR}/../template"
readonly MODULE_DIR="${ENTRY_DIR}/../module"
readonly STACK_DIR="${MODULE_DIR}/stack"

readonly APP_VERSION="1.0.0"
readonly MIN_BASH_VERSION="5.2"

readonly SORTED_LIST=( forge ops notify git github fs )

source "${ENTRY_DIR}/../core/bash.sh"
ensure_bash "${MIN_BASH_VERSION}" "$@"

source "${ENTRY_DIR}/../core/arch.sh"
source "${ENTRY_DIR}/../ensure/arch.sh"

source "${ENTRY_DIR}/installer.sh"
source "${ENTRY_DIR}/loader.sh"

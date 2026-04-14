
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "entry files should not be run directly." >&2; exit 2; }
[[ -n "${ENTRY_LOADED:-}" ]] && return 0

ENTRY_LOADED=1
ENTRY_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)"

MODULE_DIR="${ROOT_DIR}/module"
TEMPLATE_DIR="${ROOT_DIR}/template"
ENTRY_POINT="${ROOT_DIR}/exec/run.sh"

source "${ENTRY_DIR}/base.sh"

source "${ENTRY_DIR}/../core/bash.sh"
ensure_bash "$@"

source "${ENTRY_DIR}/../core/arch.sh"
source "${ENTRY_DIR}/../ensure/arch.sh"

source "${ENTRY_DIR}/build.sh"
source "${ENTRY_DIR}/install.sh"
source "${ENTRY_DIR}/load.sh"

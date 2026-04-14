
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "core files should not be run directly." >&2; exit 2; }
[[ -n "${CORE_LOADED:-}" ]] && return 0

CORE_LOADED=1
CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"

source "${CORE_DIR}/base.sh"
source "${CORE_DIR}/fsys.sh"
source "${CORE_DIR}/parse.sh"
source "${CORE_DIR}/pkg.sh"
source "${CORE_DIR}/tool.sh"

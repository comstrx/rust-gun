
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "ensure files should not be run directly." >&2; exit 2; }
[[ -n "${ENSURE_LOADED:-}" ]] && return 0

ENSURE_LOADED=1
ENSURE_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"

source "${ENSURE_DIR}/node.sh"
source "${ENSURE_DIR}/php.sh"
source "${ENSURE_DIR}/python.sh"
source "${ENSURE_DIR}/rust.sh"

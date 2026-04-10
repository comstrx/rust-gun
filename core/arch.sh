[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "core files should not be run directly." >&2; exit 2; }
[[ -n "${CORE_LOADED:-}" ]] && return 0

readonly CORE_LOADED=1
readonly CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)"

YES="${YES:-0}"
VERBOSE="${VERBOSE:-0}"

source "${CORE_DIR}/env.sh"
source "${CORE_DIR}/fsys.sh"
source "${CORE_DIR}/parse.sh"
source "${CORE_DIR}/pkg.sh"
source "${CORE_DIR}/tool.sh"

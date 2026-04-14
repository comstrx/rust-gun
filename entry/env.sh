
YES="${YES:-0}"
VERBOSE="${VERBOSE:-0}"

APP_NAME="gun"
APP_VERSION="0.1.0"
APP_BASH_VERSION="5.2"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)"

TEMPLATE_KEY="__TEMPLATE_PAYLOAD_KEY__"
TEMPLATE_DIR="${ROOT_DIR}/template"
MODULE_DIR="${ROOT_DIR}/module"

WORKSPACE_DIR="${WORKSPACE_DIR:-/var/www}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/mnt/d/Archive}"
SYNC_DIR="${SYNC_DIR:-/mnt/d}"
OUT_DIR="${OUT_DIR:-out}"

GIT_HTTP_USER="${GIT_HTTP_USER:-x-access-token}"
GIT_HOST="${GIT_HOST:-github.com}"
GIT_AUTH="${GIT_AUTH:-ssh}"
GIT_TOKEN="${GIT_TOKEN:-}"
GIT_SSH_KEY="${GIT_SSH_KEY:-}"

GH_HOST="${GH_HOST:-}"
GH_PROFILE="${GH_PROFILE:-}"

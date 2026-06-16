# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${WHITE}ℹ️  $*${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >> "$LOG_FILE" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $*" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}❌ $*${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Safe clear function that won't fail if TERM is not set or not a TTY
clear() {
    if [ -t 1 ] && [ -n "${TERM:-}" ]; then
        command clear 2>/dev/null || true
    fi
}

# Error handler
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script terminated with error code: $exit_code"
    fi
}
trap cleanup_on_error EXIT

# Safe directory creation
create_dir_safe() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || { log_error "Failed to create directory: $dir"; return 1; }
    fi
    return 0
}

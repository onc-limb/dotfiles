#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }

# Counters
COUNT_APPEND=0
COUNT_SKIP=0
COUNT_ERROR=0

# Collected entries: "section/ref|date|content_lines"
ENTRIES=()

usage() {
    echo "Usage: sort-notes.sh [--dry-run|--execute] DATE [DATE...]"
    echo ""
    echo "Options:"
    echo "  --dry-run   Preview changes without writing (default)"
    echo "  --execute   Perform actual file writes"
    echo ""
    echo "DATE format: YYYY-MM-DD"
    echo "  Single date:  sort-notes.sh 2026-02-07"
    echo "  Date range:   sort-notes.sh 2026-02-01 2026-02-07"
    exit 1
}

validate_date() {
    local date="$1"
    if [[ ! "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        error "Invalid date format: $date (expected YYYY-MM-DD)"
        exit 1
    fi
    # Verify the date is valid on macOS
    if ! date -j -f "%Y-%m-%d" "$date" "+%Y-%m-%d" &>/dev/null; then
        error "Invalid date: $date"
        exit 1
    fi
}

expand_date_range() {
    local start="$1"
    local end="$2"

    # Verify start <= end
    if [[ "$start" > "$end" ]]; then
        error "Start date must be before or equal to end date: $start > $end"
        exit 1
    fi

    local current="$start"
    while [[ "$current" < "$end" || "$current" == "$end" ]]; do
        echo "$current"
        current=$(date -j -v+1d -f "%Y-%m-%d" "$current" "+%Y-%m-%d")
    done
}

is_duplicate() {
    local target="$1"
    local date="$2"
    if [ ! -f "$target" ]; then
        return 1
    fi
    grep -qF "## ${date}" "$target"
}

# Trim leading and trailing blank lines from content
trim_blank_lines() {
    local content="$1"
    # Remove leading blank lines
    content=$(printf '%s' "$content" | sed '/./,$!d')
    # Remove trailing blank lines (macOS compatible)
    while [[ "$content" =~ $'\n'$ ]]; do
        content="${content%$'\n'}"
    done
    # Also remove trailing whitespace-only content
    local last_line
    while true; do
        last_line="${content##*$'\n'}"
        if [[ -z "${last_line// /}" ]] && [[ "$content" == *$'\n'* ]]; then
            content="${content%$'\n'*}"
        else
            break
        fi
    done
    printf '%s' "$content"
}

is_empty_content() {
    local content="$1"
    local trimmed
    trimmed=$(echo "$content" | sed '/^\s*$/d')
    [ -z "$trimmed" ]
}

flush_entry() {
    local section="$1"
    local ref="$2"
    local date="$3"
    local content="$4"

    if [ -z "$section" ] || [ -z "$ref" ]; then
        return
    fi

    if is_empty_content "$content"; then
        skip "${section}/${ref}.md: empty content"
        COUNT_SKIP=$((COUNT_SKIP + 1))
        return
    fi

    local target="${section}/${ref}.md"
    local trimmed
    trimmed=$(trim_blank_lines "$content")

    if is_duplicate "$target" "$date"; then
        skip "${target}: ## ${date} already exists"
        COUNT_SKIP=$((COUNT_SKIP + 1))
        return
    fi

    # Store entry for processing
    ENTRIES+=("${target}|${date}|${trimmed}")
    COUNT_APPEND=$((COUNT_APPEND + 1))
}

parse_daily_note() {
    local file="$1"
    local date="$2"

    if [ ! -f "$file" ]; then
        error "${file} not found"
        COUNT_ERROR=$((COUNT_ERROR + 1))
        return
    fi

    echo ""
    echo -e "${BLUE}[${file}]${NC}"

    local current_section=""
    local current_ref=""
    local content_lines=""

    while IFS= read -r line || [ -n "$line" ]; do
        # Match ## work, ## tech, ## private (with optional trailing whitespace)
        if [[ "$line" =~ ^##\ (work|tech|private)[[:space:]]*$ ]]; then
            flush_entry "$current_section" "$current_ref" "$date" "$content_lines"
            current_section="${BASH_REMATCH[1]}"
            current_ref=""
            content_lines=""

        # Match any other ## header (e.g., ## memo) — exit tracked section
        elif [[ "$line" =~ ^##\  ]]; then
            flush_entry "$current_section" "$current_ref" "$date" "$content_lines"
            current_section=""
            current_ref=""
            content_lines=""

        # Match ### #ref/xxx within a tracked section
        elif [[ "$line" =~ ^###\ \#ref/(.+)$ ]] && [ -n "$current_section" ]; then
            flush_entry "$current_section" "$current_ref" "$date" "$content_lines"
            current_ref="${BASH_REMATCH[1]}"
            # Trim trailing whitespace from ref
            current_ref=$(echo "$current_ref" | sed 's/[[:space:]]*$//')
            content_lines=""

        # Match any other ### header within a tracked section — stop collecting
        elif [[ "$line" =~ ^###\  ]] && [ -n "$current_section" ]; then
            flush_entry "$current_section" "$current_ref" "$date" "$content_lines"
            current_ref=""
            content_lines=""

        # Collect content lines when inside a tracked section + ref
        elif [ -n "$current_section" ] && [ -n "$current_ref" ]; then
            if [ -z "$content_lines" ]; then
                content_lines="$line"
            else
                content_lines="${content_lines}
${line}"
            fi
        fi
    done < "$file"

    # Flush remaining content at end of file
    flush_entry "$current_section" "$current_ref" "$date" "$content_lines"
}

print_dry_run_entries() {
    for entry in "${ENTRIES[@]}"; do
        local target="${entry%%|*}"
        local rest="${entry#*|}"
        local date="${rest%%|*}"
        local content="${rest#*|}"

        echo ""
        echo "${target} << ## ${date}"
        echo "$content" | sed 's/^/  /'
    done
}

execute_entries() {
    for entry in "${ENTRIES[@]}"; do
        local target="${entry%%|*}"
        local rest="${entry#*|}"
        local date="${rest%%|*}"
        local content="${rest#*|}"

        # Create directory if needed
        local dir
        dir=$(dirname "$target")
        mkdir -p "$dir"

        # Append to file with date header
        {
            # Add a blank line before the entry if the file already exists and is non-empty
            if [ -s "$target" ]; then
                echo ""
            fi
            echo "## ${date}"
            echo ""
            echo "$content"
        } >> "$target"

        ok "${target} << ## ${date}"
    done
}

# --- Main ---

MODE="--dry-run"
DATES=()

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            MODE="--dry-run"
            shift
            ;;
        --execute)
            MODE="--execute"
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            DATES+=("$1")
            shift
            ;;
    esac
done

if [ ${#DATES[@]} -eq 0 ]; then
    error "No dates specified"
    usage
fi

# Validate all dates
for d in "${DATES[@]}"; do
    validate_date "$d"
done

# Expand date range if two dates given
if [ ${#DATES[@]} -eq 2 ]; then
    EXPANDED=()
    while IFS= read -r d; do
        EXPANDED+=("$d")
    done < <(expand_date_range "${DATES[0]}" "${DATES[1]}")
    DATES=("${EXPANDED[@]}")
fi

# Header
if [ "$MODE" = "--dry-run" ]; then
    echo "=== sort-notes dry-run ==="
else
    echo "=== sort-notes execute ==="
fi

# Parse all daily notes
for date in "${DATES[@]}"; do
    parse_daily_note "daily/${date}.md" "$date"
done

# Execute or preview
if [ "$MODE" = "--execute" ] && [ ${#ENTRIES[@]} -gt 0 ]; then
    echo ""
    execute_entries
fi

if [ "$MODE" = "--dry-run" ] && [ ${#ENTRIES[@]} -gt 0 ]; then
    print_dry_run_entries
fi

# Summary
echo ""
echo "=== summary ==="
if [ "$MODE" = "--dry-run" ]; then
    echo "append: ${COUNT_APPEND}"
else
    echo "written: ${COUNT_APPEND}"
fi
echo "skip: ${COUNT_SKIP}"
echo "error: ${COUNT_ERROR}"

#!/usr/bin/env bash
# =============================================================================
# deploy_agent.sh - Student Attendance Tracker bootstrapper
#
# Features:
#   1) Deploy   - build attendance_tracker_{name}/ from templates/, set perms,
#                 optionally update thresholds, then run the app to verify.
#   2) Run      - run attendance_checker.py on an existing deployment.
#   3) Archive  - move reports/*.log into timestamped archive directories.
#
# Usage:
#   ./deploy_agent.sh              -> interactive menu
#   ./deploy_agent.sh deploy       -> feature 1
#   ./deploy_agent.sh run          -> feature 2
#   ./deploy_agent.sh archive      -> feature 3
#
# Signals: during deployment Ctrl+C (SIGINT) and Ctrl+Z (SIGTSTP) are trapped.
# The partial project is zipped to attendance_tracker_{name}_archive.zip and
# the incomplete directory is deleted.
# =============================================================================

# Always work from the folder that holds this script (templates/ lives here)
cd "$(dirname "${BASH_SOURCE[0]}")" || { echo "[ERROR] Cannot enter script directory." >&2; exit 1; }
ROOT_DIR="$(pwd)"
TEMPLATES_DIR="$ROOT_DIR/templates"

PROJECT_DIR=""      # set only AFTER we create the directory (so we never zip/delete something we did not make)
INPUT_NAME=""

# ---------- Small output helpers ----------
info() { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*" >&2; }

# ---------- Cleanup / failure handling ----------
remove_partial_dir() {
    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        rm -rf "$PROJECT_DIR"
    fi
}

# Used for any hard failure during deployment: report, remove half-built dir, exit.
fail() {
    err "$*"
    trap - INT TSTP
    remove_partial_dir
    exit 1
}

# ---------- Signal handling (Ctrl+C / Ctrl+Z) ----------
handle_interrupt() {
    local sig="$1"
    trap '' INT TSTP    # ignore further signals while cleaning up
    echo
    echo "[!] Deployment interrupted by $sig."

    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        local zipfile="${PROJECT_DIR}_archive.zip"
        echo "[!] Archiving the incomplete project into $zipfile ..."
        if zip -rq "$zipfile" "$PROJECT_DIR"; then
            ok "Archive created: $ROOT_DIR/$zipfile"
            rm -rf "$PROJECT_DIR"
            ok "Incomplete directory '$PROJECT_DIR' removed."
        else
            err "Could not create the archive; leaving '$PROJECT_DIR' in place."
        fi
    else
        info "Nothing had been created yet, so there is nothing to archive."
    fi

    echo "[!] Session closed cleanly."
    exit 130
}

enable_traps()  {
    trap 'handle_interrupt SIGINT'  INT
    trap 'handle_interrupt SIGTSTP' TSTP
}
disable_traps() { trap - INT TSTP; }

# ---------- Input helpers ----------

# Ask for a project name; validates and sets INPUT_NAME
ask_project_name() {
    local v
    while true; do
        read -r -p "Enter project name (used as attendance_tracker_<name>): " v || fail "Input closed."
        if [[ "$v" =~ ^[A-Za-z0-9_-]+$ ]]; then
            INPUT_NAME="$v"
            return
        fi
        err "Use only letters, numbers, '_' or '-' (no spaces, not empty)."
    done
}

# prompt_int "prompt" min max -> sets INT_VALUE
prompt_int() {
    local prompt="$1" min="$2" max="$3" v
    while true; do
        read -r -p "$prompt" v || fail "Input closed."
        if [[ "$v" =~ ^[0-9]+$ ]] && (( 10#$v >= min && 10#$v <= max )); then
            INT_VALUE=$((10#$v))
            return
        fi
        err "Please enter a whole number between $min and $max."
    done
}

# prompt_threshold "label" default -> sets THRESH (numeric 0-100, empty = default)
prompt_threshold() {
    local label="$1" def="$2" v
    while true; do
        read -r -p "New $label threshold [default $def]: " v || fail "Input closed."
        v="${v:-$def}"
        if [[ "$v" =~ ^[0-9]+$ ]] && (( 10#$v <= 100 )); then
            THRESH=$((10#$v))
            return
        fi
        err "Threshold must be a whole number between 0 and 100."
    done
}

# ---------- Sample data for Option B ----------
SAMPLE_NAMES=(
    "Alice Johnson" "Bob Smith" "Carol Williams" "David Brown" "Eva Davis"
    "Frank Miller" "Grace Wilson" "Henry Moore" "Ivy Taylor" "Jack Anderson"
    "Karen Thomas" "Leo Jackson" "Mia White" "Noah Harris" "Olivia Martin"
    "Paul Thompson" "Quinn Garcia" "Rita Martinez" "Sam Robinson" "Tina Clark"
)

generate_roster() {   # generate_roster <count> <file>
    local n="$1" file="$2" i name email
    echo "Email,Names,Attendance Count,Absence Count" > "$file" || return 1
    for ((i = 0; i < n; i++)); do
        name="${SAMPLE_NAMES[$i]}"
        email="$(echo "$name" | tr 'A-Z' 'a-z' | tr ' ' '.')@example.com"
        echo "$email,$name,0,0" >> "$file" || return 1
    done
}

# ---------- Pre-flight ----------
preflight_checks() {
    info "Running pre-flight checks..."
    if ! command -v python3 >/dev/null 2>&1; then
        err "python3 is not installed. Install it first (e.g. sudo apt install python3)."
        exit 1
    fi
    ok "$(python3 --version 2>&1)"

    if ! command -v zip >/dev/null 2>&1; then
        err "zip is not installed. Install it first (e.g. sudo apt install zip)."
        exit 1
    fi
    ok "zip is available."

    local f
    for f in attendance_checker.py assets.csv config.json; do
        if [[ ! -r "$TEMPLATES_DIR/$f" ]]; then
            err "Missing or unreadable template: templates/$f"
            exit 1
        fi
    done
    ok "All templates found in templates/."
}

# ---------- Feature 2: run ----------
run_app() {   # run_app <project_dir>
    local dir="$1"
    if [[ ! -f "$dir/attendance_checker.py" ]]; then
        err "'$dir/attendance_checker.py' not found. Deploy the project first."
        return 1
    fi
    info "Starting the Attendance Checker in $dir ..."
    ( cd "$dir" && python3 attendance_checker.py )
    local rc=$?
    if (( rc == 0 )); then
        ok "Application finished successfully."
    else
        err "Application exited with code $rc."
    fi
    return $rc
}

feature_run() {
    ask_project_name
    run_app "attendance_tracker_${INPUT_NAME}"
}

# ---------- Feature 3: archive ----------
feature_archive() {
    ask_project_name
    local dir="attendance_tracker_${INPUT_NAME}"
    if [[ ! -d "$dir" ]]; then
        err "Project '$dir' does not exist."
        return 1
    fi

    local ts att_src abs_src archived=0
    ts="$(date +%Y%m%d_%H%M%S)"
    att_src="$dir/reports/attendance.log"
    abs_src="$dir/reports/absent.log"

    mkdir -p "$dir/archives/attendance" "$dir/archives/absent" \
        || { err "Cannot create archive directories (permission denied?)."; return 1; }

    if [[ -f "$att_src" ]]; then
        local att_dest="$dir/archives/attendance/attendance_${ts}.log"
        if mv "$att_src" "$att_dest"; then
            ok "Archived attendance.log -> $att_dest"
            archived=$((archived + 1))
        else
            err "Failed to archive attendance.log"
        fi
    else
        warn "reports/attendance.log not found - nothing to archive for attendance."
    fi

    if [[ -f "$abs_src" ]]; then
        local abs_dest="$dir/archives/absent/absent_${ts}.log"
        if mv "$abs_src" "$abs_dest"; then
            ok "Archived absent.log -> $abs_dest"
            archived=$((archived + 1))
        else
            err "Failed to archive absent.log"
        fi
    else
        warn "reports/absent.log not found (nobody absent, or app not run yet)."
    fi

    info "Archive complete: $archived log file(s) archived."
    return 0
}

# ---------- Feature 1: deploy ----------
feature_deploy() {
    preflight_checks

    ask_project_name
    local dir="attendance_tracker_${INPUT_NAME}"

    # Existing directory: never overwrite silently
    if [[ -e "$dir" ]]; then
        warn "'$dir' already exists."
        local ans
        read -r -p "Overwrite it? This deletes the existing project. [y/N]: " ans || { err "Input closed."; exit 1; }
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            rm -rf "$dir" || { err "Could not remove existing '$dir' (permission denied?)."; exit 1; }
            info "Existing '$dir' removed."
        else
            err "Aborted: '$dir' already exists and overwrite was declined."
            exit 1
        fi
    fi

    # From here on, interrupts are handled (zip + clean up)
    enable_traps

    info "Creating directory structure..."
    mkdir -p "$dir/Helpers" "$dir/reports" \
        || { err "Cannot create '$dir' (permission denied?)."; disable_traps; PROJECT_DIR="$dir"; fail "Directory creation failed."; }
    PROJECT_DIR="$dir"
    ok "Created $dir/, $dir/Helpers/, $dir/reports/"

    # --- Always-unmodified files ---
    cp "$TEMPLATES_DIR/attendance_checker.py" "$dir/attendance_checker.py" || fail "Could not copy attendance_checker.py."
    cp "$TEMPLATES_DIR/config.json"           "$dir/Helpers/config.json"   || fail "Could not copy config.json."
    ok "Deployed attendance_checker.py and Helpers/config.json from templates."

    # --- Roster ---
    echo
    echo "How should the student roster (Helpers/assets.csv) be built?"
    echo "  A) Copy N students from the template (4 prior sessions each)"
    echo "  B) Generate a fresh roster (counts start at 0)"
    local choice
    while true; do
        read -r -p "Choose A or B: " choice || fail "Input closed."
        [[ "$choice" =~ ^[AaBb]$ ]] && break
        err "Please type A or B."
    done

    local total_sessions
    if [[ "$choice" =~ ^[Aa]$ ]]; then
        local available
        available=$(( $(grep -c '' "$TEMPLATES_DIR/assets.csv") - 1 ))
        (( available < 1 )) && fail "Template roster has no student rows."
        prompt_int "How many students to copy (1-$available)? " 1 "$available"
        head -n $((INT_VALUE + 1)) "$TEMPLATES_DIR/assets.csv" > "$dir/Helpers/assets.csv" \
            || fail "Could not write assets.csv."
        total_sessions=5
        ok "Copied $INT_VALUE student(s) from the template roster."
    else
        local max=${#SAMPLE_NAMES[@]}
        prompt_int "How many students to generate (1-$max)? " 1 "$max"
        generate_roster "$INT_VALUE" "$dir/Helpers/assets.csv" || fail "Could not generate assets.csv."
        total_sessions=1
        ok "Generated a fresh roster of $INT_VALUE student(s)."
    fi

    # Keep config consistent with roster: total_sessions = prior sessions + 1
    sed -i.bak -E "s/(\"total_sessions\":[[:space:]]*)[0-9]+/\1${total_sessions}/" "$dir/Helpers/config.json" \
        && rm -f "$dir/Helpers/config.json.bak" \
        || fail "Could not set total_sessions in config.json."
    ok "total_sessions set to $total_sessions (matches roster)."

    # --- Permissions ---
    chmod +x "$dir/attendance_checker.py" || fail "chmod +x failed on attendance_checker.py."
    chmod 600 "$dir/Helpers/config.json"  || fail "chmod 600 failed on config.json."
    ok "Permissions set:"
    ls -l "$dir/attendance_checker.py" "$dir/Helpers/config.json" | awk '{print "         " $1, $NF}'

    # --- Threshold update ---
    echo
    local upd
    read -r -p "Update attendance alert thresholds in config.json? [y/N]: " upd || fail "Input closed."
    if [[ "$upd" =~ ^[Yy]$ ]]; then
        local warn_val fail_val
        while true; do
            prompt_threshold "warning" 75; warn_val=$THRESH
            prompt_threshold "failure" 50; fail_val=$THRESH
            if (( fail_val < warn_val )); then
                break
            fi
            err "Failure threshold ($fail_val) must be lower than warning threshold ($warn_val). Try again."
        done
        sed -i.bak -E \
            -e "s/(\"warning\":[[:space:]]*)[0-9]+/\1${warn_val}/" \
            -e "s/(\"failure\":[[:space:]]*)[0-9]+/\1${fail_val}/" \
            "$dir/Helpers/config.json" \
            && rm -f "$dir/Helpers/config.json.bak" \
            || fail "Could not update thresholds in config.json."
        ok "Thresholds updated: warning=$warn_val, failure=$fail_val"
    else
        info "Keeping default thresholds (warning=75, failure=50)."
    fi

    # Deployment finished: stop trapping so the marking session behaves normally
    disable_traps
    echo
    ok "Deployment complete: $ROOT_DIR/$dir"
    echo
    info "Verifying deployment by running the application..."
    run_app "$dir"
}

# ---------- Menu ----------
show_menu() {
    echo "=============================================="
    echo "   Attendance Tracker - Deploy Agent"
    echo "=============================================="
    echo "  1) Deploy the application"
    echo "  2) Run the application"
    echo "  3) Archive log files"
    echo "  4) Exit"
    echo "----------------------------------------------"
}

dispatch() {
    case "$1" in
        1|deploy)  feature_deploy  ;;
        2|run)     feature_run     ;;
        3|archive) feature_archive ;;
        4|exit|quit) exit 0 ;;
        *) err "Invalid option: '$1'"; return 1 ;;
    esac
}

main() {
    if [[ $# -ge 1 ]]; then
        dispatch "$1"
        exit $?
    fi
    while true; do
        show_menu
        read -r -p "Select an option [1-4]: " opt || exit 0
        dispatch "$opt"
        echo
        done
}
 
main "$@"

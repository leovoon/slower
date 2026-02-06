#!/usr/bin/env bash
# slower - reminds you to walk every X minutes

# Configuration
APP_NAME="Slower"
DEFAULT_INTERVAL=60
DEFAULT_MESSAGE="Time to walk! Get up and move for 5 minutes."
DEFAULT_SAY_MESSAGE="Time to walk"
DEFAULT_SOUND="Glass"
DEFAULT_VOICE=""
BASE_DIR="$HOME/.slower"
LOG_DIR_DEFAULT="$BASE_DIR/logs"
SESSION="default"
PIDFILE=""
STATEFILE=""
LOG_FILE_DEFAULT=""
LOG_FILE=""
LOG_ENABLED=0
LOG_PATH_REQUEST=""
LAUNCHD_LABEL_BASE="com.leovoon.slower"
LAUNCHD_PLIST_DEFAULT=""
LOG_OUT_DEFAULT=""
LOG_ERR_DEFAULT=""
SCRIPT_NAME="$(basename "$0")"

MESSAGE="$DEFAULT_MESSAGE"
SAY_MESSAGE="$DEFAULT_SAY_MESSAGE"
SOUND="$DEFAULT_SOUND"
VOICE="$DEFAULT_VOICE"
QUIET_ENABLED=0
QUIET_START_MIN=0
QUIET_END_MIN=0

# --- Functions ---

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

escape_osascript() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

is_none() {
    case "$1" in
        [Nn][Oo][Nn][Ee]) return 0 ;;
        *) return 1 ;;
    esac
}

validate_session_name() {
    if [[ ! "$SESSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Error: invalid session name '$SESSION'. Use letters, numbers, dots, dashes, or underscores."
        exit 1
    fi
}

set_session_paths() {
    PIDFILE="$BASE_DIR/${SESSION}.pid"
    STATEFILE="$BASE_DIR/${SESSION}.state"
    LOG_FILE_DEFAULT="$LOG_DIR_DEFAULT/${SESSION}.log"

    local label="$LAUNCHD_LABEL_BASE"
    if [[ "$SESSION" != "default" ]]; then
        label="${LAUNCHD_LABEL_BASE}.${SESSION}"
    fi
    LAUNCHD_PLIST_DEFAULT="$HOME/Library/LaunchAgents/${label}.plist"
    LOG_OUT_DEFAULT="$HOME/Library/Logs/${label}.log"
    LOG_ERR_DEFAULT="$HOME/Library/Logs/${label}.err.log"

    if [[ "$LOG_ENABLED" -eq 1 ]]; then
        if [[ -n "$LOG_PATH_REQUEST" ]]; then
            LOG_FILE="${LOG_PATH_REQUEST/#\~/$HOME}"
        else
            LOG_FILE="$LOG_FILE_DEFAULT"
        fi
    else
        LOG_FILE=""
    fi
}

ensure_dirs() {
    mkdir -p "$BASE_DIR" >/dev/null 2>&1 || true
    if [[ "$LOG_ENABLED" -eq 1 && -n "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")" >/dev/null 2>&1 || true
    fi
}

log_event() {
    if [[ "$LOG_ENABLED" -eq 1 && -n "$LOG_FILE" ]]; then
        ensure_dirs
        printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SESSION" "$1" >> "$LOG_FILE"
    fi
}

parse_time_to_minutes() {
    local value=$1
    if [[ "$value" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        printf '%s' "$((10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]}))"
        return 0
    fi
    return 1
}

parse_quiet_range() {
    local range=$1
    if [[ "$range" != *-* ]]; then
        return 1
    fi
    local start="${range%-*}"
    local end="${range#*-}"
    local start_min end_min
    start_min="$(parse_time_to_minutes "$start")" || return 1
    end_min="$(parse_time_to_minutes "$end")" || return 1

    QUIET_START_MIN=$start_min
    QUIET_END_MIN=$end_min
    QUIET_ENABLED=1
}

current_minutes() {
    printf '%s' "$((10#$(date +%H) * 60 + 10#$(date +%M)))"
}

current_seconds() {
    printf '%s' "$((10#$(date +%S)))"
}

is_quiet_now() {
    local now_min=$1
    [[ "$QUIET_ENABLED" -eq 1 ]] || return 1
    if [[ "$QUIET_START_MIN" -eq "$QUIET_END_MIN" ]]; then
        return 1
    fi

    if [[ "$QUIET_START_MIN" -lt "$QUIET_END_MIN" ]]; then
        [[ "$now_min" -ge "$QUIET_START_MIN" && "$now_min" -lt "$QUIET_END_MIN" ]]
    else
        [[ "$now_min" -ge "$QUIET_START_MIN" || "$now_min" -lt "$QUIET_END_MIN" ]]
    fi
}

seconds_until_quiet_end() {
    local now_min=$1
    local now_sec=$2
    local minutes_until

    if [[ "$QUIET_START_MIN" -lt "$QUIET_END_MIN" ]]; then
        minutes_until=$((QUIET_END_MIN - now_min))
    else
        if [[ "$now_min" -ge "$QUIET_START_MIN" ]]; then
            minutes_until=$((1440 - now_min + QUIET_END_MIN))
        else
            minutes_until=$((QUIET_END_MIN - now_min))
        fi
    fi

    local seconds=$((minutes_until * 60 - now_sec))
    if [[ "$seconds" -le 0 ]]; then
        seconds=1
    fi
    printf '%s' "$seconds"
}
notify() {
    local message=$1
    local sound=$2
    if have_cmd osascript; then
        local escaped_message
        escaped_message="$(escape_osascript "$message")"
        if [[ -n "$sound" ]] && ! is_none "$sound"; then
            local escaped_sound
            escaped_sound="$(escape_osascript "$sound")"
            osascript -e "display notification \"$escaped_message\" with title \"$APP_NAME\" sound name \"$escaped_sound\"" >/dev/null 2>&1 || true
        else
            osascript -e "display notification \"$escaped_message\" with title \"$APP_NAME\"" >/dev/null 2>&1 || true
        fi
    else
        printf '%s\n' "$message"
    fi
}

speak() {
    local message=$1
    local voice=$2
    if have_cmd say; then
        if [[ -n "$voice" ]] && ! is_none "$voice"; then
            say -v "$voice" "$message" >/dev/null 2>&1 || true
        elif [[ -z "$voice" ]]; then
            say "$message" >/dev/null 2>&1 || true
        fi
    fi
}

run_daemon() {
    local interval=$1
    trap 'rm -f "$PIDFILE" "$STATEFILE"; exit 0' TERM INT HUP QUIT
    while true; do
        local now_epoch now_min now_sec sleep_seconds next_epoch
        now_epoch=$(date +%s)
        now_min="$(current_minutes)"
        now_sec="$(current_seconds)"

        if is_quiet_now "$now_min"; then
            sleep_seconds="$(seconds_until_quiet_end "$now_min" "$now_sec")"
            next_epoch=$((now_epoch + sleep_seconds))
            update_next_notification_epoch "$next_epoch"
            log_event "Quiet hours active. Next notification in $(format_duration "$sleep_seconds")."
            sleep "$sleep_seconds"
            continue
        fi

        notify "$MESSAGE" "$SOUND"
        speak "$SAY_MESSAGE" "$VOICE"
        log_event "Notification sent."

        sleep_seconds=$((interval * 60))
        next_epoch=$((now_epoch + sleep_seconds))
        update_next_notification_epoch "$next_epoch"
        sleep "$sleep_seconds"
    done
}

process_start_time() {
    ps -p "$1" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//'
}

process_start_time_with_retry() {
    local pid=$1
    local start=""
    local attempt

    for attempt in 1 2 3 4 5; do
        start="$(process_start_time "$pid")"
        if [[ -n "$start" ]]; then
            break
        fi
        sleep 0.05
    done

    printf '%s' "$start"
}

read_pidfile() {
    PID=""
    START_TIME=""
    if [[ -f "$PIDFILE" ]]; then
        IFS='|' read -r PID START_TIME < "$PIDFILE" || true
    fi
}

pid_matches_expected() {
    local pid=$1
    local recorded_start=$2

    if [[ -n "$recorded_start" ]]; then
        local current_start
        current_start="$(process_start_time "$pid")"
        [[ -n "$current_start" && "$current_start" == "$recorded_start" ]]
        return $?
    fi

    local args
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    [[ -n "$args" && "$args" == *"$SCRIPT_NAME"* ]]
}

is_running() {
    read_pidfile
    [[ -n "$PID" && "$PID" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$PID" 2>/dev/null || return 1
    pid_matches_expected "$PID" "$START_TIME"
}

write_pidfile() {
    local pid=$1
    local start_time
    ensure_dirs
    start_time="$(process_start_time_with_retry "$pid")"
    printf '%s|%s\n' "$pid" "$start_time" > "$PIDFILE"
}

prepare_start() {
    if is_running; then
        echo "Slower is already running for session '$SESSION' (PID $PID)."
        exit 1
    fi
    if [[ -f "$PIDFILE" ]]; then
        read_pidfile
        if [[ -n "$PID" ]]; then
            echo "Found stale PID file for PID $PID. Removing it."
        else
            echo "Found invalid PID file. Removing it."
        fi
        rm -f "$PIDFILE" "$STATEFILE"
    fi
}

start_background() {
    local interval=$1
    run_daemon "$interval" &>/dev/null &

    local pid=$!
    write_pidfile "$pid"
    disown
    echo "Slower started in background (PID $pid)."
    log_event "Started in background (PID $pid, interval ${interval}m)."
}

start_foreground() {
    local interval=$1
    local pid=$$
    write_pidfile "$pid"
    echo "Slower running in foreground (PID $pid). Press Ctrl+C to stop."
    log_event "Started in foreground (PID $pid, interval ${interval}m)."
    run_daemon "$interval"
}

stop_daemon() {
    if [[ -f "$PIDFILE" ]]; then
        read_pidfile
        if [[ -z "$PID" ]]; then
            rm -f "$PIDFILE"
            echo "Slower was not running."
            return
        fi
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
            rm -f "$PIDFILE" "$STATEFILE"
            echo "Slower stopped."
            log_event "Stopped (PID $PID)."
        else
            rm -f "$PIDFILE" "$STATEFILE"
            echo "Slower was not running (session '$SESSION')."
        fi
    else
        echo "Slower is not running (session '$SESSION')."
    fi
}

remove_self() {
    if is_running; then
        stop_daemon
    else
        if [[ -f "$PIDFILE" ]]; then
            rm -f "$PIDFILE"
        fi
    fi
    if [[ -f "$STATEFILE" ]]; then
        rm -f "$STATEFILE"
    fi
    log_event "Uninstalled session."
}

update_next_notification_epoch() {
    local epoch=$1
    ensure_dirs
    printf '%s\n' "$epoch" > "$STATEFILE"
}

format_duration() {
    local total=$1
    if [[ "$total" -le 0 ]]; then
        printf '0s'
        return
    fi

    local hours minutes seconds
    hours=$((total / 3600))
    minutes=$(((total % 3600) / 60))
    seconds=$((total % 60))

    if [[ "$hours" -gt 0 ]]; then
        printf '%dh %dm' "$hours" "$minutes"
    elif [[ "$minutes" -gt 0 ]]; then
        printf '%dm %ds' "$minutes" "$seconds"
    else
        printf '%ds' "$seconds"
    fi
}

status_remaining() {
    if [[ ! -f "$STATEFILE" ]]; then
        return
    fi

    local next_epoch now remaining
    next_epoch=$(cat "$STATEFILE" 2>/dev/null || true)
    if [[ ! "$next_epoch" =~ ^[0-9]+$ ]]; then
        return
    fi

    now=$(date +%s)
    remaining=$((next_epoch - now))

    if [[ "$remaining" -le 0 ]]; then
        echo "Next notification: due now."
    else
        echo "Next notification in $(format_duration "$remaining")."
    fi
}

list_voices() {
    if have_cmd say; then
        say -v '?'
    else
        echo "The 'say' command is not available on this system."
    fi
}

list_sessions() {
    local found=0
    if [[ -d "$BASE_DIR" ]]; then
        local pidfile
        for pidfile in "$BASE_DIR"/*.pid; do
            [[ -e "$pidfile" ]] || continue
            local name
            name="$(basename "$pidfile" .pid)"
            SESSION="$name"
            set_session_paths
            if is_running; then
                echo "Session '$name': running (PID $PID)"
            else
                echo "Session '$name': not running"
            fi
            found=1
        done
    fi
    if [[ "$found" -eq 0 ]]; then
        echo "No sessions found."
    fi
}

stop_all_sessions() {
    local found=0
    if [[ -d "$BASE_DIR" ]]; then
        local pidfile
        for pidfile in "$BASE_DIR"/*.pid; do
            [[ -e "$pidfile" ]] || continue
            local name
            name="$(basename "$pidfile" .pid)"
            SESSION="$name"
            set_session_paths
            if is_running; then
                stop_daemon
                echo "Stopped session '$SESSION'."
            else
                if [[ -f "$PIDFILE" || -f "$STATEFILE" ]]; then
                    rm -f "$PIDFILE" "$STATEFILE"
                fi
                echo "Slower is not running (session '$SESSION')."
            fi
            found=1
        done
    fi
    if [[ "$found" -eq 0 ]]; then
        echo "No sessions found."
    fi
}

usage() {
    echo "Usage: $SCRIPT_NAME [start|stop|status|run|uninstall|voices|sessions] [options]"
    echo "  -t, --time           Set interval in minutes (default: 60)"
    echo "  -n, --name           Session name (default: default)"
    echo "      --quiet          Quiet hours in HH:MM-HH:MM (no notifications)"
    echo "  -m, --message        Notification and spoken message"
    echo "      --say-message    Spoken message only (overrides --message for voice)"
    echo "  -s, --sound          Notification sound name (use 'none' for silent)"
    echo "  -v, --voice          Voice name for say (use 'none' to disable speech)"
    echo "      --log [path]     Enable logging (default: ~/.slower/logs/<name>.log)"
    echo "      --purge          With uninstall: remove default LaunchAgent plist and logs"
    echo "  -a, --all            With stop: stop all sessions"
    echo "  voices               List available system voices"
    echo "  sessions             List known sessions and their status"
    exit 1
}

# --- Argument Parsing ---

COMMAND="start"
INTERVAL=$DEFAULT_INTERVAL
PURGE=0
STOP_ALL=0

# Check if the first argument is a command (start/stop/status)
if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
    COMMAND=$1
    shift
fi

# Parse remaining flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--time)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                INTERVAL=$2
                shift 2
            else
                echo "Error: --time requires a numeric argument."
                exit 1
            fi
            ;;
        -n|--name)
            if [[ -n "$2" ]]; then
                SESSION=$2
                shift 2
            else
                echo "Error: --name requires an argument."
                exit 1
            fi
            ;;
        --quiet)
            if [[ -n "$2" ]]; then
                if ! parse_quiet_range "$2"; then
                    echo "Error: --quiet must be in HH:MM-HH:MM format."
                    exit 1
                fi
                shift 2
            else
                echo "Error: --quiet requires an argument."
                exit 1
            fi
            ;;
        -m|--message)
            if [[ -n "$2" ]]; then
                MESSAGE=$2
                SAY_MESSAGE=$2
                shift 2
            else
                echo "Error: --message requires an argument."
                exit 1
            fi
            ;;
        --say-message)
            if [[ -n "$2" ]]; then
                SAY_MESSAGE=$2
                shift 2
            else
                echo "Error: --say-message requires an argument."
                exit 1
            fi
            ;;
        -s|--sound)
            if [[ -n "$2" ]]; then
                SOUND=$2
                shift 2
            else
                echo "Error: --sound requires an argument."
                exit 1
            fi
            ;;
        -v|--voice)
            if [[ -n "$2" ]]; then
                VOICE=$2
                shift 2
            else
                echo "Error: --voice requires an argument."
                exit 1
            fi
            ;;
        --log)
            LOG_ENABLED=1
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                LOG_PATH_REQUEST=$2
                shift 2
            else
                shift
            fi
            ;;
        -h|--help)
            usage
            ;;
        --purge)
            PURGE=1
            shift
            ;;
        -a|--all)
            STOP_ALL=1
            shift
            ;;
        *)
            usage
            ;;
    esac
done

# --- Safety Check ---

validate_session_name
set_session_paths

# --- Main Logic ---

case "$COMMAND" in
    start)
        prepare_start
        echo "Starting slower (session '$SESSION', every ${INTERVAL} minutes)..."
        start_background "$INTERVAL"
        ;;
    run)
        prepare_start
        echo "Starting slower in foreground (session '$SESSION', every ${INTERVAL} minutes)..."
        start_foreground "$INTERVAL"
        ;;
    stop)
        if [[ "$STOP_ALL" -eq 1 ]]; then
            stop_all_sessions
            exit 0
        fi
        if is_running; then
            stop_daemon
        else
            if [[ -f "$PIDFILE" ]]; then
                read_pidfile
                echo "Slower is not running for session '$SESSION'. Removing stale PID file."
                rm -f "$PIDFILE" "$STATEFILE"
            else
                echo "Slower is not running (session '$SESSION')."
            fi
        fi
        ;;
    uninstall)
        remove_self
        if [[ "$PURGE" -eq 1 ]]; then
            if have_cmd launchctl && [[ -f "$LAUNCHD_PLIST_DEFAULT" ]]; then
                launchctl bootout "gui/$UID" "$LAUNCHD_PLIST_DEFAULT" >/dev/null 2>&1 || true
            fi
            rm -f "$LAUNCHD_PLIST_DEFAULT" "$LOG_OUT_DEFAULT" "$LOG_ERR_DEFAULT"
            if [[ -n "$LOG_FILE_DEFAULT" ]]; then
                rm -f "$LOG_FILE_DEFAULT"
            fi
            if [[ -n "$LOG_FILE" && "$LOG_FILE" != "$LOG_FILE_DEFAULT" ]]; then
                rm -f "$LOG_FILE"
            fi
            echo "Purged LaunchAgent plist and logs."
        fi
        echo "Slower stopped and local state removed."
        echo "If you installed a copy in your PATH, remove it manually."
        ;;
    voices)
        list_voices
        ;;
    sessions)
        list_sessions
        ;;
    status)
        if is_running; then
            echo "Slower is running (session '$SESSION', PID $PID)."
            status_remaining
        else
            if [[ -f "$STATEFILE" ]]; then
                rm -f "$STATEFILE"
            fi
            echo "Slower is not running (session '$SESSION')."
        fi
        ;;
    *)
        usage
        ;;
esac

#!/usr/bin/env bash
set -euo pipefail

APP_LABEL_BASE="com.leovoon.slower"
APP_LABEL="$APP_LABEL_BASE"
LABEL_OVERRIDE=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH=""
LOG_DIR="$HOME/Library/Logs"
PLIST_PATH=""
OUT_LOG=""
ERR_LOG=""

INTERVAL=60
SESSION="default"
QUIET=""
LOG_ENABLED=0
LOG_PATH=""
MESSAGE=""
SAY_MESSAGE=""
SOUND=""
VOICE=""

usage() {
    cat <<USAGE
Usage: ./launchd-setup.sh [install|uninstall|status] [options]

Commands:
  install           Install and start Walker at login
  uninstall         Stop and remove the LaunchAgent
  status            Show LaunchAgent status

Options:
  -t, --time        Interval in minutes (default: 60)
  -n, --name        Session name (default: default)
      --quiet       Quiet hours in HH:MM-HH:MM (no notifications)
  -m, --message     Notification and spoken message
      --say-message Spoken message only (overrides --message for voice)
  -s, --sound       Notification sound name (use 'none' for silent)
  -v, --voice       Voice name for say (use 'none' to disable speech)
      --log [path]  Enable logging (default: ~/.slower/logs/<name>.log)
      --label       Override LaunchAgent label (default: com.leovoon.slower)
      --logs-dir    Override logs directory (default: ~/Library/Logs)
  -h, --help        Show this help
USAGE
}

recompute_paths() {
    LOG_DIR="${LOG_DIR/#\~/$HOME}"
    PLIST_PATH="$HOME/Library/LaunchAgents/${APP_LABEL}.plist"
    OUT_LOG="$LOG_DIR/${APP_LABEL}.log"
    ERR_LOG="$LOG_DIR/${APP_LABEL}.err.log"
}

resolve_app_path() {
    local resolved
    resolved="$(command -v slower 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
        APP_PATH="$resolved"
    else
        APP_PATH="$SCRIPT_DIR/slower.sh"
    fi
}

resolve_working_dir() {
    if [[ -n "$APP_PATH" ]]; then
        printf '%s' "$(cd "$(dirname "$APP_PATH")" && pwd)"
    else
        printf '%s' "$HOME"
    fi
}

validate_session_name() {
    if [[ ! "$SESSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Error: invalid session name '$SESSION'. Use letters, numbers, dots, dashes, or underscores."
        exit 1
    fi
}

validate_quiet_range() {
    local range=$1
    if [[ "$range" != *-* ]]; then
        return 1
    fi
    local start="${range%-*}"
    local end="${range#*-}"

    if [[ ! "$start" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        return 1
    fi
    if [[ ! "$end" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        return 1
    fi
    return 0
}

xml_escape() {
    local value=$1
    value=${value//&/&amp;}
    value=${value//</&lt;}
    value=${value//>/&gt;}
    value=${value//\"/&quot;}
    value=${value//\'/&apos;}
    printf '%s' "$value"
}

print_string() {
    local value
    value="$(xml_escape "$1")"
    printf '    <string>%s</string>\n' "$value"
}

write_plist() {
    mkdir -p "$(dirname "$PLIST_PATH")" "$LOG_DIR"
    local working_dir
    working_dir="$(resolve_working_dir)"

    {
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
        printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        printf '%s\n' '<plist version="1.0">'
        printf '%s\n' '<dict>'
        printf '%s\n' '  <key>Label</key>'
        printf '  <string>%s</string>\n' "$(xml_escape "$APP_LABEL")"
        printf '%s\n' '  <key>ProgramArguments</key>'
        printf '%s\n' '  <array>'
        print_string "$APP_PATH"
        print_string "run"
        print_string "-t"
        print_string "$INTERVAL"
        if [[ "$SESSION" != "default" ]]; then
            print_string "-n"
            print_string "$SESSION"
        fi
        if [[ -n "$QUIET" ]]; then
            print_string "--quiet"
            print_string "$QUIET"
        fi
        if [[ -n "$MESSAGE" ]]; then
            print_string "-m"
            print_string "$MESSAGE"
        fi
        if [[ -n "$SAY_MESSAGE" ]]; then
            print_string "--say-message"
            print_string "$SAY_MESSAGE"
        fi
        if [[ -n "$SOUND" ]]; then
            print_string "-s"
            print_string "$SOUND"
        fi
        if [[ -n "$VOICE" ]]; then
            print_string "-v"
            print_string "$VOICE"
        fi
        if [[ "$LOG_ENABLED" -eq 1 ]]; then
            print_string "--log"
            if [[ -n "$LOG_PATH" ]]; then
                print_string "$LOG_PATH"
            fi
        fi
        printf '%s\n' '  </array>'
        printf '%s\n' '  <key>RunAtLoad</key>'
        printf '%s\n' '  <true/>'
        printf '%s\n' '  <key>WorkingDirectory</key>'
        printf '  <string>%s</string>\n' "$(xml_escape "$working_dir")"
        printf '%s\n' '  <key>StandardOutPath</key>'
        printf '  <string>%s</string>\n' "$(xml_escape "$OUT_LOG")"
        printf '%s\n' '  <key>StandardErrorPath</key>'
        printf '  <string>%s</string>\n' "$(xml_escape "$ERR_LOG")"
        printf '%s\n' '</dict>'
        printf '%s\n' '</plist>'
    } > "$PLIST_PATH"
}

ensure_launchctl() {
    if ! command -v launchctl >/dev/null 2>&1; then
        echo "Error: launchctl not found. This script only works on macOS."
        exit 1
    fi
}

ensure_app() {
    resolve_app_path
    if [[ ! -f "$APP_PATH" ]]; then
        echo "Error: slower.sh not found at $APP_PATH"
        exit 1
    fi
    if [[ ! -x "$APP_PATH" ]]; then
        chmod +x "$APP_PATH"
    fi
}

install_agent() {
    ensure_launchctl
    ensure_app
    write_plist
    launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$UID" "$PLIST_PATH"
    echo "Installed and started: $APP_LABEL (session $SESSION)"
}

uninstall_agent() {
    ensure_launchctl
    launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
    if [[ -f "$PLIST_PATH" ]]; then
        rm -f "$PLIST_PATH"
    fi
    echo "Removed: $APP_LABEL (session $SESSION)"
}

status_agent() {
    ensure_launchctl
    if launchctl print "gui/$UID/$APP_LABEL" >/dev/null 2>&1; then
        echo "Running: $APP_LABEL (session $SESSION)"
    else
        echo "Not running: $APP_LABEL (session $SESSION)"
    fi
}

COMMAND="install"
if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
    COMMAND=$1
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--time)
            if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                INTERVAL=$2
                shift 2
            else
                echo "Error: --time requires a numeric argument."
                exit 1
            fi
            ;;
        -n|--name)
            if [[ -n "${2:-}" ]]; then
                SESSION=$2
                shift 2
            else
                echo "Error: --name requires an argument."
                exit 1
            fi
            ;;
        --quiet)
            if [[ -n "${2:-}" ]]; then
                if ! validate_quiet_range "$2"; then
                    echo "Error: --quiet must be in HH:MM-HH:MM format."
                    exit 1
                fi
                QUIET=$2
                shift 2
            else
                echo "Error: --quiet requires an argument."
                exit 1
            fi
            ;;
        -m|--message)
            if [[ -n "${2:-}" ]]; then
                MESSAGE=$2
                SAY_MESSAGE=$2
                shift 2
            else
                echo "Error: --message requires an argument."
                exit 1
            fi
            ;;
        --say-message)
            if [[ -n "${2:-}" ]]; then
                SAY_MESSAGE=$2
                shift 2
            else
                echo "Error: --say-message requires an argument."
                exit 1
            fi
            ;;
        -s|--sound)
            if [[ -n "${2:-}" ]]; then
                SOUND=$2
                shift 2
            else
                echo "Error: --sound requires an argument."
                exit 1
            fi
            ;;
        -v|--voice)
            if [[ -n "${2:-}" ]]; then
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
                LOG_PATH=$2
                shift 2
            else
                shift
            fi
            ;;
        --label)
            if [[ -n "${2:-}" ]]; then
                APP_LABEL=$2
                LABEL_OVERRIDE=1
                shift 2
            else
                echo "Error: --label requires an argument."
                exit 1
            fi
            ;;
        --logs-dir)
            if [[ -n "${2:-}" ]]; then
                LOG_DIR=$2
                shift 2
            else
                echo "Error: --logs-dir requires an argument."
                exit 1
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

validate_session_name
if [[ "$LABEL_OVERRIDE" -eq 0 && "$SESSION" != "default" ]]; then
    APP_LABEL="${APP_LABEL_BASE}.${SESSION}"
fi
recompute_paths

case "$COMMAND" in
    install)
        install_agent
        ;;
    uninstall)
        uninstall_agent
        ;;
    status)
        status_agent
        ;;
    *)
        usage
        exit 1
        ;;
esac

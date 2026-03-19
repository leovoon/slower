module slowerlib

import os
import strings
import time

pub fn normalize_public_args(args []string) []string {
	if args.len == 0 {
		return args
	}
	mut out := []string{cap: args.len + 4}
	out << args[0]
	mut i := 1
	for i < args.len {
		arg := args[i]
		if i == 1 && arg == 'sessions' {
			out << 'list'
			i++
			continue
		}
		if i == 1 && arg == 'uninstall' {
			out << 'launchd'
			out << 'uninstall'
			i++
			continue
		}
		match arg {
			'--name' {
				out << '--session'
				if i + 1 < args.len {
					out << args[i + 1]
					i += 2
				} else {
					i++
				}
				continue
			}
			'--time', '-t' {
				out << '--interval'
				if i + 1 < args.len {
					out << args[i + 1]
					i += 2
				} else {
					i++
				}
				continue
			}
			'--log' {
				out << '--log'
				if i + 1 < args.len && !args[i + 1].starts_with('-') {
					out << '--log-path=${args[i + 1]}'
					i += 2
				} else {
					i++
				}
				continue
			}
			else {}
		}
		if arg.starts_with('--name=') {
			out << '--session=${arg.all_after('=')}'
		} else if arg.starts_with('--log=') {
			out << '--log'
			out << '--log-path=${arg.all_after('=')}'
		} else {
			out << arg
		}
		i++
	}
	return out
}

pub fn validate_session_name(session string) ! {
	if session == '' {
		return error('session name cannot be empty')
	}
	for ch in session {
		if (ch >= `A` && ch <= `Z`) || (ch >= `a` && ch <= `z`)
			|| (ch >= `0` && ch <= `9`) || ch in [`.`, `-`, `_`] {
			continue
		}
		return error('invalid session name `${session}`; use letters, numbers, dots, dashes, or underscores')
	}
}

pub fn parse_quiet_hours(raw string) !QuietHours {
	if raw == '' {
		return QuietHours{}
	}
	parts := raw.split('-')
	if parts.len != 2 {
		return error('quiet hours must be in HH:MM-HH:MM format')
	}
	start := parse_clock(parts[0])!
	end := parse_clock(parts[1])!
	return QuietHours{
		enabled:       true
		raw:           raw
		start_minutes: start
		end_minutes:   end
	}
}

fn parse_clock(raw string) !int {
	pieces := raw.split(':')
	if pieces.len != 2 {
		return error('invalid clock value `${raw}`')
	}
	hour := pieces[0].int()
	minute := pieces[1].int()
	if hour < 0 || hour > 23 || minute < 0 || minute > 59 {
		return error('invalid clock value `${raw}`')
	}
	return hour * 60 + minute
}

pub fn (quiet QuietHours) is_quiet_now(now time.Time) bool {
	if !quiet.enabled || quiet.start_minutes == quiet.end_minutes {
		return false
	}
	current := now.hour * 60 + now.minute
	if quiet.start_minutes < quiet.end_minutes {
		return current >= quiet.start_minutes && current < quiet.end_minutes
	}
	return current >= quiet.start_minutes || current < quiet.end_minutes
}

pub fn (quiet QuietHours) seconds_until_end(now time.Time) int {
	if !quiet.enabled {
		return 0
	}
	current := now.hour * 60 + now.minute
	mut minutes_until := 0
	if quiet.start_minutes < quiet.end_minutes {
		minutes_until = quiet.end_minutes - current
	} else if current >= quiet.start_minutes {
		minutes_until = 1440 - current + quiet.end_minutes
	} else {
		minutes_until = quiet.end_minutes - current
	}
	mut seconds := minutes_until * 60 - now.second
	if seconds <= 0 {
		seconds = 1
	}
	return seconds
}

pub fn format_duration(total int) string {
	if total <= 0 {
		return '0s'
	}
	hours := total / 3600
	minutes := (total % 3600) / 60
	seconds := total % 60
	if hours > 0 {
		return '${hours}h ${minutes}m'
	}
	if minutes > 0 {
		return '${minutes}m ${seconds}s'
	}
	return '${seconds}s'
}

pub fn is_none(value string) bool {
	return value.to_lower() == 'none'
}

pub fn expand_home(path string) string {
	if path.starts_with('~/') {
		return os.join_path(effective_home_dir(), path[2..])
	}
	return path
}

pub fn effective_home_dir() string {
	override := os.getenv_opt('SLOWER_HOME') or { '' }
	if override != '' {
		return override
	}
	return os.home_dir()
}

pub fn escape_applescript(value string) string {
	return value.replace('\\', '\\\\').replace('"', '\\"')
}

pub fn shell_quote(value string) string {
	return "'${value.replace("'", "'\\''")}'"
}

pub fn xml_escape(value string) string {
	mut escaped := value
	replacements := {
		'&': '&amp;'
		'<': '&lt;'
		'>': '&gt;'
		'"': '&quot;'
		"'": '&apos;'
	}
	for from, to in replacements {
		escaped = escaped.replace(from, to)
	}
	return escaped
}

pub fn quoted_command(parts []string) string {
	mut quoted := []string{cap: parts.len}
	for part in parts {
		quoted << shell_quote(part)
	}
	return quoted.join(' ')
}

pub fn resolve_config_from_values(session string, interval int, quiet_raw string, message string, say_message string, sound string, voice string, log_enabled bool, log_path string, mode string) !SessionConfig {
	final_session := if session == '' { 'default' } else { session }
	validate_session_name(final_session)!
	if interval <= 0 {
		return error('interval must be greater than zero')
	}
	if quiet_raw != '' {
		parse_quiet_hours(quiet_raw)!
	}
	final_message := if message == '' { default_message } else { message }
	final_say_message := if say_message == '' {
		if message == '' { default_say_message } else { message }
	} else {
		say_message
	}
	return SessionConfig{
		session:          final_session
		interval_minutes: interval
		quiet_raw:        quiet_raw
		message:          final_message
		say_message:      final_say_message
		sound:            if sound == '' { default_sound } else { sound }
		voice:            voice
		log_enabled:      log_enabled
		log_path:         expand_home(log_path)
		mode:             mode
	}
}

pub fn pretty_next_run(next_run_unix i64) string {
	if next_run_unix <= 0 {
		return ''
	}
	now := time.now().unix()
	remaining := int(next_run_unix - now)
	if remaining <= 0 {
		return 'Next notification: due now.'
	}
	return 'Next notification in ${format_duration(remaining)}.'
}

pub fn one_line(value string) string {
	return value.trim_space().replace('\n', ' ')
}

pub fn key_value_lines(values map[string]string) string {
	mut keys := values.keys()
	keys.sort()
	mut builder := strings.new_builder(256)
	for key in keys {
		builder.writeln('${key}: ${values[key]}')
	}
	return builder.str()
}

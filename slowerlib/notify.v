module slowerlib

import os
import time

fn system_effects_enabled() bool {
	return (os.getenv_opt('SLOWER_DISABLE_SYSTEM_EFFECTS') or { '' }) != '1'
}

fn append_log(config SessionConfig, paths SessionPaths, message string) {
	if !config.log_enabled {
		return
	}
	log_path := config_log_path(config, paths)
	if log_path == '' {
		return
	}
	log_dir := os.dir(log_path)
	if log_dir != '' {
		os.mkdir_all(log_dir) or { return }
	}
	mut file := os.open_append(log_path) or { return }
	defer {
		file.close()
	}
	timestamp := time.now().format_ss()
	file.writeln('${timestamp} [${config.session}] ${message}') or {}
}

fn notify_user(config SessionConfig) {
	if !system_effects_enabled() {
		return
	}
	if !os.exists_in_system_path('osascript') {
		println(config.message)
		return
	}
	mut script := 'display notification "${escape_applescript(config.message)}" with title "${escape_applescript(app_name)}"'
	if config.sound != '' && !is_none(config.sound) {
		script += ' sound name "${escape_applescript(config.sound)}"'
	}
	os.execute('/usr/bin/osascript -e ${shell_quote(script)}')
}

fn speak_message(config SessionConfig) {
	if !system_effects_enabled() {
		return
	}
	if !os.exists_in_system_path('say') {
		return
	}
	if is_none(config.voice) {
		return
	}
	mut parts := ['/usr/bin/say']
	if config.voice != '' {
		parts << '-v'
		parts << config.voice
	}
	parts << config.say_message
	os.execute(quoted_command(parts))
}

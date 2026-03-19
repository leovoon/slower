module slowerlib

import os

pub fn session_paths(session string) !SessionPaths {
	validate_session_name(session)!
	home := effective_home_dir()
	base_dir := os.join_path(home, '.slower')
	sessions_dir := os.join_path(base_dir, 'sessions')
	locks_dir := os.join_path(base_dir, 'locks')
	logs_dir := os.join_path(base_dir, 'logs')
	launch_agents_dir := os.join_path(home, 'Library', 'LaunchAgents')
	label := launchd_label(session)
	return SessionPaths{
		base_dir:            base_dir
		sessions_dir:        sessions_dir
		locks_dir:           locks_dir
		logs_dir:            logs_dir
		state_file:          os.join_path(sessions_dir, '${session}.json')
		lock_file:           os.join_path(locks_dir, '${session}.lock')
		default_log_file:    os.join_path(logs_dir, '${session}.log')
		launch_agents_dir:   launch_agents_dir
		launchd_label:       label
		launchd_plist_path:  os.join_path(launch_agents_dir, '${label}.plist')
		launchd_stdout_path: os.join_path(home, 'Library', 'Logs', '${label}.log')
		launchd_stderr_path: os.join_path(home, 'Library', 'Logs', '${label}.err.log')
	}
}

pub fn ensure_session_dirs(paths SessionPaths, config SessionConfig) ! {
	os.mkdir_all(paths.base_dir)!
	os.mkdir_all(paths.sessions_dir)!
	os.mkdir_all(paths.locks_dir)!
	os.mkdir_all(paths.logs_dir)!
	os.mkdir_all(paths.launch_agents_dir)!
	if config.log_enabled {
		log_dir := os.dir(config_log_path(config, paths))
		if log_dir != '' {
			os.mkdir_all(log_dir)!
		}
	}
}

pub fn config_log_path(config SessionConfig, paths SessionPaths) string {
	if !config.log_enabled {
		return ''
	}
	if config.log_path != '' {
		return config.log_path
	}
	return paths.default_log_file
}

pub fn launchd_label(session string) string {
	if session == 'default' {
		return label_base
	}
	return '${label_base}.${session}'
}

pub fn session_from_label(label string) ?string {
	if label == label_base {
		return 'default'
	}
	prefix := '${label_base}.'
	if label.starts_with(prefix) {
		return label.all_after(prefix)
	}
	return none
}

pub fn known_sessions() ![]string {
	mut seen := map[string]bool{}
	mut sessions := []string{}
	home := effective_home_dir()
	base_dir := os.join_path(home, '.slower', 'sessions')
	if os.exists(base_dir) {
		for entry in os.ls(base_dir)! {
			if entry.ends_with('.json') {
				name := entry.all_before_last('.json')
				if !seen[name] {
					seen[name] = true
					sessions << name
				}
			}
		}
	}
	agents_dir := os.join_path(home, 'Library', 'LaunchAgents')
	if os.exists(agents_dir) {
		for entry in os.ls(agents_dir)! {
			if !entry.starts_with(label_base) || !entry.ends_with('.plist') {
				continue
			}
			label := entry.all_before_last('.plist')
			session := session_from_label(label) or { continue }
			if !seen[session] {
				seen[session] = true
				sessions << session
			}
		}
	}
	sessions.sort()
	return sessions
}

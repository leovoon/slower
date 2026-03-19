module slowerlib

import json
import os
import os.filelock

pub fn state_from_config(config SessionConfig, paths SessionPaths) SessionState {
	return SessionState{
		session:            config.session
		mode:               config.mode
		pid:                0
		started_at_unix:    0
		next_run_unix:      0
		interval_minutes:   config.interval_minutes
		quiet_raw:          config.quiet_raw
		message:            config.message
		say_message:        config.say_message
		sound:              config.sound
		voice:              config.voice
		log_enabled:        config.log_enabled
		log_path:           config_log_path(config, paths)
		launchd_label:      paths.launchd_label
		launchd_plist_path: paths.launchd_plist_path
		installed:          config.mode == 'launchd'
	}
}

pub fn read_state(session string) !SessionState {
	paths := session_paths(session)!
	text := os.read_file(paths.state_file)!
	mut state := json.decode(SessionState, text)!
	if state.session == '' {
		state.session = session
	}
	if state.launchd_label == '' {
		state.launchd_label = paths.launchd_label
	}
	if state.launchd_plist_path == '' {
		state.launchd_plist_path = paths.launchd_plist_path
	}
	return state
}

pub fn write_state(state SessionState) ! {
	paths := session_paths(state.session)!
	os.mkdir_all(paths.sessions_dir)!
	os.write_file(paths.state_file, json.encode_pretty(state))!
}

pub fn remove_state(session string) ! {
	paths := session_paths(session)!
	if os.exists(paths.state_file) {
		os.rm(paths.state_file)!
	}
}

pub fn lock_is_held(paths SessionPaths) bool {
	lock_dir := os.dir(paths.lock_file)
	if lock_dir == '' || !os.exists(lock_dir) {
		return false
	}
	mut file_lock := filelock.new(paths.lock_file)
	if file_lock.try_acquire() {
		file_lock.release()
		return false
	}
	return true
}

pub fn inspect_session(session string) !SessionStatus {
	paths := session_paths(session)!
	mut state := SessionState{
		session:            session
		mode:               'detached'
		launchd_label:      paths.launchd_label
		launchd_plist_path: paths.launchd_plist_path
	}
	if os.exists(paths.state_file) {
		state = read_state(session) or { state }
	}
	installed := os.exists(paths.launchd_plist_path)
	mut mode := state.mode
	if mode == '' {
		mode = if installed { 'launchd' } else { 'detached' }
	}
	running := if mode == 'launchd' {
		installed && launchd_job_loaded(paths.launchd_label)
	} else {
		lock_is_held(paths)
	}
	return SessionStatus{
		session:       session
		mode:          mode
		pid:           state.pid
		running:       running
		installed:     installed
		next_run_unix: state.next_run_unix
		log_path:      state.log_path
	}
}

pub fn clean_stale_state(session string) ! {
	status := inspect_session(session)!
	if !status.running && !status.installed {
		remove_state(session) or {}
	}
}

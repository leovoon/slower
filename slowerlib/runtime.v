module slowerlib

import os
import time
import os.filelock

fn pid_is_alive(pid int) bool {
	if pid <= 0 {
		return false
	}
	return os.execute('kill -0 ${pid}').exit_code == 0
}

fn wait_for_shutdown(pid int, paths SessionPaths) bool {
	for _ in 0 .. 30 {
		if !pid_is_alive(pid) && !lock_is_held(paths) {
			return true
		}
		time.sleep(100 * time.millisecond)
	}
	return !pid_is_alive(pid) && !lock_is_held(paths)
}

fn build_worker_args(config SessionConfig) []string {
	mut args := ['_worker', '--session', config.session, '--interval', '${config.interval_minutes}',
		'--mode', config.mode]
	if config.quiet_raw != '' {
		args << '--quiet'
		args << config.quiet_raw
	}
	if config.message != default_message {
		args << '--message'
		args << config.message
	}
	if config.say_message != default_say_message && config.say_message != config.message {
		args << '--say-message'
		args << config.say_message
	}
	if config.sound != default_sound {
		args << '--sound'
		args << config.sound
	}
	if config.voice != default_voice {
		args << '--voice'
		args << config.voice
	}
	if config.log_enabled {
		args << '--log'
		if config.log_path != '' {
			args << '--log-path'
			args << config.log_path
		}
	}
	return args
}

pub fn run_internal_worker(args []string) ! {
	config := parse_worker_args(args)!
	run_session(config)!
}

fn parse_worker_args(args []string) !SessionConfig {
	mut session := 'default'
	mut interval := default_interval_minutes
	mut quiet_raw := ''
	mut message := ''
	mut say_message := ''
	mut sound := ''
	mut voice := ''
	mut log_enabled := false
	mut log_path := ''
	mut mode := 'detached'
	mut i := 0
	for i < args.len {
		arg := args[i]
		match arg {
			'--session' {
				i++
				session = args[i]
			}
			'--interval' {
				i++
				interval = args[i].int()
			}
			'--quiet' {
				i++
				quiet_raw = args[i]
			}
			'--message' {
				i++
				message = args[i]
			}
			'--say-message' {
				i++
				say_message = args[i]
			}
			'--sound' {
				i++
				sound = args[i]
			}
			'--voice' {
				i++
				voice = args[i]
			}
			'--log' {
				log_enabled = true
			}
			'--log-path' {
				i++
				log_path = args[i]
			}
			'--mode' {
				i++
				mode = args[i]
			}
			else {
				return error('unknown internal worker flag `${arg}`')
			}
		}
		i++
	}
	return resolve_config_from_values(session, interval, quiet_raw, message, say_message,
		sound, voice, log_enabled, log_path, mode)
}

pub fn run_session(config SessionConfig) ! {
	paths := session_paths(config.session)!
	ensure_session_dirs(paths, config)!
	mut file_lock := filelock.new(paths.lock_file)
	if !file_lock.try_acquire() {
		return error('session `${config.session}` is already running')
	}
	defer {
		file_lock.release()
		if config.mode == 'detached' {
			remove_state(config.session) or {}
		} else if config.mode == 'launchd' {
			mut state := read_state(config.session) or { state_from_config(config, paths) }
			state.pid = 0
			state.next_run_unix = 0
			state.installed = os.exists(paths.launchd_plist_path)
			write_state(state) or {}
		}
	}
	quiet := parse_quiet_hours(config.quiet_raw)!
	mut state := state_from_config(config, paths)
	state.pid = os.getpid()
	state.started_at_unix = time.now().unix()
	state.installed = config.mode == 'launchd'
	write_state(state)!
	append_log(config, paths, 'Started (${config.mode}, PID ${state.pid}, interval ${config.interval_minutes}m).')
	for {
		now := time.now()
		if quiet.is_quiet_now(now) {
			sleep_seconds := quiet.seconds_until_end(now)
			state.next_run_unix = now.unix() + sleep_seconds
			write_state(state)!
			append_log(config, paths, 'Quiet hours active. Next notification in ${format_duration(sleep_seconds)}.')
			time.sleep(time.second * sleep_seconds)
			continue
		}
		notify_user(config)
		speak_message(config)
		append_log(config, paths, 'Notification sent.')
		sleep_seconds := config.interval_minutes * 60
		state.next_run_unix = now.unix() + sleep_seconds
		write_state(state)!
		time.sleep(time.second * sleep_seconds)
	}
}

pub fn start_detached(config SessionConfig) ! {
	paths := session_paths(config.session)!
	clean_stale_state(config.session) or {}
	status := inspect_session(config.session) or { SessionStatus{} }
	if status.running {
		return error('session `${config.session}` is already running')
	}
	if status.installed {
		return error('session `${config.session}` is already installed via launchd')
	}
	exe_path := os.executable()
	if exe_path == '' {
		return error('could not resolve the slower executable path')
	}
	worker_args := build_worker_args(SessionConfig{
		...config
		mode: 'detached'
	})
	mut command_parts := [exe_path]
	command_parts << worker_args
	launch_cmd := 'nohup ${quoted_command(command_parts)} >/dev/null 2>&1 &'
	result := os.execute(launch_cmd)
	if result.exit_code != 0 {
		return error(one_line(result.output))
	}
	deadline := time.now().add(start_timeout_ms * time.millisecond)
	for time.now() < deadline {
		if os.exists(paths.state_file) && lock_is_held(paths) {
			mut state := read_state(config.session) or { SessionState{} }
			println('Slower started in background (PID ${state.pid}, session `${config.session}`).')
			return
		}
		time.sleep(100 * time.millisecond)
	}
	return error('detached worker did not become ready in time')
}

pub fn stop_session(session string) ! {
	paths := session_paths(session)!
	status := inspect_session(session) or {
		SessionStatus{
			session: session
		}
	}
	mut stopped := false
	if status.mode == 'launchd' && status.installed {
		os.execute('launchctl bootout gui/${os.getuid()} ${shell_quote(paths.launchd_plist_path)}')
		stopped = true
	}
	if status.mode != 'launchd' && status.pid > 0 && status.running {
		os.execute('kill -TERM ${status.pid}')
		if !wait_for_shutdown(status.pid, paths) {
			os.execute('kill -KILL ${status.pid}')
			wait_for_shutdown(status.pid, paths)
		}
		stopped = true
	}
	if status.mode == 'launchd' && status.installed {
		mut state := read_state(session) or {
			SessionState{
				session: session
			}
		}
		state.pid = 0
		state.next_run_unix = 0
		state.installed = true
		write_state(state) or {}
		println('Stopped session `${session}` (launchd job unloaded, plist kept).')
		return
	}
	if os.exists(paths.lock_file) && !lock_is_held(paths) {
		remove_state(session) or {}
	}
	remove_state(session) or {}
	if stopped {
		println('Stopped session `${session}`.')
	} else {
		println('Slower is not running (session `${session}`).')
	}
}

pub fn stop_all_sessions() ! {
	sessions := known_sessions()!
	if sessions.len == 0 {
		println('No sessions found.')
		return
	}
	for session in sessions {
		stop_session(session) or { eprintln('Error stopping `${session}`: ${err}') }
	}
}

pub fn print_status(session string) ! {
	status := inspect_session(session)!
	if !status.running && !status.installed {
		clean_stale_state(session) or {}
		println('Slower is not running (session `${session}`).')
		return
	}
	if status.running {
		println('Slower is running (session `${session}`, mode ${status.mode}, PID ${status.pid}).')
		next_run_line := pretty_next_run(status.next_run_unix)
		if next_run_line != '' {
			println(next_run_line)
		}
		return
	}
	println('Slower is installed via launchd but not running (session `${session}`).')
}

pub fn print_all_statuses() ! {
	sessions := known_sessions()!
	if sessions.len == 0 {
		println('No sessions found.')
		return
	}
	for session in sessions {
		print_status(session) or { eprintln('Error reading status for `${session}`: ${err}') }
	}
}

pub fn print_session_list() ! {
	sessions := known_sessions()!
	if sessions.len == 0 {
		println('No sessions found.')
		return
	}
	for session in sessions {
		status := inspect_session(session) or { continue }
		if status.running {
			println('Session `${session}`: running (${status.mode})')
		} else if status.installed {
			println('Session `${session}`: installed (launchd)')
		} else {
			println('Session `${session}`: not running')
		}
	}
}

pub fn list_voices() ! {
	if !os.exists_in_system_path('say') {
		println('The `say` command is not available on this system.')
		return
	}
	result := os.execute('/usr/bin/say -v ?')
	if result.exit_code != 0 {
		return error(one_line(result.output))
	}
	print(result.output)
}

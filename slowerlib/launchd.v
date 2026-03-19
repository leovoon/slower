module slowerlib

import os

pub fn launchd_job_loaded(label string) bool {
	cmd := 'launchctl print gui/${os.getuid()}/${label}'
	return os.execute(cmd).exit_code == 0
}

pub fn generate_launchd_plist(config SessionConfig, exe_path string) !string {
	paths := session_paths(config.session)!
	worker_args := build_worker_args(config)
	mut lines := []string{}
	lines << '<?xml version="1.0" encoding="UTF-8"?>'
	lines << '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
	lines << '<plist version="1.0">'
	lines << '<dict>'
	lines << '  <key>Label</key>'
	lines << '  <string>${xml_escape(paths.launchd_label)}</string>'
	lines << '  <key>ProgramArguments</key>'
	lines << '  <array>'
	lines << '    <string>${xml_escape(exe_path)}</string>'
	for arg in worker_args {
		lines << '    <string>${xml_escape(arg)}</string>'
	}
	lines << '  </array>'
	lines << '  <key>RunAtLoad</key>'
	lines << '  <true/>'
	lines << '  <key>WorkingDirectory</key>'
	lines << '  <string>${xml_escape(os.dir(exe_path))}</string>'
	lines << '  <key>StandardOutPath</key>'
	lines << '  <string>${xml_escape(paths.launchd_stdout_path)}</string>'
	lines << '  <key>StandardErrorPath</key>'
	lines << '  <string>${xml_escape(paths.launchd_stderr_path)}</string>'
	lines << '</dict>'
	lines << '</plist>'
	return lines.join('\n')
}

pub fn install_launchd(config SessionConfig, dry_run bool) ! {
	paths := session_paths(config.session)!
	status := inspect_session(config.session) or { SessionStatus{} }
	if status.running && status.mode == 'detached' {
		return error('session `${config.session}` is already running in detached mode; stop it before installing launchd')
	}
	exe_path := os.executable()
	if exe_path == '' {
		return error('could not resolve the slower executable path')
	}
	plist := generate_launchd_plist(config, exe_path)!
	if dry_run {
		println(key_value_lines({
			'executable': exe_path
			'label':      paths.launchd_label
			'plist':      paths.launchd_plist_path
			'log':        config_log_path(config, paths)
		}))
		println('')
		println(plist)
		return
	}
	ensure_session_dirs(paths, config)!
	os.write_file(paths.launchd_plist_path, plist)!
	os.execute('launchctl bootout gui/${os.getuid()} ${shell_quote(paths.launchd_plist_path)}')
	res := os.execute('launchctl bootstrap gui/${os.getuid()} ${shell_quote(paths.launchd_plist_path)}')
	if res.exit_code != 0 {
		return error(one_line(res.output))
	}
	mut state := state_from_config(SessionConfig{
		...config
		mode: 'launchd'
	}, paths)
	state.installed = true
	write_state(state)!
	println('Installed and started: ${paths.launchd_label} (session ${config.session})')
}

pub fn uninstall_launchd(session string, purge bool) ! {
	paths := session_paths(session)!
	status := inspect_session(session) or {
		SessionStatus{
			session: session
		}
	}
	if os.exists(paths.launchd_plist_path) {
		os.execute('launchctl bootout gui/${os.getuid()} ${shell_quote(paths.launchd_plist_path)}')
		os.rm(paths.launchd_plist_path) or {}
	}
	if purge {
		os.rm(paths.launchd_stdout_path) or {}
		os.rm(paths.launchd_stderr_path) or {}
		if status.log_path != '' {
			os.rm(status.log_path) or {}
		}
	}
	remove_state(session) or {}
	if purge {
		println('Removed launchd agent and purged logs for session `${session}`.')
	} else {
		println('Removed launchd agent for session `${session}`.')
	}
}

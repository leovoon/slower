module slowerlib

import os
import time

fn build_test_binary() !string {
	repo_root := os.real_path(os.join_path(os.dir(@FILE), '..'))
	entrypoint := os.join_path(repo_root, 'cmd', 'slower', 'main.v')
	output := os.join_path(os.temp_dir(), 'slower-test-${time.now().unix_micro()}')
	build_cmd := '${shell_quote(@VEXE)} -o ${shell_quote(output)} ${shell_quote(entrypoint)}'
	result := os.execute(build_cmd)
	if result.exit_code != 0 {
		return error(result.output)
	}
	return output
}

fn run_cli_cmd(bin_path string, home string, args []string) os.Result {
	env_prefix := 'SLOWER_HOME=${shell_quote(home)} SLOWER_DISABLE_SYSTEM_EFFECTS=1'
	mut parts := [bin_path]
	parts << args
	return os.execute('${env_prefix} ${quoted_command(parts)}')
}

fn wait_for_running_status(bin_path string, home string, session string) os.Result {
	mut last := os.Result{}
	for _ in 0 .. 30 {
		last = run_cli_cmd(bin_path, home, ['status', '--session', session])
		if last.output.contains('Slower is running') {
			return last
		}
		time.sleep(200 * time.millisecond)
	}
	return last
}

fn test_help_exits_zero() {
	bin_path := build_test_binary() or { panic(err) }
	defer {
		os.rm(bin_path) or {}
	}
	result := os.execute('${shell_quote(bin_path)} --help')
	assert result.exit_code == 0
	assert result.output.contains('start')
	assert result.output.contains('launchd')
}

fn test_launchd_dry_run_accepts_name_alias() {
	bin_path := build_test_binary() or { panic(err) }
	home := os.join_path(os.temp_dir(), 'slower-home-${time.now().unix_micro()}')
	os.mkdir_all(home) or { panic(err) }
	defer {
		os.rm(bin_path) or {}
		os.rmdir_all(home) or {}
	}
	result := run_cli_cmd(bin_path, home, ['launchd', 'install', '--dry-run', '--name', 'demo',
		'--interval', '45', '--message', 'Stretch', '--log'])
	assert result.exit_code == 0
	assert result.output.contains('com.leovoon.slower.demo')
	assert result.output.contains('<string>_worker</string>')
}

fn test_detached_start_status_stop_cycle() {
	bin_path := build_test_binary() or { panic(err) }
	home := os.join_path(os.temp_dir(), 'slower-home-${time.now().unix_micro()}')
	os.mkdir_all(home) or { panic(err) }
	defer {
		run_cli_cmd(bin_path, home, ['stop', '--session', 'smoke'])
		os.rm(bin_path) or {}
		os.rmdir_all(home) or {}
	}
	start := run_cli_cmd(bin_path, home, ['start', '--session', 'smoke', '--interval', '1',
		'--message', 'Stretch', '--sound', 'none', '--voice', 'none', '--log'])
	assert start.exit_code == 0
	assert start.output.contains('Slower started in background')
	status := wait_for_running_status(bin_path, home, 'smoke')
	assert status.exit_code == 0
	assert status.output.contains('Slower is running')
	stop := run_cli_cmd(bin_path, home, ['stop', '--session', 'smoke'])
	assert stop.exit_code == 0
	assert stop.output.contains('Stopped session')
	final_status := run_cli_cmd(bin_path, home, ['status', '--session', 'smoke'])
	assert final_status.exit_code == 0
	assert final_status.output.contains('Slower is not running')
}

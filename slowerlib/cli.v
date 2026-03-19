module slowerlib

import cli

pub fn run_cli(args []string) ! {
	mut app := build_app()
	app.setup()
	app.parse(args)
}

fn build_app() cli.Command {
	mut app := cli.Command{
		name:        'slower'
		description: 'A tiny background reminder that delivers custom messages on a schedule.'
		version:     version
		posix_mode:  true
		flags:       runtime_flags()
		commands:    [
			run_command(),
			start_command(),
			stop_command(),
			status_command(),
			list_command(),
			voices_command(),
			launchd_command(),
		]
	}
	return app
}

fn runtime_flags() []cli.Flag {
	return [
		cli.Flag{
			flag:        .string
			name:        'session'
			abbrev:      'n'
			description: 'session name (default: default)'
			global:      true
		},
		cli.Flag{
			flag:        .int
			name:        'interval'
			abbrev:      'i'
			description: 'interval in minutes (default: 60)'
			global:      true
		},
		cli.Flag{
			flag:        .string
			name:        'quiet'
			abbrev:      'q'
			description: 'quiet hours in HH:MM-HH:MM'
			global:      true
		},
		cli.Flag{
			flag:        .string
			name:        'message'
			abbrev:      'm'
			description: 'notification message'
			global:      true
		},
		cli.Flag{
			flag:        .string
			name:        'say-message'
			description: 'spoken message only'
			global:      true
		},
		cli.Flag{
			flag:        .string
			name:        'sound'
			abbrev:      's'
			description: 'notification sound name, or `none`'
			global:      true
		},
		cli.Flag{
			flag:        .string
			name:        'voice'
			abbrev:      'v'
			description: 'voice name for `say`, or `none`'
			global:      true
		},
		cli.Flag{
			flag:        .bool
			name:        'log'
			description: 'enable logging'
			global:      true
		},
		cli.Flag{
			flag:        .string
			name:        'log-path'
			description: 'custom log file path used with `--log`'
			global:      true
		},
	]
}

fn run_command() cli.Command {
	return cli.Command{
		name:        'run'
		description: 'Run in the foreground.'
		execute:     fn (cmd cli.Command) ! {
			config := runtime_config_from_command(cmd, 'foreground')!
			run_session(config)!
		}
	}
}

fn start_command() cli.Command {
	return cli.Command{
		name:        'start'
		description: 'Start a detached background session.'
		execute:     fn (cmd cli.Command) ! {
			config := runtime_config_from_command(cmd, 'detached')!
			start_detached(config)!
		}
	}
}

fn stop_command() cli.Command {
	return cli.Command{
		name:        'stop'
		description: 'Stop a session.'
		flags:       [
			cli.Flag{
				flag:        .bool
				name:        'all'
				abbrev:      'a'
				description: 'stop all sessions'
			},
		]
		execute:     fn (cmd cli.Command) ! {
			if cmd.flags.get_bool('all') or { false } {
				stop_all_sessions()!
				return
			}
			stop_session(session_from_command(cmd))!
		}
	}
}

fn status_command() cli.Command {
	return cli.Command{
		name:        'status'
		description: 'Show session status.'
		flags:       [
			cli.Flag{
				flag:        .bool
				name:        'all'
				abbrev:      'a'
				description: 'show status for all sessions'
			},
		]
		execute:     fn (cmd cli.Command) ! {
			if cmd.flags.get_bool('all') or { false } {
				print_all_statuses()!
				return
			}
			print_status(session_from_command(cmd))!
		}
	}
}

fn list_command() cli.Command {
	return cli.Command{
		name:        'list'
		description: 'List known sessions.'
		execute:     fn (cmd cli.Command) ! {
			print_session_list()!
		}
	}
}

fn voices_command() cli.Command {
	return cli.Command{
		name:        'voices'
		description: 'List available macOS voices.'
		execute:     fn (cmd cli.Command) ! {
			list_voices()!
		}
	}
}

fn launchd_command() cli.Command {
	return cli.Command{
		name:        'launchd'
		description: 'Manage launchd-installed sessions.'
		commands:    [
			launchd_install_command(),
			launchd_uninstall_command(),
		]
	}
}

fn launchd_install_command() cli.Command {
	return cli.Command{
		name:        'install'
		description: 'Install and bootstrap a launchd agent for this session.'
		flags:       [
			cli.Flag{
				flag:        .bool
				name:        'dry-run'
				description: 'print the generated plist without installing it'
			},
		]
		execute:     fn (cmd cli.Command) ! {
			config := runtime_config_from_command(cmd, 'launchd')!
			install_launchd(config, cmd.flags.get_bool('dry-run') or { false })!
		}
	}
}

fn launchd_uninstall_command() cli.Command {
	return cli.Command{
		name:        'uninstall'
		description: 'Unload and remove the launchd agent for this session.'
		flags:       [
			cli.Flag{
				flag:        .bool
				name:        'purge'
				description: 'remove launchd logs and the session log file'
			},
		]
		execute:     fn (cmd cli.Command) ! {
			uninstall_launchd(session_from_command(cmd), cmd.flags.get_bool('purge') or { false })!
		}
	}
}

fn session_from_command(cmd cli.Command) string {
	session := cmd.flags.get_string('session') or { '' }
	if session == '' {
		return 'default'
	}
	return session
}

fn runtime_config_from_command(cmd cli.Command, mode string) !SessionConfig {
	session := cmd.flags.get_string('session') or { '' }
	interval := cmd.flags.get_int('interval') or { 0 }
	quiet_raw := cmd.flags.get_string('quiet') or { '' }
	message := cmd.flags.get_string('message') or { '' }
	say_message := cmd.flags.get_string('say-message') or { '' }
	sound := cmd.flags.get_string('sound') or { '' }
	voice := cmd.flags.get_string('voice') or { '' }
	log_enabled := cmd.flags.get_bool('log') or { false }
	log_path := cmd.flags.get_string('log-path') or { '' }
	final_interval := if interval == 0 { default_interval_minutes } else { interval }
	return resolve_config_from_values(session, final_interval, quiet_raw, message, say_message,
		sound, voice, log_enabled, log_path, mode)
}

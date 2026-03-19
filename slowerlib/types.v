module slowerlib

pub const app_name = 'Slower'
pub const version = '2.0.0'
pub const default_interval_minutes = 60
pub const default_message = 'Time to walk! Get up and move for 5 minutes.'
pub const default_say_message = 'Time to walk'
pub const default_sound = 'Glass'
pub const default_voice = ''
pub const label_base = 'com.leovoon.slower'
pub const start_timeout_ms = 5000

pub struct SessionConfig {
pub:
	session          string
	interval_minutes int
	quiet_raw        string
	message          string
	say_message      string
	sound            string
	voice            string
	log_enabled      bool
	log_path         string
	mode             string
}

pub struct QuietHours {
pub:
	enabled       bool
	raw           string
	start_minutes int
	end_minutes   int
}

pub struct SessionPaths {
pub:
	base_dir            string
	sessions_dir        string
	locks_dir           string
	logs_dir            string
	state_file          string
	lock_file           string
	default_log_file    string
	launch_agents_dir   string
	launchd_label       string
	launchd_plist_path  string
	launchd_stdout_path string
	launchd_stderr_path string
}

pub struct SessionState {
pub mut:
	session            string
	mode               string
	pid                int
	started_at_unix    i64
	next_run_unix      i64
	interval_minutes   int
	quiet_raw          string
	message            string
	say_message        string
	sound              string
	voice              string
	log_enabled        bool
	log_path           string
	launchd_label      string
	launchd_plist_path string
	installed          bool
}

pub struct SessionStatus {
pub:
	session       string
	mode          string
	pid           int
	running       bool
	installed     bool
	next_run_unix i64
	log_path      string
}

module slowerlib

fn test_validate_session_name_accepts_expected_characters() {
	validate_session_name('default')!
	validate_session_name('work-1.alpha_beta')!
}

fn test_validate_session_name_rejects_invalid_characters() {
	validate_session_name('bad session') or {
		assert true
		return
	}
	assert false
}

fn test_validate_session_name_rejects_slashes() {
	validate_session_name('bad/session') or {
		assert true
		return
	}
	assert false
}

fn test_parse_quiet_hours_cross_midnight() {
	quiet := parse_quiet_hours('22:00-08:00')!
	assert quiet.enabled
	assert quiet.start_minutes == 22 * 60
	assert quiet.end_minutes == 8 * 60
}

fn test_format_duration() {
	assert format_duration(0) == '0s'
	assert format_duration(59) == '59s'
	assert format_duration(125) == '2m 5s'
	assert format_duration(3660) == '1h 1m'
}

fn test_normalize_public_args() {
	args := normalize_public_args(['slower', 'sessions', '--name', 'work', '--time', '45', '--log',
		'/tmp/work.log'])
	assert args == ['slower', 'list', '--session', 'work', '--interval', '45', '--log',
		'--log-path=/tmp/work.log']
}

fn test_resolve_config_prefers_message_for_say_message_when_unspecified() {
	config := resolve_config_from_values('work', 30, '', 'Stand up', '', '', '', false,
		'', 'detached')!
	assert config.message == 'Stand up'
	assert config.say_message == 'Stand up'
}

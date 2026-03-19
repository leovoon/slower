module slowerlib

fn test_generate_launchd_plist_contains_worker_args() {
	config := resolve_config_from_values('demo', 45, '22:00-08:00', 'Stretch', '', '',
		'', true, '', 'launchd')!
	plist := generate_launchd_plist(config, '/tmp/slower')!
	assert plist.contains('<string>com.leovoon.slower.demo</string>')
	assert plist.contains('<string>_worker</string>')
	assert plist.contains('<string>--session</string>')
	assert plist.contains('<string>demo</string>')
	assert plist.contains('<string>--interval</string>')
	assert plist.contains('<string>45</string>')
	assert plist.contains('<string>--quiet</string>')
	assert plist.contains('<string>22:00-08:00</string>')
	assert plist.contains('<string>--log</string>')
}

# Slower

Slower is a tiny background reminder that nudges you to stand up and walk every X minutes.

## Requirements

- macOS (uses `osascript` for notifications and `say` for voice)
- `bash` (invoked via `/usr/bin/env bash`)

If `osascript` or `say` is not available, Slower will still run but will skip that capability.

## Usage

```bash
slower start
slower start -t 45
slower start -t 45 -m "Stand up and stretch" -s "Ping" -v "Samantha"
slower start --name work -t 45 --quiet 22:00-08:00 --log
slower run -t 45
slower stop
slower stop --all
slower uninstall
slower status
slower status --all
slower --help
slower voices
slower sessions
```

## Quick Start (Programmer Default)

If you’re installing via Homebrew, you’ll typically run the binary directly:

```bash
slower start
slower status
```

Launchd is optional and only needed for auto-start at login.

### Options

- `-t`, `--time` - interval in minutes (default: 60)
- `-n`, `--name` - session name (default: `default`)
- `--quiet` - quiet hours in `HH:MM-HH:MM` (no notifications)
- `-m`, `--message` - notification and spoken message
- `--say-message` - spoken message only (overrides `--message` for voice)
- `-s`, `--sound` - notification sound name (use `none` for silent)
- `-v`, `--voice` - voice name for `say` (use `none` to disable speech)
- `--log [path]` - enable logging (default: `~/.slower/logs/<name>.log`)
- `-a`, `--all` - apply to all sessions with `stop` or `status`

## Behavior Notes

- Stores session PID files in `~/.slower/<name>.pid` and cleans up stale PID files when detected.
- Prevents accidental PID reuse by recording the process start time.
- Set `--sound none` for silent notifications and `--voice none` to disable speech.
- `./slower.sh status` shows the remaining time until the next notification when available.

## Sessions

Use `--name` to run multiple independent sessions. Each session has its own PID and state files under `~/.slower/` (for example `~/.slower/work.pid` and `~/.slower/work.state`).

Example:

```bash
slower start --name work -t 45
slower status --name work
```

## Quiet Hours

Use `--quiet HH:MM-HH:MM` to suppress notifications during a time window. Cross-midnight ranges like `22:00-08:00` are supported.

## Logging

Use `--log` to write timestamped events to `~/.slower/logs/<name>.log`, or `--log /path/to/file.log` to choose a custom location.

## Uninstall (No Launchd)

If you are not using launchd and just ran the script manually:

```bash
slower uninstall
```

To also remove default launchd plist and log files (including `~/.slower/logs/<name>.log` if present):

```bash
slower uninstall --purge
```

To uninstall a specific session:

```bash
slower uninstall --name work
slower uninstall --name work --purge
```

To stop all sessions:

```bash
slower stop --all
```

If you copied or symlinked the script into your PATH, remove that file. Examples:

```bash
rm -f ~/bin/slower
rm -f /usr/local/bin/slower
```

## Launchd (Auto-Start at Login)

Quick install (recommended):

```bash
launchd-setup.sh install -t 60
```

With custom message, sound, and voice:

```bash
launchd-setup.sh install -t 45 -m "Stand up and stretch" -s "Ping" -v "Samantha"
```

With session, quiet hours, and logging:

```bash
launchd-setup.sh install --name work --quiet 22:00-08:00 --log
```

Check status and uninstall:

```bash
launchd-setup.sh status
launchd-setup.sh uninstall
```

The helper generates and installs a plist at `~/Library/LaunchAgents/com.leovoon.slower.plist` for the default session. It prefers the `slower` binary in your PATH (e.g., Homebrew) and falls back to the local `slower.sh` next to `launchd-setup.sh`.
If you set `--name`, the helper uses `com.leovoon.slower.<name>` as the default label so multiple sessions can coexist.

Manual setup (optional): This repo also includes `com.leovoon.slower.plist.example` as a template. Launchd requires absolute paths and does not expand `$HOME`, so you must replace the placeholders before loading it.

1. Copy the plist to your LaunchAgents folder:

```bash
cp com.leovoon.slower.plist.example ~/Library/LaunchAgents/com.leovoon.slower.plist
```

2. Edit the plist to replace `/ABS/PATH/TO/REPO` and `/Users/YOUR_USER`, and update interval, message, sound, or voice (these are set in `ProgramArguments`).

3. Load it so it starts now and on future logins:

```bash
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.leovoon.slower.plist
```

4. Check status:

```bash
launchctl print gui/$UID/com.leovoon.slower
```

5. Stop it:

```bash
launchctl bootout gui/$UID ~/Library/LaunchAgents/com.leovoon.slower.plist
```

Optional cleanup:

```bash
rm -f ~/Library/LaunchAgents/com.leovoon.slower.plist
rm -f ~/.slower/*.pid
rm -f ~/.slower/*.state
rm -f ~/.slower/logs/*.log
rm -f ~/Library/Logs/com.leovoon.slower.log
rm -f ~/Library/Logs/com.leovoon.slower.err.log
```

## Homebrew (Maintainer Steps)

1) Tag a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

2) Get the tarball URL:

```text
https://github.com/<user>/<repo>/archive/refs/tags/v1.0.0.tar.gz
```

3) Compute the SHA256:

```bash
curl -L https://github.com/<user>/<repo>/archive/refs/tags/v1.0.0.tar.gz | shasum -a 256
```

4) Create a tap repo named `homebrew-tap` and add `Formula/slower.rb`:

```ruby
class Slower < Formula
  desc "Periodic walk reminder"
  homepage "https://github.com/<user>/<repo>"
  url "https://github.com/<user>/<repo>/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "<paste sha256 here>"
  license "MIT"

  depends_on :macos

  def install
    bin.install "slower.sh" => "slower"
    bin.install "launchd-setup.sh"
    pkgshare.install "com.leovoon.slower.plist.example"
    doc.install "README.md"
  end

  test do
    system bin/"slower", "--help"
  end
end
```

5) Users install with:

```bash
brew tap <user>/tap
brew install slower
```

## Credits

This script is a remix of a walker reminder by Mario Zechner (@badlogicgames, [https://x.com/badlogicgames](https://x.com/badlogicgames)). Thanks for the original inspiration.

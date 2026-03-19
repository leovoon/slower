module main

import os
import slowerlib

fn main() {
	slowerlib.run_cli(os.args) or {
		eprintln(err.msg())
		exit(1)
	}
}

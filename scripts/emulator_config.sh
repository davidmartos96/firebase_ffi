#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Joel Winarske
# SPDX-License-Identifier: Apache-2.0
#
# Echoes the firebase.json the emulators should run with.
#
# The tests read FIREBASE_*_EMULATOR_PORT; firebase-tools reads firebase.json
# and knows nothing about those variables. Overriding one moved only one side,
# and the run failed with the tests talking to a port nothing was listening on.
#
# With no override this echoes the checked-in config. With one it writes a copy
# carrying the chosen ports, beside the original so the rules paths — which are
# relative to it — still resolve. Sourced, not run: callers want the path.
# Points the SDK's persisted state at a directory of this run's own.
#
# The desktop SDK keeps state under its app data directory: Remote Config's
# fetched config in remote_config/<app>_remote_config_data, and Auth's session
# beside it. Neither name carries the project, so a live run leaves a fetched
# config that every later offline run then loads — which is what made "nothing
# fetched yet" fail with a status of success on a machine where the live test
# had ever been run.
#
# Only Linux takes the redirect. AppDataDir reads XDG_DATA_HOME there
# (app/src/filesystem_desktop_linux.cc), but on macOS it asks
# NSSearchPathForDirectoriesInDomains for Application Support, and on Windows
# SHGetKnownFolderPath(FOLDERID_LocalAppData), which reads the user profile
# rather than the environment. Neither has an env lever, so on those two this
# is inert and a stale fetch can still decide what a local run sees. CI is
# unaffected — every runner is a fresh machine — so this is a developer
# hazard on macOS and Windows, not a CI one.
#
# Exported by the caller, so the suites see it. Removed on the way out.
emulator_state_dir() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/fdb-emulator-state.XXXXXX")
  echo "$dir"
}

emulator_config() {
  local dir="$1"
  python3 - "$dir" <<'PY'
import json, os, pathlib, sys

directory = pathlib.Path(sys.argv[1])
source = directory / 'firebase.json'
config = json.loads(source.read_text())
ports = {
    'auth': 'FIREBASE_AUTH_EMULATOR_PORT',
    'database': 'FIREBASE_DATABASE_EMULATOR_PORT',
    'firestore': 'FIREBASE_FIRESTORE_EMULATOR_PORT',
    'storage': 'FIREBASE_STORAGE_EMULATOR_PORT',
    'functions': 'FIREBASE_FUNCTIONS_EMULATOR_PORT',
}

changed = False
for emulator, variable in ports.items():
    chosen = os.environ.get(variable)
    if not chosen:
        continue
    entry = config['emulators'].setdefault(emulator, {})
    if entry.get('port') != int(chosen):
        entry['port'] = int(chosen)
        changed = True

if not changed:
    print(source)
else:
    # Dot-prefixed and ignored: it is derived from the environment of one run.
    generated = directory / '.firebase-emulators.json'
    generated.write_text(json.dumps(config, indent=2) + '\n')
    print(generated)
PY
}

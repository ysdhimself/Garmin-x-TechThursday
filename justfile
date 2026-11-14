set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# List the local development commands.
default:
    @just --list

# Start the backend and build/load the watch app.
up: server-start app-start

# Stop the backend and unload the watch app; keep the simulator and Funnel.
down: app-stop server-stop

# Restart both, rebuilding the watch app.
restart: down up

# Start the routing + phone-photo server in the background.
server-start:
    @python3 scripts/dev.py server-start

server-stop:
    @python3 scripts/dev.py server-stop

server-restart: server-stop server-start

# Build and load the app, starting the simulator if needed.
app-start:
    @python3 scripts/dev.py app-start

# Unload only this app, preserving the simulator's saved settings.
app-stop:
    @python3 scripts/dev.py app-stop

app-restart: app-stop app-start

status:
    @python3 scripts/dev.py status

# Follow backend, app, and simulator logs (Ctrl-C stops following only).
logs:
    @mkdir -p .run
    @touch .run/server.log .run/app.log .run/simulator.log
    @tail -n 30 -F .run/server.log .run/app.log .run/simulator.log

# Check that lifecycle commands refuse to kill unrelated services.
check:
    python3 -m unittest discover -s scripts -p '*_test.py'

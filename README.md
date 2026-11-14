# Touch Grass

A pixel-art Garmin watch app that gets you walking, asks you to scan a QR code,
and uses your phone camera and JEV to check that your hand is touching grass or
another plant. The phone website is served by the backend; there is no separate
frontend build or phone app to install.

## Shortcut to deploy the solution

For a working phone + watch setup, **run the backend on your laptop and expose it
over HTTPS with Tailscale Funnel**, then point the watch at that HTTPS address.

1. [Set up and start the backend](#1-start-the-backend).
2. [Enable the HTTPS tunnel](#deploy-the-backend-with-tailscale-funnel).
3. [Build and run the watch app](#2-build-and-run-the-watch-app), setting
   **Photo verification backend URL** and **Walk plan backend URL** to that HTTPS origin.
4. Advance to **PROVE IT**, scan the watch's QR code with your phone, allow the
   camera, and touch a plant. Once verified, tap the watch to start filling the
   boxes; the walking stats follow the completed challenge.

**Use `npm run dev`, not `npm start`, for the complete solution.** The current
`start` entry point only serves routing, not the phone website or photo sessions.
This is a prototype deployment, not a hardened public production service.

## Run locally

The commands below use Bash on Linux/macOS and run from the **repository root**.
For Windows, use the native Garmin SDK tools and PowerShell equivalents; see the
[backend guide](backend/README.md) for PowerShell examples.

### Prerequisites

- **Node.js 22.18+ and npm**; development has been on Node 24.
- A **TypeSafe JEV API key** for photo verification. Keep it on the backend only.
- **Garmin Connect IQ SDK**, its simulator, a downloaded target-device profile,
  and a developer signing key. Add `monkeyc`, `monkeydo`, and `connectiq` to your
  PATH. The verified local setup uses SDK 9.3.0 and Java 21; use Garmin's
  [SDK setup guide](https://developer.garmin.com/connect-iq/connect-iq-basics/getting-started/)
  or the Monkey C VS Code extension to install/configure them and generate a key.
- For testing on a phone: an HTTPS tunnel or host. The instructions below use
  [Tailscale Funnel](https://tailscale.com/kb/1223/funnel).

Supported build targets are `fenix7s`, `fenix7`, and `fenix7pro`. The examples use
`fenix7s`. Linux simulator setup has a few extra library requirements; see the
[Linux setup and troubleshooting guide](.agents/skills/running-garmin-simulator/SKILL.md).
Its Docker image and shell launchers are machine-local, not included in a clone.

### 1. Start the backend

```bash
npm --prefix backend ci
test -f backend/.env || cp backend/.env.example backend/.env
```

Edit `backend/.env` and set `JEV_API_KEY`. Leave `ROUTING_MODE=fixture` for the
prepared routing data. Even in fixture mode, photo verification needs a real JEV
key and internet access. Do not commit your key or signing key.

```bash
npm --prefix backend run dev
```

Leave that terminal running. In a second terminal:

```bash
curl --fail http://127.0.0.1:8787/health
```

Expect `{"ok":true,"mode":"fixture"}`. This checks the server, not whether your
JEV key works; scanning a session and submitting a camera frame checks JEV.
Port **8787** is the default; set `PORT` to change it.

The server automatically reads **`backend/.env`**, not `.env.local`. If you already
keep your configuration in `.env.local`, start it from the repository root with
`node --env-file=backend/.env.local backend/scripts/dev-server.ts` instead.
Restart the server after changing its environment.

### 2. Build and run the watch app

Download the `fenix7s` profile in Garmin SDK Manager first. Set the path to your
existing signing key, then build:

```bash
export GARMIN_KEY="$HOME/.Garmin/ConnectIQ/developer_key.der"
mkdir -p touch-grass/bin
monkeyc -f touch-grass/monkey.jungle -d fenix7s \
  -o touch-grass/bin/touch-grass.prg -y "$GARMIN_KEY"
```

Start the simulator with `connectiq` (or through VS Code) if it is not already
running. In another terminal, load the successful build:

```bash
monkeydo touch-grass/bin/touch-grass.prg fenix7s
```

In the simulator's **App Settings** editor, set **Photo verification backend URL**
(`PhotoBaseUrl`) and **Walk plan backend URL** (`WalkPlanUrl`) to your HTTPS origin
from the deployment section below. Set the backend's `PUBLIC_BASE_URL` to that
**same origin**, with no path or login wall.

For simulator-only HTTP testing, `http://127.0.0.1:8787` is the default. Temporarily
disable **Settings → Use Device HTTPS Requirements** if requests fail with
`SECURE_CONNECTION_REQUIRED` (`-1001`); re-enable it for HTTPS testing. A real watch
requires HTTPS. A loopback or plain LAN URL will not work for your phone camera.

### 3. Try the flow

Press START or tap to advance from the title through the alarm and map to the
walk. If no usable location arrives, the watch replays a built-in short walk.
On arrival, START opens **PROVE IT**. Scan its QR code with your phone, open the
camera, and show a hand touching grass, a leaf, or another plant.

A JEV confidence of at least **70%** passes the photo check and advances the
watch. Tap again to start the touch animation/countdown. Walking stats appear
directly afterward, then the app returns to its title screen.

The watch requests a route from the backend during the alarm step and uses a
bundled route if no plan is available when the map or walk loads. Set
`ROUTING_MODE=live` on the backend for live route discovery rather than fixture
data. The touch animation is still timed, not accelerometer-based detection.
Photo verification is a playful visual check, not anti-cheating proof.

## Deploy the backend with Tailscale Funnel

This is the quickest way to use a real phone without provisioning a cloud server.
Install Tailscale on the laptop, sign in (`tailscale up` on Linux), and ensure
your tailnet permits Funnel. Follow any HTTPS/Funnel approval link Tailscale
prints. The phone does **not** need Tailscale: Funnel provides a public HTTPS URL.

With the backend running, use another terminal on that laptop:

```bash
tailscale funnel --bg 8787
tailscale funnel status
```

**This publishes port 8787 to the internet.** Use a machine/HTTPS listener that
is not already serving another app; check existing Funnel configuration before
changing it.

Copy the HTTPS origin printed by Tailscale (for example,
`https://your-laptop.your-tailnet.ts.net`) into all three settings:

- `PUBLIC_BASE_URL` in `backend/.env` (or whichever environment file you use).
- The watch's **Photo verification backend URL** setting.
- The watch's **Walk plan backend URL** setting.

Restart the backend, then open `https://your-laptop.your-tailnet.ts.net/health`
from your phone. Use the private `/p/...` link in the watch's QR code for the
camera session; opening the site's root URL does not create one. Scan a fresh
QR after changing the origin.

Keep the laptop awake and the backend process running. `--bg` keeps the tunnel
configuration active; it does not run or supervise Node for you. Rebuilding the
watch does not require restarting the backend, and backend-only changes do not
require rebuilding the watch unless its URL changes and cannot be set in settings.

### Deploy to a physical Garmin watch

Build with the matching supported device ID instead of `fenix7s` if needed.
Connect the watch by USB and copy `touch-grass/bin/touch-grass.prg` into its
`GARMIN/APPS/` directory, then safely disconnect and launch **touch-grass**.
Keep the watch paired to a phone running Garmin Connect, with internet access.

Configure `PhotoBaseUrl` and `WalkPlanUrl` to the public HTTPS backend. If your
sideloaded app has no settings editor, change both default properties in
[`touch-grass/resources/settings/settings.xml`](touch-grass/resources/settings/settings.xml)
**before building**. An already-saved app setting overrides that default.
Simulator builds have been verified; physical-device installation and behavior
still need testing. Sideloading is not a Connect IQ Store release.

### Use another HTTPS host instead

On a Node 22.18+ host, deploy the repository, install with
`npm --prefix backend ci`, and run **`npm --prefix backend run dev`** from its root
under a process supervisor. Set `JEV_API_KEY`, `PUBLIC_BASE_URL` to the external
HTTPS origin, and `PORT` if the host requires it. Put an HTTPS reverse proxy in
front of the process, and use that origin on the watch too. No database or
frontend build is required for the current single-process setup.

Keep this to trusted prototype use. Sessions expire after ten minutes and are
lost on restart; multiple backend instances do not share them. Frames are sent
to JEV, so public access can incur API costs. Photo endpoints have basic limits,
but this entry point lacks the production routing server's broader protections.
Before a production launch, add deployment-wide abuse/spending controls, review
privacy and proxy logging, and provide shared session storage if scaling out.
See [backend limits and security notes](backend/README.md#session-contract-and-limits).

## Checks and further documentation

```bash
npm --prefix backend test
```

- [Watch flow, URL settings, and focused simulator tests](touch-grass/README.md)
- [Backend API, configuration, and routing details](backend/README.md)
- [Project plan](PROJECT_PLAN.md)

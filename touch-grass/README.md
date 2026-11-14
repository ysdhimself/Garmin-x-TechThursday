# Garmin-x-TechThursday

## Phone photo verification

PROVE_IT creates a photo session and displays the backend's QR matrix. Scan
it with your phone, then take the requested grass photo on the linked site.
The watch polls every two seconds and moves to TOUCH_GRASS only when the
backend reports `passed` with confidence at least `0.70`. The existing mock
touch countdown still lasts 2.5 seconds. Its empty boxes and waving hand
appear immediately after verification; tap or press START to begin filling
them. Until then, the boxes stay empty and the countdown stays at its start.
After "GRASS TOUCHED", the walk stats appear directly for five seconds,
then the app returns to its title screen. START skips either wait.

- BACK cancels verification and returns to MAP.
- START cannot skip verification. After an initial connection error or an
  expired session, START creates a new session.
- Temporary polling failures retain the QR and retry automatically. Leaving
  the screen, app inactivity, or stopping the app invalidates callbacks and
  stops polling; resuming creates a fresh session.

Configure the Garmin app setting **Photo verification backend URL**
(`PhotoBaseUrl`). Its default `http://127.0.0.1:8787` is for the local simulator
only. In the simulator, use the App Settings editor to change the property.
For HTTP-only local testing, temporarily uncheck **Settings → Use Device HTTPS
Requirements** in the simulator; otherwise requests fail with `-1001`
(`SECURE_CONNECTION_REQUIRED`). Restore it after testing. This is not an
option on a real watch.
On a real watch/phone, use a publicly reachable **HTTPS** backend URL (for
example, your ephemeral tunnel). Phone camera access requires HTTPS; a
loopback URL on the phone points at the phone, not your development machine.
The backend must return a phone-reachable HTTPS `url` encoded in `qr` as well.
The watch renders that supplied matrix, not a separately generated QR.

The app uses `Communications.makeWebRequest` with
`REQUEST_CONTENT_TYPE_JSON` and `HTTP_RESPONSE_CONTENT_TYPE_JSON` (see the
installed SDK's `doc/Toybox/Communications.html`). Session creation sends a
flat empty parameters dictionary to `POST /photo-sessions`; subsequent
requests are `GET /photo-sessions/{id}`. A 410 expires the QR; other polling
errors never advance the flow. There is at most one HTTP request outstanding,
including an obsolete request draining after cancellation.

To compile the photo contract tests separately from the unfinished motion
fixtures (from the repository root):

```sh
monkeyc -t -f 'touch-grass/monkey.jungle;touch-grass/photo-tests.jungle' \
  -d fenix7s -o .amp/in/build/touch-grass-tests.prg \
  -y "$HOME/.Garmin/ConnectIQ/developer_key.der"
```

This only compiles the tests. Execute them in the running simulator with
`monkeydo .amp/in/build/touch-grass-tests.prg fenix7s -t`.
The simulator-to-browser round trip has been exercised with a synthetic camera
and stub JEV scores, including QR decoding and automatic watch advancement.
Real phone/watch scanning and live JEV photo classification still need testing.

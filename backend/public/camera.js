const token = /^\/p\/([A-Za-z0-9_-]{16})$/.exec(location.pathname)?.[1];
const video = document.querySelector('video');
const start = document.querySelector('#start');
const pause = document.querySelector('#pause');
const status = document.querySelector('#status');
const detail = document.querySelector('#detail');
const viewfinder = document.querySelector('.viewfinder');
const canvas = document.createElement('canvas');
canvas.width = canvas.height = 384;
let stream;
let timer;
let expiry;
let request;
let generation = 0;
let passed = false;
let ended = false;
let ready = false;

function message(title, description = '') {
  status.textContent = title;
  detail.textContent = description;
  detail.hidden = !description;
}

function stop() {
  generation++;
  clearTimeout(timer);
  request?.abort();
  stream?.getTracks().forEach(track => track.stop());
  stream = null;
  video.srcObject = null;
  canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
  viewfinder.classList.remove('live');
  document.querySelector('.privacy').hidden = passed || ended;
  pause.hidden = true;
  start.hidden = passed || ended;
  start.disabled = false;
}

function expired() {
  ended = true;
  stop();
  message('Session expired.', 'Scan a new QR on your watch.');
}

function update(result) {
  clearTimeout(expiry);
  expiry = setTimeout(() => expired(), result.expiresInS * 1000);
  if (result.status === 'passed') {
    passed = true;
    clearTimeout(expiry);
    stop();
    document.querySelector('.passed-overlay').hidden = false;
    message('You touched grass.', 'You can close this page.');
    return;
  }
  if (!stream) message('Touch grass or a plant.');
  ready = true;
  start.onclick = openCamera;
  start.textContent = 'Open camera';
  start.disabled = false;
}

async function load() {
  if (!token) {
    ended = true;
    start.hidden = true;
    document.querySelector('.privacy').hidden = true;
    message('Scan the QR on your watch.');
    return;
  }
  try {
    const response = await fetch(`/photo-sessions/${token}`, { cache: 'no-store', signal: AbortSignal.timeout(10_000) });
    const result = await response.json();
    if (response.status === 410) return expired();
    if (!response.ok) throw new Error();
    update(result);
  } catch {
    message('Couldn’t connect.', 'Check your connection and try again.');
    start.textContent = 'Try again';
    start.disabled = false;
    start.onclick = () => { start.disabled = true; load(); };
  }
}

async function checkFrame(run) {
  if (run !== generation || !stream) return;
  const started = performance.now();
  try {
    if (!video.videoWidth || !video.videoHeight) throw new Error('Camera has no image yet. Please try again.');
    // Match the square preview: no stretching and no image history.
    const side = Math.min(video.videoWidth, video.videoHeight);
    canvas.getContext('2d').drawImage(video, (video.videoWidth - side) / 2, (video.videoHeight - side) / 2, side, side, 0, 0, 384, 384);
    const image = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    if (run !== generation) return;
    request = new AbortController();
    message('Keep your hand on the plant.');
    const response = await fetch(`/photo-sessions/${token}/frame`, {
      method: 'POST', headers: { 'Content-Type': 'image/png' }, body: image,
      signal: AbortSignal.any([request.signal, AbortSignal.timeout(20_000)]),
    });
    const result = await response.json();
    if (run !== generation) return;
    if (response.status === 410) return expired();
    if (response.status !== 429) {
      if (!response.ok) throw new Error(result.error?.message || 'Photo check unavailable.');
      update(result);
      if (passed) return;
    }
    timer = setTimeout(() => checkFrame(run), Math.max(1000 - (performance.now() - started), 0));
  } catch {
    if (run !== generation) return;
    stop();
    message('Check paused.', 'Try again in a moment.');
    start.textContent = 'Try again';
  }
}

async function openCamera() {
  if (!ready || passed || ended) return;
  start.disabled = true;
  const run = ++generation;
  try {
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) throw new Error('SECURE_CONTEXT');
    const camera = await navigator.mediaDevices.getUserMedia({ audio: false, video: { facingMode: { ideal: 'environment' }, width: { ideal: 640 }, height: { ideal: 640 } } });
    if (run !== generation) { camera.getTracks().forEach(track => track.stop()); return; }
    stream = camera;
    video.srcObject = camera;
    await video.play();
    if (run !== generation) return;
    viewfinder.classList.add('live');
    start.hidden = true;
    pause.hidden = false;
    checkFrame(run);
  } catch (error) {
    if (run !== generation) return;
    stop();
    message('Camera couldn’t open.', error.message === 'SECURE_CONTEXT'
      ? 'Open the secure link from your watch.'
      : error.name === 'NotAllowedError' ? 'Allow camera access in your browser settings.' : 'Check that your camera is available.');
    start.textContent = 'Try again';
  }
}

start.onclick = openCamera;
pause.onclick = () => { stop(); message('Paused.'); start.textContent = 'Resume'; };
document.addEventListener('visibilitychange', () => {
  if (document.hidden && ready && !passed && !ended) {
    stop();
    message('Paused.');
    start.textContent = 'Resume';
  }
});
window.addEventListener('pagehide', stop);
load();

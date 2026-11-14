import { test, type TestContext } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { createPhotoHandler } from "./photo-verification.ts";
import { encodePng, newImage } from "../routing/providers/png.ts";

const frame = encodePng(newImage(384, 384, [70, 130, 40, 255]));

async function serve(t: TestContext, fetchFn: typeof fetch, apiKey: string | undefined = "test-only-key") {
  const clock = { ms: 0 };
  const handler = createPhotoHandler({ publicBaseUrl: "https://grass.example", jevUrl: "https://jev.example", apiKey, fetchFn, now: () => clock.ms });
  const server = createServer(async (req, res) => {
    if (!(await handler(req, res))) { res.writeHead(404); res.end(); }
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise<void>(resolve => { server.closeAllConnections(); server.close(() => resolve()); }));
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  const base = `http://127.0.0.1:${address.port}`;
  const get = (path: string) => fetch(base + path);
  const post = (path: string, image?: BodyInit, headers?: Record<string, string>) => fetch(base + path, {
    method: "POST", body: image, headers: { ...(image ? { "Content-Type": "image/png" } : {}), ...headers },
  });
  const create = async () => {
    const response = await post("/photo-sessions");
    assert.equal(response.status, 201);
    return await response.json() as { id: string; url: string; qr: string[]; expiresInS: number };
  };
  return { clock, get, post, create };
}

test("private QR session only passes at 70%, remains passed, and expires", async t => {
  let confidence = 0.699;
  let checks = 0;
  const app = await serve(t, async (_url, init) => {
    checks++;
    const body = JSON.parse(init!.body as string);
    assert.equal(Buffer.from(body.assets.photo.data_base64, "base64").compare(frame), 0);
    return Response.json({ answers: { touching: { noul: confidence } } });
  });
  const session = await app.create();
  assert.match(session.id, /^[A-Za-z0-9_-]{16}$/);
  assert.equal(session.url, `https://grass.example/p/${session.id}`);
  assert.equal(session.expiresInS, 600);
  assert.ok(session.qr.length >= 21 && session.qr.every(row => /^[01]+$/.test(row) && row.length === session.qr.length));
  assert.ok(Buffer.byteLength(JSON.stringify(session)) < 8192);
  const path = `/photo-sessions/${session.id}`;
  assert.equal((await (await app.get(path)).json()).status, "pending");
  let response = await app.post(path + "/frame", frame);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).status, "pending");
  assert.equal((await (await app.get(path)).json()).confidence, 0.699);
  assert.equal((await app.post(path + "/frame", frame)).status, 429);
  app.clock.ms += 1000;
  confidence = 0.70;
  response = await app.post(path + "/frame", frame);
  assert.equal((await response.json()).status, "passed");
  assert.equal((await (await app.get(path)).json()).status, "passed");
  assert.equal((await (await app.post(path + "/frame", frame)).json()).status, "passed");
  assert.equal(checks, 2);
  app.clock.ms = 600_000;
  assert.equal((await app.get(path)).status, 410);
  assert.equal((await app.post(path + "/frame", frame)).status, 410);
});

test("provider errors and malformed scores never pass; a later check can recover", async t => {
  let answer: unknown = "0.99";
  const app = await serve(t, async () => {
    if (answer === "down") throw new Error("private-key-do-not-leak");
    return Response.json({ answers: { touching: { noul: answer } } });
  });
  const { id } = await app.create();
  const path = `/photo-sessions/${id}`;
  for (const invalid of ["0.99", null, 1.1, -0.1, "down"]) {
    answer = invalid;
    app.clock.ms += 1000;
    const res = await app.post(path + "/frame", frame);
    assert.equal(res.status, 503);
    assert.ok(!(await res.text()).includes("private-key"));
    assert.equal((await (await app.get(path)).json()).status, "pending");
  }
  answer = 0.91;
  app.clock.ms += 1000;
  assert.equal((await (await app.post(path + "/frame", frame)).json()).status, "passed");
});

test("invalid images, foreign origins and creation bursts are rejected before JEV", async t => {
  let checks = 0;
  const app = await serve(t, async () => { checks++; return Response.json({}); });
  const { id } = await app.create();
  assert.equal((await app.post("/photo-sessions")).status, 429);
  const path = `/photo-sessions/${id}/frame`;
  assert.equal((await app.post(path, frame, { Origin: "https://other.example" })).status, 403);
  assert.equal((await app.post(path, frame, { "Content-Type": "text/plain" })).status, 415);
  for (const [image, expected] of [[Buffer.from("not a photo"), 400], [encodePng(newImage(100, 100)), 400], [Buffer.alloc(512 * 1024 + 1), 413]] as const) {
    app.clock.ms += 1000;
    assert.equal((await app.post(path, image)).status, expected);
  }
  assert.equal(checks, 0);
  assert.equal((await app.get("/photo-sessions/aaaaaaaaaaaaaaaa")).status, 410);
  const page = await app.get(`/p/${id}`);
  assert.equal(page.headers.get("referrer-policy"), "no-referrer");
  assert.equal(page.headers.get("cache-control"), "no-store");
  assert.match(await page.text(), /Photos sent for AI checking/);
});

test("parallel frames cannot overlap and a late result cannot revive an expired session", async t => {
  let release!: () => void;
  let received!: () => void;
  const incoming = new Promise<void>(resolve => { received = resolve; });
  const gate = new Promise<void>(resolve => { release = resolve; });
  const app = await serve(t, async () => {
    received();
    await gate;
    return Response.json({ answers: { touching: { noul: 0.99 } } });
  });
  const { id } = await app.create();
  const path = `/photo-sessions/${id}`;
  const inFlight = app.post(path + "/frame", frame);
  await incoming;
  app.clock.ms += 2000;
  assert.equal((await app.post(path + "/frame", frame)).status, 429);
  app.clock.ms = 600_000;
  release();
  assert.equal((await inFlight).status, 410);
  assert.equal((await app.get(path)).status, 410);
});

test("missing server credentials disable session creation instead of faking success", async t => {
  const app = await serve(t, async () => { throw new Error("must not call provider"); }, "");
  assert.equal((await app.post("/photo-sessions")).status, 503);
});

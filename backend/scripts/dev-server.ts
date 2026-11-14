// Part 2 DEV SERVER for testing findGrassRoute over HTTP. Not the production service: Part 3 owns that
// (HTTPS, rate limiting, deployment). Same contract, so the watch/simulator can use it in the meantime.
//
//   node backend/scripts/dev-server.ts            (PORT=8787 by default, mode from ROUTING_MODE in backend/.env)
//   GET  /health
//   POST /walk-plan  {"originLatE6":53546000,"originLonE6":-113493800,"maxWalkS":120}
import { createServer, type ServerResponse } from "node:http";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { findGrassRoute, fixtureProviderFromEnv, isFailure, liveProviderFromEnv, RoutingError, type RoutingProvider } from "../src/routing/index.ts";
import { createPhotoHandler } from "../src/photo/photo-verification.ts";

const envFile = fileURLToPath(new URL("../.env", import.meta.url));
if (existsSync(envFile)) process.loadEnvFile(envFile);

const mode = process.env.ROUTING_MODE === "live" ? "live" : "fixture";
const port = Number(process.env.PORT ?? 8787);
const STATUS = { INVALID_REQUEST: 400, NO_ROUTE: 404, PROVIDER_UNAVAILABLE: 503 } as const;
const handlePhoto = createPhotoHandler({
  publicBaseUrl: process.env.PUBLIC_BASE_URL ?? `http://127.0.0.1:${port}`,
  jevUrl: process.env.JEV_API_URL ?? "https://api.typesafe.ai/v1/systemone",
  apiKey: process.env.JEV_API_KEY,
  model: process.env.JEV_MODEL,
});

let provider: RoutingProvider | RoutingError;
try {
  provider = mode === "live" ? liveProviderFromEnv() : fixtureProviderFromEnv();
} catch (e) {
  provider = e as RoutingError; // reported per request so /health still answers
}

function send(res: ServerResponse, status: number, body: unknown) {
  const json = JSON.stringify(body);
  res.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(json) });
  res.end(json);
}

const server = createServer(async (req, res) => {
  // Photo paths contain bearer session tokens: do not put them in request logs.
  try {
    if (await handlePhoto(req, res)) return;
  } catch {
    if (!res.headersSent) send(res, 500, { error: { code: "INTERNAL_ERROR", message: "Photo service unavailable." } });
    else res.end();
    return;
  }
  const started = Date.now();
  const log = (status: number) => console.log(`${req.method} ${req.url} -> ${status} (${Date.now() - started} ms)`); // never logs coordinates

  if (req.method === "GET" && req.url === "/health") {
    log(200);
    return send(res, 200, { ok: !(provider instanceof RoutingError), mode });
  }
  if (req.method !== "POST" || req.url !== "/walk-plan") {
    log(404);
    return send(res, 404, { error: { code: "INVALID_REQUEST", message: "Use POST /walk-plan or GET /health." } });
  }

  let raw = "";
  req.on("data", (c) => {
    raw += c;
    if (raw.length > 1024) req.destroy(); // requests are three integers
  });
  req.on("end", async () => {
    let body: any;
    try {
      body = JSON.parse(raw);
    } catch {
      log(400);
      return send(res, 400, { error: { code: "INVALID_REQUEST", message: "Body must be JSON." } });
    }
    if (provider instanceof RoutingError) {
      log(503);
      return send(res, 503, { error: { code: provider.code, message: provider.message } });
    }
    const r = await findGrassRoute(body?.originLatE6, body?.originLonE6, body?.maxWalkS ?? 120, provider);
    const status = isFailure(r) ? STATUS[r.error.code] : 200;
    log(status);
    send(res, status, r);
  });
}).listen(port, () => {
  console.log(`Touch Grass dev server on port ${port}  mode=${mode}${provider instanceof RoutingError ? `  (not ready: ${provider.message})` : ""}`);
});
server.requestTimeout = 20_000;
server.headersTimeout = 10_000;

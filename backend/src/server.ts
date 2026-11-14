import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  findGrassRoute,
  fixtureProvider,
  isFailure,
  liveProviderFromEnv,
  RoutingError,
  type RoutingProvider,
} from "./routing/index.ts";
import { byteSize } from "./routing/validate.ts";

const envFile = fileURLToPath(new URL("../.env", import.meta.url));
if (existsSync(envFile)) process.loadEnvFile(envFile);

const mode = process.env.ROUTING_MODE === "live" ? "live" : "fixture";
const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? "0.0.0.0";
const MAX_BODY = 1024;
const MAX_RESPONSE_BYTES = 8192;
const RATE_LIMIT = 10;
const RATE_WINDOW_MS = 60_000;
const REQUEST_TIMEOUT_MS = 30_000;

const STATUS: Record<string, number> = {
  INVALID_REQUEST: 400,
  NO_ROUTE: 404,
  PROVIDER_UNAVAILABLE: 503,
};

let provider: RoutingProvider | RoutingError;
try {
  provider = mode === "live" ? liveProviderFromEnv() : fixtureProvider();
} catch (e) {
  provider = e as RoutingError;
}

// In-memory rate limiter per IP, resets on restart.
const hits = new Map<string, { count: number; resetAt: number }>();

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const entry = hits.get(ip);
  if (!entry || now >= entry.resetAt) {
    hits.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return false;
  }
  entry.count++;
  return entry.count > RATE_LIMIT;
}

function cors(res: ServerResponse) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Max-Age", "86400");
}

function send(res: ServerResponse, status: number, body: unknown) {
  const json = JSON.stringify(body);
  cors(res);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(json),
  });
  res.end(json);
}

function clientIp(req: IncomingMessage): string {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string") return forwarded.split(",")[0]!.trim();
  return req.socket.remoteAddress ?? "unknown";
}

const server = createServer((req, res) => {
  const started = Date.now();
  const log = (status: number) =>
    console.log(`${req.method} ${req.url} -> ${status} (${Date.now() - started} ms)`);

  cors(res);

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  const ip = clientIp(req);
  if (isRateLimited(ip)) {
    log(429);
    return send(res, 429, {
      error: { code: "INVALID_REQUEST", message: "Rate limit exceeded. Try again in a minute." },
    });
  }

  if (req.method === "GET" && req.url === "/health") {
    log(200);
    return send(res, 200, { ok: !(provider instanceof RoutingError), mode });
  }

  if (req.method !== "POST" || req.url !== "/walk-plan") {
    log(404);
    return send(res, 404, {
      error: { code: "INVALID_REQUEST", message: "Use POST /walk-plan or GET /health." },
    });
  }

  const timeout = setTimeout(() => {
    if (!res.headersSent) {
      log(504);
      send(res, 504, {
        error: { code: "PROVIDER_UNAVAILABLE", message: "Request timed out." },
      });
    }
  }, REQUEST_TIMEOUT_MS);

  let raw = "";
  req.on("data", (chunk: Buffer) => {
    raw += chunk;
    if (raw.length > MAX_BODY) {
      clearTimeout(timeout);
      log(413);
      send(res, 413, {
        error: { code: "INVALID_REQUEST", message: "Request body too large." },
      });
      req.destroy();
    }
  });

  req.on("end", async () => {
    if (res.headersSent) return;

    let body: any;
    try {
      body = JSON.parse(raw);
    } catch {
      clearTimeout(timeout);
      log(400);
      return send(res, 400, {
        error: { code: "INVALID_REQUEST", message: "Body must be JSON." },
      });
    }

    if (provider instanceof RoutingError) {
      clearTimeout(timeout);
      log(503);
      return send(res, 503, {
        error: { code: provider.code, message: provider.message },
      });
    }

    const result = await findGrassRoute(
      body?.originLatE6,
      body?.originLonE6,
      body?.maxWalkS ?? 120,
      provider,
    );

    clearTimeout(timeout);
    if (res.headersSent) return;

    if (isFailure(result)) {
      const status = STATUS[result.error.code] ?? 500;
      log(status);
      return send(res, status, result);
    }

    const size = byteSize(result);
    if (size > MAX_RESPONSE_BYTES) {
      log(500);
      return send(res, 500, {
        error: {
          code: "PROVIDER_UNAVAILABLE",
          message: `Plan exceeds ${MAX_RESPONSE_BYTES}-byte budget (${size} bytes).`,
        },
      });
    }

    log(200);
    send(res, 200, result);
  });
});

server.listen(port, host, () => {
  const providerStatus =
    provider instanceof RoutingError ? `  (not ready: ${provider.message})` : "";
  console.log(
    `Touch Grass backend on http://${host}:${port}  mode=${mode}${providerStatus}`,
  );
  console.log(`  POST /walk-plan   GET /health`);
});

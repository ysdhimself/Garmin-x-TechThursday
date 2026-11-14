import type { ErrorCode, RoutingFailure } from "./types.ts";

export class RoutingError extends Error {
  code: ErrorCode;
  constructor(code: ErrorCode, message: string) {
    super(message);
    this.name = "RoutingError";
    this.code = code;
  }
}

export function failure(code: ErrorCode, message: string): RoutingFailure {
  return { error: { code, message } };
}

export function isFailure(r: object): r is RoutingFailure {
  return "error" in r;
}

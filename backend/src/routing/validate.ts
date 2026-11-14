import { isValidE6 } from "./geo.ts";
import { LIMITS, type WalkPlan } from "./types.ts";

const isAscii = (s: unknown, max: number): s is string =>
  typeof s === "string" && s.length > 0 && s.length <= max && /^[\x20-\x7E]+$/.test(s);

export const byteSize = (v: unknown) => Buffer.byteLength(JSON.stringify(v), "utf8");

/** Contract violations; empty means the plan is safe to send to the watch. */
export function validatePlan(plan: WalkPlan): string[] {
  const errs: string[] = [];
  const L = LIMITS;

  if (plan.version !== 1) errs.push("version must be 1");
  if (plan.source !== "live" && plan.source !== "fixture") errs.push("source must be live|fixture");
  if (!isValidE6(plan.origin)) errs.push("origin must be integer [latE6, lonE6]");

  const d = plan.destination;
  if (!isAscii(d?.name, L.nameChars)) errs.push("destination.name must be 1-40 ASCII chars");
  if (!isValidE6(d?.point)) errs.push("destination.point invalid");
  if (!Number.isInteger(d?.arrivalRadiusM) || d.arrivalRadiusM <= 0)
    errs.push("destination.arrivalRadiusM must be a positive integer");

  const r = plan.route;
  if (!Array.isArray(r?.points) || r.points.length < L.routePoints.min || r.points.length > L.routePoints.max)
    errs.push(`route.points must have ${L.routePoints.min}-${L.routePoints.max} points`);
  else if (!r.points.every(isValidE6)) errs.push("route.points must be integer E6 pairs");
  if (!Number.isInteger(r?.distanceM) || r.distanceM < 0) errs.push("route.distanceM must be a non-negative integer");
  if (!Number.isInteger(r?.durationS) || r.durationS < 0) errs.push("route.durationS must be a non-negative integer");

  const gs = plan.greenSpaces;
  if (!Array.isArray(gs) || gs.length < L.greenSpaces.min || gs.length > L.greenSpaces.max)
    errs.push(`greenSpaces must have ${L.greenSpaces.min}-${L.greenSpaces.max} entries`);
  else
    gs.forEach((g, i) => {
      if (!isAscii(g.name, L.nameChars)) errs.push(`greenSpaces[${i}].name must be 1-40 ASCII chars`);
      if (!Array.isArray(g.ring) || g.ring.length < L.ringVertices.min || g.ring.length > L.ringVertices.max)
        errs.push(`greenSpaces[${i}].ring must have ${L.ringVertices.min}-${L.ringVertices.max} vertices`);
      else if (!g.ring.every(isValidE6)) errs.push(`greenSpaces[${i}].ring must be integer E6 pairs`);
    });

  if (!isAscii(plan.attribution, L.attributionChars)) errs.push("attribution must be 1-160 ASCII chars");

  const bytes = byteSize(plan);
  if (bytes > L.maxResponseBytes) errs.push(`response is ${bytes} bytes, limit ${L.maxResponseBytes}`);
  return errs;
}

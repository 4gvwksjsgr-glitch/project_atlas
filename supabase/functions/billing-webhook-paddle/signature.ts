/**
 * Paddle webhook signature verification (sandbox).
 * Signed payload = UTF-8(ts + ":") + exact raw body bytes.
 */

import { timingSafeEqualHex } from "./crypto_hash.ts";
import { WEBHOOK_SIGNATURE_TOLERANCE_SECONDS } from "./types.ts";

export interface ParsedPaddleSignature {
  ts: number;
  h1: string[];
}

export type ParseSignatureResult =
  | { ok: true; value: ParsedPaddleSignature }
  | { ok: false; reason: "missing" | "malformed" };

export function parsePaddleSignatureHeader(
  header: string | null,
): ParseSignatureResult {
  if (header === null || header === undefined || header.trim() === "") {
    return { ok: false, reason: "missing" };
  }

  const parts = header.split(";");
  let ts: number | null = null;
  const h1: string[] = [];

  for (const part of parts) {
    const trimmed = part.trim();
    if (!trimmed) continue;
    const eq = trimmed.indexOf("=");
    if (eq <= 0) return { ok: false, reason: "malformed" };
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim();
    if (!key || !value) return { ok: false, reason: "malformed" };

    if (key === "ts") {
      if (ts !== null) return { ok: false, reason: "malformed" };
      if (!/^[0-9]+$/.test(value)) return { ok: false, reason: "malformed" };
      const n = Number(value);
      if (!Number.isSafeInteger(n)) return { ok: false, reason: "malformed" };
      ts = n;
    } else if (key === "h1") {
      if (!/^[0-9a-f]+$/i.test(value) || value.length !== 64) {
        return { ok: false, reason: "malformed" };
      }
      h1.push(value.toLowerCase());
    } else {
      // Unknown keys are ignored for forward compatibility, but empty rejected above.
      continue;
    }
  }

  if (ts === null) return { ok: false, reason: "malformed" };
  if (h1.length === 0) return { ok: false, reason: "malformed" };
  return { ok: true, value: { ts, h1 } };
}

export function isTimestampWithinTolerance(
  tsSeconds: number,
  nowMs: number,
  toleranceSeconds: number = WEBHOOK_SIGNATURE_TOLERANCE_SECONDS,
): boolean {
  const nowSeconds = Math.floor(nowMs / 1000);
  const delta = Math.abs(nowSeconds - tsSeconds);
  return delta <= toleranceSeconds;
}

function bytesToHex(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i]!.toString(16).padStart(2, "0");
  }
  return out;
}

/**
 * Verify Paddle-Signature against exact raw body bytes.
 * Constant-time compare against every h1; does not early-exit on mismatch.
 */
export async function verifyPaddleSignature(args: {
  header: string | null;
  rawBody: Uint8Array;
  secret: string;
  nowMs: number;
  subtle?: SubtleCrypto;
  toleranceSeconds?: number;
}): Promise<{ ok: true } | { ok: false; reason: string }> {
  const parsed = parsePaddleSignatureHeader(args.header);
  if (!parsed.ok) return { ok: false, reason: parsed.reason };

  if (
    !isTimestampWithinTolerance(
      parsed.value.ts,
      args.nowMs,
      args.toleranceSeconds ?? WEBHOOK_SIGNATURE_TOLERANCE_SECONDS,
    )
  ) {
    return { ok: false, reason: "stale_timestamp" };
  }

  const subtle = args.subtle ?? crypto.subtle;
  const enc = new TextEncoder();
  const prefix = enc.encode(`${parsed.value.ts}:`);
  const signed = new Uint8Array(prefix.byteLength + args.rawBody.byteLength);
  signed.set(prefix, 0);
  signed.set(args.rawBody, prefix.byteLength);

  const key = await subtle.importKey(
    "raw",
    enc.encode(args.secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = new Uint8Array(await subtle.sign("HMAC", key, signed));
  const expectedHex = bytesToHex(mac);

  let matched = false;
  for (const candidate of parsed.value.h1) {
    // Always evaluate full compare; OR into matched (no early return).
    const eq = timingSafeEqualHex(expectedHex, candidate);
    matched = matched || eq;
  }

  if (!matched) return { ok: false, reason: "digest_mismatch" };
  return { ok: true };
}

/** Structured logging that never records secrets or request bodies. */

export type LogLevel = "info" | "warn" | "error";

export interface SafeLogFields {
  correlation_id?: string;
  event?: string;
  error_code?: string;
  status?: number;
  checkout_session_id?: string;
  company_id?: string;
  provider_create_status?: string;
  checkout_status?: string;
  reused?: boolean;
  applied?: boolean;
  paddle_kind?: string;
  duration_ms?: number;
  [key: string]: unknown;
}

const FORBIDDEN_KEY_FRAGMENTS = [
  "authorization",
  "api_key",
  "apikey",
  "password",
  "secret",
  "token",
  "return_token",
  "bearer",
  "cookie",
  "body",
  "request_body",
];

function isForbiddenKey(key: string): boolean {
  const lower = key.toLowerCase();
  return FORBIDDEN_KEY_FRAGMENTS.some((f) => lower.includes(f));
}

export function sanitizeLogFields(
  fields: SafeLogFields | Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(fields)) {
    if (isForbiddenKey(key)) continue;
    if (value === undefined) continue;
    if (
      typeof value === "string" || typeof value === "number" ||
      typeof value === "boolean" || value === null
    ) {
      out[key] = value;
      continue;
    }
    // Drop nested objects/arrays to avoid accidental body/token leakage.
  }
  return out;
}

export function logSafe(
  level: LogLevel,
  message: string,
  fields: SafeLogFields = {},
): void {
  const payload = {
    level,
    message,
    ...sanitizeLogFields(fields),
  };
  const line = JSON.stringify(payload);
  if (level === "error") {
    console.error(line);
  } else if (level === "warn") {
    console.warn(line);
  } else {
    console.log(line);
  }
}

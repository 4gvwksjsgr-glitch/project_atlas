/**
 * Apply-failure sanitization for the Paddle sandbox processor.
 * Allowlist-only — never persist arbitrary ATLAS_* strings.
 */

import { AtlasHttpError } from "../_shared/errors.ts";
import {
  APPROVED_APPLY_ERROR_CODES,
  type ApprovedApplyErrorCode,
  PROCESSOR_INTERNAL_ERROR,
  TERMINAL_APPLY_OUTCOMES,
  type TerminalApplyOutcome,
} from "./types.ts";

const APPROVED = new Set<string>(APPROVED_APPLY_ERROR_CODES);
const TERMINAL = new Set<string>(TERMINAL_APPLY_OUTCOMES);

const ATLAS_CODE_RE = /\b(ATLAS_[A-Z0-9_]+)\b/g;

function collectAtlasCodes(text: string): string[] {
  const found: string[] = [];
  for (const m of text.matchAll(ATLAS_CODE_RE)) {
    const code = m[1];
    if (code && !found.includes(code)) found.push(code);
  }
  return found;
}

function approveExact(code: string): string {
  if (APPROVED.has(code)) return code as ApprovedApplyErrorCode;
  return PROCESSOR_INTERNAL_ERROR;
}

/**
 * Map an apply failure into a fail-finalizer error_sanitized value.
 * Exactly one approved Atlas code → that code; otherwise INTERNAL.
 */
export function sanitizeApplyFailure(err: unknown): string {
  if (err instanceof AtlasHttpError) {
    if (/^ATLAS_[A-Z0-9_]+$/.test(err.errorCode)) {
      return approveExact(err.errorCode);
    }
    const fromMessage = collectAtlasCodes(err.message);
    if (fromMessage.length === 1) return approveExact(fromMessage[0]!);
    return PROCESSOR_INTERNAL_ERROR;
  }

  if (err instanceof Error) {
    const codes = collectAtlasCodes(err.message);
    if (codes.length === 1) return approveExact(codes[0]!);
    return PROCESSOR_INTERNAL_ERROR;
  }

  if (typeof err === "string") {
    const codes = collectAtlasCodes(err);
    if (codes.length === 1) return approveExact(codes[0]!);
    return PROCESSOR_INTERNAL_ERROR;
  }

  return PROCESSOR_INTERNAL_ERROR;
}

export function isTerminalApplyOutcome(
  outcome: string,
): outcome is TerminalApplyOutcome {
  return TERMINAL.has(outcome);
}

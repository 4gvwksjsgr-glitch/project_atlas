/** Timing-safe secret comparison helpers (Web Crypto). */

export async function timingSafeEqualString(
  left: string,
  right: string,
  subtle: SubtleCrypto = crypto.subtle,
): Promise<boolean> {
  const enc = new TextEncoder();
  const leftDigest = new Uint8Array(
    await subtle.digest("SHA-256", enc.encode(left)),
  );
  const rightDigest = new Uint8Array(
    await subtle.digest("SHA-256", enc.encode(right)),
  );
  if (leftDigest.length !== rightDigest.length) return false;
  let diff = 0;
  for (let i = 0; i < leftDigest.length; i++) {
    diff |= leftDigest[i]! ^ rightDigest[i]!;
  }
  return diff === 0;
}

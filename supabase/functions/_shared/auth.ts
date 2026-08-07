/**
 * Auth helpers — actor_user_id must come from verified auth only.
 * Body-supplied user id fields are never trusted (rejected upstream in http.ts).
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { AtlasHttpError, defaultMessageForCode } from "./errors.ts";

export interface AuthenticatedActor {
  actor_user_id: string;
}

export type AuthUserLookup = (accessToken: string) => Promise<
  {
    id: string;
  } | null
>;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function extractBearerToken(
  authorizationHeader: string | null,
): string {
  if (!authorizationHeader) {
    throw new AtlasHttpError(
      401,
      "ATLAS_NOT_AUTHENTICATED",
      defaultMessageForCode("ATLAS_NOT_AUTHENTICATED"),
    );
  }
  const match = authorizationHeader.match(/^Bearer\s+(\S+)\s*$/i);
  if (!match) {
    throw new AtlasHttpError(
      401,
      "ATLAS_NOT_AUTHENTICATED",
      defaultMessageForCode("ATLAS_NOT_AUTHENTICATED"),
    );
  }
  return match[1]!;
}

/**
 * Verify JWT via Supabase Auth and return actor_user_id (= auth.users.id).
 */
export async function requireAuthenticatedActor(
  authorizationHeader: string | null,
  lookup: AuthUserLookup,
): Promise<AuthenticatedActor> {
  const token = extractBearerToken(authorizationHeader);
  let user: { id: string } | null;
  try {
    user = await lookup(token);
  } catch {
    throw new AtlasHttpError(
      401,
      "ATLAS_NOT_AUTHENTICATED",
      defaultMessageForCode("ATLAS_NOT_AUTHENTICATED"),
    );
  }
  if (!user || typeof user.id !== "string" || !UUID_RE.test(user.id)) {
    throw new AtlasHttpError(
      401,
      "ATLAS_NOT_AUTHENTICATED",
      defaultMessageForCode("ATLAS_NOT_AUTHENTICATED"),
    );
  }
  return { actor_user_id: user.id.toLowerCase() };
}

export function createAuthUserLookup(
  supabaseUrl: string,
  anonKey: string,
  fetchImpl: typeof fetch = fetch,
): AuthUserLookup {
  return async (accessToken: string) => {
    const client: SupabaseClient = createClient(supabaseUrl, anonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
      global: {
        fetch: fetchImpl,
        headers: { Authorization: `Bearer ${accessToken}` },
      },
    });
    const { data, error } = await client.auth.getUser(accessToken);
    if (error || !data.user) return null;
    return { id: data.user.id };
  };
}

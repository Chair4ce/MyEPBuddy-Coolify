import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";
import { refreshUserSignatures } from "@/lib/style-signatures";

// Signature regeneration can involve multiple LLM calls
export const maxDuration = 60;

/**
 * POST /api/refresh-style-signatures
 *
 * Triggers regeneration of style signatures for the authenticated user.
 * Scans all finalized statements, groups by rank+AFSC+MPA, and
 * regenerates any stale signatures.
 *
 * This is intentionally rate-limited by the source hash check inside
 * generateStyleSignature() -- if statements haven't changed, the
 * signature won't be regenerated.
 */
export async function POST() {
  try {
    const supabase = await createClient();

    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const generated = await refreshUserSignatures(user.id);

    return NextResponse.json({
      success: true,
      signaturesGenerated: generated,
    });
  } catch (error) {
    console.error("[refresh-style-signatures] Error:", error);
    return NextResponse.json(
      { error: "Failed to refresh style signatures" },
      { status: 500 }
    );
  }
}

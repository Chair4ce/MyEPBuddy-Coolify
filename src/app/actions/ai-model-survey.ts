"use server";

import { createClient } from "@/lib/supabase/server";

export type PaymentPreference = "subscription" | "on_demand" | "bring_own_key" | "not_interested" | "dismissed";
export type SourcePage = "generate" | "award" | "decoration";

interface SurveySubmission {
  paymentPreference: PaymentPreference;
  pricePoint: number | null;
  sourcePage: SourcePage;
}

/**
 * Submit AI model survey response.
 * Validates and inserts securely server-side.
 */
export async function submitAiModelSurvey(
  submission: SurveySubmission
): Promise<{ success: boolean; error?: string }> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { success: false, error: "Not authenticated" };
  }

  // Validate payment preference
  const validPreferences: PaymentPreference[] = [
    "subscription",
    "on_demand",
    "bring_own_key",
    "not_interested",
    "dismissed",
  ];
  if (!validPreferences.includes(submission.paymentPreference)) {
    return { success: false, error: "Invalid payment preference" };
  }

  // Validate source page
  const validPages: SourcePage[] = ["generate", "award", "decoration"];
  if (!validPages.includes(submission.sourcePage)) {
    return { success: false, error: "Invalid source page" };
  }

  // Validate price point (must be a reasonable dollar amount or null)
  if (
    submission.pricePoint !== null &&
    (typeof submission.pricePoint !== "number" ||
      submission.pricePoint < 1 ||
      submission.pricePoint > 100)
  ) {
    return { success: false, error: "Invalid price point" };
  }

  const { error } = await supabase.from("ai_model_survey_responses").upsert(
    {
      user_id: user.id,
      payment_preference: submission.paymentPreference,
      price_point: submission.pricePoint,
      source_page: submission.sourcePage,
    } as never,
    { onConflict: "user_id" }
  );

  if (error) {
    console.error("Failed to save survey response:", error);
    return { success: false, error: "Failed to save response" };
  }

  return { success: true };
}

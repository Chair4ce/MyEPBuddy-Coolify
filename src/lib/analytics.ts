/**
 * Self-hosted analytics client for MyEPBuddy
 * All data stays in our Supabase database - no third-party services
 */

// Generate a session ID that persists for the browser session
function getSessionId(): string {
  if (typeof window === "undefined") return "server";
  
  let sessionId = sessionStorage.getItem("analytics_session_id");
  if (!sessionId) {
    sessionId = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    sessionStorage.setItem("analytics_session_id", sessionId);
  }
  return sessionId;
}

// Track an event
async function trackEvent(eventName: string, properties?: Record<string, unknown>) {
  if (typeof window === "undefined") return;
  
  try {
    await fetch("/api/analytics", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        event_name: eventName,
        properties: properties || {},
        session_id: getSessionId(),
        page_path: window.location.pathname,
        referrer: document.referrer || null,
        screen_width: window.screen.width,
        screen_height: window.screen.height,
      }),
      // Don't wait for response - fire and forget
      keepalive: true,
    });
  } catch {
    // Analytics should never break the app
  }
}

// Track page view
export function trackPageView(path?: string) {
  trackEvent("$pageview", { path: path || window.location.pathname });
}

// ============================================
// MYEPBUDDY-SPECIFIC EVENTS
// ============================================

export const Analytics = {
  // Onboarding & Activation
  signUp: (method: "email" | "google" | "phone") => 
    trackEvent("user_signed_up", { method }),
  
  profileCompleted: (rank: string, afsc: string) => 
    trackEvent("profile_completed", { rank, afsc }),

  // Core workflow - THE KEY FUNNEL
  accomplishmentCreated: (mpa: string, hasMetrics: boolean) => 
    trackEvent("accomplishment_created", { mpa, has_metrics: hasMetrics }),
  
  accomplishmentEdited: (mpa: string) => 
    trackEvent("accomplishment_edited", { mpa }),

  // Statement generation
  generateStarted: (model: string, style: string, mpaCount: number) => 
    trackEvent("generate_started", { model, style, mpa_count: mpaCount }),
  
  generateCompleted: (model: string, durationMs: number, statementCount: number) => 
    trackEvent("generate_completed", { model, duration_ms: durationMs, statement_count: statementCount }),
  
  generateFailed: (model: string, error: string) => 
    trackEvent("generate_failed", { model, error: error.slice(0, 50) }), // Truncate error

  // Statement actions
  statementCopied: (mpa: string) => 
    trackEvent("statement_copied", { mpa }),
  
  statementSaved: (mpa: string, toLibrary: boolean) => 
    trackEvent("statement_saved", { mpa, to_library: toLibrary }),
  
  statementShared: (shareType: "team" | "chain" | "community") => 
    trackEvent("statement_shared", { share_type: shareType }),

  // EPB workflow
  epbOpened: (isOwnEpb: boolean) => 
    trackEvent("epb_opened", { is_own: isOwnEpb }),
  
  epbArchived: () => 
    trackEvent("epb_archived"),
  
  epbCollaborationStarted: () => 
    trackEvent("epb_collaboration_started"),

  // Team features
  teamMemberAdded: (type: "account" | "managed") => 
    trackEvent("team_member_added", { type }),
  
  supervisionRequested: (direction: "up" | "down") => 
    trackEvent("supervision_requested", { direction }),

  // Award packages
  awardCreated: (category: string, period: string) => 
    trackEvent("award_created", { category, period }),

  // API Keys
  apiKeyAdded: (provider: string) => 
    trackEvent("api_key_added", { provider }),
  
  apiKeyRemoved: (provider: string) => 
    trackEvent("api_key_removed", { provider }),

  // Feature discovery
  featureViewed: (feature: string) => 
    trackEvent("feature_viewed", { feature }),

  // Errors (sanitized)
  errorEncountered: (context: string) => 
    trackEvent("error_encountered", { context }),
};

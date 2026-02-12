"use client";

import { useState, useEffect, useCallback } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";
import {
  Sparkles,
  CircleAlert,
  Zap,
  CreditCard,
  CalendarCheck,
  ThumbsUp,
  ArrowRight,
  Key,
} from "lucide-react";
import { Analytics } from "@/lib/analytics";
import {
  submitAiModelSurvey,
  type PaymentPreference,
  type SourcePage,
} from "@/app/actions/ai-model-survey";

const STORAGE_KEY = "ai-model-survey-seen";
const GENERATION_COUNT_KEY = "ai-generation-count";
const SURVEY_TRIGGER_EVENT = "ai-survey-trigger";
const GENERATION_THRESHOLD = 2;

type SurveyStep =
  | "question"
  | "payment_type"
  | "price_subscription"
  | "price_credits"
  | "thanks";

const SUBSCRIPTION_PRICES = [3, 5, 10, 15, 20];
const CREDIT_PRICES = [1, 3, 5, 10, 15];

// Step counter config: which step number and total for each step
function getStepInfo(step: SurveyStep): { current: number; total: number } | null {
  switch (step) {
    case "question":
      return { current: 1, total: 3 };
    case "payment_type":
      return { current: 2, total: 3 };
    case "price_subscription":
    case "price_credits":
      return { current: 3, total: 3 };
    case "thanks":
      return null;
  }
}

interface AiModelSurveyModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  sourcePage: SourcePage;
}

export function AiModelSurveyModal({
  open,
  onOpenChange,
  sourcePage,
}: AiModelSurveyModalProps) {
  const [step, setStep] = useState<SurveyStep>("question");
  const [preference, setPreference] = useState<PaymentPreference | null>(null);
  const [submitted, setSubmitted] = useState(false);

  // Track when survey is shown
  useEffect(() => {
    if (open) {
      Analytics.aiSurveyShown(sourcePage);
    }
  }, [open, sourcePage]);

  const markAsSeen = useCallback(() => {
    localStorage.setItem(STORAGE_KEY, "true");
  }, []);

  const handleClose = useCallback(() => {
    markAsSeen();
    if (!submitted) {
      Analytics.aiSurveyDismissed(sourcePage);
      submitAiModelSurvey({
        paymentPreference: "dismissed",
        pricePoint: null,
        sourcePage,
      });
    }
    onOpenChange(false);
  }, [markAsSeen, onOpenChange, sourcePage, submitted]);

  const handleBringOwnKey = useCallback(async () => {
    setPreference("bring_own_key");
    setSubmitted(true);
    markAsSeen();
    Analytics.aiSurveyCompleted("bring_own_key", null, sourcePage);
    await submitAiModelSurvey({
      paymentPreference: "bring_own_key",
      pricePoint: null,
      sourcePage,
    });
    setStep("thanks");
  }, [markAsSeen, sourcePage]);

  const handleNotInterested = useCallback(async () => {
    setPreference("not_interested");
    setSubmitted(true);
    markAsSeen();
    Analytics.aiSurveyCompleted("not_interested", null, sourcePage);
    await submitAiModelSurvey({
      paymentPreference: "not_interested",
      pricePoint: null,
      sourcePage,
    });
    setStep("thanks");
  }, [markAsSeen, sourcePage]);

  const handleWouldPay = useCallback(() => {
    setStep("payment_type");
  }, []);

  const handlePaymentType = useCallback(
    (pref: "subscription" | "on_demand") => {
      setPreference(pref);
      setStep(
        pref === "subscription" ? "price_subscription" : "price_credits"
      );
    },
    []
  );

  const handlePriceSelect = useCallback(
    async (price: number) => {
      setSubmitted(true);
      markAsSeen();
      const pref = preference ?? "subscription";
      Analytics.aiSurveyCompleted(pref, price, sourcePage);
      await submitAiModelSurvey({
        paymentPreference: pref,
        pricePoint: price,
        sourcePage,
      });
      setStep("thanks");
    },
    [markAsSeen, preference, sourcePage]
  );

  const handleSkipPrice = useCallback(async () => {
    setSubmitted(true);
    markAsSeen();
    const pref = preference ?? "subscription";
    Analytics.aiSurveyCompleted(pref, null, sourcePage);
    await submitAiModelSurvey({
      paymentPreference: pref,
      pricePoint: null,
      sourcePage,
    });
    setStep("thanks");
  }, [markAsSeen, preference, sourcePage]);

  const stepInfo = getStepInfo(step);

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="w-full max-w-md p-0 gap-0 overflow-hidden">
        {/* Header bar: greeting + step counter */}
        {stepInfo && (
          <div className="flex items-center justify-between pl-6 pr-12 pt-5 pb-0">
            <p className="text-sm font-medium">Hey, quick question for you!</p>
            <p className="text-xs text-muted-foreground shrink-0">
              Step {stepInfo.current} of {stepInfo.total}
            </p>
          </div>
        )}

        {/* ── Step 1: Education + Question ── */}
        {step === "question" && (
          <div className="px-6 pb-6 pt-3 space-y-5">
            <DialogHeader className="space-y-3">
              <div className="flex items-center gap-3">
                <div className="p-2.5 rounded-lg bg-amber-500/10">
                  <Sparkles className="size-6 text-amber-500" />
                </div>
                <div>
                  <DialogTitle className="text-lg">
                    About Your AI Model
                  </DialogTitle>
                  
                </div>
              </div>
            </DialogHeader>

            <div className="space-y-3 text-sm">
              <div className="flex items-start gap-3 p-3 rounded-lg bg-amber-500/5 border border-amber-500/20">
                <CircleAlert className="size-5 text-amber-500 shrink-0 mt-0.5" />
                <div className="space-y-1">
                  <p className="font-medium">
                    This app defaults to: Gemini 2.0 Flash
                  </p>
                  <p className="text-muted-foreground text-xs leading-relaxed">
                    <strong>it works</strong>, kind of, but
                    statements often need editing. No amount of prompt tweaking
                    will match the quality of a higher-end model.
                  </p>
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-lg bg-emerald-500/5 border border-emerald-500/20">
                <Zap className="size-5 text-emerald-500 shrink-0 mt-0.5" />
                <div className="space-y-1">
                  <p className="font-medium">Better models, better output</p>
                  <p className="text-muted-foreground text-xs leading-relaxed">
                    Models like <strong>GPT-4o</strong> and{" "}
                    <strong>Claude Sonnet 4</strong> produce higher-quality
                    statements with less editing.
                  </p>
                </div>
              </div>
            </div>

            <Separator />

            <div className="space-y-2.5">
              <p className="text-sm font-medium text-center">
                Would you be willing to pay for higher-quality AI models?
              </p>

              <div className="rounded-lg border bg-muted/30 px-3 py-1.5">
                <p className="text-[11px] text-muted-foreground text-center">
                  This is just a survey — I am not trying to charge you.
                </p>
              </div>

              <Button
                className="w-full"
                onClick={handleWouldPay}
              >
                Yes, I&apos;d pay for better AI
                <ArrowRight className="size-4 ml-1.5" />
              </Button>

              <button
                type="button"
                onClick={handleBringOwnKey}
                className="w-full flex items-center justify-center gap-2 p-2.5 rounded-lg border hover:bg-accent transition-colors text-sm"
              >
                <Key className="size-4 text-emerald-500" />
                I&apos;ll bring my own API key, thanks!
              </button>

              <button
                type="button"
                onClick={handleNotInterested}
                className="w-full p-2 rounded-lg text-sm text-muted-foreground hover:bg-muted/50 transition-colors text-center"
              >
                I&apos;ll stick with the free model
              </button>
            </div>
          </div>
        )}

        {/* ── Step 2: Subscription vs Credits ── */}
        {step === "payment_type" && (
          <div className="px-6 pb-6 pt-3 space-y-5">
            <DialogHeader className="space-y-2">
              <DialogTitle className="text-lg">
                How would you prefer to pay?
              </DialogTitle>
              <DialogDescription className="text-sm leading-relaxed">
                Would you rather subscribe monthly or buy credits when you need
                them?
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-2.5">
              <button
                type="button"
                onClick={() => handlePaymentType("subscription")}
                className="w-full flex items-center gap-3 p-3.5 rounded-lg border hover:bg-accent hover:border-primary/30 transition-colors text-left"
              >
                <div className="p-2 rounded-md bg-blue-500/10 shrink-0">
                  <CalendarCheck className="size-5 text-blue-500" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium">Monthly subscription</p>
                  <p className="text-xs text-muted-foreground">
                    Unlimited premium AI for a monthly fee
                  </p>
                </div>
                <ArrowRight className="size-4 text-muted-foreground shrink-0" />
              </button>

              <button
                type="button"
                onClick={() => handlePaymentType("on_demand")}
                className="w-full flex items-center gap-3 p-3.5 rounded-lg border hover:bg-accent hover:border-primary/30 transition-colors text-left"
              >
                <div className="p-2 rounded-md bg-violet-500/10 shrink-0">
                  <CreditCard className="size-5 text-violet-500" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium">Buy credits on-demand</p>
                  <p className="text-xs text-muted-foreground">
                    Purchase a pack of credits when you need them
                  </p>
                </div>
                <ArrowRight className="size-4 text-muted-foreground shrink-0" />
              </button>
            </div>
          </div>
        )}

        {/* ── Step 3a: Subscription Price ── */}
        {step === "price_subscription" && (
          <div className="px-6 pb-6 pt-3 space-y-5">
            <DialogHeader className="space-y-2">
              <div className="flex items-center gap-2">
                <CalendarCheck className="size-5 text-blue-500" />
                <DialogTitle className="text-lg">
                  Monthly subscription
                </DialogTitle>
              </div>
              <DialogDescription className="text-sm leading-relaxed">
                How much would you pay per month for unlimited premium AI
                statements?
              </DialogDescription>
            </DialogHeader>

            <div className="rounded-lg border bg-muted/30 px-3 py-2">
              <p className="text-[11px] text-muted-foreground text-center">
                Just gauging interest — this won&apos;t charge you anything.
              </p>
            </div>

            <div className="grid grid-cols-5 gap-2">
              {SUBSCRIPTION_PRICES.map((price) => (
                <Button
                  key={price}
                  variant="outline"
                  className={cn(
                    "h-14 flex flex-col gap-0.5 font-semibold text-base",
                    "hover:border-blue-500/50 hover:bg-blue-500/5"
                  )}
                  onClick={() => handlePriceSelect(price)}
                >
                  <span>${price}</span>
                  <span className="text-[10px] font-normal text-muted-foreground">
                    /mo
                  </span>
                </Button>
              ))}
            </div>

            <button
              type="button"
              onClick={handleSkipPrice}
              className="w-full p-2.5 rounded-lg text-sm text-muted-foreground hover:bg-muted/50 transition-colors text-center"
            >
              Not sure / Skip
            </button>
          </div>
        )}

        {/* ── Step 3b: Credit Pack Price ── */}
        {step === "price_credits" && (
          <div className="px-6 pb-6 pt-3 space-y-5">
            <DialogHeader className="space-y-2">
              <div className="flex items-center gap-2">
                <CreditCard className="size-5 text-violet-500" />
                <DialogTitle className="text-lg">Credit packs</DialogTitle>
              </div>
              <DialogDescription className="text-sm leading-relaxed">
                How much would you spend on a pack of credits at a time?
              </DialogDescription>
            </DialogHeader>

            <div className="rounded-lg border bg-muted/30 px-3 py-2">
              <p className="text-[11px] text-muted-foreground text-center">
                Just gauging interest — this won&apos;t charge you anything.
              </p>
            </div>

            <div className="grid grid-cols-5 gap-2">
              {CREDIT_PRICES.map((price) => (
                <Button
                  key={price}
                  variant="outline"
                  className={cn(
                    "h-14 flex flex-col gap-0.5 font-semibold text-base",
                    "hover:border-violet-500/50 hover:bg-violet-500/5"
                  )}
                  onClick={() => handlePriceSelect(price)}
                >
                  <span>${price}</span>
                </Button>
              ))}
            </div>

            <button
              type="button"
              onClick={handleSkipPrice}
              className="w-full p-2.5 rounded-lg text-sm text-muted-foreground hover:bg-muted/50 transition-colors text-center"
            >
              Not sure / Skip
            </button>
          </div>
        )}

        {/* ── Thank You ── */}
        {step === "thanks" && (
          <div className="p-6 space-y-5 text-center">
            <div className="flex justify-center">
              <div className="p-3 rounded-full bg-emerald-500/10">
                <ThumbsUp className="size-7 text-emerald-500" />
              </div>
            </div>
            <div className="space-y-2">
              <DialogTitle className="text-lg">
                Thanks for your feedback!
              </DialogTitle>
              <DialogDescription className="text-sm leading-relaxed max-w-xs mx-auto">
                {preference === "bring_own_key" ? (
                  <>
                    Head to{" "}
                    <a
                      href="/settings/api-keys"
                      className="text-primary hover:underline font-medium"
                    >
                      Settings &gt; API Keys
                    </a>{" "}
                    to add your key and unlock premium models.
                  </>
                ) : preference === "not_interested" ? (
                  <>
                    No problem! You can always add your own API key in
                    Settings if you change your mind.
                  </>
                ) : (
                  <>
                    Your input helps us build a better experience. We&apos;ll
                    keep you posted if we roll out premium AI options.
                  </>
                )}
              </DialogDescription>
            </div>
            <Button
              className="w-full"
              onClick={() => onOpenChange(false)}
            >
              Continue to workspace
            </Button>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

// ── Utility: call after every successful generation ──

/**
 * Tracks a successful AI generation in localStorage and triggers the
 * survey modal once the user has completed their 2nd generation (across
 * any generation page). Safe to call from any component — no prop drilling.
 */
export function trackGenerationForSurvey() {
  // Already completed the survey? Skip entirely.
  if (localStorage.getItem(STORAGE_KEY) === "true") return;

  const current = parseInt(localStorage.getItem(GENERATION_COUNT_KEY) ?? "0", 10);
  const next = current + 1;
  localStorage.setItem(GENERATION_COUNT_KEY, String(next));

  if (next >= GENERATION_THRESHOLD) {
    // Dispatch a custom DOM event that the hook listens for
    window.dispatchEvent(new Event(SURVEY_TRIGGER_EVENT));
  }
}

// ── Hook: manages one-time display logic ──

export function useAiModelSurvey(sourcePage: SourcePage) {
  const [showSurvey, setShowSurvey] = useState(false);

  useEffect(() => {
    // If already seen, never show again
    if (localStorage.getItem(STORAGE_KEY) === "true") return;

    // If the user already hit the threshold before this component mounted
    // (e.g. navigated away then back), show immediately with a short delay
    const count = parseInt(localStorage.getItem(GENERATION_COUNT_KEY) ?? "0", 10);
    if (count >= GENERATION_THRESHOLD) {
      const timer = setTimeout(() => setShowSurvey(true), 500);
      return () => clearTimeout(timer);
    }

    // Otherwise listen for the trigger event from trackGenerationForSurvey()
    const handleTrigger = () => {
      // Small delay so the generation result renders first
      setTimeout(() => setShowSurvey(true), 800);
    };

    window.addEventListener(SURVEY_TRIGGER_EVENT, handleTrigger);
    return () => window.removeEventListener(SURVEY_TRIGGER_EVENT, handleTrigger);
  }, []);

  const onOpenChange = (open: boolean) => {
    if (!open) {
      localStorage.setItem(STORAGE_KEY, "true");
    }
    setShowSurvey(open);
  };

  return {
    showSurvey,
    onOpenChange,
    sourcePage,
  };
}

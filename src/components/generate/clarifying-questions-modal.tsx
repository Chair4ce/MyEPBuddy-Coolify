"use client";

import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import {
  HelpCircle,
  TrendingUp,
  Users,
  Award,
  Hash,
  Maximize2,
  Sparkles,
  RefreshCw,
  X,
  ChevronRight,
  Lightbulb,
  CheckCircle2,
} from "lucide-react";
import {
  useClarifyingQuestionsStore,
  QUESTION_CATEGORY_LABELS,
  type ClarifyingQuestion,
} from "@/stores/clarifying-questions-store";

interface ClarifyingQuestionsModalProps {
  onRegenerate: (clarifyingContext: string) => void;
  isRegenerating?: boolean;
}

// Category icon mapping
const CATEGORY_ICONS: Record<ClarifyingQuestion["category"], React.ElementType> = {
  impact: TrendingUp,
  scope: Maximize2,
  leadership: Users,
  recognition: Award,
  metrics: Hash,
  general: HelpCircle,
};

// Category color mapping
const CATEGORY_COLORS: Record<ClarifyingQuestion["category"], string> = {
  impact: "bg-emerald-500/10 text-emerald-600 border-emerald-500/20",
  scope: "bg-blue-500/10 text-blue-600 border-blue-500/20",
  leadership: "bg-purple-500/10 text-purple-600 border-purple-500/20",
  recognition: "bg-amber-500/10 text-amber-600 border-amber-500/20",
  metrics: "bg-cyan-500/10 text-cyan-600 border-cyan-500/20",
  general: "bg-gray-500/10 text-gray-600 border-gray-500/20",
};

export function ClarifyingQuestionsModal({
  onRegenerate,
  isRegenerating = false,
}: ClarifyingQuestionsModalProps) {
  const {
    isModalOpen,
    closeModal,
    getActiveQuestionSet,
    updateAnswer,
    updateAdditionalContext,
    buildClarifyingContext,
    removeQuestionSet,
  } = useClarifyingQuestionsStore();

  const questionSet = getActiveQuestionSet();
  const [localAnswers, setLocalAnswers] = useState<Record<string, string>>({});
  const [additionalContext, setAdditionalContext] = useState("");

  // Initialize local state from store
  const initializeFromStore = () => {
    if (questionSet) {
      const answers: Record<string, string> = {};
      questionSet.questions.forEach(q => {
        answers[q.id] = q.answer;
      });
      setLocalAnswers(answers);
      setAdditionalContext(questionSet.additionalContext);
    }
  };

  // Handle modal open - initialize state
  const handleOpenChange = (open: boolean) => {
    if (open) {
      initializeFromStore();
    } else {
      closeModal();
    }
  };

  // Handle answer change
  const handleAnswerChange = (questionId: string, value: string) => {
    setLocalAnswers(prev => ({ ...prev, [questionId]: value }));
  };

  // Handle regenerate
  const handleRegenerate = () => {
    if (!questionSet) return;

    // Save answers to store
    Object.entries(localAnswers).forEach(([questionId, answer]) => {
      updateAnswer(questionSet.id, questionId, answer);
    });
    updateAdditionalContext(questionSet.id, additionalContext);

    // Build context and trigger regeneration
    const context = buildClarifyingContext(questionSet.id);
    
    // Add local additional context if different from store
    let finalContext = context;
    if (additionalContext.trim() && !context.includes(additionalContext)) {
      finalContext = `${context}\n\n=== ADDITIONAL CONTEXT FROM USER ===\n${additionalContext}`;
    }

    onRegenerate(finalContext);
    
    // Remove question set after regeneration
    removeQuestionSet(questionSet.id);
    closeModal();
  };

  // Handle dismiss
  const handleDismiss = () => {
    if (questionSet) {
      removeQuestionSet(questionSet.id);
    }
    closeModal();
  };

  // Count answered questions
  const answeredCount = Object.values(localAnswers).filter(a => a.trim().length > 0).length;
  const hasAnyInput = answeredCount > 0 || additionalContext.trim().length > 0;

  if (!questionSet) return null;

  // Group questions by category
  const groupedQuestions = questionSet.questions.reduce((acc, q) => {
    if (!acc[q.category]) acc[q.category] = [];
    acc[q.category].push(q);
    return acc;
  }, {} as Record<ClarifyingQuestion["category"], ClarifyingQuestion[]>);

  return (
    <Dialog open={isModalOpen} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-2xl max-h-[85vh] flex flex-col">
        <DialogHeader>
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-lg bg-amber-500/10">
              <Lightbulb className="h-5 w-5 text-amber-500" />
            </div>
            <div>
              <DialogTitle className="text-lg">Enhance Your Statement</DialogTitle>
              <DialogDescription className="text-sm">
                The AI identified some areas where additional details could strengthen your statement.
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <ScrollArea className="flex-1 -mx-6 px-6">
          <div className="space-y-6 pb-4">
            {/* Introduction */}
            <div className="bg-muted/50 rounded-lg p-4 text-sm">
              <p className="text-muted-foreground">
                <span className="font-medium text-foreground">Answering these questions is optional</span> — 
                but providing more context can help generate more impactful statements with specific metrics, 
                broader scope, and stronger results. You don't need to answer all of them.
              </p>
            </div>

            {/* Questions grouped by category */}
            {Object.entries(groupedQuestions).map(([category, questions]) => {
              const categoryKey = category as ClarifyingQuestion["category"];
              const Icon = CATEGORY_ICONS[categoryKey];
              const colorClass = CATEGORY_COLORS[categoryKey];

              return (
                <div key={category} className="space-y-3">
                  <div className="flex items-center gap-2">
                    <Badge variant="outline" className={cn("gap-1", colorClass)}>
                      <Icon className="h-3 w-3" />
                      {QUESTION_CATEGORY_LABELS[categoryKey]}
                    </Badge>
                  </div>

                  <div className="space-y-4 pl-4 border-l-2 border-muted">
                    {questions.map((question) => (
                      <div key={question.id} className="space-y-2">
                        <div className="flex items-start gap-2">
                          <ChevronRight className="h-4 w-4 mt-0.5 text-muted-foreground flex-shrink-0" />
                          <div className="flex-1">
                            <Label className="text-sm font-medium leading-relaxed">
                              {question.question}
                            </Label>
                            {question.hint && (
                              <p className="text-xs text-muted-foreground mt-1">
                                💡 {question.hint}
                              </p>
                            )}
                          </div>
                        </div>
                        <Textarea
                          placeholder="Your answer (optional)..."
                          value={localAnswers[question.id] || ""}
                          onChange={(e) => handleAnswerChange(question.id, e.target.value)}
                          className="min-h-[80px] resize-none text-sm"
                        />
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}

            <Separator />

            {/* Additional context */}
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <Badge variant="outline" className="gap-1 bg-indigo-500/10 text-indigo-600 border-indigo-500/20">
                  <Sparkles className="h-3 w-3" />
                  Additional Context
                </Badge>
              </div>
              <p className="text-sm text-muted-foreground">
                Have other details not covered by the questions above? Add them here.
              </p>
              <Textarea
                placeholder="Any other context that could help enhance your statement..."
                value={additionalContext}
                onChange={(e) => setAdditionalContext(e.target.value)}
                className="min-h-[100px] resize-none text-sm"
              />
            </div>
          </div>
        </ScrollArea>

        <Separator className="my-2" />

        <DialogFooter className="flex-row justify-between sm:justify-between gap-2">
          <div className="flex items-center gap-2">
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleDismiss}
                  className="text-muted-foreground hover:text-destructive"
                >
                  <X className="h-4 w-4 mr-1" />
                  Dismiss
                </Button>
              </TooltipTrigger>
              <TooltipContent>
                <p>Skip these questions and keep the current statements</p>
              </TooltipContent>
            </Tooltip>
          </div>

          <div className="flex items-center gap-2">
            <span className="text-xs text-muted-foreground">
              {answeredCount} of {questionSet.questions.length} answered
            </span>
            <Button
              onClick={handleRegenerate}
              disabled={!hasAnyInput || isRegenerating}
              className="gap-2"
            >
              {isRegenerating ? (
                <>
                  <RefreshCw className="h-4 w-4 animate-spin" />
                  Regenerating...
                </>
              ) : (
                <>
                  <Sparkles className="h-4 w-4" />
                  Regenerate with Details
                </>
              )}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/**
 * Indicator button/badge to show clarifying questions status
 * Shows different states:
 * - Has questions (amber, pulsing) - click to open modal
 * - No questions (green checkmark) - statement is complete
 */
interface ClarifyingQuestionsIndicatorProps {
  mpaKey: string;
  rateeId: string;
  /** Whether generation has completed for this MPA */
  hasGenerated?: boolean;
  className?: string;
}

export function ClarifyingQuestionsIndicator({
  mpaKey,
  rateeId,
  hasGenerated = false,
  className,
}: ClarifyingQuestionsIndicatorProps) {
  const { getQuestionsForMPA, openModal } = useClarifyingQuestionsStore();

  const questionSet = getQuestionsForMPA(mpaKey, rateeId);
  const questionCount = questionSet?.questions.length || 0;
  const hasQuestions = questionCount > 0;

  // If no questions and hasn't generated, don't show anything
  if (!hasQuestions && !hasGenerated) {
    return null;
  }

  // Show "no questions" badge when generated but no questions
  if (!hasQuestions && hasGenerated) {
    return (
      <Tooltip>
        <TooltipTrigger asChild>
          <Badge 
            variant="outline" 
            className={cn(
              "gap-1 text-xs h-6 px-2 cursor-default",
              "bg-emerald-500/10 text-emerald-600 border-emerald-500/20",
              className
            )}
          >
            <CheckCircle2 className="h-3 w-3" />
            Complete
          </Badge>
        </TooltipTrigger>
        <TooltipContent>
          <p>No clarifying questions needed</p>
          <p className="text-xs text-muted-foreground">
            The AI had enough context to generate your statement
          </p>
        </TooltipContent>
      </Tooltip>
    );
  }

  // Has questions - show indicator button
  const isNew = !questionSet?.hasBeenViewed;

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className={cn(
            "relative h-7 gap-1.5 px-2",
            isNew && "animate-pulse",
            "bg-amber-500/10 hover:bg-amber-500/20 text-amber-600",
            className
          )}
          onClick={() => questionSet && openModal(questionSet.id)}
        >
          <Lightbulb className="h-3.5 w-3.5" />
          <span className="text-xs font-medium">
            {questionCount} question{questionCount > 1 ? "s" : ""}
          </span>
          {isNew && (
            <span className="absolute -top-0.5 -right-0.5 h-2 w-2 rounded-full bg-amber-500 border border-background" />
          )}
        </Button>
      </TooltipTrigger>
      <TooltipContent>
        <p className="font-medium">Enhance your statement</p>
        <p className="text-xs text-muted-foreground">
          Answer {questionCount} question{questionCount > 1 ? "s" : ""} to add more impact
        </p>
      </TooltipContent>
    </Tooltip>
  );
}

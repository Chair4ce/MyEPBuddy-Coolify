"use client";

import { useCallback, useMemo, useState, useRef, useEffect } from "react";
import { useDecorationShellStore, type DecorationSnapshot } from "@/stores/decoration-shell-store";
import { useUserStore } from "@/stores/user-store";
import { createClient } from "@/lib/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { Spinner } from "@/components/ui/spinner";
import { ScrollArea } from "@/components/ui/scroll-area";
import { toast } from "@/components/ui/sonner";
import { cn } from "@/lib/utils";
import { DECORATION_TYPES } from "@/features/decorations/constants";
import {
  Copy,
  Check,
  Sparkles,
  AlertTriangle,
  RotateCcw,
  Camera,
  History,
  X,
  Loader2,
  Maximize2,
  Minimize2,
  RefreshCw,
} from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
  TooltipProvider,
} from "@/components/ui/tooltip";
import type { Accomplishment } from "@/types/database";

interface DecorationCitationEditorProps {
  accomplishments: Accomplishment[];
  className?: string;
}

const MAX_SNAPSHOTS = 10;

export function DecorationCitationEditor({
  accomplishments,
  className,
}: DecorationCitationEditorProps) {
  const supabase = createClient();
  const { profile } = useUserStore();
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const {
    awardType,
    reason,
    dutyTitle,
    unit,
    startDate,
    endDate,
    citationText,
    setCitationText,
    selectedStatementIds,
    getSelectedAccomplishmentTexts,
    selectedRatee,
    selectedModel,
    currentShell,
    isGenerating,
    setIsGenerating,
    isRevising,
    setIsRevising,
    snapshots,
    setSnapshots,
    addSnapshot,
    removeSnapshot,
    showHistory,
    setShowHistory,
  } = useDecorationShellStore();

  const [copied, setCopied] = useState(false);

  // Text selection state for highlight-to-revise
  const [showSelectionPopup, setShowSelectionPopup] = useState(false);
  const [selectedText, setSelectedText] = useState("");
  const [selectionStart, setSelectionStart] = useState(0);
  const [selectionEnd, setSelectionEnd] = useState(0);
  const [revisionResults, setRevisionResults] = useState<string[]>([]);
  const [isRevisingSelection, setIsRevisingSelection] = useState(false);

  // Get decoration config
  const decorationConfig = useMemo(() => {
    return DECORATION_TYPES.find((d) => d.key === awardType);
  }, [awardType]);

  const maxCharacters = decorationConfig?.maxCharacters || 1350;
  const characterCount = citationText.length;
  const characterPercent = Math.min((characterCount / maxCharacters) * 100, 100);
  const isOverLimit = characterCount > maxCharacters;

  // Load snapshots when shell changes
  useEffect(() => {
    async function loadSnapshots() {
      if (!currentShell?.id) return;

      const { data, error } = await supabase
        .from("decoration_shell_snapshots")
        .select("*")
        .eq("shell_id", currentShell.id)
        .order("created_at", { ascending: false });

      if (error) {
        console.error("Error loading snapshots:", error);
        return;
      }

      setSnapshots((data || []) as DecorationSnapshot[]);
    }

    loadSnapshots();
  }, [currentShell?.id, supabase, setSnapshots]);

  // Create a snapshot
  const handleCreateSnapshot = useCallback(async () => {
    if (!currentShell?.id || !profile || !citationText.trim()) return;

    try {
      // If we already have max snapshots, delete the oldest one
      if (snapshots.length >= MAX_SNAPSHOTS) {
        const sortedSnapshots = [...snapshots].sort(
          (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
        );
        const oldestSnapshot = sortedSnapshots[0];

        await supabase
          .from("decoration_shell_snapshots")
          .delete()
          .eq("id", oldestSnapshot.id);

        removeSnapshot(oldestSnapshot.id);
      }

      // Create new snapshot
      const { data, error } = await supabase
        .from("decoration_shell_snapshots")
        .insert({
          shell_id: currentShell.id,
          citation_text: citationText,
          created_by: profile.id,
        } as never)
        .select()
        .single();

      if (error) throw error;

      addSnapshot(data as DecorationSnapshot);
      toast.success("Snapshot saved");
    } catch (error) {
      console.error("Snapshot error:", error);
      toast.error("Failed to save snapshot");
    }
  }, [currentShell?.id, profile, citationText, snapshots, supabase, addSnapshot, removeSnapshot]);

  // Restore from snapshot
  const handleRestoreSnapshot = useCallback(
    (snapshot: DecorationSnapshot) => {
      setCitationText(snapshot.citation_text);
      setShowHistory(false);
      toast.success("Restored from snapshot");
    },
    [setCitationText, setShowHistory]
  );

  // Generate citation using API
  const handleGenerate = useCallback(async () => {
    if (selectedStatementIds.length === 0) {
      toast.error("Please select at least one accomplishment");
      return;
    }

    if (!selectedRatee) {
      toast.error("No ratee selected");
      return;
    }

    setIsGenerating(true);

    try {
      const accomplishmentTexts = getSelectedAccomplishmentTexts(accomplishments);

      const response = await fetch("/api/generate-decoration", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          rateeId: selectedRatee.id,
          rateeRank: selectedRatee.rank || "",
          rateeName: selectedRatee.fullName || "",
          rateeGender: selectedRatee.gender,
          dutyTitle: dutyTitle || "member",
          unit: unit || "the organization",
          startDate: startDate || "",
          endDate: endDate || "",
          awardType,
          reason,
          accomplishments: accomplishmentTexts,
          model: selectedModel,
        }),
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || "Failed to generate citation");
      }

      const data = await response.json();
      setCitationText(data.citation);

      if (!data.metadata.withinLimit) {
        toast.warning(
          `Citation is ${data.metadata.characterCount} characters (${data.metadata.maxCharacters} max). Consider editing to shorten.`
        );
      } else {
        toast.success("Citation generated successfully");
      }
    } catch (error) {
      console.error("Generate error:", error);
      toast.error(error instanceof Error ? error.message : "Failed to generate citation");
    } finally {
      setIsGenerating(false);
    }
  }, [
    selectedStatementIds,
    selectedRatee,
    accomplishments,
    dutyTitle,
    unit,
    startDate,
    endDate,
    awardType,
    reason,
    selectedModel,
    getSelectedAccomplishmentTexts,
    setCitationText,
    setIsGenerating,
  ]);

  // Revise the body section only (preserving opening and closing templates)
  const handleRevise = useCallback(async () => {
    if (!citationText.trim()) return;

    // Parse the citation to extract opening, body, and closing
    const { opening, body, closing } = parseCitationStructure(citationText);
    
    if (!body.trim()) {
      toast.error("No body content found to revise");
      return;
    }
    
    // Calculate remaining characters for the body
    const usedByTemplates = opening.length + closing.length + 2; // +2 for spaces
    const maxBodyChars = maxCharacters - usedByTemplates;

    setIsRevising(true);

    try {
      const response = await fetch("/api/revise-selection", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          fullStatement: body,
          selectedText: body,
          selectionStart: 0,
          selectionEnd: body.length,
          model: selectedModel,
          mode: "general",
          context: `Revise ONLY this accomplishments narrative section of a ${decorationConfig?.name || "decoration"} citation. 
This is the BODY content between the opening and closing sentences.

CRITICAL RULES:
1. DO NOT include any opening sentence (no "distinguished himself/herself" phrases)
2. DO NOT include any closing sentence (no "reflect credit upon" phrases)
3. ONLY revise the accomplishments narrative
4. Start with transition words like "During this period," or "In this important assignment,"
5. Maintain all factual content, metrics, and quantified impacts
6. Improve flow, word choice, and action verbs
7. Keep the same number of accomplishments
8. Maximum ${maxBodyChars} characters for this section`,
          aggressiveness: revisionAggressiveness,
          maxCharacters: maxBodyChars,
          versionCount: 1,
        }),
      });

      if (!response.ok) throw new Error("Revision failed");

      const data = await response.json();
      if (data.revisions?.[0]) {
        // Reconstruct the full citation with the revised body
        const revisedBody = data.revisions[0].trim();
        const newCitation = `${opening} ${revisedBody} ${closing}`.trim();
        setCitationText(newCitation);
        toast.success("Citation body revised");
      }
    } catch (error) {
      console.error("Revise error:", error);
      toast.error("Failed to revise citation");
    } finally {
      setIsRevising(false);
      setShowRevisePanel(false);
    }
  }, [citationText, selectedModel, decorationConfig, revisionAggressiveness, maxCharacters, setCitationText, setIsRevising]);

  // Handle text selection for popup
  const handleTextSelect = useCallback(() => {
    const textarea = textareaRef.current;
    if (!textarea) return;

    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const text = citationText.substring(start, end);

    if (text.trim().length > 0 && start !== end) {
      // Check if selection is within the body section
      const { bodyStart, bodyEnd } = parseCitationStructure(citationText);
      const isInBody = start >= bodyStart && end <= bodyEnd;
      
      if (!isInBody) {
        // Selection includes opening or closing - warn user
        toast.warning("Opening and closing sentences are template-based. Select text from the body section to revise.");
        setShowSelectionPopup(false);
        return;
      }
      
      setSelectedText(text);
      setSelectionStart(start);
      setSelectionEnd(end);
      setShowSelectionPopup(true);
      setRevisionResults([]);
    } else {
      setShowSelectionPopup(false);
    }
  }, [citationText]);

  // Close selection popup
  const closeSelectionPopup = useCallback(() => {
    setShowSelectionPopup(false);
    setSelectedText("");
    setRevisionResults([]);
  }, []);

  // Revise selected text
  const handleReviseSelection = useCallback(
    async (mode: "expand" | "compress" | "general") => {
      if (!selectedText.trim()) return;

      setIsRevisingSelection(true);
      setRevisionResults([]);

      try {
        const response = await fetch("/api/revise-selection", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            fullStatement: citationText,
            selectedText,
            selectionStart,
            selectionEnd,
            model: selectedModel,
            mode,
          }),
        });

        if (!response.ok) throw new Error("Revision failed");

        const data = await response.json();
        setRevisionResults(data.revisions || []);
      } catch (error) {
        console.error("Revision error:", error);
        toast.error("Failed to revise selection");
      } finally {
        setIsRevisingSelection(false);
      }
    },
    [selectedText, citationText, selectionStart, selectionEnd, selectedModel]
  );

  // Apply a revision to the text
  const applyRevision = useCallback(
    (revision: string) => {
      const newText =
        citationText.substring(0, selectionStart) + revision + citationText.substring(selectionEnd);
      setCitationText(newText);
      closeSelectionPopup();
      toast.success("Applied revision");
    },
    [citationText, selectionStart, selectionEnd, setCitationText, closeSelectionPopup]
  );

  // Copy to clipboard
  const handleCopy = useCallback(async () => {
    if (!citationText) return;
    await navigator.clipboard.writeText(citationText);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
    toast.success("Citation copied to clipboard");
  }, [citationText]);

  // Clear citation
  const handleClear = useCallback(() => {
    setCitationText("");
  }, [setCitationText]);

  // Get aggressiveness label
  const getAggressivenessLabel = (value: number) => {
    if (value <= 20) return "Minimal";
    if (value <= 40) return "Conservative";
    if (value <= 60) return "Moderate";
    if (value <= 80) return "Aggressive";
    return "Maximum";
  };

  const getAggressivenessDescription = (value: number) => {
    if (value <= 20) return "Only fix obvious issues, preserve your voice";
    if (value <= 40) return "Light touch, replace only weak words";
    if (value <= 60) return "Balanced refresh with new phrasing";
    if (value <= 80) return "Substantial rewrite, keep only metrics";
    return "Complete rewrite, preserve only data";
  };

  return (
    <TooltipProvider>
      <Card className={className}>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="text-base">Citation</CardTitle>
              <CardDescription className="text-xs mt-0.5">
                {decorationConfig?.name || "Decoration"} - {maxCharacters} character limit
              </CardDescription>
            </div>
            <div className="flex items-center gap-2">
              {/* Snapshot button */}
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    variant="outline"
                    size="icon"
                    onClick={handleCreateSnapshot}
                    disabled={!citationText.trim() || isGenerating}
                    className="h-8 w-8"
                  >
                    <Camera className="size-4" />
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Save snapshot</TooltipContent>
              </Tooltip>

              {/* History button */}
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    variant={showHistory ? "default" : "outline"}
                    size="icon"
                    onClick={() => setShowHistory(!showHistory)}
                    className="h-8 w-8"
                  >
                    <History className="size-4" />
                    {snapshots.length > 0 && (
                      <Badge
                        variant="secondary"
                        className="absolute -top-1 -right-1 h-4 w-4 p-0 text-[10px] flex items-center justify-center"
                      >
                        {snapshots.length}
                      </Badge>
                    )}
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Snapshot history</TooltipContent>
              </Tooltip>

              {/* Generate button */}
              <Button
                variant="outline"
                size="sm"
                onClick={handleGenerate}
                disabled={isGenerating || selectedStatementIds.length === 0}
                className="h-8"
              >
                {isGenerating ? (
                  <>
                    <Spinner size="sm" className="mr-1.5" />
                    Generating...
                  </>
                ) : (
                  <>
                    <Sparkles className="size-4 mr-1.5" />
                    Generate
                  </>
                )}
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-3">
          {/* Character count bar */}
          <div className="space-y-1.5">
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground">Characters</span>
              <span
                className={cn(
                  "font-mono",
                  isOverLimit ? "text-destructive font-semibold" : "text-muted-foreground"
                )}
              >
                {characterCount} / {maxCharacters}
              </span>
            </div>
            <Progress
              value={characterPercent}
              className={cn("h-1.5", isOverLimit && "[&>div]:bg-destructive")}
            />
            {isOverLimit && (
              <div className="flex items-center gap-1.5 text-xs text-destructive">
                <AlertTriangle className="size-3" />
                <span>{characterCount - maxCharacters} characters over limit</span>
              </div>
            )}
          </div>

          {/* Snapshot History Panel */}
          {showHistory && (
            <div className="rounded-lg border bg-card shadow-sm animate-in fade-in-0 duration-200">
              <div className="p-3 border-b flex items-center justify-between">
                <div>
                  <h4 className="font-medium text-sm">Snapshot History</h4>
                  <p className="text-xs text-muted-foreground">
                    {snapshots.length} snapshot{snapshots.length !== 1 && "s"} (max {MAX_SNAPSHOTS})
                  </p>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => setShowHistory(false)}
                  className="h-7 w-7"
                >
                  <X className="size-4" />
                </Button>
              </div>
              <ScrollArea className="max-h-48">
                {snapshots.length === 0 ? (
                  <p className="p-3 text-sm text-muted-foreground text-center">
                    No snapshots yet. Click the camera icon to save your current citation.
                  </p>
                ) : (
                  snapshots.map((snap) => (
                    <div key={snap.id} className="p-3 border-b last:border-0 hover:bg-muted/30">
                      <div className="flex items-start justify-between gap-2 mb-1">
                        <p className="text-xs text-muted-foreground">
                          {new Date(snap.created_at).toLocaleString()}
                        </p>
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => handleRestoreSnapshot(snap)}
                          className="h-6 px-2 text-xs"
                        >
                          <RotateCcw className="size-3 mr-1" />
                          Restore
                        </Button>
                      </div>
                      <p className="text-xs text-muted-foreground line-clamp-2">
                        {snap.citation_text.slice(0, 150)}...
                      </p>
                    </div>
                  ))
                )}
              </ScrollArea>
            </div>
          )}

          {/* Citation textarea */}
          <div className="relative">
            <Textarea
              ref={textareaRef}
              value={citationText}
              onChange={(e) => setCitationText(e.target.value)}
              onMouseUp={handleTextSelect}
              onKeyUp={handleTextSelect}
              onBlur={() => {
                // Delay to allow click on popup
                setTimeout(() => {
                  if (!document.activeElement?.closest(".selection-popup")) {
                    closeSelectionPopup();
                  }
                }, 200);
              }}
              placeholder={
                selectedStatementIds.length === 0
                  ? "Select accomplishments above, then click Generate to create a citation..."
                  : "Click Generate to create a citation based on selected accomplishments..."
              }
              className={cn(
                "min-h-[280px] font-mono text-sm resize-none",
                "focus-visible:ring-1 focus-visible:ring-primary",
                isOverLimit && "border-destructive focus-visible:ring-destructive"
              )}
              aria-label="Citation text editor"
            />
            {(isGenerating || isRevising) && (
              <div className="absolute inset-0 bg-background/80 flex items-center justify-center rounded-md">
                <div className="flex flex-col items-center gap-2">
                  <Spinner size="lg" />
                  <span className="text-sm text-muted-foreground">
                    {isGenerating ? "Generating citation..." : "Revising citation..."}
                  </span>
                </div>
              </div>
            )}
          </div>

          {/* Text Selection Popup */}
          {showSelectionPopup && (
            <div className="selection-popup p-3 rounded-lg bg-card border shadow-lg animate-in fade-in-0 zoom-in-95 duration-200">
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <p className="text-xs text-muted-foreground">
                    Selected:{" "}
                    <span className="font-medium text-foreground">
                      &ldquo;{selectedText.slice(0, 30)}
                      {selectedText.length > 30 ? "..." : ""}&rdquo;
                    </span>
                    <span className="ml-1">({selectedText.length} chars)</span>
                  </p>
                  <button
                    onClick={closeSelectionPopup}
                    className="text-muted-foreground hover:text-foreground transition-colors"
                  >
                    <X className="size-4" />
                  </button>
                </div>

                {/* Revision mode buttons */}
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => handleReviseSelection("expand")}
                    disabled={isRevisingSelection}
                    className="flex-1 h-8 px-3 rounded-md text-xs border border-input bg-background hover:bg-accent hover:text-accent-foreground inline-flex items-center justify-center gap-1.5 transition-colors disabled:opacity-50"
                  >
                    {isRevisingSelection ? (
                      <Loader2 className="size-3 animate-spin" />
                    ) : (
                      <Maximize2 className="size-3" />
                    )}
                    Expand
                  </button>
                  <button
                    onClick={() => handleReviseSelection("compress")}
                    disabled={isRevisingSelection}
                    className="flex-1 h-8 px-3 rounded-md text-xs border border-input bg-background hover:bg-accent hover:text-accent-foreground inline-flex items-center justify-center gap-1.5 transition-colors disabled:opacity-50"
                  >
                    {isRevisingSelection ? (
                      <Loader2 className="size-3 animate-spin" />
                    ) : (
                      <Minimize2 className="size-3" />
                    )}
                    Compress
                  </button>
                  <button
                    onClick={() => handleReviseSelection("general")}
                    disabled={isRevisingSelection}
                    className="flex-1 h-8 px-3 rounded-md text-xs border border-input bg-background hover:bg-accent hover:text-accent-foreground inline-flex items-center justify-center gap-1.5 transition-colors disabled:opacity-50"
                  >
                    {isRevisingSelection ? (
                      <Loader2 className="size-3 animate-spin" />
                    ) : (
                      <RefreshCw className="size-3" />
                    )}
                    Rephrase
                  </button>
                </div>

                {/* Revision results */}
                {revisionResults.length > 0 && (
                  <div className="space-y-2 pt-2 border-t">
                    <p className="text-xs text-muted-foreground font-medium">Alternatives:</p>
                    {revisionResults.map((revision, index) => (
                      <button
                        key={index}
                        onClick={() => applyRevision(revision)}
                        className="w-full text-left p-2 rounded-md text-sm border hover:bg-accent hover:border-primary/50 transition-colors"
                      >
                        <p className="whitespace-pre-wrap">{revision}</p>
                        <span className="text-[10px] text-muted-foreground mt-1">
                          {revision.length} chars (
                          {revision.length > selectedText.length ? "+" : ""}
                          {revision.length - selectedText.length})
                        </span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* TODO: Future work - Revise Panel (needs proper citation structure parsing)
          {citationText.trim() && (
            <Collapsible open={showRevisePanel} onOpenChange={setShowRevisePanel}>
              ...revise panel content...
            </Collapsible>
          )}
          */}

          {/* Action buttons */}
          <div className="flex items-center justify-between pt-2 border-t">
            <Button
              variant="ghost"
              size="sm"
              onClick={handleClear}
              disabled={!citationText || isGenerating}
              className="h-8 text-xs"
            >
              <RotateCcw className="size-3 mr-1.5" />
              Clear
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={handleCopy}
              disabled={!citationText || isGenerating}
              className="h-8"
            >
              {copied ? (
                <>
                  <Check className="size-4 mr-1.5 text-green-500" />
                  Copied!
                </>
              ) : (
                <>
                  <Copy className="size-4 mr-1.5" />
                  Copy to Clipboard
                </>
              )}
            </Button>
          </div>

          {/* Info badges */}
          <div className="flex flex-wrap gap-2 pt-2 border-t">
            <Badge variant="outline" className="text-xs">
              {decorationConfig?.abbreviation || awardType.toUpperCase()}
            </Badge>
            <Badge variant="outline" className="text-xs">
              {decorationConfig?.afForm || "AF Form"}
            </Badge>
            <Badge variant="secondary" className="text-xs">
              Courier New 11pt
            </Badge>
          </div>
        </CardContent>
      </Card>
    </TooltipProvider>
  );
}

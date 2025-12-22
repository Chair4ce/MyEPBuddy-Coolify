"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { 
  Crown, 
  Check, 
  Copy, 
  Wand2, 
  Save, 
  RotateCcw,
  Loader2,
  Plus,
  X,
  Sparkles,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import { STANDARD_MGAS } from "@/lib/constants";

interface Accomplishment {
  id: string;
  action_verb: string;
  details: string;
  impact: string;
  metrics?: string | null;
}

interface AccomplishmentsByMPA {
  mpa: string;
  accomplishments: Accomplishment[];
}

interface StatementSelectionWorkspaceProps {
  accomplishmentsByMPA: AccomplishmentsByMPA[];
  maxChars: number;
  maxHlrChars: number;
  rateeInfo: { id: string; rank: string | null; full_name: string | null; afsc?: string | null; isManagedMember?: boolean } | null;
  cycleYear: number;
  model: string;
  onSaveStatement: (mpa: string, statement: string) => Promise<void>;
}

type WorkspaceStage = "assign" | "generating" | "finalize";

// State for each MPA's workspace
interface MPAWorkspaceState {
  stage: WorkspaceStage;
  // Stage 1: Assignment - which accomplishments go to which slot
  slot1Indices: number[]; // Indices of accomplishments assigned to Statement 1
  slot2Indices: number[]; // Indices of accomplishments assigned to Statement 2
  // Stage 2-3: Generated statements after LLM processing
  generatedStatement1: string;
  generatedStatement2: string;
}

export function StatementSelectionWorkspace({
  accomplishmentsByMPA,
  maxChars,
  maxHlrChars,
  rateeInfo,
  cycleYear,
  model,
  onSaveStatement,
}: StatementSelectionWorkspaceProps) {
  const [copiedIndex, setCopiedIndex] = useState<string | null>(null);
  const [workspaceStates, setWorkspaceStates] = useState<Record<string, MPAWorkspaceState>>({});
  const [savingMPA, setSavingMPA] = useState<string | null>(null);
  const [revisingKey, setRevisingKey] = useState<string | null>(null);

  const getMaxChars = (mpaKey: string) => mpaKey === "hlr_assessment" ? maxHlrChars : maxChars;

  const copyToClipboard = (text: string, key: string) => {
    navigator.clipboard.writeText(text);
    setCopiedIndex(key);
    toast.success("Copied to clipboard");
    setTimeout(() => setCopiedIndex(null), 2000);
  };

  // Initialize workspace state for an MPA
  const initWorkspace = (mpa: string) => {
    setWorkspaceStates(prev => ({
      ...prev,
      [mpa]: {
        stage: "assign",
        slot1Indices: [],
        slot2Indices: [],
        generatedStatement1: "",
        generatedStatement2: "",
      }
    }));
  };

  // Toggle accomplishment assignment to a slot
  const toggleSlotAssignment = (mpa: string, idx: number, slot: 1 | 2) => {
    setWorkspaceStates(prev => {
      const state = prev[mpa];
      if (!state) return prev;
      
      const otherSlot = slot === 1 ? "slot2Indices" : "slot1Indices";
      const thisSlot = slot === 1 ? "slot1Indices" : "slot2Indices";
      
      // Remove from other slot if present
      const newOtherSlot = state[otherSlot].filter(i => i !== idx);
      
      // Toggle in this slot
      const isInSlot = state[thisSlot].includes(idx);
      const newThisSlot = isInSlot 
        ? state[thisSlot].filter(i => i !== idx)
        : [...state[thisSlot], idx];
      
      return {
        ...prev,
        [mpa]: {
          ...state,
          [otherSlot]: newOtherSlot,
          [thisSlot]: newThisSlot,
        }
      };
    });
  };

  // Remove from a slot
  const removeFromSlot = (mpa: string, idx: number, slot: 1 | 2) => {
    setWorkspaceStates(prev => {
      const state = prev[mpa];
      if (!state) return prev;
      const slotKey = slot === 1 ? "slot1Indices" : "slot2Indices";
      return {
        ...prev,
        [mpa]: {
          ...state,
          [slotKey]: state[slotKey].filter(i => i !== idx),
        }
      };
    });
  };

  // Generate statements from assigned accomplishments
  const generateStatements = async (mpa: string, accomplishments: Accomplishment[]) => {
    const state = workspaceStates[mpa];
    if (!state) return;
    
    const mpaMaxChars = getMaxChars(mpa);
    const hasSlot1 = state.slot1Indices.length > 0;
    const hasSlot2 = state.slot2Indices.length > 0;
    
    if (!hasSlot1 && !hasSlot2) {
      toast.error("Please assign at least one accomplishment to a slot");
      return;
    }
    
    setWorkspaceStates(prev => ({
      ...prev,
      [mpa]: { ...prev[mpa], stage: "generating" }
    }));
    
    try {
      // Get accomplishments for each slot
      const slot1Accs = state.slot1Indices.map(i => accomplishments[i]);
      const slot2Accs = state.slot2Indices.map(i => accomplishments[i]);
      
      // Calculate character targets
      const bothSlots = hasSlot1 && hasSlot2;
      const charPerSlot = bothSlots ? Math.floor((mpaMaxChars - 2) / 2) : mpaMaxChars; // -2 for ". " separator
      
      let generated1 = "";
      let generated2 = "";
      
      // Generate for slot 1
      if (hasSlot1) {
        const response = await fetch("/api/generate-slot-statement", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            accomplishments: slot1Accs.map(a => ({
              action_verb: a.action_verb,
              details: a.details,
              impact: a.impact,
              metrics: a.metrics,
            })),
            targetChars: charPerSlot,
            model,
            mpa,
            rateeRank: rateeInfo?.rank || "SSgt",
            rateeAfsc: rateeInfo?.afsc || "UNKNOWN",
          }),
        });
        
        if (response.ok) {
          const data = await response.json();
          generated1 = data.statement || "";
        }
      }
      
      // Generate for slot 2
      if (hasSlot2) {
        const response = await fetch("/api/generate-slot-statement", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            accomplishments: slot2Accs.map(a => ({
              action_verb: a.action_verb,
              details: a.details,
              impact: a.impact,
              metrics: a.metrics,
            })),
            targetChars: charPerSlot,
            model,
            mpa,
            rateeRank: rateeInfo?.rank || "SSgt",
            rateeAfsc: rateeInfo?.afsc || "UNKNOWN",
          }),
        });
        
        if (response.ok) {
          const data = await response.json();
          generated2 = data.statement || "";
        }
      }
      
      setWorkspaceStates(prev => ({
        ...prev,
        [mpa]: {
          ...prev[mpa],
          stage: "finalize",
          generatedStatement1: generated1,
          generatedStatement2: generated2,
        }
      }));
      
    } catch (error) {
      console.error("Generate error:", error);
      toast.error("Failed to generate statements");
      setWorkspaceStates(prev => ({
        ...prev,
        [mpa]: { ...prev[mpa], stage: "assign" }
      }));
    }
  };

  // Update generated statement
  const updateStatement = (mpa: string, which: 1 | 2, value: string) => {
    setWorkspaceStates(prev => ({
      ...prev,
      [mpa]: {
        ...prev[mpa],
        [which === 1 ? "generatedStatement1" : "generatedStatement2"]: value,
      }
    }));
  };

  // Revise a statement with AI
  const reviseWithAI = async (mpa: string, which: 1 | 2) => {
    const state = workspaceStates[mpa];
    if (!state) return;
    
    const statement = which === 1 ? state.generatedStatement1 : state.generatedStatement2;
    if (!statement.trim()) return;
    
    setRevisingKey(`${mpa}-${which}`);
    
    try {
      const response = await fetch("/api/revise-selection", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          fullStatement: statement,
          selectedText: statement,
          selectionStart: 0,
          selectionEnd: statement.length,
          model,
          mode: "general",
          context: "Rewrite this EPB statement with fresh verbs and improved flow while maintaining the same meaning and metrics.",
        }),
      });
      
      if (!response.ok) throw new Error("Revision failed");
      
      const data = await response.json();
      if (data.revisions && data.revisions.length > 0) {
        updateStatement(mpa, which, data.revisions[0]);
        toast.success("Statement revised");
      }
    } catch (error) {
      console.error("Revision error:", error);
      toast.error("Failed to revise statement");
    } finally {
      setRevisingKey(null);
    }
  };

  // Back to assignment
  const backToAssign = (mpa: string) => {
    setWorkspaceStates(prev => ({
      ...prev,
      [mpa]: { 
        ...prev[mpa], 
        stage: "assign",
        generatedStatement1: "",
        generatedStatement2: "",
      }
    }));
  };

  // Save to library
  const saveToLibrary = async (mpa: string) => {
    const state = workspaceStates[mpa];
    if (!state) return;
    
    const mpaMaxChars = getMaxChars(mpa);
    const combined = state.generatedStatement2 
      ? `${state.generatedStatement1}. ${state.generatedStatement2}`
      : state.generatedStatement1;
    
    if (combined.length > mpaMaxChars) {
      toast.error(`Statement exceeds ${mpaMaxChars} character limit`);
      return;
    }
    
    setSavingMPA(mpa);
    try {
      await onSaveStatement(mpa, combined);
      toast.success("Saved to library");
      // Reset workspace
      setWorkspaceStates(prev => {
        const newStates = { ...prev };
        delete newStates[mpa];
        return newStates;
      });
    } catch (error) {
      console.error("Save error:", error);
      toast.error("Failed to save");
    } finally {
      setSavingMPA(null);
    }
  };

  if (accomplishmentsByMPA.length === 0) return null;

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-2">
          <div className="min-w-0">
            <CardTitle>Statement Workspace</CardTitle>
            <CardDescription>
              Assign accomplishments to Statement 1 or 2, then generate and edit
            </CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent className="min-w-0">
        <Tabs defaultValue={accomplishmentsByMPA[0]?.mpa}>
          <TabsList className="flex flex-wrap h-auto gap-1 sm:gap-2 w-full justify-start p-1">
            {accomplishmentsByMPA.map(({ mpa }) => {
              const isHLR = mpa === "hlr_assessment";
              const label = STANDARD_MGAS.find((m) => m.key === mpa)?.label || mpa;
              const shortLabel = label
                .replace("Executing the Mission", "Mission")
                .replace("Leading People", "Leading")
                .replace("Managing Resources", "Resources")
                .replace("Improving the Unit", "Improving");
              const state = workspaceStates[mpa];
              
              return (
                <TabsTrigger 
                  key={mpa} 
                  value={mpa}
                  className={cn(
                    "text-xs sm:text-sm px-2 sm:px-3",
                    isHLR && "bg-amber-100 dark:bg-amber-900/30 text-amber-800 dark:text-amber-200",
                    state?.stage === "finalize" && "ring-2 ring-green-500"
                  )}
                >
                  {isHLR && <Crown className="size-3 sm:size-4 mr-1" />}
                  <span className="sm:hidden">{shortLabel}</span>
                  <span className="hidden sm:inline">{label}</span>
                  {state?.stage === "finalize" && (
                    <Badge variant="secondary" className="ml-1 text-[10px] px-1 bg-green-100 dark:bg-green-900/30">
                      Ready
                    </Badge>
                  )}
                </TabsTrigger>
              );
            })}
          </TabsList>

          {accomplishmentsByMPA.map(({ mpa, accomplishments }) => {
            const isHLR = mpa === "hlr_assessment";
            const mpaMaxChars = getMaxChars(mpa);
            const state = workspaceStates[mpa];
            const isInitialized = !!state;
            
            return (
              <TabsContent key={mpa} value={mpa} className="space-y-4 mt-4">
                {!isInitialized ? (
                  // Not started - show overview and start button
                  <div className="space-y-4">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        {isHLR && <Crown className="size-5 text-amber-600" />}
                        <h3 className="font-medium">
                          {STANDARD_MGAS.find((m) => m.key === mpa)?.label || mpa}
                        </h3>
                        <Badge variant="secondary">{accomplishments.length} entries</Badge>
                      </div>
                      <Button onClick={() => initWorkspace(mpa)}>
                        <Sparkles className="size-4 mr-2" />
                        Start Building
                      </Button>
                    </div>
                    
                    <p className="text-sm text-muted-foreground">
                      You have {accomplishments.length} performance entries for this MPA. Click &quot;Start Building&quot; to assign them to statements.
                    </p>
                    
                    <div className="space-y-2">
                      {accomplishments.slice(0, 3).map((acc, idx) => (
                        <div key={idx} className="p-3 rounded-lg border bg-muted/30">
                          <div className="flex items-center gap-2 mb-1">
                            <Badge variant="outline" className="text-xs">{acc.action_verb}</Badge>
                          </div>
                          <p className="text-sm line-clamp-2">{acc.details}</p>
                        </div>
                      ))}
                      {accomplishments.length > 3 && (
                        <p className="text-xs text-muted-foreground">
                          +{accomplishments.length - 3} more entries
                        </p>
                      )}
                    </div>
                  </div>
                ) : state.stage === "assign" ? (
                  // STAGE 1: Assign accomplishments to slots
                  <div className="space-y-4">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <h3 className="font-medium">Assign Accomplishments</h3>
                      </div>
                      <Button 
                        onClick={() => generateStatements(mpa, accomplishments)}
                        disabled={state.slot1Indices.length === 0 && state.slot2Indices.length === 0}
                      >
                        <Sparkles className="size-4 mr-2" />
                        Generate Statements
                      </Button>
                    </div>
                    
                    <p className="text-sm text-muted-foreground">
                      Assign accomplishments to Statement 1 and/or Statement 2. Multiple accomplishments in the same slot will be combined by AI.
                    </p>
                    
                    <div className="grid gap-4 lg:grid-cols-2">
                      {/* Statement 1 Slot */}
                      <div className="p-4 rounded-lg border-2 border-dashed border-blue-300 dark:border-blue-700 bg-blue-50/50 dark:bg-blue-900/10">
                        <div className="flex items-center gap-2 mb-3">
                          <Badge className="bg-blue-500">Statement 1</Badge>
                          <span className="text-xs text-muted-foreground">
                            ~{Math.floor(mpaMaxChars / 2)} chars
                          </span>
                        </div>
                        {state.slot1Indices.length === 0 ? (
                          <p className="text-sm text-muted-foreground italic">
                            Click &quot;+1&quot; on entries below to add here
                          </p>
                        ) : (
                          <div className="space-y-2">
                            {state.slot1Indices.map(idx => {
                              const acc = accomplishments[idx];
                              return (
                                <div key={idx} className="p-2 rounded bg-blue-100 dark:bg-blue-900/30 flex items-start gap-2">
                                  <div className="flex-1 min-w-0">
                                    <Badge variant="outline" className="text-[10px] mb-1">{acc.action_verb}</Badge>
                                    <p className="text-xs line-clamp-2">{acc.details}</p>
                                  </div>
                                  <Button
                                    variant="ghost"
                                    size="icon"
                                    className="size-6 shrink-0"
                                    onClick={() => removeFromSlot(mpa, idx, 1)}
                                  >
                                    <X className="size-3" />
                                  </Button>
                                </div>
                              );
                            })}
                          </div>
                        )}
                      </div>
                      
                      {/* Statement 2 Slot */}
                      <div className="p-4 rounded-lg border-2 border-dashed border-purple-300 dark:border-purple-700 bg-purple-50/50 dark:bg-purple-900/10">
                        <div className="flex items-center gap-2 mb-3">
                          <Badge className="bg-purple-500">Statement 2</Badge>
                          <span className="text-xs text-muted-foreground">
                            ~{Math.floor(mpaMaxChars / 2)} chars
                          </span>
                        </div>
                        {state.slot2Indices.length === 0 ? (
                          <p className="text-sm text-muted-foreground italic">
                            Click &quot;+2&quot; on entries below to add here
                          </p>
                        ) : (
                          <div className="space-y-2">
                            {state.slot2Indices.map(idx => {
                              const acc = accomplishments[idx];
                              return (
                                <div key={idx} className="p-2 rounded bg-purple-100 dark:bg-purple-900/30 flex items-start gap-2">
                                  <div className="flex-1 min-w-0">
                                    <Badge variant="outline" className="text-[10px] mb-1">{acc.action_verb}</Badge>
                                    <p className="text-xs line-clamp-2">{acc.details}</p>
                                  </div>
                                  <Button
                                    variant="ghost"
                                    size="icon"
                                    className="size-6 shrink-0"
                                    onClick={() => removeFromSlot(mpa, idx, 2)}
                                  >
                                    <X className="size-3" />
                                  </Button>
                                </div>
                              );
                            })}
                          </div>
                        )}
                      </div>
                    </div>
                    
                    {/* Available accomplishments to assign */}
                    <div className="space-y-2">
                      <h4 className="text-sm font-medium">Your Accomplishments</h4>
                      {accomplishments.map((acc, idx) => {
                        const inSlot1 = state.slot1Indices.includes(idx);
                        const inSlot2 = state.slot2Indices.includes(idx);
                        const isAssigned = inSlot1 || inSlot2;
                        
                        return (
                          <div 
                            key={idx} 
                            className={cn(
                              "p-3 rounded-lg border transition-colors",
                              isAssigned ? "bg-muted/50 opacity-70" : "bg-card hover:bg-muted/30"
                            )}
                          >
                            <div className="flex items-start gap-3">
                              <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2 mb-1 flex-wrap">
                                  <Badge variant="outline" className="text-xs">{acc.action_verb}</Badge>
                                  {acc.metrics && (
                                    <span className="text-xs text-muted-foreground">{acc.metrics}</span>
                                  )}
                                  {inSlot1 && <Badge className="bg-blue-500 text-xs">Slot 1</Badge>}
                                  {inSlot2 && <Badge className="bg-purple-500 text-xs">Slot 2</Badge>}
                                </div>
                                <p className="text-sm">{acc.details}</p>
                                {acc.impact && (
                                  <p className="text-xs text-muted-foreground mt-1">Impact: {acc.impact}</p>
                                )}
                              </div>
                              <div className="flex gap-1 shrink-0">
                                <Button
                                  variant={inSlot1 ? "default" : "outline"}
                                  size="sm"
                                  className={cn("h-8", inSlot1 && "bg-blue-500 hover:bg-blue-600")}
                                  onClick={() => toggleSlotAssignment(mpa, idx, 1)}
                                >
                                  <Plus className="size-3 mr-1" />
                                  1
                                </Button>
                                <Button
                                  variant={inSlot2 ? "default" : "outline"}
                                  size="sm"
                                  className={cn("h-8", inSlot2 && "bg-purple-500 hover:bg-purple-600")}
                                  onClick={() => toggleSlotAssignment(mpa, idx, 2)}
                                >
                                  <Plus className="size-3 mr-1" />
                                  2
                                </Button>
                              </div>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                ) : state.stage === "generating" ? (
                  // Generating (loading state)
                  <div className="flex flex-col items-center justify-center py-12 space-y-4">
                    <Loader2 className="size-8 animate-spin text-primary" />
                    <p className="text-sm text-muted-foreground">
                      AI is generating your statements...
                    </p>
                  </div>
                ) : (
                  // STAGE 2: Final workspace
                  <div className="space-y-4">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <h3 className="font-medium">Final Edits</h3>
                      </div>
                      <Button variant="ghost" size="sm" onClick={() => backToAssign(mpa)}>
                        <RotateCcw className="size-4 mr-2" />
                        Start Over
                      </Button>
                    </div>
                    
                    {/* Combined character count */}
                    {(() => {
                      const total = state.generatedStatement2
                        ? state.generatedStatement1.length + 2 + state.generatedStatement2.length
                        : state.generatedStatement1.length;
                      const isOver = total > mpaMaxChars;
                      return (
                        <div className={cn(
                          "p-3 rounded-lg border flex items-center justify-between",
                          isOver ? "bg-destructive/10 border-destructive/30" : "bg-muted/50"
                        )}>
                          <span className="text-sm font-medium">
                            Total: {total}/{mpaMaxChars}
                          </span>
                          <Progress
                            value={Math.min((total / mpaMaxChars) * 100, 100)}
                            className={cn("w-32 h-2", isOver && "*:bg-destructive")}
                          />
                        </div>
                      );
                    })()}
                    
                    <div className="space-y-4">
                      {/* Statement 1 */}
                      {state.generatedStatement1 && (
                        <div className="space-y-2">
                          <div className="flex items-center justify-between">
                            <label className="text-sm font-medium flex items-center gap-2">
                              <Badge className="bg-blue-500">Statement 1</Badge>
                              <span className="text-xs font-mono text-muted-foreground">
                                {state.generatedStatement1.length} chars
                              </span>
                            </label>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => reviseWithAI(mpa, 1)}
                              disabled={revisingKey === `${mpa}-1`}
                            >
                              {revisingKey === `${mpa}-1` ? (
                                <Loader2 className="size-4 mr-2 animate-spin" />
                              ) : (
                                <Wand2 className="size-4 mr-2" />
                              )}
                              Revise
                            </Button>
                          </div>
                          <Textarea
                            value={state.generatedStatement1}
                            onChange={(e) => updateStatement(mpa, 1, e.target.value)}
                            rows={4}
                            className="text-sm resize-none"
                          />
                        </div>
                      )}
                      
                      {/* Statement 2 */}
                      {state.generatedStatement2 && (
                        <div className="space-y-2">
                          <div className="flex items-center justify-between">
                            <label className="text-sm font-medium flex items-center gap-2">
                              <Badge className="bg-purple-500">Statement 2</Badge>
                              <span className="text-xs font-mono text-muted-foreground">
                                {state.generatedStatement2.length} chars
                              </span>
                            </label>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => reviseWithAI(mpa, 2)}
                              disabled={revisingKey === `${mpa}-2`}
                            >
                              {revisingKey === `${mpa}-2` ? (
                                <Loader2 className="size-4 mr-2 animate-spin" />
                              ) : (
                                <Wand2 className="size-4 mr-2" />
                              )}
                              Revise
                            </Button>
                          </div>
                          <Textarea
                            value={state.generatedStatement2}
                            onChange={(e) => updateStatement(mpa, 2, e.target.value)}
                            rows={4}
                            className="text-sm resize-none"
                          />
                        </div>
                      )}
                    </div>
                    
                    {/* Preview */}
                    <div className="p-4 rounded-lg border bg-muted/30">
                      <p className="text-xs text-muted-foreground mb-2">Combined Preview:</p>
                      <p className="text-sm leading-relaxed">
                        {state.generatedStatement2 
                          ? `${state.generatedStatement1}. ${state.generatedStatement2}`
                          : state.generatedStatement1
                        }
                      </p>
                    </div>
                    
                    {/* Actions */}
                    <div className="flex items-center justify-between pt-2">
                      <Button
                        variant="ghost"
                        onClick={() => copyToClipboard(
                          state.generatedStatement2 
                            ? `${state.generatedStatement1}. ${state.generatedStatement2}`
                            : state.generatedStatement1,
                          `${mpa}-combined`
                        )}
                      >
                        {copiedIndex === `${mpa}-combined` ? (
                          <Check className="size-4 mr-2" />
                        ) : (
                          <Copy className="size-4 mr-2" />
                        )}
                        Copy
                      </Button>
                      <Button
                        onClick={() => saveToLibrary(mpa)}
                        disabled={savingMPA === mpa || (
                          (state.generatedStatement2
                            ? state.generatedStatement1.length + 2 + state.generatedStatement2.length
                            : state.generatedStatement1.length) > mpaMaxChars
                        )}
                      >
                        {savingMPA === mpa ? (
                          <Loader2 className="size-4 mr-2 animate-spin" />
                        ) : (
                          <Save className="size-4 mr-2" />
                        )}
                        Save to Library
                      </Button>
                    </div>
                  </div>
                )}
              </TabsContent>
            );
          })}
        </Tabs>
      </CardContent>
    </Card>
  );
}

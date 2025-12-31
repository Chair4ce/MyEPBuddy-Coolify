"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { cn } from "@/lib/utils";
import { parseStatement, combineSentences } from "@/lib/sentence-utils";
import { getCharacterCountColor } from "@/lib/utils";

interface SplitViewEditorProps {
  text: string;
  onChange: (text: string) => void;
  maxChars: number;
  disabled?: boolean;
  placeholder?: string;
}

// Strip trailing period from a sentence (we'll add it back when combining)
function stripTrailingPeriod(text: string): string {
  const trimmed = text.trim();
  return trimmed.endsWith('.') ? trimmed.slice(0, -1) : trimmed;
}

export function SplitViewEditor({
  text,
  onChange,
  maxChars,
  disabled = false,
  placeholder = "Enter your statement here...",
}: SplitViewEditorProps) {
  // Local state for each sentence (stored WITHOUT trailing periods)
  const [sentence1, setSentence1] = useState("");
  const [sentence2, setSentence2] = useState("");
  
  // Track what we last synced to parent to avoid re-sync loops
  const lastSyncedRef = useRef<string>("");
  
  // Track if we're in the middle of a local edit
  const isLocalEditRef = useRef(false);
  
  // Initialize from external text when it changes from external source
  useEffect(() => {
    // Skip if this change came from our own edit
    if (isLocalEditRef.current) {
      isLocalEditRef.current = false;
      return;
    }
    
    // Skip if text matches what we last synced
    if (text === lastSyncedRef.current) {
      return;
    }
    
    // Parse external text into sentences
    const parsed = parseStatement(text);
    
    let newS1 = "";
    let newS2 = "";
    let needsPeroidSync = false;
    
    if (parsed.sentences.length >= 1) {
      // Strip trailing period - we'll add it back when combining
      newS1 = stripTrailingPeriod(parsed.sentences[0].text);
    } else if (text.trim() && !text.includes(".")) {
      // No period found - put all text in S1 and flag that we need to sync the period back
      newS1 = text.trim();
      needsPeroidSync = true;
    }
    
    if (parsed.sentences.length >= 2) {
      // Strip trailing period from S2 as well
      newS2 = stripTrailingPeriod(parsed.sentences[1].text);
    }
    
    setSentence1(newS1);
    setSentence2(newS2);
    
    // If text had no period, sync back with the locked period added
    if (needsPeroidSync && newS1) {
      const combined = combineSentences(newS1, newS2);
      lastSyncedRef.current = combined;
      isLocalEditRef.current = true;
      onChange(combined);
    } else {
      // Remember what we synced from
      lastSyncedRef.current = text;
    }
  }, [text, onChange]);
  
  // Combine sentences and sync back to parent
  const syncToParent = useCallback((s1: string, s2: string) => {
    // combineSentences handles adding the period to s1
    const combined = combineSentences(s1, s2);
    lastSyncedRef.current = combined;
    isLocalEditRef.current = true;
    onChange(combined);
  }, [onChange]);
  
  // Handle sentence 1 change
  const handleS1Change = (value: string) => {
    // Remove ALL periods - the period is locked and added automatically
    const cleaned = value.replace(/\./g, "");
    setSentence1(cleaned);
    syncToParent(cleaned, sentence2);
  };
  
  // Handle sentence 2 change
  const handleS2Change = (value: string) => {
    // For S2, only remove mid-text periods, allow trailing period
    const cleaned = value.replace(/\.(?=\s*\S)/g, "");
    // But also strip trailing period for consistency (combineSentences doesn't add one to S2)
    const withoutTrailing = cleaned.trim().endsWith('.') ? cleaned.trim().slice(0, -1) : cleaned;
    setSentence2(withoutTrailing);
    syncToParent(sentence1, withoutTrailing);
  };
  
  // Calculate character counts
  // S1 will have a period added, S2 might or might not (user can add it)
  const s1Trimmed = sentence1.trim();
  const s2Trimmed = sentence2.trim();
  // S1 always gets a period added when combining
  const s1Length = s1Trimmed ? s1Trimmed.length + 1 : 0; // +1 for locked period
  // S2: count as-is, user decides if they want a trailing period
  const s2Length = s2Trimmed.length;
  const spaceChar = (s1Length > 0 && s2Length > 0) ? 1 : 0;
  const totalLength = s1Length + s2Length + spaceChar;
  const isOverLimit = totalLength > maxChars;
  
  // Suggested char allocation
  const suggestedPerSentence = Math.floor(maxChars / 2);
  
  return (
    <div className="space-y-2">
      {/* Sentence 1 */}
      <div className="space-y-1">
        <div className="flex items-center justify-between">
          <span className="text-xs font-medium text-primary">
            Sentence 1
          </span>
          <span className={cn(
            "text-xs tabular-nums",
            s1Length > suggestedPerSentence ? "text-amber-500" : "text-muted-foreground"
          )}>
            {s1Length} chars
          </span>
        </div>
        <div className="relative">
          <textarea
            value={sentence1}
            onChange={(e) => handleS1Change(e.target.value)}
            disabled={disabled}
            placeholder={placeholder}
            rows={2}
            className={cn(
              "flex w-full rounded-md border border-input bg-transparent pl-3 pr-6 py-2 text-sm shadow-xs transition-colors placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px] disabled:cursor-not-allowed disabled:opacity-50 resize-none",
              s1Length > suggestedPerSentence && "border-amber-400/50"
            )}
          />
          {/* Locked period indicator - bottom right */}
          {sentence1.trim() && (
            <span className="absolute right-2.5 bottom-2 text-sm font-medium text-foreground pointer-events-none select-none">
              .
            </span>
          )}
        </div>
      </div>
      
      {/* Divider */}
      <div className="flex items-center gap-2 px-2">
        <div className="flex-1 h-px bg-border" />
        <span className="text-[10px] text-muted-foreground">+</span>
        <div className="flex-1 h-px bg-border" />
      </div>
      
      {/* Sentence 2 */}
      <div className="space-y-1">
        <div className="flex items-center justify-between">
          <span className="text-xs font-medium text-primary">
            Sentence 2
          </span>
          <span className={cn(
            "text-xs tabular-nums",
            s2Length > suggestedPerSentence ? "text-amber-500" : "text-muted-foreground"
          )}>
            {s2Length} chars
          </span>
        </div>
        <textarea
          value={sentence2}
          onChange={(e) => handleS2Change(e.target.value)}
          disabled={disabled}
          placeholder="Second sentence (optional)..."
          rows={2}
          className={cn(
            "flex w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-xs transition-colors placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px] disabled:cursor-not-allowed disabled:opacity-50 resize-none",
            s2Length > suggestedPerSentence && "border-amber-400/50"
          )}
        />
      </div>
      
      {/* Combined total */}
      <div className="flex items-center justify-between pt-1 border-t">
        <span className="text-xs text-muted-foreground">
          Combined total
        </span>
        <span className={cn(
          "text-xs tabular-nums font-medium",
          getCharacterCountColor(totalLength, maxChars)
        )}>
          {totalLength}/{maxChars}
        </span>
      </div>
      
      {isOverLimit && (
        <p className="text-xs text-destructive">
          Combined statement exceeds the {maxChars} character limit by {totalLength - maxChars} characters.
        </p>
      )}
    </div>
  );
}

"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";
import { parseStatement } from "@/lib/sentence-utils";
import type { DraggedSentence } from "./sentence-pills";

interface SentenceDropOverlayProps {
  statementText: string;
  mpaKey: string;
  draggedSentence: DraggedSentence | null;
  onDrop: (data: DraggedSentence, targetIndex: number) => void;
}

export function SentenceDropOverlay({
  statementText,
  mpaKey,
  draggedSentence,
  onDrop,
}: SentenceDropOverlayProps) {
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);

  // Only show if we're a valid drop target (different MPA is dragging)
  const isValidDropTarget = draggedSentence && draggedSentence.sourceMpa !== mpaKey;
  
  if (!isValidDropTarget) {
    return null;
  }

  const parsed = parseStatement(statementText);
  const sentences = parsed.sentences;

  const handleDragOver = (e: React.DragEvent, index: number) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    setHoverIndex(index);
  };

  const handleDragLeave = () => {
    setHoverIndex(null);
  };

  const handleDrop = (e: React.DragEvent, targetIndex: number) => {
    e.preventDefault();
    setHoverIndex(null);
    
    try {
      const data = JSON.parse(e.dataTransfer.getData("application/json")) as DraggedSentence;
      if (data.sourceMpa !== mpaKey) {
        onDrop(data, targetIndex);
      }
    } catch (err) {
      console.error("Failed to parse drag data:", err);
    }
  };

  // If no sentences, show single drop zone
  if (sentences.length === 0) {
    return (
      <div 
        className="absolute inset-0 z-20 rounded-md overflow-hidden"
        onDragOver={(e) => handleDragOver(e, 0)}
        onDragLeave={handleDragLeave}
        onDrop={(e) => handleDrop(e, 0)}
      >
        <div className={cn(
          "h-full w-full flex items-center justify-center transition-all",
          "bg-card border-2 border-dashed",
          hoverIndex === 0 
            ? "border-primary bg-accent" 
            : "border-muted-foreground/30"
        )}>
          <div className="text-center">
            <span className="text-sm font-medium px-3 py-1.5 rounded-full bg-primary/10 text-primary">
              Drop as S1
            </span>
          </div>
        </div>
      </div>
    );
  }

  // Show sentence zones
  return (
    <div className="absolute inset-0 z-20 rounded-md overflow-hidden flex flex-col">
      {[0, 1].map((index) => {
        const sentence = sentences[index];
        const isHovering = hoverIndex === index;
        const hasExisting = !!sentence;
        
        return (
          <div
            key={index}
            onDragOver={(e) => handleDragOver(e, index)}
            onDragLeave={handleDragLeave}
            onDrop={(e) => handleDrop(e, index)}
            className={cn(
              "flex-1 flex items-center px-3 py-2 transition-all cursor-pointer border-2 border-dashed",
              index === 0 ? "rounded-t-md" : "rounded-b-md border-t-0",
              isHovering 
                ? "bg-accent border-primary" 
                : "bg-card border-muted-foreground/20 hover:bg-accent/50 hover:border-muted-foreground/30"
            )}
          >
            <div className="flex items-start gap-3 w-full">
              <span className={cn(
                "shrink-0 text-xs font-medium px-2 py-1 rounded-full transition-transform",
                "bg-primary/10 text-primary",
                isHovering && "scale-105 bg-primary/20"
              )}>
                S{index + 1}
              </span>
              
              <div className="flex-1 min-w-0">
                {hasExisting ? (
                  <p className={cn(
                    "text-xs leading-relaxed transition-all",
                    isHovering 
                      ? "text-foreground" 
                      : "text-muted-foreground"
                  )}>
                    {sentence.text}
                  </p>
                ) : (
                  <p className="text-xs italic text-muted-foreground">
                    Empty — drop here to add as sentence {index + 1}
                  </p>
                )}
              </div>
              
              {hasExisting && (
                <span className="shrink-0 text-[10px] text-muted-foreground tabular-nums">
                  ({sentence.text.length})
                </span>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}

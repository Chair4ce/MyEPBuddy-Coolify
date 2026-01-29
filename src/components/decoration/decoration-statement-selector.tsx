"use client";

import { useMemo } from "react";
import { useDecorationShellStore } from "@/stores/decoration-shell-store";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Button } from "@/components/ui/button";
import { ENTRY_MGAS, MPA_ABBREVIATIONS } from "@/lib/constants";
import { cn } from "@/lib/utils";
import { FileText, X } from "lucide-react";
import type { Accomplishment } from "@/types/database";

interface DecorationStatementSelectorProps {
  accomplishments: Accomplishment[];
  className?: string;
}

export function DecorationStatementSelector({
  accomplishments,
  className,
}: DecorationStatementSelectorProps) {
  const { selectedStatementIds, toggleStatementSelection, clearSelectedStatements } =
    useDecorationShellStore();

  // Group accomplishments by MPA
  const groupedAccomplishments = useMemo(() => {
    const groups: Record<string, Accomplishment[]> = {};

    // Initialize all MPA groups
    ENTRY_MGAS.forEach((mpa) => {
      groups[mpa.key] = [];
    });

    // Group accomplishments by MPA
    accomplishments.forEach((acc) => {
      const mpaKey = acc.mpa || "miscellaneous";
      if (!groups[mpaKey]) {
        groups[mpaKey] = [];
      }
      groups[mpaKey].push(acc);
    });

    return groups;
  }, [accomplishments]);

  // Get MPA label
  const getMPALabel = (mpaKey: string) => {
    const mpa = ENTRY_MGAS.find((m) => m.key === mpaKey);
    return mpa?.label || mpaKey;
  };

  // Format accomplishment as display text
  const formatAccomplishment = (acc: Accomplishment) => {
    let text = `${acc.action_verb} ${acc.details}`;
    if (text.length > 120) {
      text = text.substring(0, 117) + "...";
    }
    return text;
  };

  // Count total and selected
  const totalCount = accomplishments.length;
  const selectedCount = selectedStatementIds.length;

  if (totalCount === 0) {
    return (
      <Card className={cn("border-dashed", className)}>
        <CardContent className="flex flex-col items-center justify-center py-8 text-center">
          <FileText className="size-10 text-muted-foreground mb-3" />
          <p className="text-sm text-muted-foreground">
            No accomplishments found for this member.
          </p>
          <p className="text-xs text-muted-foreground mt-1">
            Add accomplishments to their log to use them in decorations.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className={className}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="text-base">Select Accomplishments</CardTitle>
            <CardDescription className="text-xs mt-0.5">
              Choose accomplishments to include in the decoration citation
            </CardDescription>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant="secondary" className="text-xs">
              {selectedCount} / {totalCount} selected
            </Badge>
            {selectedCount > 0 && (
              <Button
                variant="ghost"
                size="sm"
                onClick={clearSelectedStatements}
                className="h-7 px-2 text-xs"
              >
                <X className="size-3 mr-1" />
                Clear
              </Button>
            )}
          </div>
        </div>
      </CardHeader>
      <CardContent className="pt-0">
        <ScrollArea className="h-[300px] pr-4">
          <div className="space-y-4">
            {ENTRY_MGAS.map((mpa) => {
              const mpaAccomplishments = groupedAccomplishments[mpa.key] || [];
              if (mpaAccomplishments.length === 0) return null;

              const selectedInMPA = mpaAccomplishments.filter((a) =>
                selectedStatementIds.includes(a.id)
              ).length;

              return (
                <div key={mpa.key} className="space-y-2">
                  <div className="flex items-center gap-2">
                    <Badge variant="outline" className="text-xs font-medium">
                      {MPA_ABBREVIATIONS[mpa.key] || mpa.key}
                    </Badge>
                    <span className="text-xs text-muted-foreground">
                      {mpa.label}
                    </span>
                    {selectedInMPA > 0 && (
                      <Badge variant="secondary" className="text-[10px] ml-auto">
                        {selectedInMPA} selected
                      </Badge>
                    )}
                  </div>
                  <div className="space-y-1.5 pl-2">
                    {mpaAccomplishments.map((acc) => {
                      const isSelected = selectedStatementIds.includes(acc.id);
                      return (
                        <label
                          key={acc.id}
                          className={cn(
                            "flex items-start gap-2.5 p-2 rounded-md cursor-pointer transition-colors",
                            "hover:bg-muted/50",
                            isSelected && "bg-primary/5 border border-primary/20"
                          )}
                        >
                          <Checkbox
                            checked={isSelected}
                            onCheckedChange={() => toggleStatementSelection(acc.id)}
                            className="mt-0.5"
                            aria-label={`Select accomplishment: ${acc.action_verb} ${acc.details}`}
                          />
                          <div className="flex-1 min-w-0">
                            <p className="text-sm leading-relaxed">
                              {formatAccomplishment(acc)}
                            </p>
                            <div className="flex items-center gap-2 mt-1">
                              {acc.impact && (
                                <span className="text-xs text-muted-foreground truncate max-w-[200px]">
                                  Impact: {acc.impact}
                                </span>
                              )}
                              {acc.metrics && (
                                <span className="text-xs text-muted-foreground truncate max-w-[150px]">
                                  • {acc.metrics}
                                </span>
                              )}
                            </div>
                          </div>
                        </label>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </ScrollArea>
      </CardContent>
    </Card>
  );
}

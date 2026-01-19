"use client";

import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/components/ui/sonner";
import { Loader2, Target, Calendar, Trash2 } from "lucide-react";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import type { Rank, Profile, ManagedMember, SupervisorExpectation } from "@/types/database";
import { getExpectation, setExpectation, deleteExpectation } from "@/app/actions/supervisor-expectations";
import { getActiveCycleYear } from "@/lib/constants";

interface SetExpectationsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  // Either a real subordinate profile or a managed member
  subordinate?: Profile | null;
  managedMember?: ManagedMember | null;
  supervisorRank?: Rank | null;
  onSuccess?: () => void;
}

export function SetExpectationsDialog({
  open,
  onOpenChange,
  subordinate,
  managedMember,
  supervisorRank,
  onSuccess,
}: SetExpectationsDialogProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [expectationText, setExpectationText] = useState("");
  const [existingExpectation, setExistingExpectation] = useState<SupervisorExpectation | null>(null);

  // Get member info
  const memberName = subordinate?.full_name || managedMember?.full_name || "Unknown";
  const memberRank = subordinate?.rank || managedMember?.rank || null;
  const subordinateId = subordinate?.id || null;
  const teamMemberId = managedMember?.id || null;

  // Get current cycle year based on subordinate's rank
  const cycleYear = getActiveCycleYear(memberRank as Rank);

  // Load existing expectation when dialog opens
  useEffect(() => {
    async function loadExpectation() {
      if (!open) return;
      if (!subordinateId && !teamMemberId) return;

      setIsLoading(true);
      const result = await getExpectation(subordinateId, teamMemberId, cycleYear);
      
      if (result.data) {
        setExistingExpectation(result.data);
        setExpectationText(result.data.expectation_text);
      } else {
        setExistingExpectation(null);
        setExpectationText("");
      }
      setIsLoading(false);
    }

    loadExpectation();
  }, [open, subordinateId, teamMemberId, cycleYear]);

  // Reset state when dialog closes
  useEffect(() => {
    if (!open) {
      setExpectationText("");
      setExistingExpectation(null);
      setShowDeleteConfirm(false);
    }
  }, [open]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    if (!expectationText.trim()) {
      toast.error("Please enter your expectations");
      return;
    }

    setIsSubmitting(true);

    const result = await setExpectation(
      subordinateId,
      teamMemberId,
      expectationText.trim(),
      cycleYear
    );

    if (result.error) {
      toast.error(result.error);
    } else {
      toast.success(
        existingExpectation 
          ? `Expectations updated for ${memberRank ? `${memberRank} ` : ""}${memberName}`
          : `Expectations set for ${memberRank ? `${memberRank} ` : ""}${memberName}`
      );
      onSuccess?.();
      onOpenChange(false);
    }

    setIsSubmitting(false);
  }

  async function handleDelete() {
    if (!existingExpectation) return;

    setIsDeleting(true);

    const result = await deleteExpectation(existingExpectation.id);

    if (result.error) {
      toast.error(result.error);
    } else {
      toast.success("Expectations removed");
      onSuccess?.();
      onOpenChange(false);
    }

    setIsDeleting(false);
    setShowDeleteConfirm(false);
  }

  const hasChanges = expectationText.trim() !== (existingExpectation?.expectation_text || "");

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="max-w-[calc(100vw-2rem)] sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Target className="size-5 text-primary" />
              Set Expectations
            </DialogTitle>
            <DialogDescription>
              Set performance expectations for{" "}
              <span className="font-medium text-foreground">
                {memberRank ? `${memberRank} ` : ""}{memberName}
              </span>
              . These expectations are private between you and this subordinate.
            </DialogDescription>
          </DialogHeader>

          {isLoading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="size-6 animate-spin text-muted-foreground" />
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              {/* Cycle Year Badge */}
              <div className="flex items-center gap-2">
                <Badge variant="outline" className="gap-1.5">
                  <Calendar className="size-3" />
                  Cycle Year {cycleYear}
                </Badge>
                {existingExpectation && (
                  <Badge variant="secondary" className="text-xs">
                    Last updated {new Date(existingExpectation.updated_at).toLocaleDateString()}
                  </Badge>
                )}
              </div>

              {/* Expectation Text */}
              <div className="space-y-2">
                <Label htmlFor="expectation">
                  Your Expectations
                </Label>
                <Textarea
                  id="expectation"
                  value={expectationText}
                  onChange={(e) => setExpectationText(e.target.value)}
                  placeholder="Describe your expectations for this subordinate. Consider their current rank, responsibilities, and areas for growth. These expectations will help assess their accomplishments and guide their development..."
                  className="min-h-[150px] resize-none"
                  aria-label="Expectation text for subordinate"
                />
                <p className="text-xs text-muted-foreground">
                  Keep it concise but specific. Focus on key performance areas, goals, and behaviors you expect from this Airman.
                </p>
              </div>

              <DialogFooter className="flex-col sm:flex-row gap-2 pt-2">
                {existingExpectation && (
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() => setShowDeleteConfirm(true)}
                    disabled={isSubmitting || isDeleting}
                    className="text-destructive hover:text-destructive sm:mr-auto"
                  >
                    <Trash2 className="size-4 mr-2" />
                    Remove
                  </Button>
                )}
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => onOpenChange(false)}
                  className="w-full sm:w-auto"
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={isSubmitting || !expectationText.trim() || !hasChanges}
                  className="w-full sm:w-auto"
                >
                  {isSubmitting ? (
                    <>
                      <Loader2 className="size-4 animate-spin mr-2" />
                      Saving...
                    </>
                  ) : existingExpectation ? (
                    "Update Expectations"
                  ) : (
                    "Save Expectations"
                  )}
                </Button>
              </DialogFooter>
            </form>
          )}
        </DialogContent>
      </Dialog>

      {/* Delete Confirmation */}
      <AlertDialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove Expectations?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently remove the expectations you&apos;ve set for{" "}
              {memberRank ? `${memberRank} ` : ""}{memberName} for cycle year {cycleYear}.
              This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              disabled={isDeleting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {isDeleting ? (
                <>
                  <Loader2 className="size-4 animate-spin mr-2" />
                  Removing...
                </>
              ) : (
                "Remove Expectations"
              )}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

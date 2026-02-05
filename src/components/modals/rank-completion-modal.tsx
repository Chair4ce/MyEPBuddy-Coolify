"use client";

import { useState, useEffect } from "react";
import { createClient } from "@/lib/supabase/client";
import { useUserStore } from "@/stores/user-store";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { toast } from "@/components/ui/sonner";
import { CheckCircle2, Calendar, Users, Award, Loader2 } from "lucide-react";
import { ENLISTED_RANKS, OFFICER_RANKS, CIVILIAN_RANK } from "@/lib/constants";
import type { Rank, Profile } from "@/types/database";

// Storage key is per-user to avoid cross-account dismissal issues
const getStorageKey = (userId: string) => `rank_modal_dismissed_${userId}`;

export function RankCompletionModal() {
  const { profile, setProfile } = useUserStore();
  const [isOpen, setIsOpen] = useState(false);
  const [selectedRank, setSelectedRank] = useState<Rank | "">("");
  const [isLoading, setIsLoading] = useState(false);
  const supabase = createClient();

  useEffect(() => {
    // Check if we should show the modal
    if (!profile) return;

    // Don't show if user already has a rank
    if (profile.rank) return;

    // Don't show if user has dismissed it before (per-user check)
    const storageKey = getStorageKey(profile.id);
    const dismissed = localStorage.getItem(storageKey);
    if (dismissed === "true") return;

    // Show modal after a short delay for better UX
    const timer = setTimeout(() => {
      setIsOpen(true);
    }, 1000);

    return () => clearTimeout(timer);
  }, [profile]);

  async function handleSaveRank() {
    if (!selectedRank || !profile) return;

    setIsLoading(true);

    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from("profiles")
        .update({ rank: selectedRank })
        .eq("id", profile.id)
        .select()
        .single();

      if (error) {
        toast.error(error.message);
        return;
      }

      setProfile(data as Profile);
      toast.success("Rank saved! EPB features are now enabled.");
      setIsOpen(false);
      localStorage.setItem(getStorageKey(profile.id), "true");
    } catch {
      toast.error("Failed to save rank");
    } finally {
      setIsLoading(false);
    }
  }

  function handleDismiss() {
    setIsOpen(false);
    if (profile) {
      localStorage.setItem(getStorageKey(profile.id), "true");
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && handleDismiss()}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle className="text-2xl">Complete your profile</DialogTitle>
          <DialogDescription>
            Adding your rank unlocks key features in MyEPBuddy
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-4">
          {/* Feature highlights */}
          <div className="space-y-3">
            <div className="flex items-start gap-3 p-3 rounded-lg bg-primary/5 border border-primary/10">
              <Calendar className="size-5 text-primary shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-medium">EPB Close-out Dates</p>
                <p className="text-xs text-muted-foreground">
                  See your static close-out dates and submission deadlines
                </p>
              </div>
            </div>

            <div className="flex items-start gap-3 p-3 rounded-lg bg-primary/5 border border-primary/10">
              <Users className="size-5 text-primary shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-medium">Team Management</p>
                <p className="text-xs text-muted-foreground">
                  Supervise and manage EPBs for your team members
                </p>
              </div>
            </div>

            <div className="flex items-start gap-3 p-3 rounded-lg bg-primary/5 border border-primary/10">
              <Award className="size-5 text-primary shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-medium">Award Recommendations</p>
                <p className="text-xs text-muted-foreground">
                  Get rank-appropriate award suggestions and tracking
                </p>
              </div>
            </div>
          </div>

          {/* Rank selection */}
          <div className="space-y-2 pt-2">
            <Label htmlFor="modal-rank">Your Rank</Label>
            <Select
              value={selectedRank}
              onValueChange={(value) => setSelectedRank(value as Rank)}
            >
              <SelectTrigger id="modal-rank" aria-label="Select your rank">
                <SelectValue placeholder="Select your rank" />
              </SelectTrigger>
              <SelectContent>
                <div className="px-2 py-1.5 text-xs font-semibold text-muted-foreground">
                  Enlisted
                </div>
                {ENLISTED_RANKS.map((r) => (
                  <SelectItem key={r.value} value={r.value}>
                    {r.value}
                  </SelectItem>
                ))}
                <div className="px-2 py-1.5 text-xs font-semibold text-muted-foreground border-t mt-1 pt-1">
                  Officer
                </div>
                {OFFICER_RANKS.map((r) => (
                  <SelectItem key={r.value} value={r.value}>
                    {r.value}
                  </SelectItem>
                ))}
                <div className="px-2 py-1.5 text-xs font-semibold text-muted-foreground border-t mt-1 pt-1">
                  Civilian
                </div>
                {CIVILIAN_RANK.map((r) => (
                  <SelectItem key={r.value} value={r.value}>
                    {r.value}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <p className="text-xs text-muted-foreground text-center">
            You can always update your rank later in Settings
          </p>
        </div>

        <DialogFooter className="flex-col sm:flex-row gap-2">
          <Button
            variant="ghost"
            onClick={handleDismiss}
            className="w-full sm:w-auto"
          >
            I'll do this later
          </Button>
          <Button
            onClick={handleSaveRank}
            disabled={!selectedRank || isLoading}
            className="w-full sm:w-auto"
          >
            {isLoading ? (
              <>
                <Loader2 className="size-4 animate-spin mr-2" />
                Saving...
              </>
            ) : (
              <>
                <CheckCircle2 className="size-4 mr-2" />
                Save Rank
              </>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

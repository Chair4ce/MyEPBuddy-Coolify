"use client";

import { useState, useEffect, useMemo } from "react";
import { useUserStore } from "@/stores/user-store";
import { useProjectsStore } from "@/stores/projects-store";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ComboboxInput } from "@/components/ui/combobox-input";
import { toast } from "@/components/ui/sonner";
import { createClient } from "@/lib/supabase/client";
import { createAccomplishment } from "@/app/actions/accomplishments";
import {
  DEFAULT_ACTION_VERBS,
  ENTRY_MGAS,
  getActiveCycleYear,
} from "@/lib/constants";
import type { Rank, Project, ProjectMember } from "@/types/database";
import {
  Loader2,
  ChevronRight,
  ChevronLeft,
  Check,
  AlertCircle,
  FolderKanban,
  Crown,
} from "lucide-react";
import { celebrateEntry } from "@/lib/confetti";
import { cn } from "@/lib/utils";

interface ProjectMemberOption {
  id: string;
  memberId: string; // project_member id
  type: "profile" | "managed";
  name: string;
  rank: string | null;
  afsc: string | null;
  isOwner: boolean;
}

interface SelectedMember extends ProjectMemberOption {
  actionVerb: string;
}

interface AddProjectAccomplishmentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  project: Project | null;
}

export function AddProjectAccomplishmentDialog({
  open,
  onOpenChange,
  project,
}: AddProjectAccomplishmentDialogProps) {
  const { profile } = useUserStore();
  const supabase = createClient();

  const [step, setStep] = useState<1 | 2>(1);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [selectedMembers, setSelectedMembers] = useState<SelectedMember[]>([]);

  const [form, setForm] = useState({
    date: new Date().toISOString().split("T")[0],
    details: "",
    impact: "",
    metrics: "",
    mpa: "executing_mission",
    tags: "",
  });

  const mgas = ENTRY_MGAS;
  const cycleYear = getActiveCycleYear(profile?.rank as Rank | null);

  // Build available members from project members only
  const availableMembers = useMemo((): ProjectMemberOption[] => {
    if (!project?.members) return [];

    return project.members
      .filter((m) => {
        // Only include members we can create entries for
        // (profile members we supervise or managed members)
        return m.profile_id || m.team_member_id;
      })
      .map((m): ProjectMemberOption => {
        if (m.profile_id && m.profile) {
          return {
            id: m.profile_id,
            memberId: m.id,
            type: "profile",
            name: m.profile.full_name || "Unknown",
            rank: m.profile.rank,
            afsc: m.profile.afsc,
            isOwner: m.is_owner,
          };
        } else if (m.team_member_id && m.team_member) {
          return {
            id: m.team_member_id,
            memberId: m.id,
            type: "managed",
            name: m.team_member.full_name || "Unknown",
            rank: m.team_member.rank,
            afsc: m.team_member.afsc,
            isOwner: m.is_owner,
          };
        }
        return null as unknown as ProjectMemberOption;
      })
      .filter(Boolean);
  }, [project]);

  // Reset form when dialog closes
  useEffect(() => {
    if (!open) {
      setStep(1);
      setSelectedMembers([]);
      setForm({
        date: new Date().toISOString().split("T")[0],
        details: "",
        impact: "",
        metrics: "",
        mpa: "executing_mission",
        tags: "",
      });
    }
  }, [open]);

  function toggleMember(member: ProjectMemberOption) {
    setSelectedMembers((prev) => {
      const existing = prev.find((m) => m.id === member.id && m.type === member.type);
      if (existing) {
        return prev.filter((m) => !(m.id === member.id && m.type === member.type));
      }
      return [...prev, { ...member, actionVerb: "" }];
    });
  }

  function isMemberSelected(member: ProjectMemberOption) {
    return selectedMembers.some((m) => m.id === member.id && m.type === member.type);
  }

  function updateMemberVerb(memberId: string, type: "profile" | "managed", verb: string) {
    setSelectedMembers((prev) =>
      prev.map((m) =>
        m.id === memberId && m.type === type ? { ...m, actionVerb: verb } : m
      )
    );
  }

  function selectAllMembers() {
    setSelectedMembers(availableMembers.map((m) => ({ ...m, actionVerb: "" })));
  }

  function deselectAllMembers() {
    setSelectedMembers([]);
  }

  function canProceedToStep2() {
    return form.details.trim().length > 0;
  }

  function canSubmit() {
    return (
      selectedMembers.length > 0 &&
      selectedMembers.every((m) => m.actionVerb.trim().length > 0)
    );
  }

  const duplicateVerbs = useMemo(() => {
    const verbs = selectedMembers.map((m) => m.actionVerb.toLowerCase().trim()).filter(Boolean);
    const counts = verbs.reduce((acc, v) => ({ ...acc, [v]: (acc[v] || 0) + 1 }), {} as Record<string, number>);
    return Object.entries(counts)
      .filter(([, count]) => count > 1)
      .map(([verb]) => verb);
  }, [selectedMembers]);

  async function handleSubmit() {
    if (!profile || !project || !canSubmit()) return;

    setIsSubmitting(true);

    const tags = form.tags
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean);

    const errors: string[] = [];
    const successes: string[] = [];
    const createdAccomplishmentIds: string[] = [];

    // Create accomplishment for each selected member
    for (const member of selectedMembers) {
      try {
        const isManaged = member.type === "managed";

        const result = await createAccomplishment({
          user_id: isManaged ? profile.id : member.id,
          created_by: profile.id,
          team_member_id: isManaged ? member.id : null,
          date: form.date,
          action_verb: member.actionVerb,
          details: form.details,
          impact: form.impact || null,
          metrics: form.metrics || null,
          mpa: form.mpa,
          tags,
          cycle_year: cycleYear,
          assessment_scores: null,
          assessed_at: null,
          assessment_model: null,
        });

        if (result.error) {
          errors.push(`${member.rank || ""} ${member.name}: ${result.error}`);
        } else if (result.data) {
          successes.push(`${member.rank || ""} ${member.name}`);
          createdAccomplishmentIds.push(result.data.id);
        }
      } catch (error) {
        errors.push(`${member.rank || ""} ${member.name}: ${error instanceof Error ? error.message : "Unknown error"}`);
      }
    }

    // Link all created accomplishments to the project
    if (createdAccomplishmentIds.length > 0) {
      try {
        const links = createdAccomplishmentIds.map((accomplishment_id) => ({
          accomplishment_id,
          project_id: project.id,
        }));

        await (supabase.from("accomplishment_projects") as any).insert(links);
      } catch (error) {
        console.error("Error linking accomplishments to project:", error);
        // Don't fail the whole operation if linking fails
      }
    }

    setIsSubmitting(false);

    if (successes.length > 0) {
      celebrateEntry();
      toast.success(`Created ${successes.length} entry${successes.length > 1 ? " entries" : ""}!`, {
        description: `Linked to "${project.name}"`,
        duration: 5000,
      });
    }

    if (errors.length > 0) {
      toast.error(`Failed to create ${errors.length} entry${errors.length > 1 ? " entries" : ""}`, {
        description: errors.join("; "),
        duration: 8000,
      });
    }

    if (successes.length > 0) {
      onOpenChange(false);
    }
  }

  function getInitials(name: string) {
    return name
      .split(" ")
      .map((n) => n[0])
      .join("")
      .toUpperCase()
      .slice(0, 2);
  }

  if (!project) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[calc(100%-1rem)] max-w-2xl max-h-[85dvh] overflow-hidden flex flex-col p-0">
        <DialogHeader className="px-4 pt-4 sm:px-6 sm:pt-6 pb-0">
          <DialogTitle className="flex items-center gap-2 text-base sm:text-lg">
            <FolderKanban className="size-5 text-primary" />
            Add Entry to Project
          </DialogTitle>
          <DialogDescription className="text-sm">
            {step === 1
              ? `Create an accomplishment for "${project.name}"`
              : "Select project members and assign their roles"}
          </DialogDescription>
        </DialogHeader>

        {/* Project context banner */}
        <div className="mx-4 sm:mx-6 mt-3 p-3 rounded-lg bg-muted/50 border">
          <div className="flex items-center gap-2 text-sm">
            <span className="font-medium">{project.name}</span>
            <Badge variant="secondary" className="text-[10px]">
              {availableMembers.length} members
            </Badge>
          </div>
          {project.result && (
            <p className="text-xs text-muted-foreground mt-1 line-clamp-1">
              Result: {project.result}
            </p>
          )}
        </div>

        {/* Step indicator */}
        <div className="flex items-center gap-2 px-4 sm:px-6 py-3 border-b bg-muted/30 mt-3">
          <div
            className={cn(
              "flex items-center gap-1.5 text-sm font-medium",
              step === 1 ? "text-primary" : "text-muted-foreground"
            )}
          >
            <span
              className={cn(
                "size-6 rounded-full flex items-center justify-center text-xs",
                step === 1 ? "bg-primary text-primary-foreground" : "bg-muted"
              )}
            >
              {step > 1 ? <Check className="size-3.5" /> : "1"}
            </span>
            Details
          </div>
          <ChevronRight className="size-4 text-muted-foreground" />
          <div
            className={cn(
              "flex items-center gap-1.5 text-sm font-medium",
              step === 2 ? "text-primary" : "text-muted-foreground"
            )}
          >
            <span
              className={cn(
                "size-6 rounded-full flex items-center justify-center text-xs",
                step === 2 ? "bg-primary text-primary-foreground" : "bg-muted"
              )}
            >
              2
            </span>
            Members
          </div>
        </div>

        <div className="flex-1 overflow-y-auto px-4 sm:px-6 py-4">
          {step === 1 && (
            <div className="space-y-4">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="date">Date *</Label>
                  <Input
                    id="date"
                    type="date"
                    value={form.date}
                    onChange={(e) => setForm({ ...form, date: e.target.value })}
                    required
                    aria-label="Accomplishment date"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="mpa">Major Performance Area</Label>
                  <Select
                    value={form.mpa}
                    onValueChange={(value) => setForm({ ...form, mpa: value })}
                  >
                    <SelectTrigger id="mpa" aria-label="Select MPA">
                      <SelectValue placeholder="Select MPA" />
                    </SelectTrigger>
                    <SelectContent>
                      {mgas.map((mpa) => (
                        <SelectItem key={mpa.key} value={mpa.key}>
                          {mpa.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="details">Details *</Label>
                <Textarea
                  id="details"
                  placeholder="Describe the accomplishment..."
                  value={form.details}
                  onChange={(e) => setForm({ ...form, details: e.target.value })}
                  required
                  className="min-h-[100px] resize-y"
                  aria-label="Accomplishment details"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="impact">Impact/Result</Label>
                <Textarea
                  id="impact"
                  placeholder="What was the outcome? (optional)"
                  value={form.impact}
                  onChange={(e) => setForm({ ...form, impact: e.target.value })}
                  className="min-h-[60px] resize-y"
                  aria-label="Impact or result"
                />
                {project.result && (
                  <p className="text-xs text-muted-foreground">
                    Project result will also be used: &quot;{project.result.slice(0, 80)}...&quot;
                  </p>
                )}
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="metrics">Metrics</Label>
                  <Input
                    id="metrics"
                    placeholder="e.g., 15% increase"
                    value={form.metrics}
                    onChange={(e) => setForm({ ...form, metrics: e.target.value })}
                    aria-label="Quantifiable metrics"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="tags">Tags</Label>
                  <Input
                    id="tags"
                    placeholder="comma separated"
                    value={form.tags}
                    onChange={(e) => setForm({ ...form, tags: e.target.value })}
                    aria-label="Tags"
                  />
                </div>
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-4">
              {/* Member selection */}
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <Label>Select Project Members</Label>
                  <div className="flex gap-2">
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      className="h-7 text-xs"
                      onClick={selectAllMembers}
                    >
                      Select All
                    </Button>
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      className="h-7 text-xs"
                      onClick={deselectAllMembers}
                    >
                      Clear
                    </Button>
                  </div>
                </div>
                <ScrollArea className="h-[120px] rounded-md border p-2">
                  <div className="space-y-1">
                    {availableMembers.length === 0 ? (
                      <p className="text-sm text-muted-foreground text-center py-4">
                        No members assigned to this project
                      </p>
                    ) : (
                      availableMembers.map((member) => (
                        <div
                          key={`${member.type}-${member.id}`}
                          className={cn(
                            "flex items-center gap-3 p-2 rounded-md cursor-pointer transition-colors",
                            isMemberSelected(member)
                              ? "bg-primary/10 border border-primary/30"
                              : "hover:bg-muted"
                          )}
                          onClick={() => toggleMember(member)}
                        >
                          <Checkbox
                            checked={isMemberSelected(member)}
                            onCheckedChange={() => toggleMember(member)}
                            aria-label={`Select ${member.name}`}
                          />
                          <Avatar className="size-7">
                            <AvatarFallback className="text-xs">
                              {getInitials(member.name)}
                            </AvatarFallback>
                          </Avatar>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-1.5">
                              <span className="text-sm font-medium truncate">
                                {member.rank} {member.name}
                              </span>
                              {member.isOwner && (
                                <Crown className="size-3 text-amber-500" />
                              )}
                              {member.type === "managed" && (
                                <Badge variant="secondary" className="text-[10px] px-1 py-0">
                                  Managed
                                </Badge>
                              )}
                            </div>
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                </ScrollArea>
                <p className="text-xs text-muted-foreground">
                  {selectedMembers.length} of {availableMembers.length} selected
                </p>
              </div>

              {/* Role assignment */}
              {selectedMembers.length > 0 && (
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <Label>Assign Action Verbs</Label>
                    {duplicateVerbs.length > 0 && (
                      <div className="flex items-center gap-1 text-amber-600 text-xs">
                        <AlertCircle className="size-3" />
                        Duplicate verbs
                      </div>
                    )}
                  </div>

                  <ScrollArea className="h-[180px] pr-3">
                    <div className="space-y-3">
                      {selectedMembers.map((member) => (
                        <div
                          key={`${member.type}-${member.id}`}
                          className="flex items-start gap-3 p-3 rounded-lg border bg-card"
                        >
                          <Avatar className="size-8 shrink-0">
                            <AvatarFallback className="text-xs">
                              {getInitials(member.name)}
                            </AvatarFallback>
                          </Avatar>
                          <div className="flex-1 space-y-2 min-w-0">
                            <span className="text-sm font-medium truncate block">
                              {member.rank} {member.name}
                            </span>
                            <ComboboxInput
                              value={member.actionVerb}
                              onChange={(value) =>
                                updateMemberVerb(member.id, member.type, value)
                              }
                              options={DEFAULT_ACTION_VERBS}
                              placeholder="Select action verb..."
                              aria-label={`Action verb for ${member.name}`}
                            />
                          </div>
                        </div>
                      ))}
                    </div>
                  </ScrollArea>
                </div>
              )}

              {selectedMembers.length === 0 && (
                <div className="text-center py-6 text-muted-foreground">
                  <p className="text-sm">Select members above to continue</p>
                </div>
              )}
            </div>
          )}
        </div>

        <DialogFooter className="px-4 pb-4 sm:px-6 sm:pb-6 pt-4 gap-2 border-t">
          <div className="flex w-full justify-between gap-2">
            {step === 2 && (
              <Button
                type="button"
                variant="outline"
                onClick={() => setStep(1)}
                disabled={isSubmitting}
              >
                <ChevronLeft className="size-4 mr-1" />
                Back
              </Button>
            )}
            <div className="flex gap-2 ml-auto">
              <Button
                type="button"
                variant="outline"
                onClick={() => onOpenChange(false)}
                disabled={isSubmitting}
              >
                Cancel
              </Button>
              {step === 1 ? (
                <Button
                  type="button"
                  onClick={() => setStep(2)}
                  disabled={!canProceedToStep2()}
                >
                  Next
                  <ChevronRight className="size-4 ml-1" />
                </Button>
              ) : (
                <Button
                  type="button"
                  onClick={handleSubmit}
                  disabled={isSubmitting || !canSubmit()}
                >
                  {isSubmitting ? (
                    <>
                      <Loader2 className="size-4 animate-spin mr-2" />
                      Creating...
                    </>
                  ) : (
                    `Create ${selectedMembers.length} Entr${selectedMembers.length === 1 ? "y" : "ies"}`
                  )}
                </Button>
              )}
            </div>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

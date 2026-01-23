"use client";

import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Loader2, Save, Building2, User, Star } from "lucide-react";
import { cn } from "@/lib/utils";
import { MAX_DUTY_DESCRIPTION_CHARACTERS } from "@/lib/constants";

interface SaveDutyDescriptionTemplateDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  templateText: string;
  onSave: (data: {
    template_text: string;
    office_label: string | null;
    role_label: string | null;
    rank_label: string | null;
    note: string | null;
  }) => Promise<void>;
  existingLabels?: {
    offices: string[];
    roles: string[];
    ranks: string[];
  };
}

export function SaveDutyDescriptionTemplateDialog({
  open,
  onOpenChange,
  templateText,
  onSave,
  existingLabels = { offices: [], roles: [], ranks: [] },
}: SaveDutyDescriptionTemplateDialogProps) {
  const [officeLabel, setOfficeLabel] = useState("");
  const [roleLabel, setRoleLabel] = useState("");
  const [rankLabel, setRankLabel] = useState("");
  const [note, setNote] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [showOfficeSuggestions, setShowOfficeSuggestions] = useState(false);
  const [showRoleSuggestions, setShowRoleSuggestions] = useState(false);
  const [showRankSuggestions, setShowRankSuggestions] = useState(false);

  // Filter suggestions based on current input
  const filteredOffices = existingLabels.offices.filter(
    (o) => officeLabel && o.toLowerCase().includes(officeLabel.toLowerCase())
  );
  const filteredRoles = existingLabels.roles.filter(
    (r) => roleLabel && r.toLowerCase().includes(roleLabel.toLowerCase())
  );
  const filteredRanks = existingLabels.ranks.filter(
    (r) => rankLabel && r.toLowerCase().includes(rankLabel.toLowerCase())
  );

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await onSave({
        template_text: templateText,
        office_label: officeLabel.trim() || null,
        role_label: roleLabel.trim() || null,
        rank_label: rankLabel.trim() || null,
        note: note.trim() || null,
      });
      // Reset form
      setOfficeLabel("");
      setRoleLabel("");
      setRankLabel("");
      setNote("");
      onOpenChange(false);
    } finally {
      setIsSaving(false);
    }
  };

  const handleClose = () => {
    setOfficeLabel("");
    setRoleLabel("");
    setRankLabel("");
    setNote("");
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="sm:max-w-lg" aria-describedby="save-template-description">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Save className="size-5" />
            Save as Template
          </DialogTitle>
          <DialogDescription id="save-template-description">
            Save this duty description as a reusable template. Add labels to organize and filter later.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-4">
          {/* Preview of template text */}
          <div className="space-y-2">
            <Label className="text-xs text-muted-foreground">Template Text</Label>
            <div className="rounded-md border bg-muted/30 p-3">
              <p className="text-sm line-clamp-3">{templateText}</p>
              <p className={cn(
                "text-[10px] mt-1 tabular-nums",
                templateText.length > MAX_DUTY_DESCRIPTION_CHARACTERS 
                  ? "text-destructive" 
                  : "text-muted-foreground"
              )}>
                {templateText.length}/{MAX_DUTY_DESCRIPTION_CHARACTERS} characters
              </p>
            </div>
          </div>

          {/* Office Label */}
          <div className="space-y-2 relative">
            <Label htmlFor="office-label" className="flex items-center gap-1.5 text-sm">
              <Building2 className="size-3.5" />
              Office
            </Label>
            <Input
              id="office-label"
              placeholder="e.g., Cyber Operations, Maintenance, Finance"
              value={officeLabel}
              onChange={(e) => setOfficeLabel(e.target.value)}
              onFocus={() => setShowOfficeSuggestions(true)}
              onBlur={() => setTimeout(() => setShowOfficeSuggestions(false), 200)}
              className="h-9"
              aria-label="Office label for template"
            />
            {showOfficeSuggestions && filteredOffices.length > 0 && (
              <div className="absolute z-10 w-full mt-1 bg-popover border rounded-md shadow-md max-h-32 overflow-y-auto">
                {filteredOffices.map((office) => (
                  <button
                    key={office}
                    type="button"
                    className="w-full text-left px-3 py-1.5 text-sm hover:bg-accent transition-colors"
                    onMouseDown={() => {
                      setOfficeLabel(office);
                      setShowOfficeSuggestions(false);
                    }}
                  >
                    {office}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Role Label */}
          <div className="space-y-2 relative">
            <Label htmlFor="role-label" className="flex items-center gap-1.5 text-sm">
              <User className="size-3.5" />
              Role
            </Label>
            <Input
              id="role-label"
              placeholder="e.g., Flight Chief, Section Lead, NCOIC"
              value={roleLabel}
              onChange={(e) => setRoleLabel(e.target.value)}
              onFocus={() => setShowRoleSuggestions(true)}
              onBlur={() => setTimeout(() => setShowRoleSuggestions(false), 200)}
              className="h-9"
              aria-label="Role label for template"
            />
            {showRoleSuggestions && filteredRoles.length > 0 && (
              <div className="absolute z-10 w-full mt-1 bg-popover border rounded-md shadow-md max-h-32 overflow-y-auto">
                {filteredRoles.map((role) => (
                  <button
                    key={role}
                    type="button"
                    className="w-full text-left px-3 py-1.5 text-sm hover:bg-accent transition-colors"
                    onMouseDown={() => {
                      setRoleLabel(role);
                      setShowRoleSuggestions(false);
                    }}
                  >
                    {role}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Rank Label */}
          <div className="space-y-2 relative">
            <Label htmlFor="rank-label" className="flex items-center gap-1.5 text-sm">
              <Star className="size-3.5" />
              Rank
            </Label>
            <Input
              id="rank-label"
              placeholder="e.g., TSgt, MSgt, SrA-SSgt"
              value={rankLabel}
              onChange={(e) => setRankLabel(e.target.value)}
              onFocus={() => setShowRankSuggestions(true)}
              onBlur={() => setTimeout(() => setShowRankSuggestions(false), 200)}
              className="h-9"
              aria-label="Rank label for template"
            />
            {showRankSuggestions && filteredRanks.length > 0 && (
              <div className="absolute z-10 w-full mt-1 bg-popover border rounded-md shadow-md max-h-32 overflow-y-auto">
                {filteredRanks.map((rank) => (
                  <button
                    key={rank}
                    type="button"
                    className="w-full text-left px-3 py-1.5 text-sm hover:bg-accent transition-colors"
                    onMouseDown={() => {
                      setRankLabel(rank);
                      setShowRankSuggestions(false);
                    }}
                  >
                    {rank}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Note */}
          <div className="space-y-2">
            <Label htmlFor="template-note" className="text-sm">
              Note (optional)
            </Label>
            <Textarea
              id="template-note"
              placeholder="Add a note about when to use this template..."
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
              className="resize-none"
              aria-label="Optional note about this template"
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={handleClose} disabled={isSaving}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={isSaving}>
            {isSaving ? (
              <>
                <Loader2 className="size-4 mr-2 animate-spin" />
                Saving...
              </>
            ) : (
              <>
                <Save className="size-4 mr-2" />
                Save Template
              </>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

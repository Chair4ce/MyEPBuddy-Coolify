"use client";

import { useState, useEffect } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { FolderKanban } from "lucide-react";

const STORAGE_KEY = "projects-info-seen";

interface ProjectsInfoModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function ProjectsInfoModal({ open, onOpenChange }: ProjectsInfoModalProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-full max-w-4xl max-h-[85vh] overflow-y-auto p-6 sm:p-8">
        <DialogHeader className="space-y-3">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-lg bg-primary/10">
              <FolderKanban className="size-6 text-primary" />
            </div>
            <div>
              <DialogTitle className="text-xl sm:text-2xl">Introducing Projects</DialogTitle>
              <DialogDescription className="text-sm">
                Share context across your team for better EPB statements
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <div className="mt-6 space-y-6 text-sm leading-relaxed">
          {/* What are Projects */}
          <section>
            <h3 className="font-semibold text-base mb-2">What are Projects?</h3>
            <p className="text-muted-foreground">
              Projects let you define the <strong>results</strong>, <strong>impact</strong>, and 
              <strong> key stakeholders</strong> for a major initiative once — then everyone assigned 
              can use this information when generating their EPB statements. No more repeating the 
              same context for each team member.
            </p>
          </section>

          {/* How it works - simplified */}
          <section>
            <h3 className="font-semibold text-base mb-3">How it Works</h3>
            <ol className="space-y-2 text-muted-foreground list-decimal list-inside">
              <li>
                <strong className="text-foreground">Create a project</strong> — give it a name, description, 
                and add the results/impact when known
              </li>
              <li>
                <strong className="text-foreground">Assign team members</strong> — add anyone from your 
                chain of command who contributed
              </li>
              <li>
                <strong className="text-foreground">Link accomplishments</strong> — in the Entries page, 
                members associate their entries with the project
              </li>
              <li>
                <strong className="text-foreground">Generate enhanced statements</strong> — the AI 
                automatically incorporates project context into EPB statements
              </li>
            </ol>
          </section>

          {/* Key benefits - compact grid */}
          <section>
            <h3 className="font-semibold text-base mb-3">Key Benefits</h3>
            <div className="grid sm:grid-cols-2 gap-4">
              <div>
                <p className="font-medium">Shared Context</p>
                <p className="text-muted-foreground text-xs mt-0.5">
                  Define results and impact once, used by everyone on the project
                </p>
              </div>
              <div>
                <p className="font-medium">Better Statements</p>
                <p className="text-muted-foreground text-xs mt-0.5">
                  AI connects individual contributions to broader outcomes
                </p>
              </div>
              <div>
                <p className="font-medium">Team Visibility</p>
                <p className="text-muted-foreground text-xs mt-0.5">
                  All members can see project details and who&apos;s assigned
                </p>
              </div>
              <div>
                <p className="font-medium">Leadership Framing</p>
                <p className="text-muted-foreground text-xs mt-0.5">
                  Supervisors get statements that reflect leading the team&apos;s work
                </p>
              </div>
            </div>
          </section>

          {/* Quick tips - inline */}
          <section className="bg-muted/50 rounded-lg p-4">
            <h3 className="font-semibold text-base mb-2">Quick Tips</h3>
            <ul className="text-muted-foreground text-xs space-y-1.5">
              <li>• Click a project to highlight its members in the supervision tree</li>
              <li>• Use &quot;Assign Members&quot; to quickly add people by clicking them in the tree</li>
              <li>• Add detailed results and impact for the best AI-generated statements</li>
            </ul>
          </section>
        </div>

        <DialogFooter className="mt-6">
          <Button onClick={() => onOpenChange(false)} className="w-full sm:w-auto">
            Got it
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// Hook to manage the one-time display logic
export function useProjectsInfoModal() {
  const [showModal, setShowModal] = useState(false);
  const [hasSeenInfo, setHasSeenInfo] = useState(true); // Default to true to prevent flash

  useEffect(() => {
    const seen = localStorage.getItem(STORAGE_KEY);
    setHasSeenInfo(seen === "true");
  }, []);

  const openModal = () => setShowModal(true);
  
  const closeModal = () => {
    setShowModal(false);
    localStorage.setItem(STORAGE_KEY, "true");
    setHasSeenInfo(true);
  };

  const triggerFirstTimeModal = () => {
    if (!hasSeenInfo) {
      setShowModal(true);
    }
  };

  return {
    showModal,
    openModal,
    closeModal,
    onOpenChange: (open: boolean) => {
      if (!open) closeModal();
      else setShowModal(true);
    },
    hasSeenInfo,
    triggerFirstTimeModal,
  };
}

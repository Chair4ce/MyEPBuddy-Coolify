"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { useUserStore } from "@/stores/user-store";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { toast } from "@/components/ui/sonner";
import { Loader2, Shield, Plus, X, AlertTriangle } from "lucide-react";
import type { EPBConfig, MajorGradedArea } from "@/types/database";

export default function AdminConfigPage() {
  const { profile, epbConfig, setEpbConfig } = useUserStore();
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [config, setConfig] = useState<EPBConfig | null>(null);
  const [newMPAKey, setNewMPAKey] = useState("");
  const [newMPALabel, setNewMPALabel] = useState("");

  const supabase = createClient();

  // Check admin access
  useEffect(() => {
    if (profile && profile.role !== "admin") {
      toast.error("Access denied. Admin only.");
      router.push("/dashboard");
    }
  }, [profile, router]);

  // Load config
  useEffect(() => {
    async function loadConfig() {
      const { data, error } = await supabase
        .from("epb_config")
        .select("*")
        .eq("id", 1)
        .single();

      if (!error && data) {
        setConfig(data);
      }
      setIsLoading(false);
    }

    loadConfig();
  }, [supabase]);

  async function handleSave() {
    if (!config) return;
    setIsSaving(true);

    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from("epb_config")
        .update({
          max_characters_per_statement: config.max_characters_per_statement,
          scod_date: config.scod_date,
          current_cycle_year: config.current_cycle_year,
          major_graded_areas: config.major_graded_areas,
          style_guidelines: config.style_guidelines,
          rank_verb_progression: config.rank_verb_progression,
          base_system_prompt: config.base_system_prompt,
        })
        .eq("id", 1)
        .select()
        .single();

      if (error) {
        toast.error(error.message);
        return;
      }

      if (data) {
        setConfig(data);
        setEpbConfig(data);
        toast.success("Configuration saved successfully");
      }
    } catch {
      toast.error("Failed to save configuration");
    } finally {
      setIsSaving(false);
    }
  }

  function addMPA() {
    if (!config || !newMPAKey || !newMPALabel) return;

    const newMPA: MajorGradedArea = {
      key: newMPAKey.toLowerCase().replace(/\s+/g, "_"),
      label: newMPALabel,
    };

    setConfig({
      ...config,
      major_graded_areas: [...(config.major_graded_areas as MajorGradedArea[]), newMPA],
    });

    setNewMPAKey("");
    setNewMPALabel("");
  }

  function removeMPA(key: string) {
    if (!config) return;

    setConfig({
      ...config,
      major_graded_areas: (config.major_graded_areas as MajorGradedArea[]).filter(
        (m) => m.key !== key
      ),
    });
  }

  if (profile?.role !== "admin") {
    return (
      <div className="flex flex-col items-center justify-center py-12">
        <AlertTriangle className="size-12 text-destructive mb-4" />
        <h2 className="text-xl font-semibold mb-2">Access Denied</h2>
        <p className="text-muted-foreground">
          This page is only accessible to administrators.
        </p>
      </div>
    );
  }

  if (isLoading || !config) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="size-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
            <Shield className="size-6" />
            Admin Configuration
          </h1>
          <p className="text-muted-foreground">
            Manage global EPB settings and AI prompt configuration
          </p>
        </div>
        <Button onClick={handleSave} disabled={isSaving}>
          {isSaving ? (
            <>
              <Loader2 className="size-4 animate-spin mr-2" />
              Saving...
            </>
          ) : (
            "Save Changes"
          )}
        </Button>
      </div>

      {/* Basic Settings */}
      <Card>
        <CardHeader>
          <CardTitle>Basic Settings</CardTitle>
          <CardDescription>
            Core EPB configuration parameters
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-3">
            <div className="space-y-2">
              <Label htmlFor="max_chars">Max Characters per Statement</Label>
              <Input
                id="max_chars"
                type="number"
                value={config.max_characters_per_statement}
                onChange={(e) =>
                  setConfig({
                    ...config,
                    max_characters_per_statement: parseInt(e.target.value) || 350,
                  })
                }
                min={100}
                max={500}
                aria-label="Maximum characters per statement"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="scod_date">SCOD Date</Label>
              <Input
                id="scod_date"
                value={config.scod_date}
                onChange={(e) =>
                  setConfig({ ...config, scod_date: e.target.value })
                }
                placeholder="31 Mar"
                aria-label="Static closeout date"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="cycle_year">Current Cycle Year</Label>
              <Input
                id="cycle_year"
                type="number"
                value={config.current_cycle_year}
                onChange={(e) =>
                  setConfig({
                    ...config,
                    current_cycle_year:
                      parseInt(e.target.value) || new Date().getFullYear(),
                  })
                }
                min={2020}
                max={2099}
                aria-label="Current evaluation cycle year"
              />
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Major Performance Areas */}
      <Card>
        <CardHeader>
          <CardTitle>Major Performance Areas (MPAs)</CardTitle>
          <CardDescription>
            Configure the graded areas for EPB statements
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex flex-wrap gap-2">
            {(config.major_graded_areas as MajorGradedArea[]).map((mpa) => (
              <Badge
                key={mpa.key}
                variant="secondary"
                className="text-sm py-1.5 px-3 gap-2"
              >
                {mpa.label}
                <button
                  type="button"
                  onClick={() => removeMPA(mpa.key)}
                  className="hover:text-destructive transition-colors"
                  aria-label={`Remove ${mpa.label}`}
                >
                  <X className="size-3" />
                </button>
              </Badge>
            ))}
          </div>

          <Separator />

          <div className="flex gap-2 items-end">
            <div className="space-y-2 flex-1">
              <Label htmlFor="new_mpa_key">Key</Label>
              <Input
                id="new_mpa_key"
                value={newMPAKey}
                onChange={(e) => setNewMPAKey(e.target.value)}
                placeholder="e.g., leadership"
                aria-label="New MPA key"
              />
            </div>
            <div className="space-y-2 flex-1">
              <Label htmlFor="new_mpa_label">Label</Label>
              <Input
                id="new_mpa_label"
                value={newMPALabel}
                onChange={(e) => setNewMPALabel(e.target.value)}
                placeholder="e.g., Leadership Excellence"
                aria-label="New MPA label"
              />
            </div>
            <Button
              type="button"
              variant="outline"
              onClick={addMPA}
              disabled={!newMPAKey || !newMPALabel}
            >
              <Plus className="size-4 mr-2" />
              Add
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Style Guidelines */}
      <Card>
        <CardHeader>
          <CardTitle>Style Guidelines</CardTitle>
          <CardDescription>
            Writing guidelines included in AI prompts
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Textarea
            value={config.style_guidelines}
            onChange={(e) =>
              setConfig({ ...config, style_guidelines: e.target.value })
            }
            rows={4}
            placeholder="Enter style guidelines for EPB writing..."
            aria-label="Style guidelines"
          />
        </CardContent>
      </Card>

      {/* System Prompt */}
      <Card>
        <CardHeader>
          <CardTitle>Base System Prompt</CardTitle>
          <CardDescription>
            The AI system prompt template. Use placeholders:{" "}
            <code className="text-xs bg-muted px-1 py-0.5 rounded">
              {"{{max_characters_per_statement}}"}
            </code>
            ,{" "}
            <code className="text-xs bg-muted px-1 py-0.5 rounded">
              {"{{ratee_rank}}"}
            </code>
            ,{" "}
            <code className="text-xs bg-muted px-1 py-0.5 rounded">
              {"{{primary_verbs}}"}
            </code>
            ,{" "}
            <code className="text-xs bg-muted px-1 py-0.5 rounded">
              {"{{style_guidelines}}"}
            </code>
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Textarea
            value={config.base_system_prompt}
            onChange={(e) =>
              setConfig({ ...config, base_system_prompt: e.target.value })
            }
            rows={12}
            className="font-mono text-sm"
            placeholder="Enter the base system prompt..."
            aria-label="Base system prompt"
          />
        </CardContent>
      </Card>

      {/* Rank Verb Progression */}
      <Card>
        <CardHeader>
          <CardTitle>Rank Verb Progression</CardTitle>
          <CardDescription>
            Action verbs appropriate for each rank level (JSON format)
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Textarea
            value={JSON.stringify(config.rank_verb_progression, null, 2)}
            onChange={(e) => {
              try {
                const parsed = JSON.parse(e.target.value);
                setConfig({ ...config, rank_verb_progression: parsed });
              } catch {
                // Invalid JSON, don't update
              }
            }}
            rows={20}
            className="font-mono text-sm"
            placeholder="Enter rank verb progression JSON..."
            aria-label="Rank verb progression"
          />
        </CardContent>
      </Card>

      <div className="flex justify-end">
        <Button onClick={handleSave} disabled={isSaving} size="lg">
          {isSaving ? (
            <>
              <Loader2 className="size-4 animate-spin mr-2" />
              Saving Configuration...
            </>
          ) : (
            "Save All Changes"
          )}
        </Button>
      </div>
    </div>
  );
}


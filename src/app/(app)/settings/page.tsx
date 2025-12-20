"use client";

import { useState, useEffect } from "react";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "@/components/ui/sonner";
import { RANKS } from "@/lib/constants";
import { Loader2, User } from "lucide-react";
import type { Rank, Profile } from "@/types/database";

export default function SettingsPage() {
  const { profile, setProfile } = useUserStore();
  const [isLoading, setIsLoading] = useState(false);
  const [form, setForm] = useState({
    full_name: "",
    rank: "" as Rank | "",
    afsc: "",
    unit: "",
  });

  const supabase = createClient();

  useEffect(() => {
    if (profile) {
      setForm({
        full_name: profile.full_name || "",
        rank: profile.rank || "",
        afsc: profile.afsc || "",
        unit: profile.unit || "",
      });
    }
  }, [profile]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setIsLoading(true);

    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from("profiles")
        .update({
          full_name: form.full_name,
          rank: form.rank || null,
          afsc: form.afsc || null,
          unit: form.unit || null,
        })
        .eq("id", profile?.id)
        .select()
        .single();

      if (error) {
        toast.error(error.message);
        return;
      }

      setProfile(data as Profile);
      toast.success("Profile updated successfully");
    } catch {
      toast.error("Failed to update profile");
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Profile Settings</h1>
        <p className="text-muted-foreground">
          Manage your personal information and preferences
        </p>
      </div>

      <Card>
        <CardHeader>
          <div className="flex items-center gap-3">
            <div className="size-10 rounded-full bg-primary/10 flex items-center justify-center">
              <User className="size-5 text-primary" />
            </div>
            <div>
              <CardTitle>Personal Information</CardTitle>
              <CardDescription>
                Update your profile details used across the app
              </CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={profile?.email || ""}
                disabled
                className="bg-muted"
                aria-label="Email (read-only)"
              />
              <p className="text-xs text-muted-foreground">
                Email cannot be changed
              </p>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="full_name">Full Name</Label>
                <Input
                  id="full_name"
                  value={form.full_name}
                  onChange={(e) =>
                    setForm({ ...form, full_name: e.target.value })
                  }
                  placeholder="John Doe"
                  aria-label="Full name"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="rank">Rank</Label>
                <Select
                  value={form.rank}
                  onValueChange={(value) =>
                    setForm({ ...form, rank: value as Rank })
                  }
                >
                  <SelectTrigger id="rank" aria-label="Select rank">
                    <SelectValue placeholder="Select rank" />
                  </SelectTrigger>
                  <SelectContent>
                    {RANKS.map((r) => (
                      <SelectItem key={r.value} value={r.value}>
                        {r.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="afsc">AFSC</Label>
                <Input
                  id="afsc"
                  value={form.afsc}
                  onChange={(e) =>
                    setForm({ ...form, afsc: e.target.value.toUpperCase() })
                  }
                  placeholder="1N0X1"
                  aria-label="Air Force Specialty Code"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="unit">Unit</Label>
                <Input
                  id="unit"
                  value={form.unit}
                  onChange={(e) => setForm({ ...form, unit: e.target.value })}
                  placeholder="25 IS"
                  aria-label="Unit"
                />
              </div>
            </div>

            <div className="flex justify-end">
              <Button type="submit" disabled={isLoading}>
                {isLoading ? (
                  <>
                    <Loader2 className="size-4 animate-spin mr-2" />
                    Saving...
                  </>
                ) : (
                  "Save Changes"
                )}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Account Role</CardTitle>
          <CardDescription>
            Your account type and team relationships
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center gap-3">
            <div
              className={`px-3 py-1.5 rounded-full text-sm font-medium ${
                profile?.role === "admin"
                  ? "bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300"
                  : "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300"
              }`}
            >
              {profile?.role === "admin" ? "Administrator" : "Member"}
            </div>
          </div>
          <p className="text-sm text-muted-foreground mt-3">
            Team relationships determine who you can supervise and who supervises you. 
            Visit the Team page to manage your supervision relationships.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}


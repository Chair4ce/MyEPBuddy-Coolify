"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { Accomplishment } from "@/types/database";

export async function createAccomplishment(
  data: Omit<Accomplishment, "id" | "created_at" | "updated_at">
) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Not authenticated" };
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: accomplishment, error } = await (supabase as any)
    .from("accomplishments")
    .insert({
      ...data,
      created_by: data.created_by || user.id,
    })
    .select()
    .single();

  if (error) {
    console.error("Create accomplishment error:", error);
    return { error: error.message };
  }

  revalidatePath("/entries");
  revalidatePath("/dashboard");
  return { data: accomplishment as Accomplishment };
}

export async function updateAccomplishment(
  id: string,
  data: Partial<Omit<Accomplishment, "id" | "created_at" | "updated_at">>
) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Not authenticated" };
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: accomplishment, error } = await (supabase as any)
    .from("accomplishments")
    .update(data)
    .eq("id", id)
    .select()
    .single();

  if (error) {
    console.error("Update accomplishment error:", error);
    return { error: error.message };
  }

  revalidatePath("/entries");
  revalidatePath("/dashboard");
  return { data: accomplishment as Accomplishment };
}

export async function deleteAccomplishment(id: string) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Not authenticated" };
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { error } = await (supabase as any)
    .from("accomplishments")
    .delete()
    .eq("id", id);

  if (error) {
    console.error("Delete accomplishment error:", error);
    return { error: error.message };
  }

  revalidatePath("/entries");
  revalidatePath("/dashboard");
  return { success: true };
}

export async function getAccomplishments(
  userId: string,
  cycleYear: number
) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("accomplishments")
    .select("*")
    .eq("user_id", userId)
    .eq("cycle_year", cycleYear)
    .order("date", { ascending: false });

  if (error) {
    console.error("Get accomplishments error:", error);
    return { error: error.message };
  }

  return { data: data as unknown as Accomplishment[] };
}

export async function getAccomplishmentsByMPA(
  userId: string,
  cycleYear: number,
  mpa: string
) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("accomplishments")
    .select("*")
    .eq("user_id", userId)
    .eq("cycle_year", cycleYear)
    .eq("mpa", mpa)
    .order("date", { ascending: false });

  if (error) {
    console.error("Get accomplishments by MPA error:", error);
    return { error: error.message };
  }

  return { data: data as unknown as Accomplishment[] };
}

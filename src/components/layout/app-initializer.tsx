"use client";

import { useEffect } from "react";
import { useUserStore } from "@/stores/user-store";
import type { Profile, EPBConfig } from "@/types/database";

interface AppInitializerProps {
  profile: Profile | null;
  subordinates: Profile[];
  epbConfig: EPBConfig | null;
  children: React.ReactNode;
}

export function AppInitializer({
  profile,
  subordinates,
  epbConfig,
  children,
}: AppInitializerProps) {
  const { setProfile, setSubordinates, setEpbConfig, setIsLoading } =
    useUserStore();

  useEffect(() => {
    setProfile(profile);
    setSubordinates(subordinates);
    setEpbConfig(epbConfig);
    setIsLoading(false);
  }, [profile, subordinates, epbConfig, setProfile, setSubordinates, setEpbConfig, setIsLoading]);

  return <>{children}</>;
}


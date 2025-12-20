import { create } from "zustand";
import type { Profile, EPBConfig } from "@/types/database";

interface UserState {
  profile: Profile | null;
  subordinates: Profile[];
  epbConfig: EPBConfig | null;
  isLoading: boolean;
  setProfile: (profile: Profile | null) => void;
  setSubordinates: (subordinates: Profile[]) => void;
  setEpbConfig: (config: EPBConfig | null) => void;
  setIsLoading: (loading: boolean) => void;
  reset: () => void;
}

export const useUserStore = create<UserState>((set) => ({
  profile: null,
  subordinates: [],
  epbConfig: null,
  isLoading: true,
  setProfile: (profile) => set({ profile }),
  setSubordinates: (subordinates) => set({ subordinates }),
  setEpbConfig: (epbConfig) => set({ epbConfig }),
  setIsLoading: (isLoading) => set({ isLoading }),
  reset: () =>
    set({
      profile: null,
      subordinates: [],
      epbConfig: null,
      isLoading: true,
    }),
}));


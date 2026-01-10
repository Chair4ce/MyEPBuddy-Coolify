import { create } from "zustand";
import type { OPBShell, OPBShellSection, OPBShellSnapshot, Rank } from "@/types/database";

// MPA workspace mode for each section
export type OPBWorkspaceMode = "view" | "edit" | "ai-assist";

// Source type for statement generation
// OPB uses custom context focus (officer-focused narrative)
// "opb-summary" is HLR-only: uses all MPA statements to generate holistic assessment
export type OPBSourceType = "custom" | "opb-summary";

// Local state for each MPA section (not persisted to DB)
export interface OPBSectionState {
  mode: OPBWorkspaceMode;
  draftText: string;
  isDirty: boolean;
  isGenerating: boolean;
  isRevising: boolean;
  isSaving: boolean;
  showHistory: boolean;
  
  // Source toggle (officers primarily use custom context)
  sourceType: OPBSourceType;
  
  // For two-statement generation
  usesTwoStatements: boolean;
  statement1Context: string; // Custom context for statement 1
  statement2Context: string; // Custom context for statement 2
}

// Officer info for the current user
export interface OfficerInfo {
  id: string;
  fullName: string | null;
  rank: Rank | null;
  afsc: string | null;
}

interface OPBShellState {
  // Current officer info (from profile)
  officerInfo: OfficerInfo | null;
  
  // The loaded OPB shell for the current cycle
  currentShell: OPBShell | null;
  
  // Sections indexed by MPA key for quick access
  sections: Record<string, OPBShellSection>;
  
  // Snapshots indexed by section ID
  snapshots: Record<string, OPBShellSnapshot[]>;
  
  // Local UI state for each MPA section
  sectionStates: Record<string, OPBSectionState>;
  
  // Collapsed state for each MPA section
  collapsedSections: Record<string, boolean>;
  
  // Split view state for each MPA section (shows S1/S2 separately)
  splitViewSections: Record<string, boolean>;
  
  // Duty description draft state
  dutyDescriptionDraft: string;
  isDutyDescriptionDirty: boolean;
  isSavingDutyDescription: boolean;
  
  // Loading states
  isLoadingShell: boolean;
  isCreatingShell: boolean;
  
  // Version counter - increments each time to force component remounts
  loadVersion: number;
  
  // Autosave debounce tracking
  autosaveTimers: Record<string, NodeJS.Timeout | null>;
  
  // Actions
  setOfficerInfo: (officer: OfficerInfo | null) => void;
  setCurrentShell: (shell: OPBShell | null) => void;
  setSections: (sections: OPBShellSection[]) => void;
  updateSection: (mpa: string, updates: Partial<OPBShellSection>) => void;
  setSnapshots: (sectionId: string, snapshots: OPBShellSnapshot[]) => void;
  addSnapshot: (sectionId: string, snapshot: OPBShellSnapshot) => void;
  
  // Section state management
  getSectionState: (mpa: string) => OPBSectionState;
  updateSectionState: (mpa: string, updates: Partial<OPBSectionState>) => void;
  initializeSectionState: (mpa: string, currentText: string) => void;
  resetSectionState: (mpa: string) => void;
  
  // Collapsed state management
  toggleSectionCollapsed: (mpa: string) => void;
  setSectionCollapsed: (mpa: string, collapsed: boolean) => void;
  setAllCollapsedSections: (collapsedSections: Record<string, boolean>) => void;
  expandAll: () => void;
  collapseAll: () => void;
  
  // Split view management
  toggleSplitView: (mpa: string) => void;
  setSplitView: (mpa: string, enabled: boolean) => void;
  setAllSplitView: (enabled: boolean) => void;
  
  // Loading states
  setIsLoadingShell: (loading: boolean) => void;
  setIsCreatingShell: (creating: boolean) => void;
  
  // Autosave management
  setAutosaveTimer: (mpa: string, timer: NodeJS.Timeout | null) => void;
  clearAutosaveTimer: (mpa: string) => void;
  
  // Duty description management
  setDutyDescriptionDraft: (text: string) => void;
  setIsDutyDescriptionDirty: (dirty: boolean) => void;
  setIsSavingDutyDescription: (saving: boolean) => void;
  
  // Reset
  reset: () => void;
}

const getDefaultSectionState = (): OPBSectionState => ({
  mode: "view",
  draftText: "",
  isDirty: false,
  isGenerating: false,
  isRevising: false,
  isSaving: false,
  showHistory: false,
  
  // Officers primarily use custom context
  sourceType: "custom",
  
  // Two-statement mode
  usesTwoStatements: false,
  statement1Context: "",
  statement2Context: "",
});

export const useOPBShellStore = create<OPBShellState>((set, get) => ({
  officerInfo: null,
  currentShell: null,
  sections: {},
  snapshots: {},
  sectionStates: {},
  collapsedSections: {},
  splitViewSections: {},
  dutyDescriptionDraft: "",
  isDutyDescriptionDirty: false,
  isSavingDutyDescription: false,
  isLoadingShell: false,
  isCreatingShell: false,
  loadVersion: 0,
  autosaveTimers: {},

  setOfficerInfo: (officer) => {
    // Clear autosave timers when switching
    const timers = get().autosaveTimers;
    Object.values(timers).forEach((timer) => {
      if (timer) clearTimeout(timer);
    });

    // Reset all state and increment loadVersion
    set((state) => ({
      officerInfo: officer,
      currentShell: null,
      sections: {},
      sectionStates: {},
      splitViewSections: {},
      snapshots: {},
      autosaveTimers: {},
      dutyDescriptionDraft: "",
      isDutyDescriptionDirty: false,
      loadVersion: state.loadVersion + 1,
    }));
  },
  
  setCurrentShell: (shell) => {
    set({ currentShell: shell });
    // Initialize sections from shell
    if (shell?.sections) {
      const sectionsMap: Record<string, OPBShellSection> = {};
      shell.sections.forEach((s) => {
        sectionsMap[s.mpa] = s;
      });
      set({ sections: sectionsMap });
    } else {
      set({ sections: {} });
    }
    // Initialize duty description from shell
    set({ 
      dutyDescriptionDraft: shell?.duty_description || "",
      isDutyDescriptionDirty: false,
    });
  },

  setSections: (sections) => {
    const sectionsMap: Record<string, OPBShellSection> = {};
    sections.forEach((s) => {
      sectionsMap[s.mpa] = s;
    });
    set({ sections: sectionsMap });
  },

  updateSection: (mpa, updates) =>
    set((state) => ({
      sections: {
        ...state.sections,
        [mpa]: state.sections[mpa]
          ? { ...state.sections[mpa], ...updates }
          : { ...updates, mpa } as OPBShellSection,
      },
    })),

  setSnapshots: (sectionId, snapshots) =>
    set((state) => ({
      snapshots: {
        ...state.snapshots,
        [sectionId]: snapshots,
      },
    })),

  addSnapshot: (sectionId, snapshot) =>
    set((state) => ({
      snapshots: {
        ...state.snapshots,
        [sectionId]: [snapshot, ...(state.snapshots[sectionId] || [])],
      },
    })),

  getSectionState: (mpa) => {
    const state = get().sectionStates[mpa];
    return state || getDefaultSectionState();
  },

  updateSectionState: (mpa, updates) =>
    set((state) => ({
      sectionStates: {
        ...state.sectionStates,
        [mpa]: {
          ...(state.sectionStates[mpa] || getDefaultSectionState()),
          ...updates,
        },
      },
    })),

  initializeSectionState: (mpa, currentText) =>
    set((state) => ({
      sectionStates: {
        ...state.sectionStates,
        [mpa]: {
          ...getDefaultSectionState(),
          draftText: currentText,
        },
      },
    })),

  resetSectionState: (mpa) =>
    set((state) => {
      const currentText = state.sections[mpa]?.statement_text || "";
      return {
        sectionStates: {
          ...state.sectionStates,
          [mpa]: {
            ...getDefaultSectionState(),
            draftText: currentText,
          },
        },
      };
    }),

  toggleSectionCollapsed: (mpa) =>
    set((state) => ({
      collapsedSections: {
        ...state.collapsedSections,
        [mpa]: !state.collapsedSections[mpa],
      },
    })),

  setSectionCollapsed: (mpa, collapsed) =>
    set((state) => ({
      collapsedSections: {
        ...state.collapsedSections,
        [mpa]: collapsed,
      },
    })),

  expandAll: () => set({ collapsedSections: {} }),
  
  toggleSplitView: (mpa) =>
    set((state) => ({
      splitViewSections: {
        ...state.splitViewSections,
        [mpa]: !state.splitViewSections[mpa],
      },
    })),
    
  setSplitView: (mpa, enabled) =>
    set((state) => ({
      splitViewSections: {
        ...state.splitViewSections,
        [mpa]: enabled,
      },
    })),
    
  setAllSplitView: (enabled) =>
    set((state) => {
      const splitViewSections: Record<string, boolean> = {};
      Object.keys(state.sections).forEach((mpa) => {
        splitViewSections[mpa] = enabled;
      });
      return { splitViewSections };
    }),

  collapseAll: () =>
    set((state) => {
      const collapsed: Record<string, boolean> = {};
      Object.keys(state.sections).forEach((mpa) => {
        collapsed[mpa] = true;
      });
      return { collapsedSections: collapsed };
    }),

  setAllCollapsedSections: (collapsedSections) =>
    set({ collapsedSections }),

  setIsLoadingShell: (loading) => set({ isLoadingShell: loading }),
  setIsCreatingShell: (creating) => set({ isCreatingShell: creating }),

  setAutosaveTimer: (mpa, timer) =>
    set((state) => ({
      autosaveTimers: {
        ...state.autosaveTimers,
        [mpa]: timer,
      },
    })),

  clearAutosaveTimer: (mpa) => {
    const timer = get().autosaveTimers[mpa];
    if (timer) {
      clearTimeout(timer);
    }
    set((state) => ({
      autosaveTimers: {
        ...state.autosaveTimers,
        [mpa]: null,
      },
    }));
  },

  // Duty description management
  setDutyDescriptionDraft: (text) => set({ 
    dutyDescriptionDraft: text,
    isDutyDescriptionDirty: text !== (get().currentShell?.duty_description || ""),
  }),
  
  setIsDutyDescriptionDirty: (dirty) => set({ isDutyDescriptionDirty: dirty }),
  
  setIsSavingDutyDescription: (saving) => set({ isSavingDutyDescription: saving }),

  reset: () => {
    // Clear all autosave timers
    const timers = get().autosaveTimers;
    Object.values(timers).forEach((timer) => {
      if (timer) clearTimeout(timer);
    });

    set((state) => ({
      officerInfo: null,
      currentShell: null,
      sections: {},
      snapshots: {},
      sectionStates: {},
      collapsedSections: {},
      splitViewSections: {},
      dutyDescriptionDraft: "",
      isDutyDescriptionDirty: false,
      isSavingDutyDescription: false,
      isLoadingShell: false,
      isCreatingShell: false,
      loadVersion: state.loadVersion + 1,
      autosaveTimers: {},
    }));
  },
}));

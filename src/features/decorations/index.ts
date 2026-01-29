/**
 * Decoration Citations Feature
 * 
 * AI-powered Air Force decoration citation generator.
 * Based on DAFMAN 36-2806 and MyDecs Reimagined (Oct 2022+).
 */

// Types
export type {
  DecorationAwardType,
  DecorationReason,
  DecorationConfig,
  DecorationPromptParams,
  DecorationReasonOption,
  ClosingIntensity,
  RankVerbs,
  GenerateDecorationRequest,
  GenerateDecorationResponse,
} from "./types";

// Constants
export {
  DECORATION_TYPES,
  DECORATION_REASONS,
  RANK_VERBS,
  ABBREVIATIONS_TO_EXPAND,
  getVerbCategory,
} from "./constants";

// Prompts
export {
  buildDecorationSystemPrompt,
  expandAbbreviations,
} from "./prompts";

export interface Abbreviation {
  word: string;
  abbreviation: string;
}

// Common Air Force abbreviations that vary by AFSC
// Users can customize these based on their career field
export const DEFAULT_ABBREVIATIONS: Abbreviation[] = [
  { word: "maintenance", abbreviation: "maint" },
  { word: "equipment", abbreviation: "equip" },
  { word: "operational", abbreviation: "ops" },
  { word: "operations", abbreviation: "ops" },
  { word: "administration", abbreviation: "admin" },
  { word: "administrative", abbreviation: "admin" },
  { word: "communications", abbreviation: "comm" },
  { word: "communication", abbreviation: "comm" },
  { word: "information", abbreviation: "info" },
  { word: "management", abbreviation: "mgmt" },
  { word: "requirements", abbreviation: "reqs" },
  { word: "requirement", abbreviation: "req" },
  { word: "training", abbreviation: "trng" },
  { word: "personnel", abbreviation: "pers" },
  { word: "organization", abbreviation: "org" },
  { word: "organizational", abbreviation: "org" },
  { word: "development", abbreviation: "dev" },
  { word: "evaluation", abbreviation: "eval" },
  { word: "squadron", abbreviation: "sq" },
  { word: "headquarters", abbreviation: "HQ" },
  { word: "commander", abbreviation: "CC" },
  { word: "superintendent", abbreviation: "supt" },
  { word: "supervisor", abbreviation: "supv" },
  { word: "technical", abbreviation: "tech" },
  { word: "intelligence", abbreviation: "intel" },
  { word: "reconnaissance", abbreviation: "recce" },
  { word: "surveillance", abbreviation: "surv" },
  { word: "aircraft", abbreviation: "acft" },
  { word: "mission", abbreviation: "msn" },
  { word: "configuration", abbreviation: "config" },
  { word: "documentation", abbreviation: "docs" },
  { word: "specification", abbreviation: "spec" },
  { word: "specifications", abbreviation: "specs" },
  { word: "authorization", abbreviation: "auth" },
  { word: "certification", abbreviation: "cert" },
  { word: "qualification", abbreviation: "qual" },
  { word: "qualification", abbreviation: "qual" },
];

export function formatAbbreviationsList(abbreviations: Abbreviation[]): string {
  return abbreviations
    .map((a) => `"${a.word}" → "${a.abbreviation}"`)
    .join("\n");
}


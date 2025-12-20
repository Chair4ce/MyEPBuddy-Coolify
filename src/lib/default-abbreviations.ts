export interface Abbreviation {
  word: string;
  abbreviation: string;
}

// Abbreviations default to empty - users add their own based on their AFSC
// This gives users full control over word shortening preferences
export const DEFAULT_ABBREVIATIONS: Abbreviation[] = [];

export function formatAbbreviationsList(abbreviations: Abbreviation[]): string {
  return abbreviations
    .map((a) => `"${a.word}" → "${a.abbreviation}"`)
    .join("\n");
}


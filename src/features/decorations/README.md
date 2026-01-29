# Decoration Citations Feature

AI-powered Air Force decoration citation generator. Converts EPB accomplishment statements into properly formatted citations for AFAM, AFCM, MSM, LOM, and BSM.

## Format Compliance

Based on **DAFMAN 36-2806** and **MyDecs Reimagined** (October 2022+).

### Key Rules (MyDecs Reimagined)
- **Character limit:** 1350 characters (MSM, AFCM, AFAM)
- **Font:** Courier New 11pt
- **Abbreviations:** Allowed if on DAF approved list
- **Numbers:** 1-9 spelled out, 10+ can be numerals
- **Symbols:** Only $ allowed

## Files

```
src/features/decorations/
├── README.md              # This file
├── constants.ts           # Award configs, reasons, templates
├── prompts.ts             # LLM prompt builder
├── types.ts               # TypeScript interfaces
└── docs/
    ├── RESEARCH.md        # Full research notes
    ├── CITATION_TEMPLATES.md  # Opening/closing sentence templates
    └── EXAMPLES.md        # Real citation examples
```

## API Endpoint

`POST /api/generate-decoration`

### Request
```typescript
{
  rateeId: string;
  rateeRank: string;       // "Staff Sergeant", "Technical Sergeant", etc.
  rateeName: string;       // "John A. Smith"
  rateeGender?: "male" | "female";
  dutyTitle: string;
  unit: string;
  startDate: string;       // "1 January 2024"
  endDate: string;         // "31 December 2025"
  awardType: "afam" | "afcm" | "msm" | "lom" | "bsm";
  reason: DecorationReason;
  accomplishments: string[];
  model: string;
}
```

### Response
```typescript
{
  citation: string;
  metadata: {
    awardType: string;
    awardName: string;
    characterCount: number;
    maxCharacters: number;
    withinLimit: boolean;
    estimatedLines: number;
    model: string;
  }
}
```

## Usage Flow

1. User selects ratee from their supervision tree
2. User picks accomplishment statements from EPB
3. User selects award type and reason
4. System generates citation with proper formatting
5. User copies to MyDecs/AF Form

## Award Types

| Award | Abbrev | Typical Ranks | Character Limit |
|-------|--------|---------------|-----------------|
| Air Force Achievement Medal | AFAM | E-1 to E-6 | 1350 |
| Air Force Commendation Medal | AFCM | E-5 to E-7, O-1 to O-3 | 1350 |
| Meritorious Service Medal | MSM | E-7+, O-4+ | 1350 |
| Legion of Merit | LOM | E-9, O-5+ | 2000 |
| Bronze Star Medal | BSM | Combat | 2000 |

## Reasons

- `meritorious_service` - PCS/extended period
- `outstanding_achievement` - Specific project/operation  
- `act_of_courage` - Non-combat heroism
- `retirement` - End of career
- `separation` - End of service
- `posthumous` - Awarded after death
- `combat_meritorious` - BSM combat service
- `combat_valor` - BSM with V device

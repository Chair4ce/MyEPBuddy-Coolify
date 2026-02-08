import { createClient } from "@/lib/supabase/server";
import { createOpenAI } from "@ai-sdk/openai";
import { createAnthropic } from "@ai-sdk/anthropic";
import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { createXai } from "@ai-sdk/xai";
import { generateText, type LanguageModel } from "ai";
import { NextResponse } from "next/server";
import { getDecryptedApiKeys } from "@/app/actions/api-keys";
import { buildDecorationSystemPrompt, expandAbbreviations } from "@/lib/decoration-prompts";
import type { DecorationAwardType, DecorationReason } from "@/lib/decoration-constants";
import { DECORATION_TYPES } from "@/lib/decoration-constants";
import type { UserLLMSettings } from "@/types/database";
import { scanTextForLLM } from "@/lib/sensitive-data-scanner";

// Allow up to 60s for LLM calls
export const maxDuration = 60;

interface GenerateDecorationRequest {
  // Ratee info
  rateeId: string;
  rateeRank: string;
  rateeName: string;
  rateeGender?: "male" | "female";
  
  // Position info
  dutyTitle: string;
  unit: string;
  startDate: string;
  endDate: string;
  
  // Award info
  awardType: DecorationAwardType;
  reason: DecorationReason;
  /** @deprecated MyDecs Reimagined uses character limits, not line limits */
  fontSize?: 10 | 12;
  
  // Content
  accomplishments: string[];
  
  // AI config
  model: string;
}

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    
    // Verify user is authenticated
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    
    const body: GenerateDecorationRequest = await request.json();
    
    // Validate required fields
    if (!body.rateeRank || !body.rateeName || !body.awardType || !body.accomplishments?.length) {
      return NextResponse.json(
        { error: "Missing required fields" },
        { status: 400 }
      );
    }

    // Scan accomplishment text for PII/CUI/classification markings before sending to LLM
    for (const accomplishment of body.accomplishments) {
      const { blocked, matches } = scanTextForLLM(accomplishment);
      if (blocked) {
        const types = [...new Set(matches.map((m) => m.label))].join(", ");
        return NextResponse.json(
          { error: `Sensitive data detected (${types}). Please remove before generating.` },
          { status: 400 }
        );
      }
    }
    
    // Get decoration config
    const decorationConfig = DECORATION_TYPES.find(d => d.key === body.awardType);
    if (!decorationConfig) {
      return NextResponse.json(
        { error: "Invalid award type" },
        { status: 400 }
      );
    }
    
    // Get API keys
    const apiKeys = await getDecryptedApiKeys();
    
    // Select model provider
    const modelProvider = getModelProvider(body.model, apiKeys || {});
    if (!modelProvider) {
      return NextResponse.json(
        { error: "No API key available for selected model" },
        { status: 400 }
      );
    }
    
    // Load user LLM settings for custom decoration prompt and rank verbs
    const { data: settingsData } = await supabase
      .from("user_llm_settings")
      .select("decoration_system_prompt, decoration_style_guidelines, rank_verb_progression")
      .eq("user_id", user.id)
      .maybeSingle();
    
    const userSettings = settingsData as unknown as Partial<UserLLMSettings> | null;
    
    // Build system prompt - use user's custom decoration prompt if available
    let systemPrompt: string;
    
    if (userSettings?.decoration_system_prompt) {
      // User has a custom decoration prompt - apply verb placeholder replacements
      // Decorations do NOT get abbreviations or acronyms (everything spelled out)
      const rankVerbs = userSettings.rank_verb_progression?.[body.rateeRank as keyof typeof userSettings.rank_verb_progression] || {
        primary: ["Led", "Managed"],
        secondary: ["Executed", "Coordinated"],
      };
      const rankVerbGuidance = `Primary verbs: ${rankVerbs.primary.join(", ")}\n  Secondary verbs: ${rankVerbs.secondary.join(", ")}`;
      
      let prompt = userSettings.decoration_system_prompt;
      prompt = prompt.replace(/\{\{ratee_rank\}\}/g, body.rateeRank);
      prompt = prompt.replace(/\{\{primary_verbs\}\}/g, rankVerbs.primary.join(", "));
      prompt = prompt.replace(/\{\{rank_verb_guidance\}\}/g, rankVerbGuidance);
      
      // Append style guidelines if available
      if (userSettings.decoration_style_guidelines) {
        prompt += `\n\nADDITIONAL STYLE GUIDANCE:\n${userSettings.decoration_style_guidelines}`;
      }
      
      // Append the structured citation details (opening template, accomplishments, etc.)
      // The user prompt handles ratee info, accomplishments, and closing template
      systemPrompt = prompt;
    } else {
      // Use default hardcoded decoration prompt builder
      systemPrompt = buildDecorationSystemPrompt({
        awardType: body.awardType,
        reason: body.reason || "meritorious_service",
        rank: body.rateeRank,
        fullName: body.rateeName,
        dutyTitle: body.dutyTitle || "member",
        unit: body.unit || "the organization",
        startDate: body.startDate || "start date",
        endDate: body.endDate || "end date",
        accomplishments: body.accomplishments,
        gender: body.rateeGender,
        maxCharacters: decorationConfig.maxCharacters,
      });
    }
    
    // Build user prompt with ratee details and accomplishments
    const userPrompt = userSettings?.decoration_system_prompt
      ? `Generate a ${decorationConfig.name} (${decorationConfig.abbreviation}) citation.

## RATEE INFORMATION
- Rank: ${body.rateeRank}
- Full Name: ${body.rateeName}
- Duty Title: ${body.dutyTitle || "member"}
- Unit: ${body.unit || "the organization"}
- Period: ${body.startDate || "start date"} to ${body.endDate || "end date"}
- Award Reason: ${body.reason || "meritorious_service"}
- Maximum Characters: ${decorationConfig.maxCharacters}

## ACCOMPLISHMENTS TO INCORPORATE
${body.accomplishments.map((a, i) => `${i + 1}. ${a}`).join("\n")}

Generate the complete decoration citation. Output ONLY the citation text, ready to paste directly onto ${decorationConfig.afForm}.`
      : "Generate the complete decoration citation based on the provided information and accomplishments.";

    // Generate citation
    const { text: rawCitation } = await generateText({
      model: modelProvider,
      system: systemPrompt,
      prompt: userPrompt,
      temperature: 0.7,
      maxTokens: 2000,
    });
    
    // Post-process to expand any remaining abbreviations
    const citation = expandAbbreviations(rawCitation);
    
    // Character count check (MyDecs Reimagined uses 1350 char limit)
    const characterCount = citation.length;
    const maxCharacters = decorationConfig.maxCharacters;
    
    // Also calculate legacy line estimate for reference
    const estimatedLines = Math.ceil(characterCount / 80);
    
    return NextResponse.json({
      citation,
      metadata: {
        awardType: body.awardType,
        awardName: decorationConfig.name,
        characterCount,
        maxCharacters,
        withinLimit: characterCount <= maxCharacters,
        estimatedLines, // Legacy reference
        model: body.model,
      },
    });
    
  } catch (error) {
    console.error("Generate decoration error:", error);
    return NextResponse.json(
      { error: "Failed to generate citation" },
      { status: 500 }
    );
  }
}

function getModelProvider(
  model: string,
  apiKeys: { openai_key?: string | null; anthropic_key?: string | null; google_key?: string | null; grok_key?: string | null }
): LanguageModel | null {
  // Check user keys first, then fall back to env keys
  const openaiKey = apiKeys.openai_key || process.env.OPENAI_API_KEY;
  const anthropicKey = apiKeys.anthropic_key || process.env.ANTHROPIC_API_KEY;
  const googleKey = apiKeys.google_key || process.env.GOOGLE_GENERATIVE_AI_API_KEY;
  const xaiKey = apiKeys.grok_key || process.env.XAI_API_KEY;
  
  if (model.startsWith("gpt-") && openaiKey) {
    const openai = createOpenAI({ apiKey: openaiKey });
    return openai(model);
  }
  
  if (model.startsWith("claude-") && anthropicKey) {
    const anthropic = createAnthropic({ apiKey: anthropicKey });
    return anthropic(model);
  }
  
  if (model.startsWith("gemini-") && googleKey) {
    const google = createGoogleGenerativeAI({ apiKey: googleKey });
    return google(model);
  }
  
  if (model.startsWith("grok-") && xaiKey) {
    const xai = createXai({ apiKey: xaiKey });
    return xai(model);
  }
  
  // Default fallback - try each provider in order
  if (anthropicKey) {
    const anthropic = createAnthropic({ apiKey: anthropicKey });
    return anthropic("claude-sonnet-4-20250514");
  }
  if (openaiKey) {
    const openai = createOpenAI({ apiKey: openaiKey });
    return openai("gpt-4o");
  }
  if (googleKey) {
    const google = createGoogleGenerativeAI({ apiKey: googleKey });
    return google("gemini-2.0-flash");
  }
  if (xaiKey) {
    const xai = createXai({ apiKey: xaiKey });
    return xai("grok-2");
  }
  
  return null;
}

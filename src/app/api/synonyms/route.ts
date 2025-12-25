import { createClient } from "@/lib/supabase/server";
import { createOpenAI } from "@ai-sdk/openai";
import { createAnthropic } from "@ai-sdk/anthropic";
import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { createXai } from "@ai-sdk/xai";
import { generateText } from "ai";
import { NextResponse } from "next/server";

interface SynonymRequest {
  word: string;
  fullStatement: string;
  model: string;
}

function getModelProvider(
  modelId: string,
  userKeys: {
    openai_key?: string | null;
    anthropic_key?: string | null;
    google_key?: string | null;
    grok_key?: string | null;
  } | null
) {
  const provider = modelId.includes("claude")
    ? "anthropic"
    : modelId.includes("gemini")
      ? "google"
      : modelId.includes("grok")
        ? "xai"
        : "openai";

  switch (provider) {
    case "anthropic": {
      const customAnthropic = createAnthropic({
        apiKey: userKeys?.anthropic_key || process.env.ANTHROPIC_API_KEY || "",
      });
      return customAnthropic(modelId);
    }
    case "google": {
      const customGoogle = createGoogleGenerativeAI({
        apiKey: userKeys?.google_key || process.env.GOOGLE_GENERATIVE_AI_API_KEY || "",
      });
      return customGoogle(modelId);
    }
    case "xai": {
      const customXai = createXai({
        apiKey: userKeys?.grok_key || process.env.XAI_API_KEY || "",
      });
      return customXai(modelId);
    }
    default: {
      const customOpenai = createOpenAI({
        apiKey: userKeys?.openai_key || process.env.OPENAI_API_KEY || "",
      });
      return customOpenai(modelId);
    }
  }
}

export async function POST(request: Request) {
  try {
    const supabase = await createClient();

    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body: SynonymRequest = await request.json();
    const { word, fullStatement, model } = body;

    if (!word || !fullStatement) {
      return NextResponse.json(
        { error: "Word and full statement are required" },
        { status: 400 }
      );
    }

    // Get user API keys
    const { data: userKeysData } = await supabase
      .from("user_api_keys")
      .select("*")
      .eq("user_id", user.id)
      .single();

    const userKeys = userKeysData as unknown as {
      openai_key?: string | null;
      anthropic_key?: string | null;
      google_key?: string | null;
      grok_key?: string | null;
    } | null;

    const modelProvider = getModelProvider(model, userKeys);

    const systemPrompt = `You are an expert military writing assistant specializing in Air Force Enlisted Performance Brief (EPB) statements. Your task is to suggest context-appropriate synonyms for a specific word within an EPB statement.

GUIDELINES:
1. Consider the full context of the statement when suggesting synonyms
2. Prioritize strong, active verbs commonly used in military performance writing
3. Suggest words that maintain or enhance the professional, action-oriented tone
4. Include a mix of:
   - Direct synonyms that fit the context
   - Stronger/more impactful alternatives
   - Military-appropriate terminology
5. Each suggestion should be grammatically correct when substituted
6. Keep suggestions concise (preferably single words, but short phrases are OK)

IMPORTANT: Return ONLY a JSON array of 10-15 synonyms/alternatives, ordered from most to least relevant.`;

    const userPrompt = `Find synonyms for the word "${word}" in this EPB statement:

"${fullStatement}"

The word "${word}" appears in the context above. Provide 10-15 context-appropriate alternatives that would work well in this military performance statement.

Return ONLY a JSON array of strings:
["synonym1", "synonym2", "synonym3", ...]`;

    const { text } = await generateText({
      model: modelProvider,
      system: systemPrompt,
      prompt: userPrompt,
      temperature: 0.7,
      maxTokens: 500,
    });

    let synonyms: string[] = [];
    try {
      const jsonMatch = text.match(/\[[\s\S]*\]/);
      if (jsonMatch) {
        synonyms = JSON.parse(jsonMatch[0]);
      }
    } catch {
      // Fallback: try to extract words from text
      synonyms = text
        .split(/[,\n]/)
        .map((s) => s.replace(/["\[\]]/g, "").trim())
        .filter((s) => s.length > 0 && s.length < 50);
    }

    // Clean up and deduplicate
    synonyms = [...new Set(synonyms.map((s) => s.toLowerCase().trim()))]
      .filter((s) => s.length > 0 && s !== word.toLowerCase())
      .slice(0, 15);

    return NextResponse.json({ synonyms });
  } catch (error) {
    console.error("Synonyms API error:", error);
    return NextResponse.json(
      { error: "Failed to generate synonyms" },
      { status: 500 }
    );
  }
}



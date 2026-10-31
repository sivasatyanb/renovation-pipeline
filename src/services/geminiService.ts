export interface RenovationPromptPlan {
  nanoBananaPrompt: string;
  voiceConfirmation: string;
}

export interface RenovationResult {
  renovatedImageUrl: string;
  nanoBananaPrompt: string;
  voiceConfirmation: string;
  modelUsed: string;
  latencyMs: number;
}

/**
 * Default real photograph of an unrenovated / bare room used before the user uploads their own photo.
 */
export const DEFAULT_RAW_ROOM_PHOTO_URL =
  'https://images.unsplash.com/photo-1513694203232-719a280e022f?auto=format&fit=crop&w=1400&q=85';

/**
 * System prompt for Gemini to translate the user's request into a strict
 * Image-to-Image / Inpainting replacement and renovation instruction for Nano Banana.
 */
export const GEMINI_RENOVATION_SYSTEM_PROMPT = `Tu es un architecte d'intérieur expert en édition photographique Image-to-Image / Inpainting pour le modèle Nano Banana.
Tu reçois en entrée la photo d'origine de la pièce (Uploaded Site Photo) ainsi que la demande vocale ou textuelle de l'utilisateur.

Ton rôle est de traduire la demande de l'utilisateur en une consigne de "remplacement" et "rénovation" naturelle et cohérente ("nanoBananaPrompt") destinée à Nano Banana.

Règles strictes pour "nanoBananaPrompt" :
1. Référence structurelle absolue : Ordonne à Nano Banana de conserver strictement la perspective exacte, le cadrage, l'angle de caméra, les fenêtres, les portes, les arches, les moulures de plafond et les volumes architecturaux de la photo d'entrée.
2. Remplacer et rénover au lieu de superposer : Formule la consigne comme un remplacement physique des matériaux existants et une rénovation naturelle de la pièce (exemple : "Conserve la perspective, la fenêtre et les arches de cette pièce, mais remplace complètement le sol existant par un parquet chevron en chêne massif et repeins tous les murs en enduit minéral propre, puis intègre naturellement un canapé et une table basse dans le même angle de perspective et avec la lumière naturelle de la fenêtre").
3. Ne demande jamais d'ajouter des éléments graphiques ou objets virtuels flottants par-dessus l'image brute : toute surface (sol, murs, plafond) et tout mobilier doivent remplacer ou s'intégrer photographiquement dans la scène avec des ombres de contact réelles et la lumière existante.
4. Rédige "nanoBananaPrompt" de façon ultra-claire et descriptive pour Nano Banana, et rédige "voiceConfirmation" sous forme d'une courte phrase naturelle en anglais (1 à 2 phrases maximum) résumant les transformations effectuées pour la synthèse vocale.

Renvoie exclusivement un JSON valide :
{
  "nanoBananaPrompt": "...",
  "voiceConfirmation": "..."
}`;

/**
 * Fallback prompt builder if the text reformulation step is skipped or unavailable.
 * Formulates the user's instruction strictly as an inpainting / replacement & renovation command.
 */
export function buildNaturalReplacementPrompt(userInstruction: string): RenovationPromptPlan {
  const cleanRequest = userInstruction.trim();
  return {
    nanoBananaPrompt: [
      `Utilise cette photo d'origine comme référence structurelle absolue (Image-to-Image / Inpainting).`,
      `Conserve strictement la perspective exacte, l'angle de prise de vue, les dimensions, les fenêtres, les portes, les arches et la structure architecturale de cette pièce.`,
      `Ne superpose pas d'objets virtuels artificiels par-dessus l'image : REMPLACE et RÉNOVE véritablement l'existant dans la pièce selon cette demande : "${cleanRequest}".`,
      `Exemple d'application : conserve la perspective, la fenêtre et les ouvertures de cette pièce, mais remplace proprement le revêtement de sol existant, rénove et repeins tous les murs avec la finition demandée, et intègre le mobilier demandé exactement dans le même angle de perspective avec un éclairage naturel cohérent et des ombres portées réalistes au sol.`,
      `Keep the exact camera angle, room geometry, windows, and arches of the input photograph. Replace and renovate the existing walls and floor seamlessly, and integrate any requested furniture naturally into the room's true perspective. Photorealistic architectural photography.`,
    ].join(' '),
    voiceConfirmation: `I have renovated the space while preserving its original perspective and architecture, applying your requested changes: ${cleanRequest}.`,
  };
}

/**
 * Converts any image source (Data URL from file upload or HTTP URL) into raw Base64 + mimeType
 * so Nano Banana always receives the actual source image bytes in `inlineData`.
 */
export async function extractImageInlineData(
  imageSource: string
): Promise<{ mimeType: string; data: string }> {
  if (imageSource.startsWith('data:')) {
    const commaIndex = imageSource.indexOf(',');
    const header = imageSource.slice(0, commaIndex);
    const data = imageSource.slice(commaIndex + 1);
    const mimeMatch = header.match(/data:(.*?);base64/);
    return {
      mimeType: mimeMatch?.[1] || 'image/jpeg',
      data,
    };
  }

  const response = await fetch(imageSource, { mode: 'cors' });
  if (!response.ok) {
    throw new Error(`Unable to read source image (${response.status})`);
  }
  const blob = await response.blob();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      const dataUrl = reader.result as string;
      const commaIdx = dataUrl.indexOf(',');
      resolve({
        mimeType: blob.type || 'image/jpeg',
        data: dataUrl.slice(commaIdx + 1),
      });
    };
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

/**
 * Step 1: Uses Gemini (gemini-3.8-flash) with the original photo + user request
 * to reformulate the instruction into a strict replacement & renovation prompt for Nano Banana.
 */
async function reformulateRenovationPrompt(
  apiKey: string,
  inlineImage: { mimeType: string; data: string },
  userInstruction: string
): Promise<RenovationPromptPlan> {
  const fallbackPlan = buildNaturalReplacementPrompt(userInstruction);

  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=${encodeURIComponent(
        apiKey
      )}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{ text: GEMINI_RENOVATION_SYSTEM_PROMPT }],
          },
          contents: [
            {
              role: 'user',
              parts: [
                {
                  inlineData: {
                    mimeType: inlineImage.mimeType,
                    data: inlineImage.data,
                  },
                },
                {
                  text: `Demande de l'utilisateur pour rénover cette pièce : "${userInstruction.trim()}"`,
                },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: 'application/json',
            temperature: 0.25,
          },
        }),
      }
    );

    if (!response.ok) {
      return fallbackPlan;
    }

    const data = await response.json();
    const rawText = data?.candidates?.[0]?.content?.parts
      ?.map((p: { text?: string }) => p.text || '')
      .join('')
      .trim();

    if (!rawText) {
      return fallbackPlan;
    }

    const parsed = JSON.parse(rawText) as Partial<RenovationPromptPlan>;
    return {
      nanoBananaPrompt:
        parsed.nanoBananaPrompt && parsed.nanoBananaPrompt.trim().length > 20
          ? parsed.nanoBananaPrompt.trim()
          : fallbackPlan.nanoBananaPrompt,
      voiceConfirmation:
        parsed.voiceConfirmation && parsed.voiceConfirmation.trim().length > 5
          ? parsed.voiceConfirmation.trim()
          : fallbackPlan.voiceConfirmation,
    };
  } catch {
    return fallbackPlan;
  }
}

/**
 * Step 2: Calls Nano Banana (`gemini-2.5-flash-image`, with fallback to `gemini-3.1-flash-image`)
 * in true Image-to-Image / Inpainting mode by passing BOTH the original room photograph (`inlineData`)
 * and the strict replacement/renovation prompt.
 */
export async function renovateRoomWithNanoBanana(
  sourceImage: string,
  userInstruction: string
): Promise<RenovationResult> {
  const startTime = performance.now();
  const apiKey = (import.meta.env.VITE_GEMINI_API_KEY as string | undefined)?.trim();

  if (!apiKey) {
    throw new Error(
      'Missing VITE_GEMINI_API_KEY in .env.local. Nano Banana requires a valid Gemini API key.'
    );
  }

  // 1. Ensure we have the exact base64 bytes of the Original / Uploaded Site Photo
  const inlineImage = await extractImageInlineData(sourceImage);

  // 2. Reformulate user request into a natural "replace & renovate" inpainting instruction
  const plan = await reformulateRenovationPrompt(
    apiKey,
    inlineImage,
    userInstruction
  );

  // 3. Call Nano Banana Image-to-Image API with the original photo as structural reference
  const candidateModels = [
    'gemini-2.5-flash-image',
    'gemini-3.1-flash-image',
  ];

  let lastError = 'Nano Banana did not return an edited image.';

  for (const modelName of candidateModels) {
    try {
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${encodeURIComponent(
          apiKey
        )}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [
              {
                role: 'user',
                parts: [
                  {
                    inlineData: {
                      mimeType: inlineImage.mimeType,
                      data: inlineImage.data,
                    },
                  },
                  {
                    text: `${plan.nanoBananaPrompt}\n\nIMPORTANT: Edit and renovate the input room image directly. Keep the exact same camera angle, perspective, windows, arches, and structural geometry as the input image. Replace the existing floor and walls cleanly and integrate the furniture naturally inside the room.`,
                  },
                ],
              },
            ],
            generationConfig: {
              responseModalities: ['TEXT', 'IMAGE'],
            },
          }),
        }
      );

      if (!response.ok) {
        const errBody = await response.text();
        lastError = `Nano Banana (${modelName}) HTTP ${response.status}: ${errBody.slice(0, 180)}`;
        continue;
      }

      const data = await response.json();
      const parts = data?.candidates?.[0]?.content?.parts || [];
      const imagePart = parts.find(
        (p: { inlineData?: { data?: string; mimeType?: string } }) =>
          Boolean(p.inlineData?.data)
      );

      if (imagePart?.inlineData?.data) {
        const outputMime = imagePart.inlineData.mimeType || 'image/png';
        return {
          renovatedImageUrl: `data:${outputMime};base64,${imagePart.inlineData.data}`,
          nanoBananaPrompt: plan.nanoBananaPrompt,
          voiceConfirmation: plan.voiceConfirmation,
          modelUsed: modelName,
          latencyMs: Math.round(performance.now() - startTime),
        };
      }
    } catch (err) {
      lastError = err instanceof Error ? err.message : String(err);
    }
  }

  throw new Error(lastError);
}

/**
 * Speaks a short voice confirmation describing the renovation changes via `window.speechSynthesis`.
 */
export function speakRenovationConfirmation(
  text: string,
  muted = false,
  onStart?: () => void,
  onEnd?: () => void
) {
  if (muted || typeof window === 'undefined' || !('speechSynthesis' in window)) {
    onEnd?.();
    return;
  }

  try {
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = 'en-US';
    utterance.rate = 1.02;
    utterance.pitch = 1.0;

    const voices = window.speechSynthesis.getVoices();
    const preferredVoice =
      voices.find(
        (v) =>
          v.lang.startsWith('en') &&
          (v.name.includes('Samantha') ||
            v.name.includes('Natural') ||
            v.name.includes('Google US English') ||
            v.name.includes('Ava') ||
            v.name.includes('Alex'))
      ) || voices.find((v) => v.lang.startsWith('en'));

    if (preferredVoice) {
      utterance.voice = preferredVoice;
    }

    utterance.onstart = () => onStart?.();
    utterance.onend = () => onEnd?.();
    utterance.onerror = () => onEnd?.();

    window.speechSynthesis.speak(utterance);
  } catch {
    onEnd?.();
  }
}

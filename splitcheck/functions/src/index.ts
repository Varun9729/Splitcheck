import {HttpsError, onCall} from "firebase-functions/v2/https";
import {GoogleGenAI} from "@google/genai";

export const parseReceiptWithAi = onCall(
  {secrets: ["GEMINI_API_KEY"]},
  async (request) => {
    try {
      const imageUrl = request.data?.imageUrl;

      if (!imageUrl) {
        throw new HttpsError("invalid-argument", "imageUrl is required");
      }

      // Fetch the image from Firebase Storage and convert to base64
      const imageResponse = await fetch(imageUrl);
      if (!imageResponse.ok) {
        throw new HttpsError(
          "not-found",
          `Failed to fetch image: ${imageResponse.status}`,
        );
      }
      const imageBuffer = await imageResponse.arrayBuffer();
      const base64Image = Buffer.from(imageBuffer).toString("base64");

      // Detect mime type from Content-Type header, fallback to jpeg
      const mimeType =
        imageResponse.headers.get("content-type") ?? "image/jpeg";

      const ai = new GoogleGenAI({
        apiKey: process.env.GEMINI_API_KEY,
      });

      const result = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        contents: [
          {
            role: "user",
            parts: [
              {
                text:
                  "You are an expert receipt OCR system that handles " +
                  "ALL receipt formats: restaurants, grocery stores, " +
                  "retail, bars, coffee shops, fast food, handwritten, " +
                  "thermal prints, and blurry photos. " +
                  "\n\nRules:" +
                  "\n1. Transcribe item names EXACTLY as printed. " +
                  "Do not guess, autocorrect, or interpret unclear text. " +
                  "If a letter is ambiguous, prefer the reading that " +
                  "forms a real word or menu item name." +
                  "\n2. Each item must have a price > 0. " +
                  "Omit items with price 0 (like separators or headers)." +
                  "\n3. Use the quantity shown on the receipt. " +
                  "If an item appears as '2x Taco $7.00', use " +
                  "quantity: 2 and itemPrice: 7.00 (per-unit price). " +
                  "If it says '2x Taco $14.00', use quantity: 2 " +
                  "and itemPrice: 14.00 (line total)." +
                  "\n4. Ignore discounts/coupons/void lines. " +
                  "Only extract actual purchased items." +
                  "\n5. If subtotal/tax/total are not visible, " +
                  "calculate subtotal from items and set tax to 0." +
                  "\n6. placeName: the restaurant or store name at the " +
                  "top of the receipt. If unclear, use 'Receipt'." +
                  "\n\nReturn ONLY strict JSON with no markdown fences. " +
                  "Fields: placeName (string), " +
                  "items (array of {itemName: string, itemPrice: number, " +
                  "quantity: number}), " +
                  "subtotal (number), tax (number), total (number).",
              },
              {
                inlineData: {
                  mimeType: mimeType,
                  data: base64Image,
                },
              },
            ],
          },
        ],
      });

      const raw = result.text ?? "{}";

      // Strip markdown fences if Gemini wraps the JSON anyway
      const cleaned = raw
        .replace(/^```json\s*/i, "")
        .replace(/^```\s*/i, "")
        .replace(/```\s*$/i, "")
        .trim();

      return JSON.parse(cleaned);
    } catch (error: unknown) {
      console.error("parseReceiptWithAi failed:", error);

      const message =
        error instanceof Error ? error.message : "Unknown function error";

      const status =
        typeof error === "object" &&
        error !== null &&
        "status" in error &&
        typeof (error as {status?: unknown}).status === "number" ?
          (error as {status: number}).status :
          undefined;

      if (status === 429 || message.includes("Quota exceeded")) {
        throw new HttpsError(
          "resource-exhausted",
          "Gemini quota exceeded. Check API key project, billing, " +
            "and Generative Language API.",
        );
      }

      if (status === 404 || message.includes("no longer available")) {
        throw new HttpsError(
          "failed-precondition",
          "The configured Gemini model is unavailable.Update to a newer model.",
        );
      }

      throw new HttpsError("internal", message);
    }
  },
);

// Sanitizer boundary — docs/event-model.md §4.3. Two zones as two branded
// types with NO cast path between them: free narration text can never reach
// the share zone. Share text is regenerated from counters via fixed
// templates ("there is no string to sanitize").
//
// The unique-symbol brands make structural assignment impossible; building a
// value of either type requires the constructor functions below. Any `as`
// cast bridging the zones is a review-blocking incident, not a style issue.

declare const deviceZoneBrand: unique symbol;
declare const shareZoneBrand: unique symbol;

export type NarrationClass = 'routine' | 'situational' | 'golden';

/** Device zone: rendered ONLY in-app on the user's own phone. */
export interface DeviceNarration {
  readonly [deviceZoneBrand]: true;
  readonly narrationClass: NarrationClass;
  readonly workerId: string;
  readonly text: string; // free-form LLM narration — never leaves the device zone
}

/** Share zone: recap cards, replays, octagon clips — anything exportable. */
export interface ShareCardModel {
  readonly [shareZoneBrand]: true;
  readonly personaId: string;
  readonly title: string;               // worker title from the fixed title table
  readonly templateId: string;          // fixed template set — share text is templated, never free-form
  readonly counters: Readonly<Record<string, number>>;
  readonly octagonRecord?: { readonly w: number; readonly l: number };
}

export function deviceNarration(
  fields: Omit<DeviceNarration, typeof deviceZoneBrand>,
): DeviceNarration {
  return fields as DeviceNarration;
}

export function shareCardModel(
  fields: Omit<ShareCardModel, typeof shareZoneBrand>,
): ShareCardModel {
  // TODO(P4): runtime assertion that no field contains free-form strings
  // beyond the enumerated template/persona/title ids.
  return fields as ShareCardModel;
}

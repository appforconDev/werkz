// Destructive-operation classifier — data-driven, list lives in
// destructive-list.json (versioned; docs/event-model.md §3.2).
// Category 11 ("unknown = dangerous") is routing logic, not a pattern:
// anything the decision router cannot classify escalates to the user.
// False positive = a decision the user gets to make anyway. False negative
// = incident.

import destructiveList from './destructive-list.json' with { type: 'json' };

export interface DestructiveVerdict {
  destructive: boolean;
  categoryId?: string;
}

interface Category {
  id: string;
  label: string;
  commandPatterns?: string[];
  pathPatterns?: string[];
}

const categories: Category[] = destructiveList.categories;

const commandMatchers = categories.flatMap((c) =>
  (c.commandPatterns ?? []).map((p) => ({ id: c.id, re: new RegExp(p, 'i') })),
);

const pathMatchers = categories.flatMap((c) =>
  (c.pathPatterns ?? []).map((p) => ({ id: c.id, re: globToRegExp(p) })),
);

/** Classify a shell command string (Bash tool_input.command). */
export function classifyCommand(command: string): DestructiveVerdict {
  for (const m of commandMatchers) {
    if (m.re.test(command)) return { destructive: true, categoryId: m.id };
  }
  return { destructive: false };
}

/** Classify a file path targeted by Write/Edit tools. */
export function classifyFileTarget(filePath: string): DestructiveVerdict {
  for (const m of pathMatchers) {
    if (m.re.test(filePath)) return { destructive: true, categoryId: m.id };
  }
  return { destructive: false };
}

export const listVersion: number = destructiveList.version;

// Minimal glob → RegExp: supports ** (any depth) and * (within a segment).
// Wildcards go through placeholder tokens so the single-* substitution
// cannot corrupt regex text already produced by the ** substitution.
function globToRegExp(glob: string): RegExp {
  const GLOBSTAR_SLASH = '<<GSS>>';
  const GLOBSTAR = '<<GS>>';
  const pattern = glob
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replaceAll('**/', GLOBSTAR_SLASH)
    .replaceAll('**', GLOBSTAR)
    .replaceAll('*', '[^/]*')
    .replaceAll(GLOBSTAR_SLASH, '(?:.*/)?')
    .replaceAll(GLOBSTAR, '.*');
  return new RegExp(`^${pattern}$`, 'i');
}

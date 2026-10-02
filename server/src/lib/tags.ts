export const MAX_TAGS = 20;
export const MAX_TAG_LENGTH = 40;

/** "  @Deep   work " → "Deep work": no leading @, single spaces, trimmed. */
export function normalizeTag(tag: string): string {
  return tag.replace(/^[\s@]+/, '').replace(/\s+/g, ' ').trim();
}

export function sameTag(a: string, b: string): boolean {
  return a.toLocaleLowerCase() === b.toLocaleLowerCase();
}

/** Cleans a list of tags and drops repeats, ignoring case. The first spelling wins. */
export function normalizeTags(tags: readonly string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const raw of tags) {
    const tag = normalizeTag(raw);
    const key = tag.toLocaleLowerCase();
    if (!tag || seen.has(key)) continue;
    seen.add(key);
    result.push(tag);
  }
  return result;
}

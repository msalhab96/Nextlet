import { describe, expect, it } from 'vitest';
import { normalizeTag, normalizeTags } from '../src/lib/tags.js';

describe('tags', () => {
  it('drops the leading @ and tidies spaces', () => {
    expect(normalizeTag('@phone')).toBe('phone');
    expect(normalizeTag('  Deep   work ')).toBe('Deep work');
    expect(normalizeTag('@@ ')).toBe('');
  });

  it('keeps the first spelling of a tag and skips empty ones', () => {
    expect(normalizeTags(['Phone', '@phone', ' ', 'errands', 'PHONE'])).toEqual(['Phone', 'errands']);
    expect(normalizeTags([])).toEqual([]);
  });
});

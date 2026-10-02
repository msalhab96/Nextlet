import { z } from 'zod';
import { addDays, daysInMonth, formatDay, isoWeekday } from './dates.js';

export const repeatRuleSchema = z.discriminatedUnion('type', [
  z.strictObject({ type: z.literal('daily') }),
  z.strictObject({ type: z.literal('weekdays') }),
  z.strictObject({
    type: z.literal('weekly'),
    days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
  }),
  z.strictObject({ type: z.literal('interval'), every: z.number().int().min(2).max(365) }),
  z.strictObject({ type: z.literal('monthly') }),
]);

export type RepeatRule = z.infer<typeof repeatRuleSchema>;

/**
 * The first day strictly after `after` on which the rule fires.
 * `anchor` is the day the task was scheduled for: monthly rules keep its day of the month.
 */
export function nextOccurrence(rule: RepeatRule, after: string, anchor: string): string {
  switch (rule.type) {
    case 'daily':
      return addDays(after, 1);
    case 'interval':
      return addDays(after, rule.every);
    case 'weekdays':
      return firstMatching(after, (weekday) => weekday <= 5);
    case 'weekly': {
      const days = new Set(rule.days);
      return firstMatching(after, (weekday) => days.has(weekday));
    }
    case 'monthly':
      return nextMonthly(after, Number(anchor.slice(8, 10)));
  }
}

function firstMatching(after: string, matches: (weekday: number) => boolean): string {
  for (let offset = 1; offset <= 7; offset++) {
    const day = addDays(after, offset);
    if (matches(isoWeekday(day))) return day;
  }
  return addDays(after, 1);
}

function nextMonthly(after: string, dayOfMonth: number): string {
  let year = Number(after.slice(0, 4));
  let month = Number(after.slice(5, 7)) - 1;
  // Short months clamp to their last day, so "the 31st" lands on 30 Apr or 28 Feb.
  for (;;) {
    const candidate = formatDay(year, month, Math.min(dayOfMonth, daysInMonth(year, month)));
    if (candidate > after) return candidate;
    month += 1;
    if (month === 12) {
      month = 0;
      year += 1;
    }
  }
}

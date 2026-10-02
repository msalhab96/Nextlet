import type { Project } from '../types';
import { addDays, daysInMonth, isoWeekday, isValidDay, makeDay, startOfWeek } from './dates';

// Quick add understands days, #projects and !priority, e.g.
//   "Call mom tomorrow #Personal !2"
// Times are deliberately not a thing: tasks belong to a day, never an hour.

export type ParsedProject = { kind: 'existing'; project: Project } | { kind: 'new'; name: string };

export interface QuickAdd {
  title: string;
  /** undefined: no day was typed. null: "someday", i.e. the Inbox. */
  day?: string | null;
  priority?: number;
  project?: ParsedProject;
}

const WEEKDAYS: Record<string, number> = {
  mon: 1,
  monday: 1,
  tue: 2,
  tues: 2,
  tuesday: 2,
  wed: 3,
  weds: 3,
  wednesday: 3,
  thu: 4,
  thur: 4,
  thurs: 4,
  thursday: 4,
  fri: 5,
  friday: 5,
  sat: 6,
  saturday: 6,
  sun: 7,
  sunday: 7,
};

const MONTHS: Record<string, number> = {
  jan: 0,
  january: 0,
  feb: 1,
  february: 1,
  mar: 2,
  march: 2,
  apr: 3,
  april: 3,
  may: 4,
  jun: 5,
  june: 5,
  jul: 6,
  july: 6,
  aug: 7,
  august: 7,
  sep: 8,
  sept: 8,
  september: 8,
  oct: 9,
  october: 9,
  nov: 10,
  november: 10,
  dec: 11,
  december: 11,
};

const alternation = (words: string[]) => [...words].sort((a, b) => b.length - a.length).join('|');
const ANY_WEEKDAY = alternation(Object.keys(WEEKDAYS));
const FULL_WEEKDAY = alternation(Object.keys(WEEKDAYS).filter((word) => word.length > 4));
const SHORT_WEEKDAY = alternation(['mon', 'tue', 'tues', 'wed', 'weds', 'thu', 'thur', 'fri', 'sat', 'sun']);
const ANY_MONTH = alternation(Object.keys(MONTHS));

const PROJECT = /(^|\s)#([\p{L}\p{N}][\p{L}\p{N}_-]*)/u;
const PRIORITY = /(^|\s)!([1-3])(?=\s|$)/;

/** The next time `weekday` comes round, never today itself. */
function upcoming(today: string, weekday: number): string {
  const ahead = (weekday - isoWeekday(today) + 7) % 7 || 7;
  return addDays(today, ahead);
}

function dateInMonth(today: string, month: number, date: number): string | undefined {
  const year = Number(today.slice(0, 4));
  if (date < 1 || date > 31) return undefined;
  for (const candidateYear of [year, year + 1]) {
    if (date > daysInMonth(candidateYear, month)) continue;
    const candidate = makeDay(candidateYear, month, date);
    if (candidate >= today) return candidate;
  }
  return undefined;
}

type DayRule = { pattern: RegExp; resolve: (match: RegExpMatchArray, today: string) => string | null | undefined };

const DAY_RULES: DayRule[] = [
  { pattern: /\bnext week\b/i, resolve: (_, today) => addDays(startOfWeek(today), 7) },
  {
    pattern: new RegExp(`\\bnext (${ANY_WEEKDAY})\\b`, 'i'),
    resolve: (match, today) => addDays(upcoming(today, WEEKDAYS[match[1]!.toLowerCase()]!), 7),
  },
  {
    pattern: /\bin (\d{1,3}) (days?|weeks?)\b/i,
    resolve: (match, today) => addDays(today, Number(match[1]) * (match[2]!.toLowerCase().startsWith('week') ? 7 : 1)),
  },
  { pattern: /\b(today|tonight)\b/i, resolve: (_, today) => today },
  { pattern: /\b(tomorrow|tmrw|tmr)\b/i, resolve: (_, today) => addDays(today, 1) },
  { pattern: /\bsomeday\b/i, resolve: () => null },
  { pattern: /\b(?:on )?(\d{4}-\d{2}-\d{2})\b/, resolve: (match) => (isValidDay(match[1]) ? match[1] : undefined) },
  {
    pattern: new RegExp(`\\b(?:on )?(\\d{1,2})(?:st|nd|rd|th)? (${ANY_MONTH})\\b`, 'i'),
    resolve: (match, today) => dateInMonth(today, MONTHS[match[2]!.toLowerCase()]!, Number(match[1])),
  },
  {
    pattern: new RegExp(`\\b(?:on )?(${ANY_MONTH}) (\\d{1,2})(?:st|nd|rd|th)?\\b`, 'i'),
    resolve: (match, today) => dateInMonth(today, MONTHS[match[1]!.toLowerCase()]!, Number(match[2])),
  },
  // Full weekday names count anywhere. Short ones ("sun", "sat") only after "on" or at
  // the very end, so "Buy sun cream" stays a title.
  {
    pattern: new RegExp(`\\b(?:on )?(${FULL_WEEKDAY})\\b`, 'i'),
    resolve: (match, today) => upcoming(today, WEEKDAYS[match[1]!.toLowerCase()]!),
  },
  {
    pattern: new RegExp(`(?:\\bon (${SHORT_WEEKDAY})\\b|\\b(${SHORT_WEEKDAY})\\s*$)`, 'i'),
    resolve: (match, today) => upcoming(today, WEEKDAYS[(match[1] ?? match[2])!.toLowerCase()]!),
  },
];

export function normalizeProjectName(name: string): string {
  return name.toLowerCase().replace(/[-_]+/g, ' ').replace(/\s+/g, ' ').trim();
}

function cut(text: string, match: RegExpMatchArray): string {
  const start = match.index ?? 0;
  return `${text.slice(0, start)} ${text.slice(start + match[0].length)}`;
}

export function parseQuickAdd(input: string, context: { today: string; projects: Project[] }): QuickAdd {
  let text = input;
  const result: QuickAdd = { title: '' };

  const project = text.match(PROJECT);
  if (project) {
    const raw = project[2]!;
    const wanted = normalizeProjectName(raw);
    const existing = context.projects.find((candidate) => normalizeProjectName(candidate.name) === wanted);
    result.project = existing ? { kind: 'existing', project: existing } : { kind: 'new', name: raw.replace(/[-_]+/g, ' ') };
    text = cut(text, project);
  }

  const priority = text.match(PRIORITY);
  if (priority) {
    result.priority = Number(priority[2]);
    text = cut(text, priority);
  }

  for (const rule of DAY_RULES) {
    const match = text.match(rule.pattern);
    if (!match) continue;
    const day = rule.resolve(match, context.today);
    if (day === undefined) continue;
    result.day = day;
    text = cut(text, match);
    break;
  }

  result.title = text.replace(/\s+/g, ' ').trim();
  return result;
}

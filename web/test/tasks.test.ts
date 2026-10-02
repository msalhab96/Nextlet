import { describe, expect, it } from 'vitest';
import {
  addDays,
  dayWithDate,
  fromLabel,
  isoWeekNumber,
  monthWeeks,
  relativeDay,
  startOfWeek,
  weekRangeLabel,
} from '../src/lib/dates';
import { repeatLabel } from '../src/lib/repeat';
import { carriedFrom, countTasks, doneOn, effectiveDay, moveInOrder, openOn, reorderSlots } from '../src/lib/tasks';
import type { Task } from '../src/types';

const today = '2026-10-01'; // Thursday

let counter = 0;
function task(overrides: Partial<Task>): Task {
  counter += 1;
  return {
    id: `t${counter}`,
    title: `Task ${counter}`,
    notes: '',
    projectId: null,
    day: today,
    plannedDay: overrides.day ?? today,
    estimateMinutes: null,
    priority: 0,
    repeat: null,
    sortOrder: counter,
    completedAt: null,
    completedFromDay: null,
    postponedAt: null,
    nextOccurrenceId: null,
    createdAt: `2026-09-01T00:00:${String(counter).padStart(2, '0')}Z`,
    updatedAt: '2026-09-01T00:00:00Z',
    subtasks: [],
    ...overrides,
  };
}

describe('dates', () => {
  it('formats days for people', () => {
    expect(relativeDay(today, today)).toBe('Today');
    expect(relativeDay(addDays(today, 1), today)).toBe('Tomorrow');
    expect(dayWithDate(addDays(today, 1), today)).toBe('Tomorrow · Fri 2 Oct');
    expect(dayWithDate('2026-10-05', today)).toBe('Mon 5 Oct');
    expect(dayWithDate('2027-01-04', today)).toBe('Mon 4 Jan 2027');
    expect(fromLabel('2026-09-29', today)).toBe('From Tue');
    expect(fromLabel('2026-09-12', today)).toBe('From 12 Sep');
  });

  it('works in Monday-first ISO weeks', () => {
    expect(startOfWeek(today)).toBe('2026-09-28');
    expect(startOfWeek('2026-10-04')).toBe('2026-09-28');
    expect(isoWeekNumber('2026-09-28')).toBe(40);
    expect(isoWeekNumber('2027-01-01')).toBe(53);
    expect(weekRangeLabel('2026-09-28')).toBe('28 Sep – 4 Oct');
    expect(weekRangeLabel('2026-10-05')).toBe('5 – 11 Oct');
  });

  it('builds a month grid that covers whole weeks', () => {
    const { monthStart, weeks } = monthWeeks(today);
    expect(monthStart).toBe('2026-10-01');
    expect(weeks[0]![0]).toBe('2026-09-28');
    expect(weeks.at(-1)!.at(-1)).toBe('2026-11-01');
    expect(weeks.every((week) => week.length === 7)).toBe(true);
  });
});

describe('task days', () => {
  it('rolls unfinished tasks from earlier days onto today', () => {
    const late = task({ day: '2026-09-29' });
    expect(effectiveDay(late, today)).toBe(today);
    expect(carriedFrom(late, today)).toBe('2026-09-29');
  });

  it('remembers where a pushed task was planned', () => {
    const pushed = task({ day: '2026-10-02', plannedDay: today });
    expect(effectiveDay(pushed, today)).toBe('2026-10-02');
    expect(carriedFrom(pushed, today)).toBe(today);
    const rescheduled = task({ day: '2026-10-05', plannedDay: '2026-10-05' });
    expect(carriedFrom(rescheduled, today)).toBeNull();
  });

  it('lists the day in order and keeps done tasks apart', () => {
    const first = task({ sortOrder: 1 });
    const second = task({ sortOrder: 5, day: '2026-09-30' });
    const done = task({ completedAt: '2026-10-01T08:00:00Z' });
    const inbox = task({ day: null, plannedDay: null });
    const later = task({ day: '2026-10-03' });
    const all = [later, done, second, inbox, first];
    expect(openOn(all, today, today).map((t) => t.id)).toEqual([first.id, second.id]);
    expect(doneOn(all, today).map((t) => t.id)).toEqual([done.id]);
    expect(countTasks(all, today)).toMatchObject({ inbox: 1, today: 2, upcoming: 1 });
  });

  it('reorders within existing slots', () => {
    const a = task({ sortOrder: 1 });
    const b = task({ sortOrder: 4 });
    const c = task({ sortOrder: 9 });
    expect(moveInOrder([a.id, b.id, c.id], c.id, 0)).toEqual([c.id, a.id, b.id]);
    expect(reorderSlots([a, b, c], [c.id, a.id, b.id])).toEqual({ [c.id]: 1, [a.id]: 4, [b.id]: 9 });
  });
});

describe('repeat labels', () => {
  it('reads naturally', () => {
    expect(repeatLabel({ type: 'daily' })).toBe('Daily');
    expect(repeatLabel({ type: 'weekly', days: [5, 1, 3] })).toBe('Mon, Wed, Fri');
    expect(repeatLabel({ type: 'weekly', days: [4] })).toBe('Every Thu');
    expect(repeatLabel({ type: 'interval', every: 3 })).toBe('Every 3 days');
    expect(repeatLabel(null)).toBeNull();
  });
});

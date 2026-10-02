import { describe, expect, it } from 'vitest';
import { addDays, isValidDay, isoWeekday } from '../src/lib/dates.js';
import { nextOccurrence } from '../src/lib/repeat.js';

describe('dates', () => {
  it('validates real calendar days only', () => {
    expect(isValidDay('2026-10-01')).toBe(true);
    expect(isValidDay('2028-02-29')).toBe(true);
    expect(isValidDay('2026-02-29')).toBe(false);
    expect(isValidDay('2026-13-01')).toBe(false);
    expect(isValidDay('2026-1-01')).toBe(false);
    expect(isValidDay('0000-01-01')).toBe(false);
    expect(isValidDay('2026-10-01T10:00')).toBe(false);
  });

  it('adds days across month and year boundaries', () => {
    expect(addDays('2026-09-30', 1)).toBe('2026-10-01');
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
  });

  it('numbers weekdays the ISO way', () => {
    expect(isoWeekday('2026-09-28')).toBe(1); // Monday
    expect(isoWeekday('2026-10-01')).toBe(4); // Thursday
    expect(isoWeekday('2026-10-04')).toBe(7); // Sunday
  });
});

describe('nextOccurrence', () => {
  const thursday = '2026-10-01';

  it('repeats daily and every n days', () => {
    expect(nextOccurrence({ type: 'daily' }, thursday, thursday)).toBe('2026-10-02');
    expect(nextOccurrence({ type: 'interval', every: 3 }, thursday, thursday)).toBe('2026-10-04');
  });

  it('skips weekends for weekday repeats', () => {
    expect(nextOccurrence({ type: 'weekdays' }, '2026-10-02', '2026-10-02')).toBe('2026-10-05');
    expect(nextOccurrence({ type: 'weekdays' }, thursday, thursday)).toBe('2026-10-02');
  });

  it('finds the next matching weekday', () => {
    const monWedFri = { type: 'weekly' as const, days: [1, 3, 5] };
    expect(nextOccurrence(monWedFri, thursday, thursday)).toBe('2026-10-02');
    expect(nextOccurrence(monWedFri, '2026-10-02', '2026-10-02')).toBe('2026-10-05');
    expect(nextOccurrence({ type: 'weekly', days: [4] }, thursday, thursday)).toBe('2026-10-08');
  });

  it('keeps the day of the month and clamps short months', () => {
    expect(nextOccurrence({ type: 'monthly' }, '2026-10-15', '2026-10-15')).toBe('2026-11-15');
    expect(nextOccurrence({ type: 'monthly' }, '2027-01-31', '2027-01-31')).toBe('2027-02-28');
    expect(nextOccurrence({ type: 'monthly' }, '2027-02-28', '2027-01-31')).toBe('2027-03-31');
    expect(nextOccurrence({ type: 'monthly' }, '2026-12-05', '2026-12-05')).toBe('2027-01-05');
  });
});

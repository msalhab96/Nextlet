const DAY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

/** True for a real calendar date written as YYYY-MM-DD, between 1900 and 2999. */
export function isValidDay(value: string): boolean {
  const match = DAY_PATTERN.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  if (year < 1900 || year > 2999) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function toUtc(day: string): Date {
  return new Date(`${day}T00:00:00Z`);
}

function fromUtc(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function addDays(day: string, amount: number): string {
  const date = toUtc(day);
  date.setUTCDate(date.getUTCDate() + amount);
  return fromUtc(date);
}

/** ISO weekday: Monday is 1, Sunday is 7. */
export function isoWeekday(day: string): number {
  const weekday = toUtc(day).getUTCDay();
  return weekday === 0 ? 7 : weekday;
}

export function daysInMonth(year: number, monthIndex: number): number {
  return new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
}

export function formatDay(year: number, monthIndex: number, date: number): string {
  return `${year}-${String(monthIndex + 1).padStart(2, '0')}-${String(date).padStart(2, '0')}`;
}

export function laterDay(a: string, b: string): string {
  return a > b ? a : b;
}

export function utcToday(now: Date = new Date()): string {
  return fromUtc(now);
}

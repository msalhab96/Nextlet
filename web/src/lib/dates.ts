// Days are plain 'YYYY-MM-DD' strings. All arithmetic happens in UTC so that a
// day never shifts because of the viewer's timezone or daylight saving.

export const WEEKDAY_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as const;
export const WEEKDAY_LONG = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'] as const;
export const MONTH_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;
export const MONTH_LONG = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
] as const;

const pad = (value: number) => String(value).padStart(2, '0');

/** The viewer's local calendar day. */
export function localDay(date: Date = new Date()): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function isValidDay(value: string | null | undefined): value is string {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = toUtc(value);
  return !Number.isNaN(date.getTime()) && fromUtc(date) === value;
}

function toUtc(day: string): Date {
  const [year, month, date] = day.split('-').map(Number);
  return new Date(Date.UTC(year!, month! - 1, date!));
}

function fromUtc(date: Date): string {
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

export function makeDay(year: number, monthIndex: number, date: number): string {
  return fromUtc(new Date(Date.UTC(year, monthIndex, date)));
}

export function dayParts(day: string): { year: number; month: number; date: number } {
  const [year, month, date] = day.split('-').map(Number);
  return { year: year!, month: month! - 1, date: date! };
}

export function addDays(day: string, amount: number): string {
  const date = toUtc(day);
  date.setUTCDate(date.getUTCDate() + amount);
  return fromUtc(date);
}

/** First day of the month, `amount` months away. */
export function addMonths(day: string, amount: number): string {
  const { year, month } = dayParts(day);
  return makeDay(year, month + amount, 1);
}

export function daysInMonth(year: number, monthIndex: number): number {
  return new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
}

/** ISO weekday: Monday is 1, Sunday is 7. */
export function isoWeekday(day: string): number {
  const weekday = toUtc(day).getUTCDay();
  return weekday === 0 ? 7 : weekday;
}

/** Weeks start on Monday. */
export function startOfWeek(day: string): string {
  return addDays(day, 1 - isoWeekday(day));
}

export function daysBetween(from: string, to: string): number {
  return Math.round((toUtc(to).getTime() - toUtc(from).getTime()) / 86_400_000);
}

export function isoWeekNumber(day: string): number {
  const thursday = addDays(day, 4 - isoWeekday(day));
  return Math.floor(daysBetween(`${thursday.slice(0, 4)}-01-01`, thursday) / 7) + 1;
}

/** "Thu 1 Oct", with the year added when it is not the current one. */
export function formatShort(day: string, today?: string): string {
  const { year, month, date } = dayParts(day);
  const label = `${WEEKDAY_SHORT[isoWeekday(day) - 1]} ${date} ${MONTH_SHORT[month]}`;
  return today && Number(today.slice(0, 4)) !== year ? `${label} ${year}` : label;
}

/** "Thursday · 1 October" */
export function formatLong(day: string): string {
  const { month, date } = dayParts(day);
  return `${WEEKDAY_LONG[isoWeekday(day) - 1]} · ${date} ${MONTH_LONG[month]}`;
}

/** "Today", "Tomorrow", "Yesterday", or "Mon 5 Oct". */
export function relativeDay(day: string, today: string): string {
  const diff = daysBetween(today, day);
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Tomorrow';
  if (diff === -1) return 'Yesterday';
  return formatShort(day, today);
}

/** "Today · Thu 1 Oct", or just "Mon 5 Oct" for days without a nickname. */
export function dayWithDate(day: string, today: string): string {
  const relative = relativeDay(day, today);
  const short = formatShort(day, today);
  return relative === short ? short : `${relative} · ${short}`;
}

/** "From Tue" for recent days, "From 12 Sep" for older ones. */
export function fromLabel(origin: string, today: string): string {
  if (Math.abs(daysBetween(origin, today)) <= 6) return `From ${WEEKDAY_SHORT[isoWeekday(origin) - 1]}`;
  const { month, date } = dayParts(origin);
  return `From ${date} ${MONTH_SHORT[month]}`;
}

/** "28 Sep – 4 Oct" */
export function weekRangeLabel(weekStart: string): string {
  const start = dayParts(weekStart);
  const end = dayParts(addDays(weekStart, 6));
  return start.month === end.month
    ? `${start.date} – ${end.date} ${MONTH_SHORT[end.month]}`
    : `${start.date} ${MONTH_SHORT[start.month]} – ${end.date} ${MONTH_SHORT[end.month]}`;
}

/** "October 2026" */
export function monthLabel(day: string): string {
  const { year, month } = dayParts(day);
  return `${MONTH_LONG[month]} ${year}`;
}

/** The Monday-first weeks that cover the month containing `day`. */
export function monthWeeks(day: string): { monthStart: string; weeks: string[][] } {
  const { year, month } = dayParts(day);
  const monthStart = makeDay(year, month, 1);
  const monthEnd = makeDay(year, month, daysInMonth(year, month));
  const weeks: string[][] = [];
  for (let weekStart = startOfWeek(monthStart); weekStart <= monthEnd; weekStart = addDays(weekStart, 7)) {
    weeks.push(Array.from({ length: 7 }, (_, index) => addDays(weekStart, index)));
  }
  return { monthStart, weeks };
}

export function ordinal(value: number): string {
  const mod100 = value % 100;
  if (mod100 >= 11 && mod100 <= 13) return `${value}th`;
  switch (value % 10) {
    case 1:
      return `${value}st`;
    case 2:
      return `${value}nd`;
    case 3:
      return `${value}rd`;
    default:
      return `${value}th`;
  }
}

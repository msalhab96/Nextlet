import type { RepeatRule } from '../types';
import { WEEKDAY_LONG, WEEKDAY_SHORT, isoWeekday, ordinal } from './dates';

export function repeatLabel(rule: RepeatRule | null): string | null {
  if (!rule) return null;
  switch (rule.type) {
    case 'daily':
      return 'Daily';
    case 'weekdays':
      return 'Weekdays';
    case 'interval':
      return `Every ${rule.every} days`;
    case 'monthly':
      return 'Monthly';
    case 'weekly': {
      const days = [...new Set(rule.days)].sort((a, b) => a - b);
      if (days.length === 7) return 'Daily';
      if (days.length === 1) return `Every ${WEEKDAY_SHORT[days[0]! - 1]}`;
      return days.map((day) => WEEKDAY_SHORT[day - 1]).join(', ');
    }
  }
}

export type RepeatChoice = 'none' | 'daily' | 'weekdays' | 'weekly' | 'every2' | 'every3' | 'monthly' | 'custom' | `every${number}`;

export function repeatChoice(rule: RepeatRule | null, day: string): RepeatChoice {
  if (!rule) return 'none';
  switch (rule.type) {
    case 'daily':
      return 'daily';
    case 'weekdays':
      return 'weekdays';
    case 'monthly':
      return 'monthly';
    case 'interval':
      return `every${rule.every}`;
    case 'weekly':
      return rule.days.length === 1 && rule.days[0] === isoWeekday(day) ? 'weekly' : 'custom';
  }
}

export function repeatOptions(day: string, rule: RepeatRule | null): { value: RepeatChoice; label: string }[] {
  const options: { value: RepeatChoice; label: string }[] = [
    { value: 'none', label: 'Never' },
    { value: 'daily', label: 'Daily' },
    { value: 'weekdays', label: 'Weekdays' },
    { value: 'weekly', label: `Weekly on ${WEEKDAY_LONG[isoWeekday(day) - 1]}` },
    { value: 'every2', label: 'Every 2 days' },
    { value: 'every3', label: 'Every 3 days' },
    { value: 'monthly', label: `Monthly on the ${ordinal(Number(day.slice(8, 10)))}` },
    { value: 'custom', label: 'Pick weekdays…' },
  ];
  if (rule?.type === 'interval' && rule.every !== 2 && rule.every !== 3) {
    options.splice(6, 0, { value: `every${rule.every}`, label: `Every ${rule.every} days` });
  }
  return options;
}

export function ruleForChoice(choice: RepeatChoice, day: string, current: RepeatRule | null): RepeatRule | null {
  switch (choice) {
    case 'none':
      return null;
    case 'daily':
      return { type: 'daily' };
    case 'weekdays':
      return { type: 'weekdays' };
    case 'weekly':
      return { type: 'weekly', days: [isoWeekday(day)] };
    case 'monthly':
      return { type: 'monthly' };
    case 'custom':
      return current?.type === 'weekly' ? current : { type: 'weekly', days: [isoWeekday(day)] };
    default:
      return { type: 'interval', every: Number(choice.slice('every'.length)) };
  }
}

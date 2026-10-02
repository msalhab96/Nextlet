export function cx(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(' ');
}

export function formatEstimate(minutes: number): string {
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${hours} h ${rest} min` : `${hours} h`;
}

export function formatClock(totalSeconds: number): string {
  const seconds = Math.max(0, Math.round(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = String(Math.floor((seconds % 3600) / 60)).padStart(2, '0');
  const rest = String(seconds % 60).padStart(2, '0');
  return hours ? `${hours}:${minutes}:${rest}` : `${minutes}:${rest}`;
}

export function plural(count: number, one: string, many = `${one}s`): string {
  return `${count} ${count === 1 ? one : many}`;
}

/** Mixes a hex colour with white, for project dots that sit on the dark Next up card. */
export function lighten(hex: string, amount: number): string {
  const value = Number.parseInt(hex.slice(1), 16);
  const mix = (channel: number) => Math.round(channel + (255 - channel) * amount);
  const r = mix((value >> 16) & 255);
  const g = mix((value >> 8) & 255);
  const b = mix(value & 255);
  return `#${((r << 16) | (g << 8) | b).toString(16).padStart(6, '0')}`;
}

export const PRIORITY_LABELS = ['No priority', 'P1 · High', 'P2 · Medium', 'P3 · Low'] as const;
export const PRIORITY_COLORS = ['#8A8D96', '#C2410C', '#3B3BD6', '#8A8D96'] as const;
export const NO_PROJECT_COLOR = '#A9ABB3';
export const ESTIMATE_CHOICES = [5, 10, 15, 20, 25, 30, 45, 60, 90, 120, 180];
export const DEFAULT_FOCUS_MINUTES = 25;

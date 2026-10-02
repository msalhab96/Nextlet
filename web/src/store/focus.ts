import { useEffect, useState, useSyncExternalStore } from 'react';

// A focus session is a countdown for one task (or a short break). It lives in
// localStorage so a reload, or another tab, picks up the same running timer.

export interface FocusSession {
  kind: 'task' | 'break';
  taskId: string | null;
  totalSeconds: number;
  /** Seconds left when paused. While running, endsAt is the source of truth. */
  remainingSeconds: number;
  /** Epoch milliseconds when a running session reaches zero; null when paused. */
  endsAt: number | null;
  /** The task was marked done from the focus screen. */
  finished: boolean;
}

const STORAGE_KEY = 'nextlet.focus.v1';
const listeners = new Set<() => void>();

function read(): FocusSession | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as FocusSession;
    return typeof parsed.totalSeconds === 'number' && (parsed.kind === 'task' || parsed.kind === 'break') ? parsed : null;
  } catch {
    return null;
  }
}

let session: FocusSession | null = read();

function set(next: FocusSession | null) {
  session = next;
  try {
    if (next) localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
    else localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Private browsing or storage disabled: the timer still works for this tab.
  }
  for (const listener of listeners) listener();
}

if (typeof window !== 'undefined') {
  window.addEventListener('storage', (event) => {
    if (event.key !== STORAGE_KEY) return;
    session = read();
    for (const listener of listeners) listener();
  });
}

export function remainingSeconds(current: FocusSession, now: number): number {
  return current.endsAt === null ? current.remainingSeconds : Math.max(0, Math.ceil((current.endsAt - now) / 1000));
}

export const focus = {
  get: () => session,

  start(taskId: string, minutes: number) {
    const seconds = Math.round(minutes * 60);
    set({ kind: 'task', taskId, totalSeconds: seconds, remainingSeconds: seconds, endsAt: Date.now() + seconds * 1000, finished: false });
  },

  startBreak(minutes = 5) {
    const seconds = minutes * 60;
    set({ kind: 'break', taskId: null, totalSeconds: seconds, remainingSeconds: seconds, endsAt: Date.now() + seconds * 1000, finished: false });
  },

  pause() {
    if (!session || session.endsAt === null) return;
    set({ ...session, remainingSeconds: remainingSeconds(session, Date.now()), endsAt: null });
  },

  resume() {
    if (!session || session.endsAt !== null || session.remainingSeconds <= 0) return;
    set({ ...session, endsAt: Date.now() + session.remainingSeconds * 1000 });
  },

  addMinutes(minutes: number) {
    if (!session) return;
    const now = Date.now();
    const remaining = remainingSeconds(session, now) + minutes * 60;
    set({
      ...session,
      remainingSeconds: remaining,
      totalSeconds: Math.max(session.totalSeconds, remaining),
      endsAt: now + remaining * 1000,
      finished: false,
    });
  },

  /** Called when a running countdown reaches zero. */
  timeUp() {
    if (!session || session.endsAt === null) return;
    set({ ...session, remainingSeconds: 0, endsAt: null });
  },

  finish() {
    if (!session) return;
    set({ ...session, remainingSeconds: remainingSeconds(session, Date.now()), endsAt: null, finished: true });
  },

  end() {
    set(null);
  },
};

export function useFocusSession(): FocusSession | null {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    () => session,
    () => session,
  );
}

/** The current time, refreshed every second while `active`. */
export function useNow(active: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) return;
    setNow(Date.now());
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [active]);
  return now;
}

import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { localDay } from './dates';

const TodayContext = createContext<string>(localDay());

/** Keeps "today" correct across midnight and when the laptop wakes up. */
export function TodayProvider({ children }: { children: ReactNode }) {
  const [today, setToday] = useState(() => localDay());

  useEffect(() => {
    let timer: number | undefined;
    const sync = () => setToday(localDay());
    const scheduleMidnight = () => {
      const now = new Date();
      const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
      timer = window.setTimeout(() => {
        sync();
        scheduleMidnight();
      }, midnight.getTime() - now.getTime());
    };
    const onVisible = () => {
      if (document.visibilityState === 'visible') sync();
    };
    scheduleMidnight();
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('focus', sync);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('focus', sync);
    };
  }, []);

  return <TodayContext.Provider value={today}>{children}</TodayContext.Provider>;
}

export function useToday(): string {
  return useContext(TodayContext);
}

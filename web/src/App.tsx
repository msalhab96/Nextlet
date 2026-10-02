import { useEffect, useRef, useState } from 'react';
import { Navigate, Route, Routes, useLocation, useNavigate } from 'react-router';
import { CaptureDialog } from './components/CaptureDialog';
import { LogoMark } from './components/Icon';
import { SearchDialog } from './components/SearchDialog';
import { ShortcutsDialog } from './components/ShortcutsDialog';
import { SignIn } from './components/SignIn';
import { MobileBar, Sidebar } from './components/Sidebar';
import { TaskDetail } from './components/TaskDetail';
import { Toaster } from './components/Toaster';
import { DEFAULT_FOCUS_MINUTES, cx, formatClock } from './lib/format';
import { TodayProvider, useToday } from './lib/today';
import { focus, remainingSeconds, useFocusSession, useNow } from './store/focus';
import { actions, getState, useStore } from './store/store';
import { FocusView } from './views/FocusView';
import { InboxView } from './views/InboxView';
import { ProjectView } from './views/ProjectView';
import { TodayView } from './views/TodayView';
import { UpcomingView } from './views/UpcomingView';

type DialogName = 'search' | 'capture' | 'shortcuts' | null;

export function App() {
  return (
    <TodayProvider>
      <Shell />
    </TodayProvider>
  );
}

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  if (target.isContentEditable) return true;
  if (target.tagName === 'TEXTAREA' || target.tagName === 'SELECT') return true;
  if (target.tagName === 'INPUT') {
    return !['checkbox', 'radio', 'button', 'submit', 'reset'].includes((target as HTMLInputElement).type);
  }
  return false;
}

function Shell() {
  const today = useToday();
  const navigate = useNavigate();
  const location = useLocation();
  const status = useStore((state) => state.status);
  const loadError = useStore((state) => state.loadError);
  const selectedId = useStore((state) => state.selectedTaskId);
  const hasSelection = useStore((state) => state.selectedTaskId !== null && state.tasks[state.selectedTaskId] !== undefined);
  const [dialog, setDialog] = useState<DialogName>(null);
  const [navOpen, setNavOpen] = useState(false);
  const dialogRef = useRef<DialogName>(dialog);
  dialogRef.current = dialog;

  useEffect(() => {
    void actions.load(today);
    // Load once; later changes of "today" are picked up by the refresh below.
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Pick up changes from other tabs or devices when the window regains attention.
  useEffect(() => {
    const refresh = () => void actions.refresh(today);
    const onVisible = () => {
      if (document.visibilityState === 'visible') refresh();
    };
    refresh();
    window.addEventListener('focus', refresh);
    window.addEventListener('online', refresh);
    document.addEventListener('visibilitychange', onVisible);
    const timer = window.setInterval(refresh, 60_000);
    return () => {
      window.removeEventListener('focus', refresh);
      window.removeEventListener('online', refresh);
      document.removeEventListener('visibilitychange', onVisible);
      window.clearInterval(timer);
    };
  }, [today]);

  useEffect(() => setNavOpen(false), [location.pathname, location.search]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const mod = event.metaKey || event.ctrlKey;
      if (mod && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setDialog((current) => (current === 'search' ? null : 'search'));
        return;
      }
      if (dialogRef.current || event.defaultPrevented || isTypingTarget(event.target)) return;

      const { selectedTaskId, tasks } = getState();
      const selected = selectedTaskId ? tasks[selectedTaskId] : undefined;

      if (mod && event.key === 'Enter') {
        if (selected) {
          event.preventDefault();
          void actions.toggleComplete(selected.id, today);
        }
        return;
      }
      if (mod && event.key === 'ArrowRight') {
        if (selected && !selected.completedAt) {
          event.preventDefault();
          actions.pushToNextDay([selected.id], today);
        }
        return;
      }
      if (mod && event.key.toLowerCase() === 'z' && !event.shiftKey) {
        if (actions.undoLatest()) event.preventDefault();
        return;
      }
      if (mod || event.altKey) return;

      switch (event.key) {
        case 'n':
        case 'N':
          event.preventDefault();
          setDialog('capture');
          break;
        case '?':
          event.preventDefault();
          setDialog('shortcuts');
          break;
        case 'f':
        case 'F':
          event.preventDefault();
          if (selected && !selected.completedAt) focus.start(selected.id, selected.estimateMinutes ?? DEFAULT_FOCUS_MINUTES);
          navigate('/focus');
          break;
        case 't':
          navigate('/today');
          break;
        case 'i':
          navigate('/inbox');
          break;
        case 'u':
          navigate('/upcoming');
          break;
        case 'Escape':
          if (selectedTaskId) actions.select(null);
          else setNavOpen(false);
          break;
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [today, navigate]);

  if (status === 'locked') return <SignIn />;

  if (status !== 'ready') {
    return (
      <div className="splash">
        <LogoMark size={44} />
        {status === 'loading' ? (
          <p className="splash__text">Loading your day…</p>
        ) : (
          <>
            <h1 className="splash__title">Can’t reach Nextlet</h1>
            <p className="splash__text">{loadError}</p>
            <button type="button" className="btn btn--primary" onClick={() => void actions.load(today)}>
              Try again
            </button>
          </>
        )}
      </div>
    );
  }

  const closeDialog = () => setDialog(null);

  return (
    <div className={cx('app', hasSelection && 'has-detail', navOpen && 'nav-open')}>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <MobileBar onMenu={() => setNavOpen(true)} onSearch={() => setDialog('search')} onCapture={() => setDialog('capture')} />
      <Sidebar onSearch={() => setDialog('search')} onCapture={() => setDialog('capture')} onShortcuts={() => setDialog('shortcuts')} />
      {navOpen && <div className="nav-backdrop" aria-hidden="true" onClick={() => setNavOpen(false)} />}

      <main className="main" id="main" tabIndex={-1}>
        <Routes>
          <Route path="/" element={<Navigate to="/today" replace />} />
          <Route path="/today" element={<TodayView />} />
          <Route path="/inbox" element={<InboxView />} />
          <Route path="/upcoming" element={<UpcomingView />} />
          <Route path="/projects/:projectId" element={<ProjectView />} />
          <Route path="/focus" element={<FocusView />} />
          <Route path="*" element={<Navigate to="/today" replace />} />
        </Routes>
      </main>

      {hasSelection && selectedId && (
        <>
          <div className="detail-backdrop" aria-hidden="true" onClick={() => actions.select(null)} />
          <TaskDetail key={selectedId} taskId={selectedId} />
        </>
      )}

      <Toaster />
      <DocumentTitle />

      {dialog === 'search' && <SearchDialog onClose={closeDialog} />}
      {dialog === 'capture' && <CaptureDialog onClose={closeDialog} />}
      {dialog === 'shortcuts' && <ShortcutsDialog onClose={closeDialog} />}
    </div>
  );
}

const VIEW_TITLES: Record<string, string> = { '/today': 'Today', '/inbox': 'Inbox', '/upcoming': 'Upcoming', '/focus': 'Focus' };

/** Keeps the tab title useful: the running timer during focus, otherwise the view's name. */
function DocumentTitle() {
  const location = useLocation();
  const session = useFocusSession();
  const running = session !== null && session.endsAt !== null;
  const now = useNow(running);
  const sessionTask = useStore((state) => (session?.taskId ? state.tasks[session.taskId] : undefined));
  const projectName = useStore((state) => {
    const match = location.pathname.match(/^\/projects\/(.+)$/);
    return match ? state.projects.find((project) => project.id === match[1])?.name : undefined;
  });
  const remaining = session ? remainingSeconds(session, now) : 0;

  useEffect(() => {
    if (running && remaining <= 0) focus.timeUp();
  }, [running, remaining]);

  useEffect(() => {
    if (session && !session.finished) {
      const label = session.kind === 'break' ? 'Break' : (sessionTask?.title ?? 'Focus');
      document.title =
        remaining <= 0 ? `Time’s up · ${label}` : `${running ? '' : 'Paused · '}${formatClock(remaining)} · ${label}`;
      return;
    }
    const view = VIEW_TITLES[location.pathname] ?? projectName;
    document.title = view ? `${view} · Nextlet` : 'Nextlet';
  }, [session, sessionTask?.title, remaining, running, location.pathname, projectName]);

  return null;
}

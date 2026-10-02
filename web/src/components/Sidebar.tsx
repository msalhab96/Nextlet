import { useMemo, useState } from 'react';
import { NavLink } from 'react-router';
import { cx, formatClock } from '../lib/format';
import { countTasks } from '../lib/tasks';
import { useToday } from '../lib/today';
import { remainingSeconds, useFocusSession, useNow } from '../store/focus';
import { useTaskList } from '../store/hooks';
import { actions, useStore } from '../store/store';
import { Icon, LogoMark, type IconName } from './Icon';

const isMac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad/.test(navigator.platform);

function NavItem({ to, icon, label, count, accent }: { to: string; icon: IconName; label: string; count?: string | number; accent?: boolean }) {
  return (
    <NavLink to={to} className={({ isActive }) => cx('nav-item', isActive && 'is-active')}>
      <Icon name={icon} />
      <span className="nav-item__label">{label}</span>
      {count !== undefined && count !== 0 && <span className={cx('nav-item__count', accent && 'is-accent')}>{count}</span>}
    </NavLink>
  );
}

function NewProject({ onDone }: { onDone: () => void }) {
  const [name, setName] = useState('');
  const save = async () => {
    const value = name.trim();
    if (value) await actions.createProject(value);
    onDone();
  };
  return (
    <div className="nav-item nav-item--input">
      <span className="dot dot--lg" style={{ background: '#A9ABB3' }} />
      <input
        autoFocus
        aria-label="New project name"
        placeholder="Project name"
        maxLength={60}
        value={name}
        onChange={(event) => setName(event.target.value)}
        onBlur={() => void save()}
        onKeyDown={(event) => {
          if (event.key === 'Enter') event.currentTarget.blur();
          if (event.key === 'Escape') {
            setName('');
            onDone();
          }
        }}
      />
    </div>
  );
}

function SyncStatus() {
  const pending = useStore((state) => state.pending);
  const syncError = useStore((state) => state.syncError);
  if (pending > 0) {
    return (
      <span className="sync-status">
        <Icon name="loader" size={15} className="spin" />
        Saving…
      </span>
    );
  }
  if (syncError) {
    return (
      <span className="sync-status is-error" title={syncError}>
        <Icon name="cloudOff" size={15} />
        Last change not saved
      </span>
    );
  }
  return (
    <span className="sync-status">
      <Icon name="cloudCheck" size={15} />
      All changes saved
    </span>
  );
}

interface SidebarProps {
  onSearch: () => void;
  onCapture: () => void;
  onShortcuts: () => void;
}

export function Sidebar({ onSearch, onCapture, onShortcuts }: SidebarProps) {
  const today = useToday();
  const tasks = useTaskList();
  const projects = useStore((state) => state.projects);
  const authRequired = useStore((state) => state.authRequired);
  const counts = useMemo(() => countTasks(tasks, today), [tasks, today]);
  const session = useFocusSession();
  const now = useNow(!!session && session.endsAt !== null);
  const [creating, setCreating] = useState(false);

  const focusBadge = session && !session.finished ? formatClock(remainingSeconds(session, now)) : undefined;

  return (
    <aside className="sidebar" aria-label="Sidebar">
      <div className="sidebar__brand">
        <LogoMark />
        <span className="wordmark">Nextlet</span>
      </div>

      <div className="sidebar__tools">
        <button type="button" className="search-btn" onClick={onSearch}>
          <Icon name="search" size={17} />
          <span>Search</span>
          <kbd className="kbd">{isMac ? '⌘K' : 'Ctrl K'}</kbd>
        </button>
        <button type="button" className="icon-btn icon-btn--boxed" aria-label="Quick capture (N)" title="Quick capture (N)" onClick={onCapture}>
          <Icon name="plus" strokeWidth={2.2} />
        </button>
      </div>

      <nav aria-label="Main" className="nav">
        <NavItem to="/inbox" icon="inbox" label="Inbox" count={counts.inbox} />
        <NavItem to="/today" icon="sun" label="Today" count={counts.today} accent />
        <NavItem to="/upcoming" icon="calendar" label="Upcoming" count={counts.upcoming} />
        <NavItem to="/focus" icon="target" label="Focus" count={focusBadge} accent />
      </nav>

      <div className="projects">
        <div className="projects__head">
          <span className="eyebrow">Projects</span>
          <button type="button" className="icon-btn icon-btn--sm" aria-label="New project" onClick={() => setCreating(true)}>
            <Icon name="plus" size={16} strokeWidth={2} />
          </button>
        </div>
        {projects.map((project) => (
          <NavLink key={project.id} to={`/projects/${project.id}`} className={({ isActive }) => cx('nav-item nav-item--project', isActive && 'is-active')}>
            <span className="dot dot--lg" style={{ background: project.color }} />
            <span className="nav-item__label">{project.name}</span>
            {counts.byProject[project.id] ? <span className="nav-item__count">{counts.byProject[project.id]}</span> : null}
          </NavLink>
        ))}
        {creating && <NewProject onDone={() => setCreating(false)} />}
        {projects.length === 0 && !creating && <p className="projects__empty">No projects yet.</p>}
      </div>

      <div className="sidebar__foot">
        <SyncStatus />
        <span className="sidebar__foot-actions">
          <button type="button" className="icon-btn" aria-label="Keyboard shortcuts" title="Keyboard shortcuts (?)" onClick={onShortcuts}>
            <Icon name="keyboard" />
          </button>
          {authRequired && (
            <button type="button" className="icon-btn" aria-label="Lock Nextlet" title="Lock Nextlet" onClick={() => void actions.signOut()}>
              <Icon name="lock" />
            </button>
          )}
        </span>
      </div>
    </aside>
  );
}

export function MobileBar({ onMenu, onSearch, onCapture }: { onMenu: () => void; onSearch: () => void; onCapture: () => void }) {
  return (
    <header className="mobile-bar">
      <button type="button" className="icon-btn" aria-label="Open menu" onClick={onMenu}>
        <Icon name="menu" />
      </button>
      <span className="mobile-bar__brand">
        <LogoMark size={26} />
        <span className="wordmark wordmark--sm">Nextlet</span>
      </span>
      <button type="button" className="icon-btn" aria-label="Search" onClick={onSearch}>
        <Icon name="search" />
      </button>
      <button type="button" className="icon-btn" aria-label="Quick capture" onClick={onCapture}>
        <Icon name="plus" strokeWidth={2.2} />
      </button>
    </header>
  );
}

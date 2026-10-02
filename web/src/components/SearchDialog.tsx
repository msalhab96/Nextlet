import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router';
import { api } from '../api';
import { dayWithDate } from '../lib/dates';
import { NO_PROJECT_COLOR, cx } from '../lib/format';
import { effectiveDay } from '../lib/tasks';
import { useToday } from '../lib/today';
import { useProjectMap } from '../store/hooks';
import { actions } from '../store/store';
import type { Task } from '../types';
import { Dialog } from './Dialog';
import { Icon } from './Icon';

/** Where a task lives in the app, so search can take you there. */
export function routeForTask(task: Task, today: string): string {
  const day = effectiveDay(task, today);
  if (!day) return '/inbox';
  if (day === today) return '/today';
  return `/upcoming?date=${day}`;
}

export function SearchDialog({ onClose }: { onClose: () => void }) {
  const today = useToday();
  const navigate = useNavigate();
  const projects = useProjectMap();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Task[]>([]);
  const [active, setActive] = useState(0);
  const [state, setState] = useState<'idle' | 'loading' | 'done' | 'error'>('idle');

  useEffect(() => {
    const term = query.trim();
    if (!term) {
      setResults([]);
      setState('idle');
      return;
    }
    let cancelled = false;
    setState('loading');
    const timer = window.setTimeout(async () => {
      try {
        const found = await api.searchTasks(term);
        if (cancelled) return;
        setResults(found);
        setActive(0);
        setState('done');
      } catch {
        if (!cancelled) setState('error');
      }
    }, 150);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [query]);

  const open = (task: Task) => {
    actions.rememberTasks([task]);
    navigate(routeForTask(task, today));
    actions.select(task.id);
    onClose();
  };

  return (
    <Dialog label="Search tasks" onClose={onClose} className="dialog--search">
      <div className="search-field">
        <Icon name="search" size={19} />
        <input
          autoFocus
          role="combobox"
          aria-expanded={results.length > 0}
          aria-controls="search-results"
          aria-activedescendant={results[active] ? `search-${results[active].id}` : undefined}
          aria-label="Search tasks"
          placeholder="Search tasks and notes"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'ArrowDown') {
              event.preventDefault();
              setActive((index) => Math.min(index + 1, results.length - 1));
            } else if (event.key === 'ArrowUp') {
              event.preventDefault();
              setActive((index) => Math.max(index - 1, 0));
            } else if (event.key === 'Enter' && results[active]) {
              event.preventDefault();
              open(results[active]);
            }
          }}
        />
        <kbd className="kbd">esc</kbd>
      </div>
      <ul id="search-results" role="listbox" className="search-results" aria-label="Results">
        {results.map((task, index) => {
          const project = task.projectId ? projects.get(task.projectId) : undefined;
          const day = effectiveDay(task, today);
          return (
            <li
              key={task.id}
              id={`search-${task.id}`}
              role="option"
              aria-selected={index === active}
              className={cx('search-result', index === active && 'is-active', task.completedAt && 'is-done')}
              onMouseEnter={() => setActive(index)}
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => open(task)}
            >
              <span className="dot" style={{ background: project?.color ?? NO_PROJECT_COLOR }} />
              <span className="search-result__title">{task.title}</span>
              <span className="search-result__meta">
                {task.completedAt ? 'Done' : day ? dayWithDate(day, today) : 'Inbox'}
              </span>
            </li>
          );
        })}
      </ul>
      {state === 'done' && results.length === 0 && <p className="search-empty">No tasks match “{query.trim()}”.</p>}
      {state === 'error' && <p className="search-empty">Search isn’t available right now.</p>}
      {state === 'idle' && <p className="search-empty">Type to search titles and notes, including finished tasks.</p>}
    </Dialog>
  );
}

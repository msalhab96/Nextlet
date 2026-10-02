import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router';
import { AddTask } from '../components/AddTask';
import { Dialog } from '../components/Dialog';
import { Icon } from '../components/Icon';
import { SectionTitle, TaskList } from '../components/TaskList';
import { cx, plural } from '../lib/format';
import { bySortOrder, effectiveDay, isOpen } from '../lib/tasks';
import { useToday } from '../lib/today';
import { useTaskList } from '../store/hooks';
import { actions, useStore } from '../store/store';

const PALETTE = ['#3B3BD6', '#0F766E', '#C2410C', '#A16207', '#7C3AED', '#BE185D', '#0369A1', '#4D7C0F'];

export function ProjectView() {
  const { projectId } = useParams();
  const navigate = useNavigate();
  const today = useToday();
  const tasks = useTaskList();
  const project = useStore((state) => state.projects.find((candidate) => candidate.id === projectId));
  const [renaming, setRenaming] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!menuOpen) return;
    const close = (event: MouseEvent) => {
      if (!menuRef.current?.contains(event.target as Node)) setMenuOpen(false);
    };
    document.addEventListener('mousedown', close);
    return () => document.removeEventListener('mousedown', close);
  }, [menuOpen]);

  const groups = useMemo(() => {
    const open = tasks.filter((task) => isOpen(task) && task.projectId === projectId);
    const shownDay = (task: (typeof open)[number]) => effectiveDay(task, today);
    return {
      today: open.filter((task) => shownDay(task) === today).sort(bySortOrder),
      later: open
        .filter((task) => {
          const day = shownDay(task);
          return day !== null && day > today;
        })
        .sort((a, b) => (shownDay(a) ?? '').localeCompare(shownDay(b) ?? '') || bySortOrder(a, b)),
      noDay: open.filter((task) => shownDay(task) === null).sort(bySortOrder),
      recentlyDone: tasks
        .filter((task) => !isOpen(task) && task.projectId === projectId)
        .sort((a, b) => (b.completedAt ?? '').localeCompare(a.completedAt ?? ''))
        .slice(0, 5),
      openCount: open.length,
    };
  }, [tasks, projectId, today]);

  if (!project) {
    return (
      <div className="view">
        <div className="empty">
          <h1 className="empty__title">Project not found</h1>
          <p className="empty__text">It may have been deleted.</p>
          <button type="button" className="btn" onClick={() => navigate('/today')}>
            Go to Today
          </button>
        </div>
      </div>
    );
  }

  const isEmpty = groups.openCount === 0 && groups.recentlyDone.length === 0;

  return (
    <div className="view">
      <header className="view-header">
        <div className="view-header__titles">
          <span className="eyebrow">Project · {plural(groups.openCount, 'open task')}</span>
          {renaming ? (
            <ProjectNameInput
              initial={project.name}
              onDone={(name) => {
                setRenaming(false);
                if (name && name !== project.name) void actions.updateProject(project.id, { name });
              }}
            />
          ) : (
            <h1 className="view-title view-title--project">
              <span className="dot dot--title" style={{ background: project.color }} />
              {project.name}
            </h1>
          )}
        </div>
        <div className="view-header__aside">
          <div className="menu" ref={menuRef}>
            <button type="button" className="btn" aria-expanded={menuOpen} onClick={() => setMenuOpen((open) => !open)}>
              <Icon name="more" />
              Project options
            </button>
            {menuOpen && (
              <div className="menu__panel">
                <button
                  type="button"
                  className="menu__item"
                  onClick={() => {
                    setMenuOpen(false);
                    setRenaming(true);
                  }}
                >
                  <Icon name="edit" size={16} />
                  Rename
                </button>
                <div className="menu__colors" role="group" aria-label="Colour">
                  {PALETTE.map((color) => (
                    <button
                      key={color}
                      type="button"
                      className={cx('swatch', project.color.toUpperCase() === color && 'is-active')}
                      style={{ background: color }}
                      aria-label={`Use colour ${color}`}
                      aria-pressed={project.color.toUpperCase() === color}
                      onClick={() => void actions.updateProject(project.id, { color })}
                    />
                  ))}
                </div>
                <button
                  type="button"
                  className="menu__item menu__item--danger"
                  onClick={() => {
                    setMenuOpen(false);
                    setConfirmDelete(true);
                  }}
                >
                  <Icon name="trash" size={16} />
                  Delete project
                </button>
              </div>
            )}
          </div>
        </div>
      </header>

      {isEmpty && (
        <div className="empty">
          <h2 className="empty__title">Nothing here yet.</h2>
          <p className="empty__text">Add a task below, or type #{project.name.replace(/\s+/g, '-')} in any quick add.</p>
        </div>
      )}

      <div className="sections">
        {groups.today.length > 0 && (
          <section className="section">
            <SectionTitle title="Today" count={String(groups.today.length)} />
            <TaskList tasks={groups.today} today={today} showProject={false} />
          </section>
        )}
        {groups.later.length > 0 && (
          <section className="section">
            <SectionTitle title="Coming up" count={String(groups.later.length)} />
            <TaskList tasks={groups.later} today={today} showProject={false} showDay />
          </section>
        )}
        {groups.noDay.length > 0 && (
          <section className="section">
            <SectionTitle title="No day yet" count={String(groups.noDay.length)} />
            <TaskList tasks={groups.noDay} today={today} showProject={false} action="today" />
          </section>
        )}
        {groups.recentlyDone.length > 0 && (
          <section className="section">
            <SectionTitle title="Recently done" />
            <TaskList tasks={groups.recentlyDone} today={today} showProject={false} showDay />
          </section>
        )}
      </div>

      <AddTask
        defaultDay={null}
        defaultProjectId={project.id}
        label={`Add a task to ${project.name}`}
        placeholder={`Add to ${project.name} — try “Book flights next week”`}
      />

      {confirmDelete && (
        <Dialog label={`Delete ${project.name}`} onClose={() => setConfirmDelete(false)} className="dialog--confirm">
          <h2 className="confirm__title">Delete “{project.name}”?</h2>
          <p className="confirm__text">
            {groups.openCount > 0
              ? `Its ${plural(groups.openCount, 'open task')} stay in Nextlet, just without a project.`
              : 'Its tasks stay in Nextlet, just without a project.'}
          </p>
          <div className="confirm__actions">
            <button type="button" className="btn" autoFocus onClick={() => setConfirmDelete(false)}>
              Cancel
            </button>
            <button
              type="button"
              className="btn btn--danger-solid"
              onClick={async () => {
                setConfirmDelete(false);
                if (await actions.deleteProject(project.id)) {
                  actions.toast(`Deleted the project “${project.name}”`);
                  navigate('/today');
                }
              }}
            >
              Delete project
            </button>
          </div>
        </Dialog>
      )}
    </div>
  );
}

function ProjectNameInput({ initial, onDone }: { initial: string; onDone: (name: string | null) => void }) {
  const [name, setName] = useState(initial);
  return (
    <input
      className="view-title view-title--input"
      aria-label="Project name"
      autoFocus
      maxLength={60}
      value={name}
      onChange={(event) => setName(event.target.value)}
      onFocus={(event) => event.currentTarget.select()}
      onBlur={() => onDone(name.trim() || null)}
      onKeyDown={(event) => {
        if (event.key === 'Enter') event.currentTarget.blur();
        if (event.key === 'Escape') onDone(null);
      }}
    />
  );
}

import { useMemo } from 'react';
import { AddTask } from '../components/AddTask';
import { Icon } from '../components/Icon';
import { AllClear, NextUpCard } from '../components/NextUpCard';
import { SectionTitle, TaskList } from '../components/TaskList';
import { addDays, formatLong, formatShort } from '../lib/dates';
import { NO_PROJECT_COLOR } from '../lib/format';
import { doneOn, openOn, pushedToTomorrow } from '../lib/tasks';
import { useToday } from '../lib/today';
import { useProjectMap, useTaskList } from '../store/hooks';
import { actions } from '../store/store';

export function TodayView() {
  const today = useToday();
  const tasks = useTaskList();
  const projects = useProjectMap();
  const todo = useMemo(() => openOn(tasks, today, today), [tasks, today]);
  const done = useMemo(() => doneOn(tasks, today), [tasks, today]);
  const pushed = useMemo(() => pushedToTomorrow(tasks, today), [tasks, today]);

  const total = todo.length + done.length;
  const percent = total ? Math.round((done.length / total) * 100) : 0;
  const next = todo[0];

  return (
    <div className="view">
      <header className="view-header">
        <div className="view-header__titles">
          <span className="eyebrow">{formatLong(today)}</span>
          <h1 className="view-title">Today</h1>
        </div>
        <div className="view-header__aside">
          {total > 0 && (
            <div className="progress">
              <span className="progress__label">
                <strong>
                  {done.length} of {total}
                </strong>{' '}
                done
              </span>
              <span
                className="progress__bar"
                role="progressbar"
                aria-label="Done today"
                aria-valuemin={0}
                aria-valuemax={total}
                aria-valuenow={done.length}
              >
                <span style={{ width: `${percent}%` }} />
              </span>
            </div>
          )}
          <button
            type="button"
            className="btn"
            disabled={todo.length === 0}
            onClick={() => actions.pushToNextDay(todo.map((task) => task.id), today)}
          >
            <Icon name="push" size={17} />
            Move unfinished to tomorrow
          </button>
        </div>
      </header>

      {next ? (
        <NextUpCard task={next} project={next.projectId ? projects.get(next.projectId) : undefined} today={today} />
      ) : (
        <AllClear hadTasks={total > 0} />
      )}

      <div className="sections">
        {todo.length > 0 && (
          <section className="section">
            <SectionTitle title="To do" count={`${todo.length} left`} />
            <TaskList tasks={todo} today={today} reorderable />
          </section>
        )}

        {done.length > 0 && (
          <section className="section">
            <SectionTitle title="Done" count={String(done.length)} />
            <TaskList tasks={done} today={today} />
          </section>
        )}

        {pushed.length > 0 && (
          <section className="section">
            <SectionTitle title="Moved to tomorrow" count={formatShort(addDays(today, 1), today)} />
            <ul className="moved-list">
              {pushed.map((task) => {
                const project = task.projectId ? projects.get(task.projectId) : undefined;
                return (
                  <li key={task.id} className="moved-row">
                    <button type="button" className="moved-row__title" onClick={() => actions.select(task.id)}>
                      {task.title}
                    </button>
                    <span className="meta">
                      <span className="dot" style={{ background: project?.color ?? NO_PROJECT_COLOR }} />
                      {project?.name ?? 'No project'}
                    </span>
                    <button
                      type="button"
                      className="btn btn--sm"
                      aria-label={`Move “${task.title}” back to today`}
                      onClick={() => actions.bringBackToToday(task.id, today)}
                    >
                      <Icon name="back" size={15} strokeWidth={2} />
                      Back to today
                    </button>
                  </li>
                );
              })}
            </ul>
          </section>
        )}
      </div>

      <AddTask defaultDay={today} label="Add a task for today" placeholder="Add a task for today — try “Call mom #Personal”" />
    </div>
  );
}

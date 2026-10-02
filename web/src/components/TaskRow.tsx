import type { ReactNode } from 'react';
import { addDays, dayWithDate, formatShort, fromLabel, relativeDay } from '../lib/dates';
import { NO_PROJECT_COLOR, PRIORITY_COLORS, PRIORITY_LABELS, cx, formatEstimate } from '../lib/format';
import { repeatLabel } from '../lib/repeat';
import { carriedFrom, effectiveDay } from '../lib/tasks';
import { actions } from '../store/store';
import type { Project, Task } from '../types';
import { Icon } from './Icon';

export function CheckButton({ task, today, size = 'md' }: { task: Task; today: string; size?: 'md' | 'lg' | 'sm' }) {
  const done = task.completedAt !== null;
  return (
    <button
      type="button"
      className={cx('check', `check--${size}`, done && 'is-done', !done && task.priority === 1 && 'is-p1')}
      aria-label={done ? `Mark “${task.title}” as not done` : `Complete “${task.title}”`}
      onClick={(event) => {
        event.stopPropagation();
        void actions.toggleComplete(task.id, today);
      }}
    >
      <span className="check__ring">{done && <Icon name="check" size={size === 'lg' ? 14 : 12} strokeWidth={3.2} />}</span>
    </button>
  );
}

export type RowAction = 'push' | 'today' | 'none';

interface TaskRowProps {
  task: Task;
  today: string;
  project: Project | undefined;
  selected: boolean;
  action?: RowAction;
  showDay?: boolean;
  showProject?: boolean;
  grip?: ReactNode;
}

export function TaskRow({ task, today, project, selected, action = 'push', showDay = false, showProject = true, grip }: TaskRowProps) {
  const done = task.completedAt !== null;
  const shownDay = effectiveDay(task, today);
  const carried = carriedFrom(task, today);
  const repeat = repeatLabel(task.repeat);
  const doneSubtasks = task.subtasks.filter((subtask) => subtask.done).length;
  const nextDay = addDays(shownDay ?? today, 1);
  const nextLabel = relativeDay(nextDay, today) === 'Tomorrow' ? 'tomorrow' : formatShort(nextDay, today);

  return (
    <div className={cx('task-row', selected && 'is-selected', done && 'is-done')}>
      {grip}
      <CheckButton task={task} today={today} />
      <button type="button" className="task-row__main" onClick={() => actions.select(task.id)} aria-current={selected || undefined}>
        <span className="task-row__title">{task.title}</span>
        <span className="task-row__meta">
          {showProject && (
            <span className="meta">
              <span className="dot" style={{ background: project?.color ?? NO_PROJECT_COLOR }} />
              {project?.name ?? 'No project'}
            </span>
          )}
          {showDay && shownDay && <span className="meta">{dayWithDate(shownDay, today)}</span>}
          {task.estimateMinutes !== null && <span className="meta">{formatEstimate(task.estimateMinutes)}</span>}
          {task.subtasks.length > 0 && (
            <span className="meta" title="Subtasks done">
              <Icon name="list" size={13} strokeWidth={2} />
              {doneSubtasks}/{task.subtasks.length}
            </span>
          )}
          {repeat && (
            <span className="meta">
              <Icon name="repeat" size={13} strokeWidth={2} />
              {repeat}
            </span>
          )}
          {carried && <span className="tag-carried">{fromLabel(carried, today)}</span>}
        </span>
      </button>
      {task.priority > 0 && !done && (
        <span className="flag" role="img" aria-label={PRIORITY_LABELS[task.priority]} style={{ color: PRIORITY_COLORS[task.priority] }}>
          <Icon name="flag" size={16} strokeWidth={1.8} />
        </span>
      )}
      {action === 'push' && !done && (
        <button
          type="button"
          className="icon-btn task-row__action"
          aria-label={`Move “${task.title}” to ${nextLabel}`}
          title={`Move to ${nextLabel}`}
          onClick={() => actions.pushToNextDay([task.id], today)}
        >
          <Icon name="push" />
        </button>
      )}
      {action === 'today' && !done && (
        <button
          type="button"
          className="icon-btn task-row__action"
          aria-label={`Do “${task.title}” today`}
          title="Do today"
          onClick={() => actions.rescheduleTask(task.id, today, today)}
        >
          <Icon name="sun" />
        </button>
      )}
    </div>
  );
}

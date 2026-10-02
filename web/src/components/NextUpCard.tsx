import { useNavigate } from 'react-router';
import { fromLabel } from '../lib/dates';
import { DEFAULT_FOCUS_MINUTES, NO_PROJECT_COLOR, formatEstimate, lighten } from '../lib/format';
import { carriedFrom } from '../lib/tasks';
import { focus } from '../store/focus';
import { actions } from '../store/store';
import type { Project, Task } from '../types';
import { Icon } from './Icon';

export function NextUpCard({ task, project, today }: { task: Task; project: Project | undefined; today: string }) {
  const navigate = useNavigate();
  const carried = carriedFrom(task, today);
  const doneSubtasks = task.subtasks.filter((subtask) => subtask.done).length;

  return (
    <section className="next-card" aria-labelledby="next-card-title">
      <span className="next-card__label">
        <span className="marker-dot" aria-hidden="true" />
        Next up
      </span>
      <h2 className="next-card__title" id="next-card-title">
        <button type="button" className="next-card__title-btn" onClick={() => actions.select(task.id)}>
          {task.title}
        </button>
      </h2>
      <div className="next-card__meta">
        <span className="meta">
          <span className="dot dot--lg" style={{ background: lighten(project?.color ?? NO_PROJECT_COLOR, 0.42) }} />
          {project?.name ?? 'No project'}
        </span>
        {task.estimateMinutes !== null && <span className="meta">{formatEstimate(task.estimateMinutes)}</span>}
        {task.subtasks.length > 0 && (
          <span className="meta">
            <Icon name="list" size={15} />
            {doneSubtasks}/{task.subtasks.length} steps
          </span>
        )}
        {carried && <span className="meta">{fromLabel(carried, today)}</span>}
      </div>
      <div className="next-card__actions">
        <button
          type="button"
          className="btn btn--lg btn--marker"
          onClick={() => {
            focus.start(task.id, task.estimateMinutes ?? DEFAULT_FOCUS_MINUTES);
            navigate('/focus');
          }}
        >
          <Icon name="play" size={16} />
          Start focus
        </button>
        <button type="button" className="btn btn--lg btn--on-dark" onClick={() => void actions.toggleComplete(task.id, today)}>
          <Icon name="check" size={17} strokeWidth={2.2} />
          Done
        </button>
        <button
          type="button"
          className="btn btn--lg btn--on-dark"
          aria-label="Move to tomorrow"
          onClick={() => actions.pushToNextDay([task.id], today)}
        >
          <Icon name="push" size={17} strokeWidth={2} />
          Tomorrow
        </button>
      </div>
    </section>
  );
}

export function AllClear({ hadTasks }: { hadTasks: boolean }) {
  return (
    <section className="all-clear">
      <h2 className="all-clear__title">{hadTasks ? 'All clear for today.' : 'Nothing planned for today.'}</h2>
      <p className="all-clear__text">
        {hadTasks
          ? 'Nothing left on your list. Pull something from Upcoming, or call it a day.'
          : 'Add a task below, or pick one from your Inbox or Upcoming.'}
      </p>
    </section>
  );
}

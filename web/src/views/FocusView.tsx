import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router';
import { Icon } from '../components/Icon';
import { DEFAULT_FOCUS_MINUTES, NO_PROJECT_COLOR, cx, formatClock, formatEstimate } from '../lib/format';
import { openOn } from '../lib/tasks';
import { useToday } from '../lib/today';
import { focus, remainingSeconds, useFocusSession, useNow, type FocusSession } from '../store/focus';
import { useProjectMap, useTaskList } from '../store/hooks';
import { actions, useStore } from '../store/store';
import type { Task } from '../types';

const RING_RADIUS = 108;
const RING_LENGTH = 2 * Math.PI * RING_RADIUS;
const LENGTH_CHOICES = [15, 25, 45, 60];

export function FocusView() {
  const today = useToday();
  const session = useFocusSession();
  const tasks = useTaskList();
  const sessionTask = useStore((state) => (session?.taskId ? state.tasks[session.taskId] : undefined));
  const todayOpen = useMemo(() => openOn(tasks, today, today), [tasks, today]);

  const upNext = todayOpen.find((task) => task.id !== session?.taskId);

  if (!session || (session.kind === 'task' && !sessionTask)) {
    return <FocusPicker tasks={todayOpen} />;
  }
  if (session.finished) {
    return <FocusFinished upNext={upNext} wasBreak={session.kind === 'break'} />;
  }
  return <FocusTimer session={session} task={session.kind === 'task' ? sessionTask : undefined} upNext={upNext} today={today} />;
}

function FocusPicker({ tasks }: { tasks: Task[] }) {
  const navigate = useNavigate();
  const projects = useProjectMap();
  const [length, setLength] = useState<number | 'estimate'>('estimate');
  const minutesFor = (task: Task) => (length === 'estimate' ? (task.estimateMinutes ?? DEFAULT_FOCUS_MINUTES) : length);
  const [first, ...rest] = tasks;

  return (
    <div className="view view--focus">
      <header className="view-header">
        <div className="view-header__titles">
          <span className="eyebrow">Focus</span>
          <h1 className="view-title">What’s next?</h1>
        </div>
      </header>

      {first ? (
        <>
          <div className="focus-length" role="group" aria-label="Session length">
            <span className="focus-length__label">Session length</span>
            <div className="segmented segmented--sm">
              <button type="button" aria-pressed={length === 'estimate'} onClick={() => setLength('estimate')}>
                Task estimate
              </button>
              {LENGTH_CHOICES.map((minutes) => (
                <button key={minutes} type="button" aria-pressed={length === minutes} onClick={() => setLength(minutes)}>
                  {minutes} min
                </button>
              ))}
            </div>
          </div>

          <section className="focus-pick" aria-label="Next up">
            <span className="next-card__label">
              <span className="marker-dot" aria-hidden="true" />
              Next up
            </span>
            <h2 className="focus-pick__title">{first.title}</h2>
            <button type="button" className="btn btn--lg btn--marker" onClick={() => focus.start(first.id, minutesFor(first))}>
              <Icon name="play" size={16} />
              Focus for {formatEstimate(minutesFor(first))}
            </button>
          </section>

          {rest.length > 0 && (
            <section className="section">
              <h2 className="section-title">Or pick another task from today</h2>
              <ul className="focus-list">
                {rest.map((task) => {
                  const project = task.projectId ? projects.get(task.projectId) : undefined;
                  return (
                    <li key={task.id} className="focus-list__row">
                      <span className="dot" style={{ background: project?.color ?? NO_PROJECT_COLOR }} />
                      <span className="focus-list__title">{task.title}</span>
                      <button type="button" className="btn btn--sm" onClick={() => focus.start(task.id, minutesFor(task))}>
                        <Icon name="play" size={13} />
                        {formatEstimate(minutesFor(task))}
                      </button>
                    </li>
                  );
                })}
              </ul>
            </section>
          )}
        </>
      ) : (
        <div className="empty">
          <h2 className="empty__title">Nothing on today’s list.</h2>
          <p className="empty__text">Add a task to Today, or bring one over from your Inbox or Upcoming.</p>
          <button type="button" className="btn" onClick={() => navigate('/today')}>
            Go to Today
          </button>
        </div>
      )}
    </div>
  );
}

function FocusTimer({ session, task, upNext, today }: { session: FocusSession; task: Task | undefined; upNext: Task | undefined; today: string }) {
  const navigate = useNavigate();
  const projects = useProjectMap();
  const running = session.endsAt !== null;
  const now = useNow(running);
  const remaining = remainingSeconds(session, now);
  const timeUp = remaining <= 0;
  const progress = session.totalSeconds ? 1 - remaining / session.totalSeconds : 1;
  const project = task?.projectId ? projects.get(task.projectId) : undefined;
  const step = task?.subtasks.find((subtask) => !subtask.done);
  const doneSteps = task ? task.subtasks.filter((subtask) => subtask.done).length : 0;

  const status = timeUp
    ? session.kind === 'break'
      ? 'Break’s over'
      : 'Time’s up'
    : running
      ? `of ${formatEstimate(Math.round(session.totalSeconds / 60))}`
      : 'Paused';

  const complete = () => {
    if (task) void actions.toggleComplete(task.id, today);
    focus.finish();
  };

  return (
    <div className="view view--focus">
      <section className="focus-card" aria-label={session.kind === 'break' ? 'Break' : 'Focus session'}>
        <div className="focus-card__top">
          <span className="focus-card__label">{session.kind === 'break' ? 'Break' : `Focus · ${project?.name ?? 'No project'}`}</span>
          <button
            type="button"
            className="icon-btn icon-btn--on-dark"
            aria-label="End session"
            title="End session"
            onClick={() => {
              focus.end();
              navigate('/today');
            }}
          >
            <Icon name="close" size={16} strokeWidth={2.4} />
          </button>
        </div>

        <h1 className="focus-card__title">
          {session.kind === 'break' ? 'Short break' : (task?.title ?? 'Focus')}
        </h1>
        {session.kind === 'break' && <p className="focus-card__note">Stand up, drink some water, look away from the screen.</p>}

        <div className={cx('ring', timeUp && 'is-up')}>
          <svg width="252" height="252" viewBox="0 0 252 252" aria-hidden="true">
            <circle cx="126" cy="126" r={RING_RADIUS} className="ring__track" />
            <circle
              cx="126"
              cy="126"
              r={RING_RADIUS}
              className="ring__progress"
              strokeDasharray={RING_LENGTH}
              strokeDashoffset={RING_LENGTH * Math.min(1, Math.max(0, progress))}
              transform="rotate(-90 126 126)"
            />
          </svg>
          <div className="ring__center" role="timer" aria-label={`${formatClock(remaining)} remaining`}>
            <span className="ring__time">{formatClock(remaining)}</span>
            <span className="ring__status">{status}</span>
          </div>
        </div>

        <div className="focus-controls">
          <button type="button" className="pill-btn" onClick={() => focus.addMinutes(5)}>
            +5 min
          </button>
          {timeUp ? (
            <button type="button" className="play-btn" aria-label="Add 5 minutes and keep going" onClick={() => focus.addMinutes(5)}>
              <Icon name="play" size={22} />
            </button>
          ) : (
            <button type="button" className="play-btn" aria-label={running ? 'Pause' : 'Resume'} onClick={() => (running ? focus.pause() : focus.resume())}>
              <Icon name={running ? 'pause' : 'play'} size={22} strokeWidth={3} />
            </button>
          )}
          {session.kind === 'task' ? (
            <button type="button" className="pill-btn" onClick={complete}>
              <Icon name="check" size={15} strokeWidth={2.6} />
              Done
            </button>
          ) : (
            <button type="button" className="pill-btn" onClick={() => focus.finish()}>
              Skip
            </button>
          )}
        </div>

        {task && task.subtasks.length > 0 && (
          <div className="focus-step">
            <button
              type="button"
              role="checkbox"
              aria-checked={!step}
              aria-label={step ? `Complete step: ${step.title}` : 'All steps done'}
              className="focus-step__check"
              disabled={!step}
              onClick={() => step && void actions.updateSubtask(task.id, step.id, { done: true })}
            >
              <span className="focus-step__box">{!step && <Icon name="check" size={11} strokeWidth={3.4} />}</span>
            </button>
            <span className="focus-step__text">
              <span className="focus-step__heading">{step ? 'Current step' : 'All steps done'}</span>
              <span className="focus-step__title">{step ? step.title : 'Wrap up and mark it done'}</span>
            </span>
            <span className="focus-step__count">
              {doneSteps}/{task.subtasks.length}
            </span>
          </div>
        )}
      </section>

      {upNext && session.kind === 'task' && (
        <p className="focus-upnext">
          Up next: <strong>{upNext.title}</strong>
        </p>
      )}
    </div>
  );
}

function FocusFinished({ upNext, wasBreak }: { upNext: Task | undefined; wasBreak: boolean }) {
  const navigate = useNavigate();
  const startNext = () => upNext && focus.start(upNext.id, upNext.estimateMinutes ?? DEFAULT_FOCUS_MINUTES);

  return (
    <div className="view view--focus">
      <section className="focus-card focus-card--done" aria-live="polite">
        <span className="focus-done__badge" aria-hidden="true">
          <Icon name="check" size={30} strokeWidth={2.8} />
        </span>
        <h1 className="focus-card__title">{wasBreak ? 'Break’s over.' : 'Done. Nice work.'}</h1>
        {upNext ? (
          <p className="focus-card__note">
            Up next: <strong>{upNext.title}</strong>
            {upNext.estimateMinutes !== null && ` · ${formatEstimate(upNext.estimateMinutes)}`}
          </p>
        ) : (
          <p className="focus-card__note">That was the last task on today’s list.</p>
        )}
        <div className="focus-controls">
          {upNext && (
            <button type="button" className="btn btn--lg btn--marker" onClick={startNext}>
              <Icon name="play" size={15} />
              Start next
            </button>
          )}
          {!wasBreak && (
            <button type="button" className="btn btn--lg btn--on-dark" onClick={() => focus.startBreak(5)}>
              5-min break
            </button>
          )}
        </div>
        <button
          type="button"
          className="focus-card__link"
          onClick={() => {
            focus.end();
            navigate('/today');
          }}
        >
          Back to Today
        </button>
      </section>
    </div>
  );
}

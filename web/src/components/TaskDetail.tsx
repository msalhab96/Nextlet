import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router';
import { WEEKDAY_SHORT, addDays, dayWithDate, formatShort, fromLabel, isValidDay, localDay, relativeDay } from '../lib/dates';
import {
  DEFAULT_FOCUS_MINUTES,
  ESTIMATE_CHOICES,
  NO_PROJECT_COLOR,
  PRIORITY_COLORS,
  PRIORITY_LABELS,
  cx,
  formatEstimate,
} from '../lib/format';
import { repeatChoice, repeatOptions, ruleForChoice, type RepeatChoice } from '../lib/repeat';
import { carriedFrom, effectiveDay, openOn } from '../lib/tasks';
import { useToday } from '../lib/today';
import { focus } from '../store/focus';
import { useTaskList } from '../store/hooks';
import { actions, useStore } from '../store/store';
import type { Project, Subtask, Task } from '../types';
import { Icon } from './Icon';
import { CheckButton } from './TaskRow';

function autosize(element: HTMLTextAreaElement | null) {
  if (!element) return;
  element.style.height = 'auto';
  element.style.height = `${element.scrollHeight}px`;
}

export function TaskDetail({ taskId }: { taskId: string }) {
  const today = useToday();
  const navigate = useNavigate();
  const task = useStore((state) => state.tasks[taskId]);
  const projects = useStore((state) => state.projects);
  const tasks = useTaskList();
  if (!task) return null;

  const done = task.completedAt !== null;
  const todayOrder = openOn(tasks, today, today);
  const canMakeNext = !done && effectiveDay(task, today) === today && todayOrder.length > 1 && todayOrder[0]?.id !== task.id;

  const startFocus = () => {
    focus.start(task.id, task.estimateMinutes ?? DEFAULT_FOCUS_MINUTES);
    navigate('/focus');
  };

  const makeNext = () => {
    void actions.reorder([task.id, ...todayOrder.map((other) => other.id).filter((id) => id !== task.id)]);
    actions.toast(`“${task.title}” is next up`, { icon: 'info' });
  };

  return (
    <aside className="detail" aria-label="Task details">
      <div className="detail__head">
        <ProjectPicker task={task} projects={projects} />
        <button type="button" className="icon-btn" aria-label="Close details" onClick={() => actions.select(null)}>
          <Icon name="close" />
        </button>
      </div>

      <div className="detail__title-row">
        <CheckButton task={task} today={today} size="lg" />
        <TitleEditor task={task} />
      </div>

      <DayBlock task={task} today={today} />
      <Fields task={task} today={today} />
      <hr className="detail__rule" />
      <Subtasks task={task} />
      <Notes task={task} />

      <div className="detail__footer">
        {!done && (
          <button type="button" className="btn btn--primary btn--block" onClick={startFocus}>
            <span className="icon-marker">
              <Icon name="play" size={15} />
            </span>
            Start focus session
          </button>
        )}
        <div className="detail__secondary">
          {canMakeNext && (
            <button type="button" className="btn btn--sm" onClick={makeNext}>
              <Icon name="arrowUp" size={15} strokeWidth={2} />
              Make next up
            </button>
          )}
          <button type="button" className="btn btn--sm btn--danger" onClick={() => void actions.deleteTask(task.id)}>
            <Icon name="trash" size={15} />
            Delete
          </button>
        </div>
        <p className="detail__stamp">Added {formatShort(localDay(new Date(task.createdAt)), today)}</p>
      </div>
    </aside>
  );
}

function ProjectPicker({ task, projects }: { task: Task; projects: Project[] }) {
  const project = projects.find((candidate) => candidate.id === task.projectId);
  return (
    <label className="project-picker">
      <span className="dot" style={{ background: project?.color ?? NO_PROJECT_COLOR }} />
      <span className="sr-only">Project</span>
      <select
        value={task.projectId ?? ''}
        onChange={(event) => void actions.updateTask(task.id, { projectId: event.target.value || null })}
      >
        <option value="">No project</option>
        {projects.map((candidate) => (
          <option key={candidate.id} value={candidate.id}>
            {candidate.name}
          </option>
        ))}
      </select>
      <Icon name="chevronDown" size={14} strokeWidth={2.2} />
    </label>
  );
}

function TitleEditor({ task }: { task: Task }) {
  const [draft, setDraft] = useState(task.title);
  const editing = useRef(false);
  const cancelled = useRef(false);
  const ref = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (!editing.current) setDraft(task.title);
  }, [task.title]);
  useLayoutEffect(() => autosize(ref.current), [draft]);

  const commit = () => {
    editing.current = false;
    if (cancelled.current) {
      cancelled.current = false;
      setDraft(task.title);
      return;
    }
    const value = draft.replace(/\s+/g, ' ').trim();
    if (!value) {
      setDraft(task.title);
      return;
    }
    setDraft(value);
    if (value !== task.title) void actions.updateTask(task.id, { title: value });
  };

  return (
    <textarea
      ref={ref}
      rows={1}
      maxLength={500}
      className={cx('detail__title', task.completedAt !== null && 'is-done')}
      aria-label="Task title"
      value={draft}
      onFocus={() => {
        editing.current = true;
      }}
      onChange={(event) => setDraft(event.target.value)}
      onBlur={commit}
      onKeyDown={(event) => {
        if (event.key === 'Enter') {
          event.preventDefault();
          event.currentTarget.blur();
        } else if (event.key === 'Escape') {
          event.preventDefault();
          cancelled.current = true;
          event.currentTarget.blur();
        }
      }}
    />
  );
}

function DayBlock({ task, today }: { task: Task; today: string }) {
  const done = task.completedAt !== null;
  const shown = effectiveDay(task, today);
  const carried = carriedFrom(task, today);
  const pickerRef = useRef<HTMLInputElement>(null);
  const [pickerVisible, setPickerVisible] = useState(false);
  const nextDay = addDays(shown ?? today, 1);
  const pushLabel = relativeDay(nextDay, today) === 'Tomorrow' ? 'Move to tomorrow' : `Push to ${formatShort(nextDay, today)}`;

  const label = done
    ? `Done · ${task.day ? dayWithDate(task.day, today) : 'Today'}`
    : shown
      ? dayWithDate(shown, today)
      : 'No day · Inbox';

  const openPicker = () => {
    const input = pickerRef.current;
    if (!input) return;
    try {
      input.showPicker();
    } catch {
      setPickerVisible(true);
      input.focus();
    }
  };

  return (
    <div className="day-block">
      <span className="day-block__label">
        <Icon name="calendar" size={16} />
        Day
      </span>
      <span className="day-block__value">
        {label}
        {carried && <span className="tag-carried">{fromLabel(carried, today)}</span>}
      </span>
      {!done && (
        <div className="day-block__actions">
          {shown ? (
            <button type="button" className="btn btn--sm" onClick={() => actions.pushToNextDay([task.id], today)}>
              <Icon name="push" size={15} strokeWidth={2} />
              {pushLabel}
            </button>
          ) : (
            <>
              <button type="button" className="btn btn--sm" onClick={() => actions.rescheduleTask(task.id, today, today)}>
                <Icon name="sun" size={15} />
                Today
              </button>
              <button type="button" className="btn btn--sm" onClick={() => actions.rescheduleTask(task.id, addDays(today, 1), today)}>
                Tomorrow
              </button>
            </>
          )}
          {shown && shown !== today && (
            <button type="button" className="btn btn--sm" onClick={() => actions.bringBackToToday(task.id, today)}>
              <Icon name="back" size={15} strokeWidth={2} />
              Back to today
            </button>
          )}
          <span className="date-pick">
            <button type="button" className="btn btn--sm" onClick={openPicker}>
              Pick a day…
            </button>
            <input
              ref={pickerRef}
              type="date"
              className={cx('date-input', !pickerVisible && 'date-input--hidden')}
              aria-label="Pick a day"
              tabIndex={pickerVisible ? 0 : -1}
              min={today}
              value={task.day && task.day >= today ? task.day : ''}
              onChange={(event) => {
                if (isValidDay(event.target.value)) actions.rescheduleTask(task.id, event.target.value, today);
                setPickerVisible(false);
              }}
              onBlur={() => setPickerVisible(false)}
            />
          </span>
          {task.day && (
            <button type="button" className="btn btn--sm btn--quiet" onClick={() => actions.rescheduleTask(task.id, null, today)}>
              Remove day
            </button>
          )}
        </div>
      )}
    </div>
  );
}

function Fields({ task, today }: { task: Task; today: string }) {
  const anchorDay = task.day ?? today;
  const choice = repeatChoice(task.repeat, anchorDay);
  const [pickingDays, setPickingDays] = useState(choice === 'custom');
  const estimateId = useId();
  const priorityId = useId();
  const repeatId = useId();
  const estimates =
    task.estimateMinutes !== null && !ESTIMATE_CHOICES.includes(task.estimateMinutes)
      ? [...ESTIMATE_CHOICES, task.estimateMinutes].sort((a, b) => a - b)
      : ESTIMATE_CHOICES;

  const onRepeat = (value: RepeatChoice) => {
    setPickingDays(value === 'custom');
    void actions.updateTask(task.id, { repeat: ruleForChoice(value, anchorDay, task.repeat) });
  };

  const toggleWeekday = (weekday: number) => {
    if (task.repeat?.type !== 'weekly') return;
    const days = task.repeat.days.includes(weekday)
      ? task.repeat.days.filter((day) => day !== weekday)
      : [...task.repeat.days, weekday].sort((a, b) => a - b);
    if (days.length) void actions.updateTask(task.id, { repeat: { type: 'weekly', days } });
  };

  return (
    <div className="fields">
      <label className="field__label" htmlFor={estimateId}>
        <Icon name="hourglass" size={16} />
        Estimate
      </label>
      <select
        id={estimateId}
        className="select"
        value={task.estimateMinutes ?? ''}
        onChange={(event) => void actions.updateTask(task.id, { estimateMinutes: event.target.value ? Number(event.target.value) : null })}
      >
        <option value="">None</option>
        {estimates.map((minutes) => (
          <option key={minutes} value={minutes}>
            {formatEstimate(minutes)}
          </option>
        ))}
      </select>

      <label className="field__label" htmlFor={priorityId}>
        <Icon name="flag" size={15} strokeWidth={1.8} />
        Priority
      </label>
      <span className="select-wrap">
        <span className="dot dot--round" style={{ background: PRIORITY_COLORS[task.priority] }} />
        <select
          id={priorityId}
          className="select select--with-dot"
          value={task.priority}
          onChange={(event) => void actions.updateTask(task.id, { priority: Number(event.target.value) })}
        >
          {PRIORITY_LABELS.map((label, value) => (
            <option key={label} value={value}>
              {label}
            </option>
          ))}
        </select>
      </span>

      <label className="field__label" htmlFor={repeatId}>
        <Icon name="repeat" size={16} />
        Repeat
      </label>
      <select
        id={repeatId}
        className="select"
        value={pickingDays ? 'custom' : choice}
        onChange={(event) => onRepeat(event.target.value as RepeatChoice)}
      >
        {repeatOptions(anchorDay, task.repeat).map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>

      {(pickingDays || choice === 'custom') && task.repeat?.type === 'weekly' && (
        <div className="weekday-picker" role="group" aria-label="Repeat on">
          {WEEKDAY_SHORT.map((label, index) => {
            const weekday = index + 1;
            const active = task.repeat?.type === 'weekly' && task.repeat.days.includes(weekday);
            return (
              <button
                key={label}
                type="button"
                className={cx('weekday-picker__day', active && 'is-active')}
                aria-pressed={active}
                aria-label={label}
                onClick={() => toggleWeekday(weekday)}
              >
                {label.slice(0, 2)}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

function Subtasks({ task }: { task: Task }) {
  const [draft, setDraft] = useState('');
  const headingId = useId();
  const doneCount = task.subtasks.filter((subtask) => subtask.done).length;

  const add = () => {
    const title = draft.trim();
    if (!title) return;
    setDraft('');
    void actions.addSubtask(task.id, title);
  };

  return (
    <section className="subtasks" aria-labelledby={headingId}>
      <h3 className="detail__h3" id={headingId}>
        Subtasks
        {task.subtasks.length > 0 && (
          <span className="detail__h3-count">
            {doneCount}/{task.subtasks.length}
          </span>
        )}
      </h3>
      {task.subtasks.length > 0 ? (
        <ul className="subtask-list">
          {task.subtasks.map((subtask) => (
            <SubtaskItem key={subtask.id} taskId={task.id} subtask={subtask} />
          ))}
        </ul>
      ) : (
        <p className="detail__hint">No subtasks. Break it down if it feels big.</p>
      )}
      <div className="subtask-add">
        <Icon name="plus" size={15} strokeWidth={2.2} />
        <input
          value={draft}
          placeholder="Add subtask"
          aria-label="Add a subtask"
          maxLength={500}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter' && !event.nativeEvent.isComposing) {
              event.preventDefault();
              add();
            } else if (event.key === 'Escape') {
              setDraft('');
            }
          }}
        />
      </div>
    </section>
  );
}

function SubtaskItem({ taskId, subtask }: { taskId: string; subtask: Subtask }) {
  const [draft, setDraft] = useState(subtask.title);
  useEffect(() => setDraft(subtask.title), [subtask.title]);

  const commit = () => {
    const value = draft.trim();
    if (!value) {
      setDraft(subtask.title);
      return;
    }
    if (value !== subtask.title) void actions.updateSubtask(taskId, subtask.id, { title: value });
  };

  return (
    <li className={cx('subtask', subtask.done && 'is-done')}>
      <button
        type="button"
        role="checkbox"
        aria-checked={subtask.done}
        aria-label={subtask.title}
        className="subtask__check"
        onClick={() => void actions.updateSubtask(taskId, subtask.id, { done: !subtask.done })}
      >
        <span className="subtask__box">{subtask.done && <Icon name="check" size={11} strokeWidth={3.4} />}</span>
      </button>
      <input
        className="subtask__title"
        value={draft}
        aria-label="Subtask title"
        maxLength={500}
        onChange={(event) => setDraft(event.target.value)}
        onBlur={commit}
        onKeyDown={(event) => {
          if (event.key === 'Enter') event.currentTarget.blur();
          if (event.key === 'Escape') {
            setDraft(subtask.title);
            event.currentTarget.blur();
          }
        }}
      />
      <button
        type="button"
        className="icon-btn icon-btn--sm subtask__delete"
        aria-label={`Delete subtask “${subtask.title}”`}
        onClick={() => void actions.deleteSubtask(taskId, subtask.id)}
      >
        <Icon name="close" size={14} />
      </button>
    </li>
  );
}

function Notes({ task }: { task: Task }) {
  const [draft, setDraft] = useState(task.notes);
  const ref = useRef<HTMLTextAreaElement>(null);
  const dirty = useRef(false);
  const timer = useRef<number | undefined>(undefined);
  const latest = useRef({ id: task.id, saved: task.notes, draft: task.notes });
  latest.current.id = task.id;
  latest.current.saved = task.notes;
  const inputId = useId();

  useEffect(() => {
    if (!dirty.current) setDraft(task.notes);
  }, [task.notes]);
  useLayoutEffect(() => autosize(ref.current), [draft]);

  const save = () => {
    window.clearTimeout(timer.current);
    if (!dirty.current) return;
    dirty.current = false;
    const { id, saved, draft: value } = latest.current;
    if (value !== saved) void actions.updateTask(id, { notes: value });
  };

  // Flush unsaved notes when the panel closes or switches to another task.
  useEffect(() => () => save(), []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <section className="notes">
      <label className="detail__h3" htmlFor={inputId}>
        Notes
      </label>
      <textarea
        id={inputId}
        ref={ref}
        className="notes__input"
        value={draft}
        placeholder="Add notes, links or context…"
        maxLength={20_000}
        onChange={(event) => {
          setDraft(event.target.value);
          latest.current.draft = event.target.value;
          dirty.current = true;
          window.clearTimeout(timer.current);
          timer.current = window.setTimeout(save, 700);
        }}
        onBlur={save}
      />
    </section>
  );
}

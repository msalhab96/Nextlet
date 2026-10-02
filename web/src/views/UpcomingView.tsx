import { useEffect, useMemo, useState, type DragEvent } from 'react';
import { useSearchParams } from 'react-router';
import { AddTask } from '../components/AddTask';
import { Icon } from '../components/Icon';
import {
  WEEKDAY_LONG,
  WEEKDAY_SHORT,
  addDays,
  addMonths,
  formatShort,
  fromLabel,
  isValidDay,
  isoWeekNumber,
  isoWeekday,
  monthLabel,
  monthWeeks,
  startOfWeek,
  weekRangeLabel,
} from '../lib/dates';
import { NO_PROJECT_COLOR, PRIORITY_LABELS, cx, plural } from '../lib/format';
import { repeatLabel } from '../lib/repeat';
import { carriedFrom, doneOn, effectiveDay, isOpen, openOn } from '../lib/tasks';
import { useToday } from '../lib/today';
import { useProjectMap, useTaskList } from '../store/hooks';
import { actions, useStore } from '../store/store';
import type { Project, Task } from '../types';

type Mode = 'week' | 'month';

export function UpcomingView() {
  const today = useToday();
  const tasks = useTaskList();
  const [params, setParams] = useSearchParams();
  const mode: Mode = params.get('view') === 'month' ? 'month' : 'week';
  const dateParam = params.get('date');
  const anchor = isValidDay(dateParam) ? dateParam : today;

  const go = (next: { mode?: Mode; date?: string }) => {
    const search = new URLSearchParams();
    if ((next.mode ?? mode) === 'month') search.set('view', 'month');
    const date = next.date ?? anchor;
    if (date !== today) search.set('date', date);
    setParams(search);
  };

  const weekStart = startOfWeek(anchor);
  const month = monthWeeks(anchor);
  const rangeStart = mode === 'week' ? weekStart : month.weeks[0]![0]!;

  useEffect(() => {
    void actions.ensureDoneFrom(rangeStart);
  }, [rangeStart]);

  const isCurrent = mode === 'week' ? weekStart === startOfWeek(today) : month.monthStart === addMonths(today, 0);

  return (
    <div className="view view--wide">
      <header className="view-header">
        <div className="view-header__titles">
          <span className="eyebrow">
            {mode === 'week' ? `Week ${isoWeekNumber(weekStart)} · ${weekRangeLabel(weekStart)}` : monthLabel(anchor)}
          </span>
          <h1 className="view-title">Upcoming</h1>
        </div>
        <div className="view-header__aside view-header__aside--controls">
          <div className="segmented" role="group" aria-label="View">
            <button type="button" aria-pressed={mode === 'week'} onClick={() => go({ mode: 'week' })}>
              Week
            </button>
            <button type="button" aria-pressed={mode === 'month'} onClick={() => go({ mode: 'month' })}>
              Month
            </button>
          </div>
          <button
            type="button"
            className="icon-btn icon-btn--boxed"
            aria-label={mode === 'week' ? 'Previous week' : 'Previous month'}
            onClick={() => go({ date: mode === 'week' ? addDays(weekStart, -7) : addMonths(anchor, -1) })}
          >
            <Icon name="chevronLeft" strokeWidth={2} />
          </button>
          <button type="button" className="btn" disabled={isCurrent} onClick={() => go({ date: today })}>
            {mode === 'week' ? 'This week' : 'This month'}
          </button>
          <button
            type="button"
            className="icon-btn icon-btn--boxed"
            aria-label={mode === 'week' ? 'Next week' : 'Next month'}
            onClick={() => go({ date: mode === 'week' ? addDays(weekStart, 7) : addMonths(anchor, 1) })}
          >
            <Icon name="chevronRight" strokeWidth={2} />
          </button>
        </div>
      </header>

      {mode === 'week' ? (
        <WeekBoard weekStart={weekStart} today={today} tasks={tasks} />
      ) : (
        <MonthGrid weeks={month.weeks} monthStart={month.monthStart} today={today} tasks={tasks} onOpenWeek={(day) => go({ mode: 'week', date: day })} />
      )}
    </div>
  );
}

interface Column {
  day: string;
  open: Task[];
  done: Task[];
}

function WeekBoard({ weekStart, today, tasks }: { weekStart: string; today: string; tasks: Task[] }) {
  const projects = useProjectMap();
  const selectedId = useStore((state) => state.selectedTaskId);
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [overDay, setOverDay] = useState<string | null>(null);
  const [addingDay, setAddingDay] = useState<string | null>(null);
  const [showDone, setShowDone] = useState(false);

  const columns: Column[] = useMemo(
    () =>
      Array.from({ length: 7 }, (_, index) => {
        const day = addDays(weekStart, index);
        return { day, open: openOn(tasks, day, today), done: doneOn(tasks, day) };
      }),
    [tasks, weekStart, today],
  );

  const total = columns.reduce((sum, column) => sum + column.open.length + column.done.length, 0);
  const doneCount = columns.reduce((sum, column) => sum + column.done.length, 0);

  const dropOn = (event: DragEvent, day: string) => {
    event.preventDefault();
    const id = draggingId;
    setDraggingId(null);
    setOverDay(null);
    if (!id) return;
    const task = tasks.find((candidate) => candidate.id === id);
    if (task && effectiveDay(task, today) !== day) actions.rescheduleTask(id, day, today);
  };

  return (
    <>
      <p className="week-summary">
        <span>
          <strong>{plural(total, 'task')}</strong> this week · {doneCount} done
        </span>
        <span className="week-summary__hint">
          <Icon name="push" size={15} strokeWidth={2} />
          Push a task to the next day, or drag it to any day
        </span>
      </p>

      <div className="week-scroll">
        <div className="week-board">
          {columns.map((column) => {
            const isToday = column.day === today;
            const isPast = column.day < today;
            const canDrop = !isPast && draggingId !== null;
            const visibleDone = isToday && !showDone ? [] : column.done;
            return (
              <section
                key={column.day}
                className={cx('day-col', isToday && 'is-today', isPast && 'is-past', overDay === column.day && canDrop && 'is-over')}
                aria-label={`${WEEKDAY_LONG[isoWeekday(column.day) - 1]} ${formatShort(column.day, today)}${isToday ? ', today' : ''}`}
                onDragOver={(event) => {
                  if (!canDrop) return;
                  event.preventDefault();
                  event.dataTransfer.dropEffect = 'move';
                  setOverDay(column.day);
                }}
                onDragLeave={(event) => {
                  if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setOverDay(null);
                }}
                onDrop={(event) => dropOn(event, column.day)}
              >
                <header className="day-col__head">
                  <span className="day-col__date">
                    <span className="day-col__num">{Number(column.day.slice(8))}</span>
                    <span className="day-col__dow">{WEEKDAY_SHORT[isoWeekday(column.day) - 1]}</span>
                  </span>
                  {isToday && <span className="badge">Today</span>}
                </header>

                <ul className="day-col__list">
                  {[...column.open, ...visibleDone].map((task) => (
                    <li key={task.id}>
                      <DayCard
                        task={task}
                        today={today}
                        project={task.projectId ? projects.get(task.projectId) : undefined}
                        selected={selectedId === task.id}
                        onDragStart={() => setDraggingId(task.id)}
                        onDragEnd={() => {
                          setDraggingId(null);
                          setOverDay(null);
                        }}
                      />
                    </li>
                  ))}
                </ul>

                {isToday && column.done.length > 0 && (
                  <button type="button" className="day-col__toggle" aria-expanded={showDone} onClick={() => setShowDone((value) => !value)}>
                    {showDone ? 'Hide done' : `+ ${column.done.length} done`}
                  </button>
                )}

                {!isPast &&
                  (addingDay === column.day ? (
                    <AddTask compact autoFocus defaultDay={column.day} label={`Add a task on ${formatShort(column.day, today)}`} placeholder="Add a task" onClose={() => setAddingDay(null)} />
                  ) : (
                    <button
                      type="button"
                      className="day-col__add"
                      aria-label={`Add a task on ${formatShort(column.day, today)}`}
                      onClick={() => setAddingDay(column.day)}
                    >
                      <Icon name="plus" size={15} strokeWidth={2.2} />
                      Add
                    </button>
                  ))}
              </section>
            );
          })}
        </div>
      </div>
    </>
  );
}

interface DayCardProps {
  task: Task;
  today: string;
  project: Project | undefined;
  selected: boolean;
  onDragStart: () => void;
  onDragEnd: () => void;
}

function DayCard({ task, today, project, selected, onDragStart, onDragEnd }: DayCardProps) {
  const done = !isOpen(task);
  const shown = effectiveDay(task, today) ?? today;
  const carried = carriedFrom(task, today);
  const nextDay = addDays(shown, 1);
  const repeat = repeatLabel(task.repeat);

  return (
    <div
      className={cx('day-card', selected && 'is-selected', done && 'is-done')}
      draggable={!done}
      onDragStart={(event) => {
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', task.title);
        onDragStart();
      }}
      onDragEnd={onDragEnd}
    >
      <button type="button" className="day-card__title" onClick={() => actions.select(task.id)}>
        {task.title}
      </button>
      <div className="day-card__meta">
        <span className="day-card__info">
          <span className="meta">
            <span className="dot dot--sm" style={{ background: project?.color ?? NO_PROJECT_COLOR }} />
            {project?.name ?? 'No project'}
          </span>
          {repeat && (
            <span className="meta" title={repeat}>
              <Icon name="repeat" size={13} strokeWidth={2} />
              <span className="sr-only">Repeats {repeat}</span>
            </span>
          )}
          {task.priority === 1 && !done && (
            <span className="flag flag--sm" role="img" aria-label={PRIORITY_LABELS[1]}>
              <Icon name="flag" size={13} strokeWidth={1.8} />
            </span>
          )}
          {carried && <span className="tag-carried tag-carried--sm">{fromLabel(carried, today)}</span>}
        </span>
        {!done && (
          <button
            type="button"
            className="icon-btn icon-btn--xs day-card__push"
            aria-label={`Move “${task.title}” to ${formatShort(nextDay, today)}`}
            title="Move to next day"
            onClick={() => actions.pushToNextDay([task.id], today)}
          >
            <Icon name="push" size={15} strokeWidth={2} />
          </button>
        )}
      </div>
    </div>
  );
}

interface MonthGridProps {
  weeks: string[][];
  monthStart: string;
  today: string;
  tasks: Task[];
  onOpenWeek: (day: string) => void;
}

function MonthGrid({ weeks, monthStart, today, tasks, onOpenWeek }: MonthGridProps) {
  const projects = useProjectMap();
  const byDay = useMemo(() => {
    const map = new Map<string, Task[]>();
    for (const task of tasks) {
      const day = effectiveDay(task, today);
      if (!day) continue;
      const list = map.get(day) ?? [];
      list.push(task);
      map.set(day, list);
    }
    for (const list of map.values()) {
      list.sort((a, b) => Number(!isOpen(a)) - Number(!isOpen(b)) || a.sortOrder - b.sortOrder);
    }
    return map;
  }, [tasks, today]);

  return (
    <div className="month">
      <div className="month__weekdays" aria-hidden="true">
        {WEEKDAY_SHORT.map((label) => (
          <span key={label}>{label}</span>
        ))}
      </div>
      <div className="month__grid">
        {weeks.flat().map((day) => {
          const items = byDay.get(day) ?? [];
          const outside = day.slice(0, 7) !== monthStart.slice(0, 7);
          return (
            <div key={day} className={cx('month-cell', outside && 'is-outside', day === today && 'is-today', day < today && 'is-past')}>
              <button type="button" className="month-cell__date" aria-label={`Open the week of ${formatShort(day, today)}`} onClick={() => onOpenWeek(day)}>
                {Number(day.slice(8))}
              </button>
              <ul className="month-cell__list">
                {items.slice(0, 3).map((task) => (
                  <li key={task.id}>
                    <button type="button" className={cx('month-task', !isOpen(task) && 'is-done')} onClick={() => actions.select(task.id)}>
                      <span className="dot dot--sm" style={{ background: (task.projectId && projects.get(task.projectId)?.color) || NO_PROJECT_COLOR }} />
                      <span className="month-task__title">{task.title}</span>
                    </button>
                  </li>
                ))}
              </ul>
              {items.length > 3 && (
                <button type="button" className="month-cell__more" onClick={() => onOpenWeek(day)}>
                  +{items.length - 3} more
                </button>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

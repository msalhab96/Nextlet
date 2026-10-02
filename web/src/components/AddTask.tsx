import { useId, useMemo, useState, type KeyboardEvent, type RefObject } from 'react';
import { dayWithDate, relativeDay } from '../lib/dates';
import { NO_PROJECT_COLOR, PRIORITY_LABELS, cx } from '../lib/format';
import { parseQuickAdd, type QuickAdd } from '../lib/parse';
import { useToday } from '../lib/today';
import { actions, useStore } from '../store/store';
import { Icon } from './Icon';

export function ParsedChips({ parsed, today }: { parsed: QuickAdd; today: string }) {
  const hasChips = parsed.day !== undefined || parsed.project || parsed.priority;
  if (!hasChips) return null;
  return (
    <div className="chips">
      {parsed.day !== undefined && (
        <span className="chip chip--date">
          <Icon name="calendar" size={14} strokeWidth={2} />
          {parsed.day ? dayWithDate(parsed.day, today) : 'Someday · Inbox'}
        </span>
      )}
      {parsed.project && (
        <span className="chip chip--project">
          <span
            className="dot"
            style={{ background: parsed.project.kind === 'existing' ? parsed.project.project.color : NO_PROJECT_COLOR }}
          />
          {parsed.project.kind === 'existing' ? parsed.project.project.name : `New project: ${parsed.project.name}`}
        </span>
      )}
      {parsed.priority ? (
        <span className={cx('chip', `chip--p${parsed.priority}`)}>
          <Icon name="flag" size={13} strokeWidth={1.8} />
          {PRIORITY_LABELS[parsed.priority]}
        </span>
      ) : null}
    </div>
  );
}

/** Where a quick-added task will land: "Personal · Tomorrow", "Inbox". */
export function destinationLabel(parsed: QuickAdd, defaultDay: string | null, today: string): string {
  const day = parsed.day !== undefined ? parsed.day : defaultDay;
  const place = day ? relativeDay(day, today) : 'Inbox';
  const project = parsed.project?.kind === 'existing' ? parsed.project.project.name : parsed.project?.name;
  return project ? `${project} · ${place}` : place;
}

/** Creates the task described by quick-add text. Returns false if nothing was created. */
export async function createFromQuickAdd(
  parsed: QuickAdd,
  defaults: { day: string | null; projectId?: string | null },
): Promise<boolean> {
  if (!parsed.title) return false;
  let projectId = defaults.projectId ?? null;
  if (parsed.project?.kind === 'existing') projectId = parsed.project.project.id;
  if (parsed.project?.kind === 'new') {
    const created = await actions.createProject(parsed.project.name);
    if (!created) return false;
    projectId = created.id;
  }
  const id = await actions.createTask({
    title: parsed.title,
    day: parsed.day !== undefined ? parsed.day : defaults.day,
    projectId,
    priority: parsed.priority,
  });
  return id !== null;
}

interface AddTaskProps {
  defaultDay: string | null;
  defaultProjectId?: string | null;
  placeholder: string;
  label?: string;
  compact?: boolean;
  autoFocus?: boolean;
  inputRef?: RefObject<HTMLInputElement | null>;
  onClose?: () => void;
}

export function AddTask({
  defaultDay,
  defaultProjectId,
  placeholder,
  label = 'Add a task',
  compact = false,
  autoFocus,
  inputRef,
  onClose,
}: AddTaskProps) {
  const id = useId();
  const today = useToday();
  const projects = useStore((state) => state.projects);
  const [text, setText] = useState('');
  const parsed = useMemo(() => parseQuickAdd(text, { today, projects }), [text, today, projects]);

  const submit = async () => {
    if (!parsed.title) return;
    const day = parsed.day !== undefined ? parsed.day : defaultDay;
    const landsElsewhere = day !== defaultDay || (parsed.project && parsed.project.kind === 'new');
    const destination = destinationLabel(parsed, defaultDay, today);
    setText('');
    const created = await createFromQuickAdd(parsed, { day: defaultDay, projectId: defaultProjectId });
    if (created && landsElsewhere) actions.toast(`“${parsed.title}” added to ${destination}`, { icon: 'check' });
  };

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'Enter' && !event.nativeEvent.isComposing) {
      event.preventDefault();
      void submit();
    } else if (event.key === 'Escape') {
      if (text) setText('');
      else onClose?.();
    }
  };

  return (
    <div className={cx('add-task', compact && 'add-task--compact')}>
      <div className="add-task__field">
        <Icon name="plus" size={compact ? 15 : 18} strokeWidth={2.2} className="add-task__icon" />
        <label className="sr-only" htmlFor={id}>
          {label}
        </label>
        <input
          ref={inputRef}
          id={id}
          className="add-task__input"
          value={text}
          placeholder={placeholder}
          autoComplete="off"
          autoFocus={autoFocus}
          onChange={(event) => setText(event.target.value)}
          onKeyDown={onKeyDown}
          onBlur={() => {
            if (compact && !text) onClose?.();
          }}
        />
        {!compact && <kbd className="kbd">Enter</kbd>}
      </div>
      {text.trim() && <ParsedChips parsed={parsed} today={today} />}
    </div>
  );
}

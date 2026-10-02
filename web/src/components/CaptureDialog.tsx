import { useMemo, useState } from 'react';
import { parseQuickAdd } from '../lib/parse';
import { useToday } from '../lib/today';
import { actions, useStore } from '../store/store';
import { ParsedChips, createFromQuickAdd, destinationLabel } from './AddTask';
import { Dialog } from './Dialog';
import { LogoMark } from './Icon';

/** Quick capture (N): jot a task down from anywhere. With no day it lands in the Inbox. */
export function CaptureDialog({ onClose }: { onClose: () => void }) {
  const today = useToday();
  const projects = useStore((state) => state.projects);
  const [text, setText] = useState('');
  const parsed = useMemo(() => parseQuickAdd(text, { today, projects }), [text, today, projects]);
  const destination = destinationLabel(parsed, null, today);

  const submit = async () => {
    if (!parsed.title) return;
    onClose();
    if (await createFromQuickAdd(parsed, { day: null })) {
      actions.toast(`“${parsed.title}” added to ${destination}`, { icon: 'check' });
    }
  };

  return (
    <Dialog label="Quick capture" onClose={onClose} className="dialog--capture">
      <div className="capture__row">
        <LogoMark size={34} />
        <label className="sr-only" htmlFor="capture-input">
          Capture a task
        </label>
        <input
          id="capture-input"
          className="capture__input"
          autoFocus
          autoComplete="off"
          placeholder="What’s next?"
          value={text}
          onChange={(event) => setText(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter' && !event.nativeEvent.isComposing) {
              event.preventDefault();
              void submit();
            }
          }}
        />
      </div>
      <div className="capture__parsed">
        {parsed.title && (
          <span className="capture__creates">
            <span className="eyebrow">Creates</span>
            <strong>{parsed.title}</strong>
          </span>
        )}
        <ParsedChips parsed={parsed} today={today} />
        {!text.trim() && (
          <span className="capture__hint">
            Add details as you type: <code>tomorrow #Home !1</code>, <code>fri</code>, <code>next week</code> or <code>someday</code>
          </span>
        )}
      </div>
      <div className="capture__foot">
        <span className="capture__dest">
          Lands in <strong>{destination}</strong>
        </span>
        <button type="button" className="btn btn--sm btn--quiet" onClick={onClose}>
          <kbd className="kbd">esc</kbd>
          Close
        </button>
        <button type="button" className="btn btn--sm btn--primary" disabled={!parsed.title} onClick={() => void submit()}>
          Add task
          <kbd className="kbd kbd--on-dark">↵</kbd>
        </button>
      </div>
    </Dialog>
  );
}

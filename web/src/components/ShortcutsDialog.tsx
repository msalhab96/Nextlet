import { Dialog } from './Dialog';

const isMac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad/.test(navigator.platform);
const MOD = isMac ? '⌘' : 'Ctrl';

const SHORTCUTS: [keys: string[], label: string][] = [
  [[MOD, 'K'], 'Search'],
  [['N'], 'Quick capture'],
  [['F'], 'Start focus on the selected or next task'],
  [[MOD, '↵'], 'Complete the selected task'],
  [[MOD, '→'], 'Move the selected task to the next day'],
  [[MOD, 'Z'], 'Undo the last move or completion'],
  [['T'], 'Go to Today'],
  [['I'], 'Go to Inbox'],
  [['U'], 'Go to Upcoming'],
  [['Esc'], 'Close the details panel'],
  [['?'], 'Show these shortcuts'],
];

export function ShortcutsDialog({ onClose }: { onClose: () => void }) {
  return (
    <Dialog label="Keyboard shortcuts" onClose={onClose} className="dialog--shortcuts">
      <div className="shortcuts__head">
        <h2 className="shortcuts__title">Keyboard shortcuts</h2>
        <button type="button" className="btn btn--sm btn--quiet" onClick={onClose}>
          Close
        </button>
      </div>
      <dl className="shortcuts">
        {SHORTCUTS.map(([keys, label]) => (
          <div key={label} className="shortcuts__row">
            <dt>{label}</dt>
            <dd>
              {keys.map((key) => (
                <kbd key={key} className="kbd kbd--key">
                  {key}
                </kbd>
              ))}
            </dd>
          </div>
        ))}
      </dl>
    </Dialog>
  );
}

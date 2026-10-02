import { cx } from '../lib/format';
import { actions, useStore, type ToastIcon } from '../store/store';
import { Icon, type IconName } from './Icon';

const ICONS: Record<Exclude<ToastIcon, 'info'>, IconName> = { push: 'push', check: 'check', error: 'alert' };

export function Toaster() {
  const toasts = useStore((state) => state.toasts);
  return (
    <div className="toaster" role="region" aria-label="Notifications">
      <div className="toaster__stack" aria-live="polite">
        {toasts.map((toast) => (
          <div key={toast.id} className={cx('toast', toast.icon === 'error' && 'toast--error')}>
            {toast.icon !== 'info' && (
              <span className="toast__icon">
                <Icon name={ICONS[toast.icon]} size={17} strokeWidth={2.1} />
              </span>
            )}
            <span className="toast__message">{toast.message}</span>
            {toast.actionLabel && (
              <button
                type="button"
                className="toast__action"
                onClick={() => {
                  toast.onAction?.();
                  actions.dismissToast(toast.id);
                }}
              >
                {toast.actionLabel}
              </button>
            )}
            <button type="button" className="toast__close" aria-label="Dismiss" onClick={() => actions.dismissToast(toast.id)}>
              <Icon name="close" size={14} />
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}

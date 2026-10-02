import { useEffect, useRef, type ReactNode } from 'react';
import { cx } from '../lib/format';

interface DialogProps {
  label: string;
  onClose: () => void;
  className?: string;
  children: ReactNode;
}

/** A modal built on the native <dialog>, which handles focus trapping and Escape. */
export function Dialog({ label, onClose, className, children }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    const previouslyFocused = document.activeElement as HTMLElement | null;
    if (!dialog.open) dialog.showModal();
    const onCancel = (event: Event) => {
      event.preventDefault();
      onCloseRef.current();
    };
    dialog.addEventListener('cancel', onCancel);
    return () => {
      dialog.removeEventListener('cancel', onCancel);
      if (dialog.open) dialog.close();
      previouslyFocused?.focus?.();
    };
  }, []);

  return (
    <dialog
      ref={ref}
      className={cx('dialog', className)}
      aria-label={label}
      onMouseDown={(event) => {
        // A click on the backdrop lands on the <dialog> element itself.
        if (event.target === event.currentTarget) onCloseRef.current();
      }}
    >
      <div className="dialog__body">{children}</div>
    </dialog>
  );
}

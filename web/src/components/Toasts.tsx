import { useAppState, useStore } from '../state/useStore';

export function Toasts() {
  const { toasts } = useAppState();
  const store = useStore();
  if (toasts.length === 0) return null;

  return (
    <div className="toasts" role="log" aria-live="polite">
      {toasts.map((toast) => (
        <button
          key={toast.id}
          type="button"
          className={`toast toast--${toast.kind}`}
          onClick={() => store.dismissToast(toast.id)}
        >
          {toast.message}
        </button>
      ))}
    </div>
  );
}

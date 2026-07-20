import { createContext, useCallback, useContext, useRef, useState, ReactNode } from 'react';
import { Link } from 'react-router-dom';

export const Icon = ({
  name,
  className = '',
  fill = false,
}: {
  name: string;
  className?: string;
  fill?: boolean;
}) => (
  <span className={`material-symbols-outlined ${fill ? 'msym-fill' : ''} ${className}`}>
    {name}
  </span>
);

export const Spinner = ({ className = '' }: { className?: string }) => (
  <div className={`flex items-center justify-center py-16 ${className}`}>
    <div className="w-8 h-8 border-[3px] border-brand/20 border-t-brand rounded-full animate-spin" />
  </div>
);

export const EmptyState = ({
  icon,
  title,
  subtitle,
  action,
}: {
  icon: string;
  title: string;
  subtitle?: string;
  action?: ReactNode;
}) => (
  <div className="flex flex-col items-center justify-center py-20 px-6 text-center">
    <div className="w-16 h-16 rounded-full bg-surface-2 flex items-center justify-center mb-4">
      <Icon name={icon} className="text-muted !text-[28px]" />
    </div>
    <p className="font-semibold text-[17px] mb-1">{title}</p>
    {subtitle && <p className="text-[14px] text-muted max-w-[280px]">{subtitle}</p>}
    {action && <div className="mt-5">{action}</div>}
  </div>
);

export const SectionHeader = ({
  title,
  to,
  linkLabel = 'See all',
}: {
  title: string;
  to?: string;
  linkLabel?: string;
}) => (
  <div className="flex items-center justify-between mb-3">
    <h2 className="text-[20px] font-bold tracking-tight">{title}</h2>
    {to && (
      <Link to={to} className="text-brand text-[13px] font-semibold flex items-center gap-0.5">
        {linkLabel}
        <Icon name="chevron_right" className="!text-[16px]" />
      </Link>
    )}
  </div>
);

// ---- Toast ------------------------------------------------------
interface Toast {
  id: number;
  text: string;
  kind: 'ok' | 'err';
}
const ToastCtx = createContext<(text: string, kind?: 'ok' | 'err') => void>(() => {});

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const idRef = useRef(0);
  const show = useCallback((text: string, kind: 'ok' | 'err' = 'ok') => {
    const id = ++idRef.current;
    setToasts((t) => [...t, { id, text, kind }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 3200);
  }, []);
  return (
    <ToastCtx.Provider value={show}>
      {children}
      <div className="fixed bottom-24 md:bottom-8 inset-x-0 z-[100] flex flex-col items-center gap-2 px-4 pointer-events-none">
        {toasts.map((t) => (
          <div
            key={t.id}
            className={`toastin pointer-events-auto max-w-sm w-fit px-4 py-3 rounded-2xl shadow-ios-lg text-[14px] font-medium text-white flex items-center gap-2 ${
              t.kind === 'err' ? 'bg-danger' : 'bg-ink'
            }`}
          >
            <Icon name={t.kind === 'err' ? 'error' : 'check_circle'} className="!text-[18px]" />
            {t.text}
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}
export const useToast = () => useContext(ToastCtx);

// ---- Qty stepper ------------------------------------------------
export const QtyStepper = ({
  qty,
  onChange,
  small = false,
}: {
  qty: number;
  onChange: (q: number) => void;
  small?: boolean;
}) => (
  <div
    className={`flex items-center rounded-full bg-brand text-white shadow-md overflow-hidden ${
      small ? 'h-8' : 'h-10'
    }`}
  >
    <button
      aria-label="Decrease"
      className="px-2.5 h-full press flex items-center"
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        onChange(qty - 1);
      }}
    >
      <Icon name={qty <= 1 ? 'delete' : 'remove'} className="!text-[18px]" />
    </button>
    <span className={`font-bold ${small ? 'text-[13px] min-w-[16px]' : 'text-[15px] min-w-[20px]'} text-center`}>
      {qty}
    </span>
    <button
      aria-label="Increase"
      className="px-2.5 h-full press flex items-center"
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        onChange(qty + 1);
      }}
    >
      <Icon name="add" className="!text-[18px]" />
    </button>
  </div>
);

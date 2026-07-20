import { ReactNode } from 'react';
import { Link, NavLink, useLocation, useNavigate } from 'react-router-dom';
import { Icon } from './Bits';
import { useCart, cartCount } from '../store/cart';
import { useAuth } from '../lib/auth';

const tabs = [
  { to: '/', icon: 'home', label: 'Home' },
  { to: '/search', icon: 'search', label: 'Search' },
  { to: '/orders', icon: 'shopping_bag', label: 'Orders' },
  { to: '/profile', icon: 'person', label: 'Profile' },
];

/** Brand mark: green m + gold dot, like the launcher icon. */
export const BrandMark = ({ size = 'text-[22px]' }: { size?: string }) => (
  <span className={`font-extrabold tracking-tight ${size}`}>
    <span className="text-ink">my</span>
    <span className="text-[#1DA043]">Minto</span>
    <span className="text-[#F5B800]">.</span>
  </span>
);

export function AppShell({ children }: { children: ReactNode }) {
  const items = useCart((s) => s.items);
  const count = cartCount(items);
  const { session } = useAuth();
  const nav = useNavigate();
  const { pathname } = useLocation();
  const showCartPill = count > 0 && pathname !== '/cart';

  return (
    <div className="min-h-dvh mx-auto max-w-app">
      {/* Desktop top bar */}
      <header className="hidden md:flex glass sticky top-0 z-50 items-center justify-between px-8 h-16 border-b border-border-subtle rounded-b-2xl">
        <Link to="/">
          <BrandMark size="text-[24px]" />
        </Link>
        <nav className="flex items-center gap-6">
          {tabs.map((t) => (
            <NavLink
              key={t.to}
              to={t.to}
              className={({ isActive }) =>
                `flex items-center gap-1.5 text-[14px] font-semibold transition-colors ${
                  isActive ? 'text-brand' : 'text-ink-soft hover:text-ink'
                }`
              }
            >
              <Icon name={t.icon} className="!text-[20px]" />
              {t.label}
            </NavLink>
          ))}
          <button
            onClick={() => nav('/cart')}
            className="relative press flex items-center gap-1.5 bg-brand text-white font-semibold text-[14px] pl-3 pr-4 py-2 rounded-full shadow-md"
          >
            <Icon name="shopping_cart" className="!text-[20px]" />
            Cart
            {count > 0 && (
              <span className="absolute -top-1.5 -right-1.5 min-w-[20px] h-5 px-1 rounded-full bg-ink text-white text-[11px] font-bold flex items-center justify-center">
                {count}
              </span>
            )}
          </button>
          {!session && (
            <Link
              to="/login"
              className="text-[14px] font-semibold text-ink border border-border-subtle bg-card px-4 py-2 rounded-full shadow-sm press"
            >
              Sign in
            </Link>
          )}
        </nav>
      </header>

      <main className="pb-28 md:pb-12">{children}</main>

      {/* Mobile floating cart pill */}
      {showCartPill && (
        <button
          onClick={() => nav('/cart')}
          className="md:hidden fixed bottom-24 right-4 z-50 press flex items-center gap-2 bg-brand text-white font-bold text-[14px] pl-3.5 pr-4 py-3 rounded-full shadow-ios-lg"
        >
          <Icon name="shopping_cart" className="!text-[20px]" />
          {count} item{count > 1 ? 's' : ''}
        </button>
      )}

      {/* Mobile bottom tab bar */}
      <nav className="md:hidden glass fixed bottom-0 inset-x-0 z-50 border-t border-border-subtle flex justify-around items-start pt-2.5 pb-[max(env(safe-area-inset-bottom),12px)] rounded-t-2xl">
        {tabs.map((t) => (
          <NavLink
            key={t.to}
            to={t.to}
            className={({ isActive }) =>
              `flex flex-col items-center gap-0.5 press min-w-[64px] ${
                isActive ? 'text-brand font-semibold' : 'text-ink-soft'
              }`
            }
          >
            {({ isActive }) => (
              <>
                <Icon name={t.icon} fill={isActive} className="!text-[24px]" />
                <span className="text-[11px] font-medium">{t.label}</span>
              </>
            )}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}

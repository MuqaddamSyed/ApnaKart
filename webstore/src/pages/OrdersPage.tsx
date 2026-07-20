import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { rupees, timeAgo, shortId } from '../lib/format';
import { SESSION_STATUS_LABEL } from '../lib/constants';
import { Icon, Spinner, EmptyState } from '../components/Bits';
import type { OrderSession } from '../lib/types';

const statusStyle: Record<string, string> = {
  waiting_suppliers: 'bg-amber-100 text-amber-800',
  all_confirmed: 'bg-sky-100 text-sky-800',
  out_for_delivery: 'bg-brand-tint text-brand',
  delivered: 'bg-success-tint text-success',
  cancelled: 'bg-surface-2 text-muted',
};

export default function OrdersPage() {
  const { session, loading } = useAuth();
  const [sessions, setSessions] = useState<OrderSession[] | null>(null);

  useEffect(() => {
    if (!session) return;
    (async () => {
      const { data } = await supabase
        .from('order_sessions')
        .select()
        .eq('customer_id', session.user.id)
        .order('placed_at', { ascending: false });
      setSessions((data as OrderSession[]) ?? []);
    })();
  }, [session]);

  if (loading) return <Spinner />;
  if (!session) {
    return (
      <EmptyState
        icon="shopping_bag"
        title="Sign in to see your orders"
        action={
          <Link to="/login" className="bg-brand text-white font-bold text-[14px] px-6 py-3 rounded-full press shadow-md">
            Sign in
          </Link>
        }
      />
    );
  }
  if (sessions === null) return <Spinner />;
  if (sessions.length === 0) {
    return (
      <EmptyState
        icon="receipt_long"
        title="No orders yet"
        subtitle="Your orders will appear here once you place one."
        action={
          <Link to="/" className="bg-brand text-white font-bold text-[14px] px-6 py-3 rounded-full press shadow-md">
            Start shopping
          </Link>
        }
      />
    );
  }

  const active = sessions.filter((s) => !['delivered', 'cancelled'].includes(s.status));
  const past = sessions.filter((s) => ['delivered', 'cancelled'].includes(s.status));

  const SessionCard = ({ s }: { s: OrderSession }) => (
    <Link
      to={`/track/${s.id}`}
      className="flex items-center gap-3 bg-card rounded-2xl p-4 shadow-ios border border-border-subtle press"
    >
      <div className="w-11 h-11 rounded-[24%] bg-brand-tint flex items-center justify-center flex-shrink-0">
        <Icon name="receipt_long" className="text-brand !text-[22px]" />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-bold text-[14px]">{shortId(s.id, s.display_id)}</span>
          <span
            className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${statusStyle[s.status] ?? 'bg-surface-2 text-muted'}`}
          >
            {(SESSION_STATUS_LABEL[s.status] ?? s.status).toUpperCase()}
          </span>
        </div>
        <p className="text-[12px] text-muted mt-0.5">
          {timeAgo(s.placed_at)} · {rupees(s.total)}
        </p>
      </div>
      <Icon name="chevron_right" className="text-muted" />
    </Link>
  );

  return (
    <div className="pagein px-5 md:px-8 py-6 max-w-2xl mx-auto">
      <h1 className="font-bold text-[24px] mb-5">Your orders</h1>
      {active.length > 0 && (
        <section className="mb-7">
          <h2 className="text-[13px] font-bold text-muted uppercase tracking-wide mb-2.5">Active</h2>
          <div className="space-y-2.5">
            {active.map((s) => (
              <SessionCard key={s.id} s={s} />
            ))}
          </div>
        </section>
      )}
      {past.length > 0 && (
        <section>
          <h2 className="text-[13px] font-bold text-muted uppercase tracking-wide mb-2.5">Past</h2>
          <div className="space-y-2.5">
            {past.map((s) => (
              <SessionCard key={s.id} s={s} />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

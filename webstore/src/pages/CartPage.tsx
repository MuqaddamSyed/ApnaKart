import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { useCart, cartSubtotal, cartBySupplier } from '../store/cart';
import { rupees } from '../lib/format';
import { FLAT_DELIVERY_FEE, MIN_ORDER_VALUE } from '../lib/constants';
import { getFix, isPrecise } from '../lib/geo';
import { Icon, QtyStepper, useToast, EmptyState } from '../components/Bits';
import { PageHeader } from './CategoryPage';
import type { Address } from '../lib/types';

export default function CartPage() {
  const { items, setQty, clear } = useCart();
  const { session } = useAuth();
  const nav = useNavigate();
  const toast = useToast();

  const [address, setAddress] = useState('');
  const [lat, setLat] = useState<number | null>(null);
  const [lng, setLng] = useState<number | null>(null);
  const [pinnedLive, setPinnedLive] = useState(false);
  const [saved, setSaved] = useState<Address[]>([]);
  const [locating, setLocating] = useState(false);
  const [placing, setPlacing] = useState(false);
  const [confirmNoPin, setConfirmNoPin] = useState(false);

  const subtotal = cartSubtotal(items);
  const total = subtotal + FLAT_DELIVERY_FEE;
  const bySupplier = cartBySupplier(items);
  const underMin = subtotal < MIN_ORDER_VALUE;

  // Prefill from customer's default + load saved addresses.
  useEffect(() => {
    if (!session) return;
    (async () => {
      const [{ data: c }, { data: a }] = await Promise.all([
        supabase
          .from('customers')
          .select('default_address,default_lat,default_lng')
          .eq('id', session.user.id)
          .maybeSingle(),
        supabase
          .from('addresses')
          .select()
          .eq('customer_id', session.user.id)
          .order('is_default', { ascending: false }),
      ]);
      if (c?.default_address && !address) {
        setAddress(c.default_address as string);
        setLat((c.default_lat as number | null) ?? null);
        setLng((c.default_lng as number | null) ?? null);
      }
      setSaved((a as Address[]) ?? []);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session]);

  const useMyLocation = async () => {
    setLocating(true);
    try {
      const fix = await getFix();
      setLat(fix.lat);
      setLng(fix.lng);
      setPinnedLive(true);
      toast(
        isPrecise(fix)
          ? 'Current location pinned for delivery'
          : `Pinned, but approximate (±${Math.round(fix.accuracyM)}m) — move outdoors and retry for precision`,
        isPrecise(fix) ? 'ok' : 'err',
      );
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not get location', 'err');
    } finally {
      setLocating(false);
    }
  };

  const pickSaved = (a: Address) => {
    setAddress(a.full_address);
    setLat(a.lat ?? null);
    setLng(a.lng ?? null);
    setPinnedLive(false);
  };

  /** Mirrors OrderService.placeMultiSupplierOrder in the mobile app. */
  const placeOrder = async (allowNoPin = false) => {
    if (!session) {
      nav('/login', { state: { from: '/cart' } });
      return;
    }
    if (address.trim().length < 8) {
      toast('Enter your full delivery address', 'err');
      return;
    }
    if (underMin) return;

    let finalLat = lat;
    let finalLng = lng;
    // GPS fallback only when no coords chosen; only trust a precise fix.
    if (finalLat == null || finalLng == null) {
      try {
        const fix = await getFix(8000);
        if (isPrecise(fix)) {
          finalLat = fix.lat;
          finalLng = fix.lng;
        }
      } catch {
        /* handled by the confirm below */
      }
      if ((finalLat == null || finalLng == null) && !allowNoPin) {
        setConfirmNoPin(true);
        return;
      }
    }

    setPlacing(true);
    try {
      // Closed-shop guard (friendly message before the DB trigger backstop).
      const supplierIds = Array.from(bySupplier.keys());
      const { data: shopRows } = await supabase
        .from('suppliers')
        .select('id, shop_name, is_open')
        .in('id', supplierIds);
      const closed = (shopRows ?? []).filter((s) => s.is_open === false);
      if (closed.length > 0) {
        throw new Error(
          `${closed.map((s) => s.shop_name).join(', ')} is closed right now. Remove those items and try again.`,
        );
      }

      // Session row.
      const { data: sessionRow, error: sErr } = await supabase
        .from('order_sessions')
        .insert({
          customer_id: session.user.id,
          status: 'waiting_suppliers',
          delivery_address: address.trim(),
          delivery_lat: finalLat,
          delivery_lng: finalLng,
          delivery_fee: FLAT_DELIVERY_FEE,
          total,
        })
        .select()
        .single();
      if (sErr) throw sErr;
      const sessionId = sessionRow.id as string;

      // One order per supplier + its items.
      for (const [supplierId, list] of bySupplier) {
        const shopSubtotal = list.reduce((s, i) => s + i.price * i.qty, 0);
        const { data: orderRow, error: oErr } = await supabase
          .from('orders')
          .insert({
            session_id: sessionId,
            customer_id: session.user.id,
            supplier_id: supplierId,
            status: 'placed',
            payment_method: 'COD',
            subtotal: shopSubtotal,
            delivery_fee: 0,
            total: shopSubtotal,
            delivery_address: address.trim(),
            delivery_lat: finalLat,
            delivery_lng: finalLng,
          })
          .select()
          .single();
        if (oErr) throw oErr;
        const { error: iErr } = await supabase.from('order_items').insert(
          list.map((i) => ({
            order_id: orderRow.id,
            product_id: i.productId,
            quantity: i.qty,
            unit_price: i.price,
            total_price: i.price * i.qty,
          })),
        );
        if (iErr) throw iErr;

        // Best-effort push to the shop; never block the order on it.
        supabase.functions
          .invoke('send-push', {
            body: {
              userId: supplierId,
              title: 'New order received',
              body: 'A customer placed a new order. Please confirm.',
              data: { type: 'new_order' },
            },
          })
          .catch(() => {});
      }

      clear();
      toast('Order placed! Pay cash on delivery.');
      nav(`/track/${sessionId}`, { replace: true });
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not place the order', 'err');
    } finally {
      setPlacing(false);
      setConfirmNoPin(false);
    }
  };

  if (items.length === 0) {
    return (
      <div className="pagein">
        <PageHeader title="Cart" />
        <EmptyState
          icon="shopping_cart"
          title="Your cart is empty"
          subtitle="Browse nearby shops and add something tasty."
          action={
            <Link to="/" className="bg-brand text-white font-bold text-[14px] px-6 py-3 rounded-full press shadow-md">
              Start shopping
            </Link>
          }
        />
      </div>
    );
  }

  return (
    <div className="pagein">
      <PageHeader title="Cart" subtitle={`${items.length} product${items.length > 1 ? 's' : ''}`} />
      <div className="px-5 md:px-8 py-5 max-w-3xl mx-auto">
        {/* Items grouped by shop */}
        {Array.from(bySupplier.entries()).map(([sid, list]) => (
          <section key={sid} className="mb-5">
            <div className="flex items-center gap-2 mb-2">
              <Icon name="storefront" className="text-brand !text-[18px]" />
              <span className="font-bold text-[14px]">{list[0].shopName}</span>
              <span className="text-[12px] text-muted ml-auto">
                {rupees(list.reduce((s, i) => s + i.price * i.qty, 0))}
              </span>
            </div>
            <div className="space-y-2.5">
              {list.map((i) => (
                <div
                  key={i.productId}
                  className="flex items-center gap-3 bg-card rounded-2xl p-3 shadow-ios border border-border-subtle"
                >
                  <div className="w-14 h-14 rounded-xl bg-surface-2 overflow-hidden flex-shrink-0">
                    {i.imageUrl ? (
                      <img src={i.imageUrl} alt="" className="w-full h-full object-cover" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center">
                        <Icon name="shopping_basket" className="text-muted !text-[22px]" />
                      </div>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-[14px] leading-tight line-clamp-1">{i.name}</p>
                    <p className="text-[12px] text-muted">
                      {i.unit ? `${i.unit} · ` : ''}
                      {rupees(i.price)} each
                    </p>
                    <p className="text-[13px] font-bold mt-0.5">{rupees(i.price * i.qty)}</p>
                  </div>
                  <QtyStepper small qty={i.qty} onChange={(q) => setQty(i.productId, q)} />
                </div>
              ))}
            </div>
          </section>
        ))}

        {/* Delivery address */}
        <section className="mb-5">
          <h2 className="font-bold text-[15px] mb-2.5">Delivery address</h2>
          <div className="flex gap-2 mb-2.5">
            <button
              onClick={useMyLocation}
              disabled={locating}
              className="flex-1 h-11 rounded-xl border border-border-subtle bg-card shadow-sm text-[13px] font-semibold press flex items-center justify-center gap-1.5 disabled:opacity-50"
            >
              {locating ? (
                <span className="w-4 h-4 border-2 border-brand/30 border-t-brand rounded-full animate-spin" />
              ) : (
                <Icon name="my_location" className="text-brand !text-[18px]" />
              )}
              {locating ? 'Locating…' : 'Use current location'}
            </button>
            {saved.length > 0 && (
              <div className="relative flex-1">
                <select
                  className="w-full h-11 rounded-xl border border-border-subtle bg-card shadow-sm text-[13px] font-semibold px-3 appearance-none outline-none"
                  onChange={(e) => {
                    const a = saved.find((x) => x.id === e.target.value);
                    if (a) pickSaved(a);
                  }}
                  defaultValue=""
                >
                  <option value="" disabled>
                    Saved addresses
                  </option>
                  {saved.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.label ?? 'Address'} — {a.full_address.slice(0, 30)}
                    </option>
                  ))}
                </select>
                <Icon
                  name="expand_more"
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 text-muted pointer-events-none !text-[18px]"
                />
              </div>
            )}
          </div>
          <textarea
            className="w-full min-h-[72px] px-4 py-3 bg-card rounded-2xl shadow-ios border border-border-subtle text-[14px] outline-none focus:ring-2 focus:ring-brand/25 placeholder:text-muted"
            placeholder="House, street, area, city, pincode"
            value={address}
            onChange={(e) => setAddress(e.target.value)}
          />
          {lat != null && lng != null && (
            <p className="flex items-center gap-1.5 text-[12px] text-success font-medium mt-1.5">
              <Icon name="check_circle" className="!text-[15px]" />
              {pinnedLive
                ? 'Live location pinned — the delivery partner will be guided here'
                : 'Delivery location set'}
            </p>
          )}
        </section>

        {/* Bill */}
        <section className="bg-card rounded-2xl shadow-ios border border-border-subtle p-4 mb-4">
          <div className="flex justify-between text-[14px] py-1">
            <span className="text-ink-soft">Items subtotal</span>
            <span className="font-semibold">{rupees(subtotal)}</span>
          </div>
          <div className="flex justify-between text-[14px] py-1">
            <span className="text-ink-soft">Delivery fee</span>
            <span className="font-semibold">{rupees(FLAT_DELIVERY_FEE)}</span>
          </div>
          <div className="border-t border-border-subtle my-2" />
          <div className="flex justify-between text-[16px] font-bold py-1">
            <span>Total</span>
            <span>{rupees(total)}</span>
          </div>
        </section>

        {/* COD */}
        <div className="flex items-center gap-3 bg-success-tint rounded-2xl px-4 py-3.5 mb-5">
          <Icon name="payments" className="text-success" />
          <div className="flex-1">
            <p className="font-bold text-[14px] text-success">Cash on Delivery</p>
            <p className="text-[12px] text-ink-soft">Pay when your order arrives — no card needed</p>
          </div>
          <Icon name="check_circle" className="text-success" fill />
        </div>

        {underMin && (
          <p className="text-center text-[13px] text-danger font-semibold mb-3">
            Minimum order is {rupees(MIN_ORDER_VALUE)} — add {rupees(MIN_ORDER_VALUE - subtotal)} more to
            check out.
          </p>
        )}

        <button
          onClick={() => placeOrder()}
          disabled={placing || underMin}
          className="w-full h-14 rounded-2xl bg-brand text-white font-bold text-[16px] press shadow-ios-lg disabled:opacity-50 flex items-center justify-center gap-2"
        >
          {placing ? (
            <>
              <span className="w-5 h-5 border-2 border-white/40 border-t-white rounded-full animate-spin" />
              Placing order…
            </>
          ) : session ? (
            `Place order · ${rupees(total)}`
          ) : (
            'Sign in to place order'
          )}
        </button>
      </div>

      {/* No-GPS confirm dialog */}
      {confirmNoPin && (
        <div className="fixed inset-0 z-[90] bg-black/40 flex items-end md:items-center justify-center p-4">
          <div className="bg-card rounded-3xl p-6 max-w-sm w-full shadow-ios-lg toastin">
            <h3 className="font-bold text-[18px] mb-2">No GPS location</h3>
            <p className="text-[14px] text-ink-soft mb-5">
              We couldn't get your exact location, so the delivery partner will rely only on your
              written address. Make sure it's complete (house, street, landmark).
            </p>
            <div className="flex gap-2.5">
              <button
                onClick={() => setConfirmNoPin(false)}
                className="flex-1 h-12 rounded-xl border border-border-subtle bg-surface text-[14px] font-bold press"
              >
                Fix address
              </button>
              <button
                onClick={() => placeOrder(true)}
                className="flex-1 h-12 rounded-xl bg-brand text-white text-[14px] font-bold press"
              >
                Place anyway
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

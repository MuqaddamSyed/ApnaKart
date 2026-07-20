import { useEffect, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import L from 'leaflet';
import { supabase } from '../lib/supabase';
import { rupees, shortId } from '../lib/format';
import { SESSION_STATUS_LABEL, ORDER_STATUS_LABEL, TILE_URL } from '../lib/constants';
import { distanceKm, etaMinutes } from '../lib/geo';
import { Icon, Spinner, useToast, EmptyState } from '../components/Bits';
import { PageHeader } from './CategoryPage';
import type { OrderSession, SubOrder } from '../lib/types';

interface AgentInfo {
  current_lat: number | null;
  current_lng: number | null;
  location_updated_at: string | null;
  users: { name: string | null; phone: string | null } | null;
}

const STEPS = ['waiting_suppliers', 'all_confirmed', 'out_for_delivery', 'delivered'];

export default function TrackPage() {
  const { id = '' } = useParams();
  const toast = useToast();
  const [session, setSession] = useState<OrderSession | null>(null);
  const [subOrders, setSubOrders] = useState<SubOrder[]>([]);
  const [agent, setAgent] = useState<AgentInfo | null>(null);
  const [otp, setOtp] = useState<string | null>(null);
  const [notFound, setNotFound] = useState(false);
  const [cancelling, setCancelling] = useState(false);

  const mapRef = useRef<L.Map | null>(null);
  const agentMarkerRef = useRef<L.Marker | null>(null);
  const mapDivRef = useRef<HTMLDivElement>(null);

  // Load + poll everything every 12s (parity with the app's 15s agent poll).
  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      const { data: s } = await supabase.from('order_sessions').select().eq('id', id).maybeSingle();
      if (cancelled) return;
      if (!s) {
        setNotFound(true);
        return;
      }
      setSession(s as OrderSession);

      const { data: o } = await supabase
        .from('orders')
        .select('id, session_id, supplier_id, status, subtotal, total, suppliers(shop_name)')
        .eq('session_id', id);
      if (!cancelled) setSubOrders((o as unknown as SubOrder[]) ?? []);

      if ((s as OrderSession).delivery_id) {
        const { data: a } = await supabase
          .from('delivery_agents')
          .select('current_lat,current_lng,location_updated_at,users(name,phone)')
          .eq('id', (s as OrderSession).delivery_id!)
          .maybeSingle();
        if (!cancelled) setAgent((a as unknown as AgentInfo) ?? null);
      }

      // Handoff OTP appears once the agent marks arrival (RLS: customer-only).
      const { data: h } = await supabase
        .from('session_handoff')
        .select('otp')
        .eq('session_id', id)
        .maybeSingle();
      if (!cancelled) setOtp((h?.otp as string | undefined) ?? null);
    };
    load();
    const t = setInterval(load, 12000);
    return () => {
      cancelled = true;
      clearInterval(t);
    };
  }, [id]);

  // Realtime: session status flips arrive instantly.
  useEffect(() => {
    const ch = supabase
      .channel(`track-${id}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'order_sessions', filter: `id=eq.${id}` },
        (payload) => setSession((prev) => ({ ...(prev ?? {}), ...(payload.new as OrderSession) })),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [id]);

  const agentFresh =
    agent?.location_updated_at != null &&
    Date.now() - new Date(agent.location_updated_at).getTime() < 60_000;
  const agentLat = agent?.current_lat ?? null;
  const agentLng = agent?.current_lng ?? null;

  // Map lifecycle.
  useEffect(() => {
    if (!session || !mapDivRef.current) return;
    const destLat = session.delivery_lat;
    const destLng = session.delivery_lng;
    if (destLat == null || destLng == null) return;

    if (!mapRef.current) {
      const map = L.map(mapDivRef.current, { zoomControl: false, attributionControl: true });
      L.tileLayer(TILE_URL, {
        attribution: '© MapTiler · © OpenStreetMap contributors',
        maxZoom: 19,
      }).addTo(map);
      map.setView([destLat, destLng], 14);
      L.marker([destLat, destLng], {
        icon: L.divIcon({
          className: '',
          html: `<div style="font-size:28px;line-height:1">🏠</div>`,
          iconSize: [28, 28],
          iconAnchor: [14, 26],
        }),
      }).addTo(map);
      mapRef.current = map;
    }

    if (agentLat != null && agentLng != null && mapRef.current) {
      const icon = L.divIcon({
        className: '',
        html: `<div style="font-size:28px;line-height:1;${agentFresh ? '' : 'filter:grayscale(1);opacity:.55'}">🛵</div>`,
        iconSize: [28, 28],
        iconAnchor: [14, 26],
      });
      if (!agentMarkerRef.current) {
        agentMarkerRef.current = L.marker([agentLat, agentLng], { icon }).addTo(mapRef.current);
        mapRef.current.fitBounds(
          L.latLngBounds([destLat, destLng], [agentLat, agentLng]).pad(0.3),
        );
      } else {
        agentMarkerRef.current.setLatLng([agentLat, agentLng]);
        agentMarkerRef.current.setIcon(icon);
      }
    }
  }, [session, agentLat, agentLng, agentFresh]);

  useEffect(
    () => () => {
      mapRef.current?.remove();
      mapRef.current = null;
      agentMarkerRef.current = null;
    },
    [],
  );

  if (notFound) return <EmptyState icon="receipt_long" title="Order not found" />;
  if (!session) return <Spinner />;

  const stepIdx = STEPS.indexOf(session.status);
  const cancelled = session.status === 'cancelled';
  const delivered = session.status === 'delivered';

  let eta: number | null = null;
  if (
    session.status === 'out_for_delivery' &&
    agentFresh &&
    agentLat != null &&
    agentLng != null &&
    session.delivery_lat != null &&
    session.delivery_lng != null
  ) {
    eta = etaMinutes(distanceKm(agentLat, agentLng, session.delivery_lat, session.delivery_lng));
  }

  const cancelOrder = async () => {
    if (!window.confirm('Cancel this order?')) return;
    setCancelling(true);
    try {
      const { error } = await supabase.rpc('reject_session_by_customer', { p_session_id: id });
      if (error) throw error;
      toast('Order cancelled');
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not cancel', 'err');
    } finally {
      setCancelling(false);
    }
  };

  return (
    <div className="pagein">
      <PageHeader title={`Order ${shortId(session.id, session.display_id)}`} />
      <div className="px-5 md:px-8 py-5 max-w-3xl mx-auto">
        {/* Status hero */}
        <div
          className={`rounded-3xl p-5 mb-5 ${
            cancelled
              ? 'bg-surface-2'
              : delivered
                ? 'bg-success-tint'
                : 'bg-gradient-to-br from-[#128A3C] to-[#17A34A] text-white'
          }`}
        >
          <p
            className={`text-[13px] font-semibold mb-1 ${
              cancelled ? 'text-muted' : delivered ? 'text-success' : 'text-white/80'
            }`}
          >
            {cancelled ? 'Order cancelled' : delivered ? 'Delivered — enjoy!' : 'Order status'}
          </p>
          <h2
            className={`font-extrabold text-[24px] leading-tight ${
              cancelled ? 'text-ink-soft' : delivered ? 'text-success' : 'text-white'
            }`}
          >
            {SESSION_STATUS_LABEL[session.status] ?? session.status}
            {eta != null && ` · ~${eta} min`}
          </h2>

          {/* Progress steps */}
          {!cancelled && (
            <div className="flex items-center gap-1.5 mt-4">
              {STEPS.map((st, i) => (
                <div
                  key={st}
                  className={`h-1.5 flex-1 rounded-full ${
                    i <= stepIdx
                      ? delivered
                        ? 'bg-success'
                        : 'bg-white'
                      : delivered
                        ? 'bg-success/25'
                        : 'bg-white/30'
                  }`}
                />
              ))}
            </div>
          )}
        </div>

        {/* Handoff OTP */}
        {otp && !delivered && !cancelled && (
          <div className="flex items-center gap-4 bg-card rounded-2xl shadow-ios border-2 border-brand p-4 mb-5">
            <Icon name="pin" className="text-brand !text-[28px]" />
            <div className="flex-1">
              <p className="font-bold text-[14px]">Your delivery code</p>
              <p className="text-[12px] text-muted">Share with the delivery partner at the door</p>
            </div>
            <span className="font-extrabold text-[28px] tracking-[0.2em] text-brand">{otp}</span>
          </div>
        )}

        {/* Map */}
        {session.delivery_lat != null && session.delivery_lng != null && !cancelled && (
          <div className="mb-2 rounded-3xl overflow-hidden shadow-ios border border-border-subtle">
            <div ref={mapDivRef} className="h-56 md:h-72 w-full" />
          </div>
        )}
        {agentLat != null && !agentFresh && !delivered && !cancelled && (
          <p className="text-[12px] text-muted mb-4 px-1">
            Delivery partner's location was last updated a while ago — showing last known position.
          </p>
        )}

        {/* Agent card */}
        {agent?.users && !cancelled && (
          <div className="flex items-center gap-3 bg-card rounded-2xl shadow-ios border border-border-subtle p-4 mb-5 mt-3">
            <div className="w-11 h-11 rounded-full bg-brand-tint flex items-center justify-center">
              <Icon name="sports_motorsports" className="text-brand" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-bold text-[14px]">{agent.users.name ?? 'Delivery partner'}</p>
              <p className="text-[12px] text-muted">Your delivery partner</p>
            </div>
            {agent.users.phone && (
              <a
                href={`tel:${agent.users.phone}`}
                className="w-11 h-11 rounded-full bg-success text-white flex items-center justify-center press shadow-md"
                aria-label="Call delivery partner"
              >
                <Icon name="call" />
              </a>
            )}
          </div>
        )}

        {/* Shops in this order */}
        {subOrders.length > 0 && (
          <section className="mb-6">
            <h3 className="font-bold text-[15px] mb-2.5">Shops in this order</h3>
            <div className="space-y-2">
              {subOrders.map((o) => (
                <div
                  key={o.id}
                  className="flex items-center gap-3 bg-card rounded-2xl shadow-ios border border-border-subtle px-4 py-3"
                >
                  <Icon name="storefront" className="text-brand !text-[20px]" />
                  <span className="flex-1 font-semibold text-[14px] truncate">
                    {o.suppliers?.shop_name ?? 'Shop'}
                  </span>
                  <span className="text-[12px] font-bold text-ink-soft">
                    {ORDER_STATUS_LABEL[o.status] ?? o.status}
                  </span>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* Bill + address */}
        <section className="bg-card rounded-2xl shadow-ios border border-border-subtle p-4 mb-5">
          <div className="flex justify-between text-[14px] py-0.5">
            <span className="text-ink-soft">Items</span>
            <span className="font-semibold">{rupees(session.total - session.delivery_fee)}</span>
          </div>
          <div className="flex justify-between text-[14px] py-0.5">
            <span className="text-ink-soft">Delivery fee</span>
            <span className="font-semibold">{rupees(session.delivery_fee)}</span>
          </div>
          <div className="border-t border-border-subtle my-2" />
          <div className="flex justify-between font-bold text-[15px]">
            <span>Total (Cash on Delivery)</span>
            <span>{rupees(session.total)}</span>
          </div>
          {session.delivery_address && (
            <p className="text-[12px] text-muted mt-3 flex items-start gap-1.5">
              <Icon name="location_on" className="!text-[15px] mt-px" />
              {session.delivery_address}
            </p>
          )}
        </section>

        {session.status === 'waiting_suppliers' && (
          <button
            onClick={cancelOrder}
            disabled={cancelling}
            className="w-full h-12 rounded-2xl border border-danger/30 text-danger font-bold text-[14px] press disabled:opacity-50"
          >
            {cancelling ? 'Cancelling…' : 'Cancel order'}
          </button>
        )}
      </div>
    </div>
  );
}

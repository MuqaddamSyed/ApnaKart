import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { getFix } from '../lib/geo';
import {
  CATEGORIES,
  FAST_FOOD,
  DEFAULT_RADIUS_KM,
  TOP_DEAL_MIN,
  FALLBACK_LAT,
  FALLBACK_LNG,
} from '../lib/constants';
import type { Product, Supplier } from '../lib/types';
import { Icon, SectionHeader, EmptyState } from '../components/Bits';
import { BrandMark } from '../components/AppShell';
import { ProductCard, ProductGrid, ProductSkeleton } from '../components/ProductCard';

export default function Home() {
  const { session } = useAuth();
  const nav = useNavigate();
  const [shops, setShops] = useState<Supplier[] | null>(null);
  const [deals, setDeals] = useState<Product[] | null>(null);
  const [locLabel, setLocLabel] = useState<string>('Set your location');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      // Location priority: saved default -> browser GPS -> fallback town centre.
      let lat = FALLBACK_LAT;
      let lng = FALLBACK_LNG;
      let label = 'Around your town';
      try {
        if (session) {
          const { data: c } = await supabase
            .from('customers')
            .select('default_address,default_lat,default_lng')
            .eq('id', session.user.id)
            .maybeSingle();
          if (c?.default_lat != null && c?.default_lng != null) {
            lat = c.default_lat;
            lng = c.default_lng;
            label = (c.default_address as string) || 'Saved address';
          }
        }
        if (label === 'Around your town') {
          try {
            const fix = await getFix(6000);
            lat = fix.lat;
            lng = fix.lng;
            label = 'Current location';
          } catch {
            /* fall back silently — browsing still works */
          }
        }
      } finally {
        if (!cancelled) setLocLabel(label);
      }

      // Nearby shops via PostGIS RPC, with a plain query as fallback.
      try {
        const { data, error } = await supabase.rpc('nearby_suppliers', {
          user_lng: lng,
          user_lat: lat,
          radius_m: DEFAULT_RADIUS_KM * 1000,
        });
        if (error) throw error;
        if (!cancelled) setShops((data as Supplier[]) ?? []);
      } catch {
        const { data } = await supabase
          .from('suppliers')
          .select()
          .eq('is_verified', true)
          .order('shop_name');
        if (!cancelled) setShops((data as Supplier[]) ?? []);
      }

      // Top deals.
      const { data: dealRows } = await supabase
        .from('products')
        .select('*, suppliers(shop_name, is_open)')
        .gte('discount_percent', TOP_DEAL_MIN)
        .eq('is_available', true)
        .limit(10);
      if (!cancelled) setDeals((dealRows as Product[]) ?? []);
    })();
    return () => {
      cancelled = true;
    };
  }, [session]);

  return (
    <div className="pagein">
      {/* Mobile glass header */}
      <header className="md:hidden glass sticky top-0 z-40 flex items-center justify-between px-5 py-3 border-b border-border-subtle">
        <BrandMark />
        <button
          onClick={() => nav(session ? '/profile' : '/login')}
          className="flex items-center gap-1 text-[13px] font-medium text-ink-soft press max-w-[55%]"
        >
          <Icon name="location_on" className="text-brand !text-[18px]" />
          <span className="truncate">{locLabel}</span>
          <Icon name="expand_more" className="!text-[16px]" />
        </button>
      </header>

      <div className="px-5 md:px-8">
        {/* Search bar */}
        <div className="pt-4 pb-2">
          <button
            onClick={() => nav('/search')}
            className="w-full h-[52px] flex items-center gap-3 px-4 bg-card rounded-2xl shadow-ios border border-border-subtle text-muted text-[15px] press"
          >
            <Icon name="search" />
            Search for “milk”, “bread”…
          </button>
        </div>

        {/* Hero banner */}
        <section className="mt-3 mb-8">
          <div className="relative w-full h-44 md:h-56 rounded-3xl overflow-hidden shadow-ios-lg bg-gradient-to-br from-[#128A3C] via-[#17A34A] to-[#F5B800]">
            <div className="absolute -right-8 -bottom-10 w-52 h-52 rounded-full bg-white/10" />
            <div className="absolute right-16 -top-10 w-36 h-36 rounded-full bg-white/10" />
            <div className="absolute inset-0 flex flex-col justify-center px-6 md:px-10">
              <span className="text-white/85 text-[11px] font-bold tracking-[0.18em] mb-1.5">
                EXPRESS DELIVERY
              </span>
              <h1 className="text-white font-extrabold text-[26px] md:text-[34px] leading-tight max-w-[260px] md:max-w-[400px] mb-4">
                Your local shops, delivered in minutes
              </h1>
              <button
                onClick={() => nav('/search')}
                className="bg-white text-[#128A3C] text-[13px] font-bold px-5 py-2.5 rounded-full w-fit press shadow-md"
              >
                Shop Now
              </button>
            </div>
          </div>
        </section>

        {/* Categories */}
        <section className="mb-8">
          <SectionHeader title="Categories" />
          <div className="flex md:grid md:grid-cols-9 overflow-x-auto hide-scrollbar gap-5 md:gap-3 -mx-5 px-5 md:mx-0 md:px-0">
            {[...CATEGORIES, FAST_FOOD].map((c) => (
              <Link
                key={c.name}
                to={
                  c.name === 'Fast Food'
                    ? '/category/Fast%20Food'
                    : `/category/${encodeURIComponent(c.name)}`
                }
                className="flex flex-col items-center gap-2 flex-shrink-0 group w-[68px] md:w-auto"
              >
                <div
                  className={`w-16 h-16 ${c.tint} rounded-[24%] flex items-center justify-center transition-transform group-active:scale-90 group-hover:scale-105`}
                >
                  <Icon name={c.icon} className={`${c.fg} !text-[28px]`} />
                </div>
                <span className="text-[12px] font-medium text-center leading-tight">
                  {'short' in c ? (c as { short: string }).short : c.name}
                </span>
              </Link>
            ))}
          </div>
        </section>

        {/* Shops near you */}
        <section className="mb-8">
          <SectionHeader title="Shops near you" />
          {shops === null ? (
            <div className="flex gap-4 overflow-hidden">
              {[1, 2, 3].map((i) => (
                <div key={i} className="w-56 h-32 rounded-2xl skeleton flex-shrink-0" />
              ))}
            </div>
          ) : shops.length === 0 ? (
            <EmptyState
              icon="storefront"
              title="No shops in range yet"
              subtitle="We're onboarding shops in your area. Check back soon!"
            />
          ) : (
            <div className="flex overflow-x-auto hide-scrollbar gap-4 -mx-5 px-5 md:mx-0 md:px-0 md:grid md:grid-cols-3 lg:grid-cols-4">
              {shops.map((s) => (
                <Link
                  key={s.id}
                  to={`/shop/${s.id}`}
                  className="w-60 md:w-auto flex-shrink-0 bg-card rounded-2xl p-4 shadow-ios border border-border-subtle press group"
                >
                  <div className="flex items-start justify-between mb-3">
                    <div className="w-12 h-12 rounded-[24%] bg-brand-tint flex items-center justify-center">
                      <Icon name="storefront" className="text-brand !text-[24px]" />
                    </div>
                    <span
                      className={`text-[11px] font-bold px-2.5 py-1 rounded-full ${
                        s.is_open ? 'bg-success-tint text-success' : 'bg-surface-2 text-muted'
                      }`}
                    >
                      {s.is_open ? 'OPEN' : 'CLOSED'}
                    </span>
                  </div>
                  <h3 className="font-bold text-[16px] leading-tight mb-0.5 line-clamp-1 group-hover:text-brand transition-colors">
                    {s.shop_name}
                  </h3>
                  <p className="text-[12px] text-muted line-clamp-1">
                    {s.category || 'Local shop'}
                    {s.distance_m != null && ` · ${(s.distance_m / 1000).toFixed(1)} km`}
                  </p>
                </Link>
              ))}
            </div>
          )}
        </section>

        {/* Top deals */}
        <section className="mb-8">
          <SectionHeader title="Top Deals" />
          {deals === null ? (
            <ProductGrid>
              {[1, 2, 3, 4].map((i) => (
                <ProductSkeleton key={i} />
              ))}
            </ProductGrid>
          ) : deals.length === 0 ? (
            <p className="text-[14px] text-muted py-4">
              No big discounts right now — browse the categories above.
            </p>
          ) : (
            <ProductGrid>
              {deals.map((p) => (
                <ProductCard key={p.id} p={p} />
              ))}
            </ProductGrid>
          )}
        </section>
      </div>
    </div>
  );
}

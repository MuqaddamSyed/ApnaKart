import { useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import type { Product, Supplier } from '../lib/types';
import { Icon, EmptyState, Spinner } from '../components/Bits';
import { ProductCard, ProductGrid } from '../components/ProductCard';
import { PageHeader } from './CategoryPage';

export default function ShopPage() {
  const { id = '' } = useParams();
  const [shop, setShop] = useState<Supplier | null>(null);
  const [products, setProducts] = useState<Product[] | null>(null);
  const [filter, setFilter] = useState<string>('All');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [{ data: s }, { data: p }] = await Promise.all([
        supabase.from('suppliers').select().eq('id', id).maybeSingle(),
        supabase
          .from('products')
          .select('*, suppliers(shop_name, is_open)')
          .eq('supplier_id', id)
          .eq('is_available', true)
          .order('category'),
      ]);
      if (cancelled) return;
      setShop((s as Supplier) ?? null);
      setProducts((p as Product[]) ?? []);
    })();
    return () => {
      cancelled = true;
    };
  }, [id]);

  const cats = useMemo(() => {
    const set = new Set<string>();
    (products ?? []).forEach((p) => p.category && set.add(p.category));
    return ['All', ...Array.from(set)];
  }, [products]);

  const visible = useMemo(
    () => (products ?? []).filter((p) => filter === 'All' || p.category === filter),
    [products, filter],
  );

  if (products === null) {
    return (
      <div>
        <PageHeader title="Shop" />
        <Spinner />
      </div>
    );
  }

  return (
    <div className="pagein">
      <PageHeader title={shop?.shop_name ?? 'Shop'} subtitle={shop?.address ?? undefined} />
      <div className="px-5 md:px-8 py-5">
        {/* Shop status banner */}
        {shop && !shop.is_open && (
          <div className="mb-5 flex items-center gap-3 bg-surface-2 border border-border-subtle rounded-2xl px-4 py-3">
            <Icon name="schedule" className="text-muted" />
            <p className="text-[14px] text-ink-soft">
              This shop is <strong>closed</strong> right now — you can browse, but ordering resumes
              when it reopens.
            </p>
          </div>
        )}

        {/* Category filter chips */}
        {cats.length > 2 && (
          <div className="flex overflow-x-auto hide-scrollbar gap-2 mb-5 -mx-5 px-5 md:mx-0 md:px-0">
            {cats.map((c) => (
              <button
                key={c}
                onClick={() => setFilter(c)}
                className={`flex-shrink-0 px-4 py-2 rounded-full text-[13px] font-semibold press border ${
                  filter === c
                    ? 'bg-ink text-white border-ink'
                    : 'bg-card text-ink-soft border-border-subtle shadow-sm'
                }`}
              >
                {c}
              </button>
            ))}
          </div>
        )}

        {visible.length === 0 ? (
          <EmptyState icon="inventory_2" title="Nothing on the shelves yet" />
        ) : (
          <ProductGrid>
            {visible.map((p) => (
              <ProductCard key={p.id} p={p} shopName={shop?.shop_name} />
            ))}
          </ProductGrid>
        )}
      </div>
    </div>
  );
}

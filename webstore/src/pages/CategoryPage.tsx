import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import type { Product } from '../lib/types';
import { Icon, EmptyState } from '../components/Bits';
import { ProductCard, ProductGrid, ProductSkeleton } from '../components/ProductCard';

export function PageHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  const nav = useNavigate();
  return (
    <header className="glass sticky top-0 md:top-16 z-40 flex items-center gap-3 px-4 py-3 border-b border-border-subtle">
      <button
        onClick={() => nav(-1)}
        className="w-10 h-10 rounded-full bg-card shadow-sm border border-border-subtle flex items-center justify-center press"
        aria-label="Back"
      >
        <Icon name="arrow_back" className="!text-[20px]" />
      </button>
      <div className="min-w-0">
        <h1 className="font-bold text-[18px] leading-tight truncate">{title}</h1>
        {subtitle && <p className="text-[12px] text-muted truncate">{subtitle}</p>}
      </div>
    </header>
  );
}

export default function CategoryPage() {
  const { name = '' } = useParams();
  const category = decodeURIComponent(name);
  const [products, setProducts] = useState<Product[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    setProducts(null);
    (async () => {
      const { data } = await supabase
        .from('products')
        .select('*, suppliers(shop_name, is_open)')
        .eq('category', category)
        .eq('is_available', true)
        .order('discount_percent', { ascending: false });
      if (!cancelled) setProducts((data as Product[]) ?? []);
    })();
    return () => {
      cancelled = true;
    };
  }, [category]);

  return (
    <div className="pagein">
      <PageHeader
        title={category}
        subtitle={products ? `${products.length} item${products.length === 1 ? '' : 's'}` : undefined}
      />
      <div className="px-5 md:px-8 py-5">
        {products === null ? (
          <ProductGrid>
            {[1, 2, 3, 4, 5, 6].map((i) => (
              <ProductSkeleton key={i} />
            ))}
          </ProductGrid>
        ) : products.length === 0 ? (
          <EmptyState
            icon="category"
            title={`No ${category} yet`}
            subtitle="Shops are still stocking this aisle. Try another category."
          />
        ) : (
          <ProductGrid>
            {products.map((p) => (
              <ProductCard key={p.id} p={p} />
            ))}
          </ProductGrid>
        )}
      </div>
    </div>
  );
}

import { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import type { Product } from '../lib/types';
import { Icon, EmptyState } from '../components/Bits';
import { ProductCard, ProductGrid, ProductSkeleton } from '../components/ProductCard';
import { CATEGORIES } from '../lib/constants';
import { Link } from 'react-router-dom';

export default function SearchPage() {
  const [q, setQ] = useState('');
  const [results, setResults] = useState<Product[] | null>(null);
  const [busy, setBusy] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    const query = q.trim();
    if (query.length < 2) {
      setResults(null);
      setBusy(false);
      return;
    }
    setBusy(true);
    debounceRef.current = setTimeout(async () => {
      const { data } = await supabase
        .from('products')
        .select('*, suppliers(shop_name, is_open)')
        .ilike('name', `%${query}%`)
        .eq('is_available', true)
        .limit(40);
      setResults((data as Product[]) ?? []);
      setBusy(false);
    }, 300);
    return () => clearTimeout(debounceRef.current);
  }, [q]);

  return (
    <div className="pagein">
      <header className="glass sticky top-0 md:top-16 z-40 px-4 py-3 border-b border-border-subtle">
        <div className="relative">
          <Icon
            name="search"
            className="absolute left-4 top-1/2 -translate-y-1/2 text-muted !text-[22px]"
          />
          <input
            ref={inputRef}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search products…"
            className="w-full h-[52px] pl-12 pr-10 bg-card rounded-2xl shadow-ios border border-border-subtle text-[15px] outline-none focus:ring-2 focus:ring-brand/25 placeholder:text-muted"
          />
          {q && (
            <button
              onClick={() => setQ('')}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-muted press"
              aria-label="Clear"
            >
              <Icon name="close" className="!text-[20px]" />
            </button>
          )}
        </div>
      </header>

      <div className="px-5 md:px-8 py-5">
        {results === null && !busy ? (
          <>
            <h2 className="text-[15px] font-bold text-ink-soft mb-3">Browse categories</h2>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {CATEGORIES.map((c) => (
                <Link
                  key={c.name}
                  to={`/category/${encodeURIComponent(c.name)}`}
                  className="flex items-center gap-3 bg-card rounded-2xl px-4 py-3.5 shadow-ios border border-border-subtle press"
                >
                  <div className={`w-10 h-10 ${c.tint} rounded-[24%] flex items-center justify-center`}>
                    <Icon name={c.icon} className={`${c.fg} !text-[20px]`} />
                  </div>
                  <span className="text-[14px] font-semibold leading-tight">{c.short}</span>
                </Link>
              ))}
            </div>
          </>
        ) : busy ? (
          <ProductGrid>
            {[1, 2, 3, 4].map((i) => (
              <ProductSkeleton key={i} />
            ))}
          </ProductGrid>
        ) : results && results.length === 0 ? (
          <EmptyState
            icon="search_off"
            title={`Nothing found for “${q.trim()}”`}
            subtitle="Try a shorter word — like “milk” instead of “fresh cow milk”."
          />
        ) : (
          <ProductGrid>
            {results!.map((p) => (
              <ProductCard key={p.id} p={p} />
            ))}
          </ProductGrid>
        )}
      </div>
    </div>
  );
}

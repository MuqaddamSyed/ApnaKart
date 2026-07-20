import { Icon, QtyStepper, useToast } from './Bits';
import { rupees } from '../lib/format';
import type { Product } from '../lib/types';
import { useCart } from '../store/cart';

export function ProductCard({ p, shopName }: { p: Product; shopName?: string }) {
  const { items, add, setQty } = useCart();
  const inCart = items.find((i) => i.productId === p.id);
  const toast = useToast();
  const shop = shopName ?? p.suppliers?.shop_name ?? '';
  const shopOpen = p.suppliers?.is_open !== false;
  const hasDiscount = p.discount_percent >= 5 && p.mrp > p.sale_price;

  const addToCart = () => {
    if (!shopOpen) {
      toast('This shop is closed right now', 'err');
      return;
    }
    add({
      productId: p.id,
      supplierId: p.supplier_id,
      shopName: shop || 'Shop',
      name: p.name,
      unit: p.unit,
      price: p.sale_price,
      imageUrl: p.image_url,
    });
  };

  return (
    <div className="bg-card rounded-2xl p-3 shadow-ios border border-border-subtle flex flex-col relative group pagein">
      {hasDiscount && (
        <span className="absolute top-2 left-2 z-10 bg-success text-white text-[11px] font-bold px-2 py-0.5 rounded-full shadow-sm">
          {p.discount_percent}% OFF
        </span>
      )}
      <div className="aspect-square rounded-xl overflow-hidden mb-3 bg-surface-2">
        {p.image_url ? (
          <img
            src={p.image_url}
            alt={p.name}
            loading="lazy"
            className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center">
            <Icon name="shopping_basket" className="text-muted !text-[32px]" />
          </div>
        )}
      </div>
      {shop && (
        <span className="text-[11px] font-semibold text-muted uppercase tracking-wide mb-0.5 line-clamp-1">
          {shop}
          {!shopOpen && <span className="text-danger normal-case font-medium"> · closed</span>}
        </span>
      )}
      <h3 className="text-[15px] font-semibold leading-tight mb-0.5 line-clamp-2">{p.name}</h3>
      {p.unit && <p className="text-[12px] text-muted mb-2">{p.unit}</p>}
      <div className="mt-auto flex items-center justify-between pt-1">
        <div className="flex flex-col">
          <span className="text-[16px] font-bold">{rupees(p.sale_price)}</span>
          {hasDiscount && (
            <span className="text-[11px] text-muted line-through">{rupees(p.mrp)}</span>
          )}
        </div>
        {inCart ? (
          <QtyStepper small qty={inCart.qty} onChange={(q) => setQty(p.id, q)} />
        ) : (
          <button
            aria-label={`Add ${p.name}`}
            onClick={addToCart}
            className="w-9 h-9 rounded-full bg-brand text-white flex items-center justify-center press shadow-md hover:brightness-110"
          >
            <Icon name="add" className="!text-[20px]" />
          </button>
        )}
      </div>
    </div>
  );
}

export const ProductGrid = ({ children }: { children: React.ReactNode }) => (
  <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
    {children}
  </div>
);

export const ProductSkeleton = () => (
  <div className="bg-card rounded-2xl p-3 shadow-ios border border-border-subtle">
    <div className="aspect-square rounded-xl skeleton mb-3" />
    <div className="h-3 w-2/3 skeleton rounded mb-2" />
    <div className="h-4 w-full skeleton rounded mb-2" />
    <div className="h-4 w-1/3 skeleton rounded" />
  </div>
);

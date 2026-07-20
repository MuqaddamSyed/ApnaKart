import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export interface CartItem {
  productId: string;
  supplierId: string;
  shopName: string;
  name: string;
  unit?: string | null;
  price: number;
  imageUrl?: string | null;
  qty: number;
}

interface CartState {
  items: CartItem[];
  add: (item: Omit<CartItem, 'qty'>) => void;
  setQty: (productId: string, qty: number) => void;
  remove: (productId: string) => void;
  clear: () => void;
}

export const useCart = create<CartState>()(
  persist(
    (set) => ({
      items: [],
      add: (item) =>
        set((s) => {
          const existing = s.items.find((i) => i.productId === item.productId);
          if (existing) {
            return {
              items: s.items.map((i) =>
                i.productId === item.productId ? { ...i, qty: i.qty + 1 } : i,
              ),
            };
          }
          return { items: [...s.items, { ...item, qty: 1 }] };
        }),
      setQty: (productId, qty) =>
        set((s) => ({
          items:
            qty <= 0
              ? s.items.filter((i) => i.productId !== productId)
              : s.items.map((i) => (i.productId === productId ? { ...i, qty } : i)),
        })),
      remove: (productId) =>
        set((s) => ({ items: s.items.filter((i) => i.productId !== productId) })),
      clear: () => set({ items: [] }),
    }),
    { name: 'myminto-cart' },
  ),
);

export const cartSubtotal = (items: CartItem[]) =>
  items.reduce((s, i) => s + i.price * i.qty, 0);

export const cartBySupplier = (items: CartItem[]) => {
  const map = new Map<string, CartItem[]>();
  for (const i of items) {
    const list = map.get(i.supplierId) ?? [];
    list.push(i);
    map.set(i.supplierId, list);
  }
  return map;
};

export const cartCount = (items: CartItem[]) => items.reduce((s, i) => s + i.qty, 0);

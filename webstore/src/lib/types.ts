export interface Supplier {
  id: string;
  shop_name: string;
  address?: string | null;
  category?: string | null;
  is_open: boolean;
  is_verified: boolean;
  image_url?: string | null;
  distance_m?: number | null; // from nearby_suppliers RPC
}

export interface Product {
  id: string;
  supplier_id: string;
  name: string;
  description?: string | null;
  image_url?: string | null;
  category?: string | null;
  mrp: number;
  sale_price: number;
  discount_percent: number;
  stock_qty: number;
  unit?: string | null;
  is_available: boolean;
  suppliers?: { shop_name?: string | null; is_open?: boolean | null } | null;
}

export interface Address {
  id: string;
  customer_id: string;
  label?: string | null;
  full_address: string;
  lat?: number | null;
  lng?: number | null;
  is_default?: boolean | null;
}

export interface OrderSession {
  id: string;
  display_id?: string | null;
  customer_id?: string | null;
  delivery_id?: string | null;
  status: string;
  delivery_address?: string | null;
  delivery_lat?: number | null;
  delivery_lng?: number | null;
  delivery_fee: number;
  total: number;
  delivery_mode?: string | null;
  placed_at: string;
  delivered_at?: string | null;
}

export interface SubOrder {
  id: string;
  session_id?: string | null;
  supplier_id: string;
  status: string;
  subtotal: number;
  total: number;
  suppliers?: { shop_name?: string | null } | null;
}

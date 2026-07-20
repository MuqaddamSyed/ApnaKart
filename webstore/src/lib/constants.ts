// Business rules — mirror lib/core/constants/app_constants.dart exactly.
export const APP_NAME = 'myMinto';
export const FLAT_DELIVERY_FEE = 10;
export const MIN_ORDER_VALUE = 39;
export const DEFAULT_RADIUS_KM = 5;
export const TOP_DEAL_MIN = 20;
export const SUPPORT_EMAIL = 'customer_care@myminto.in';

// Fallback town centre (matches the Flutter customer app).
export const FALLBACK_LAT = 14.4644;
export const FALLBACK_LNG = 75.9218;

export const MAPTILER_KEY = import.meta.env.VITE_MAPTILER_KEY as string;
export const TILE_URL = `https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=${MAPTILER_KEY}`;

export interface CategoryDef {
  name: string;
  icon: string;      // material symbol
  tint: string;      // tailwind bg class for the squircle
  fg: string;        // tailwind text class for the icon
  short: string;     // short display label
}

export const CATEGORIES: CategoryDef[] = [
  { name: 'Vegetables', short: 'Veggies', icon: 'nutrition', tint: 'bg-green-100', fg: 'text-green-700' },
  { name: 'Fruits', short: 'Fruits', icon: 'eco', tint: 'bg-orange-100', fg: 'text-orange-600' },
  { name: 'Rice, Atta, Dals - Groceries', short: 'Groceries', icon: 'grain', tint: 'bg-amber-100', fg: 'text-amber-700' },
  { name: 'Chocolates', short: 'Chocolates', icon: 'cookie', tint: 'bg-yellow-100', fg: 'text-yellow-800' },
  { name: 'Ice Cream', short: 'Ice Cream', icon: 'icecream', tint: 'bg-sky-100', fg: 'text-sky-600' },
  { name: 'Packaged food', short: 'Packaged', icon: 'lunch_dining', tint: 'bg-purple-100', fg: 'text-purple-700' },
  { name: 'Medical Store', short: 'Medical', icon: 'medical_services', tint: 'bg-red-100', fg: 'text-red-600' },
  { name: 'Home Essentials', short: 'Home', icon: 'cleaning_services', tint: 'bg-teal-100', fg: 'text-teal-700' },
];

export const FAST_FOOD = { name: 'Fast Food', icon: 'fastfood', tint: 'bg-rose-100', fg: 'text-rose-600' };

export const SESSION_STATUS_LABEL: Record<string, string> = {
  waiting_suppliers: 'Waiting for shops',
  all_confirmed: 'Being prepared',
  out_for_delivery: 'On the way',
  delivered: 'Delivered',
  cancelled: 'Cancelled',
};

export const ORDER_STATUS_LABEL: Record<string, string> = {
  placed: 'Placed',
  confirmed: 'Confirmed',
  preparing: 'Preparing',
  picked_up: 'Picked up',
  on_the_way: 'On the way',
  arrived: 'Reached you',
  delivered: 'Delivered',
  returned: 'Returned',
  cancelled: 'Cancelled',
};

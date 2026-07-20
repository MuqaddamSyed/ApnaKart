export const rupees = (v: number) =>
  `₹${v % 1 === 0 ? v.toFixed(0) : v.toFixed(2)}`;

export const timeAgo = (iso: string) => {
  const d = Date.now() - new Date(iso).getTime();
  const m = Math.floor(d / 60000);
  if (m < 1) return 'just now';
  if (m < 60) return `${m} min ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  return new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
};

export const shortId = (id: string, display?: string | null) =>
  display ?? `#${id.slice(0, 6).toUpperCase()}`;

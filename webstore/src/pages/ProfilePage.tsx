import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { Icon, useToast, Spinner, EmptyState } from '../components/Bits';
import { getFix, isPrecise } from '../lib/geo';
import { SUPPORT_EMAIL } from '../lib/constants';
import type { Address } from '../lib/types';

export default function ProfilePage() {
  const { session, profile, loading } = useAuth();
  const nav = useNavigate();
  const toast = useToast();
  const [addresses, setAddresses] = useState<Address[] | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [label, setLabel] = useState('Home');
  const [full, setFull] = useState('');
  const [lat, setLat] = useState<number | null>(null);
  const [lng, setLng] = useState<number | null>(null);
  const [locating, setLocating] = useState(false);
  const [busy, setBusy] = useState(false);

  const loadAddresses = async (uid: string) => {
    const { data } = await supabase
      .from('addresses')
      .select()
      .eq('customer_id', uid)
      .order('is_default', { ascending: false });
    setAddresses((data as Address[]) ?? []);
  };

  useEffect(() => {
    if (session) loadAddresses(session.user.id);
  }, [session]);

  if (loading) return <Spinner />;
  if (!session) {
    return (
      <EmptyState
        icon="person"
        title="You're not signed in"
        subtitle="Sign in to see your profile, addresses and orders."
        action={
          <Link to="/login" className="bg-brand text-white font-bold text-[14px] px-6 py-3 rounded-full press shadow-md">
            Sign in
          </Link>
        }
      />
    );
  }

  const saveAddress = async () => {
    if (full.trim().length < 8) {
      toast('Enter the full address', 'err');
      return;
    }
    setBusy(true);
    try {
      const { error } = await supabase.from('addresses').insert({
        customer_id: session.user.id,
        label: label.trim() || 'Home',
        full_address: full.trim(),
        lat,
        lng,
      });
      if (error) throw error;
      setShowForm(false);
      setFull('');
      setLat(null);
      setLng(null);
      await loadAddresses(session.user.id);
      toast('Address saved');
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not save', 'err');
    } finally {
      setBusy(false);
    }
  };

  const setDefault = async (a: Address) => {
    await supabase.from('addresses').update({ is_default: false }).eq('customer_id', session.user.id);
    await supabase.from('addresses').update({ is_default: true }).eq('id', a.id);
    await supabase
      .from('customers')
      .update({ default_address: a.full_address, default_lat: a.lat, default_lng: a.lng })
      .eq('id', session.user.id);
    await loadAddresses(session.user.id);
    toast('Default address updated');
  };

  const deleteAddress = async (a: Address) => {
    await supabase.from('addresses').delete().eq('id', a.id);
    await loadAddresses(session.user.id);
  };

  const useMyLocation = async () => {
    setLocating(true);
    try {
      const fix = await getFix();
      setLat(fix.lat);
      setLng(fix.lng);
      toast(isPrecise(fix) ? 'Location pinned' : `Approximate (±${Math.round(fix.accuracyM)}m)`);
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Location failed', 'err');
    } finally {
      setLocating(false);
    }
  };

  const logout = async () => {
    await supabase.auth.signOut();
    nav('/');
  };

  const deleteAccount = async () => {
    const first = window.confirm(
      'Delete your account permanently?\n\nThis removes your profile, addresses and sign-in. Past orders stay with the shops but are no longer linked to you.',
    );
    if (!first) return;
    const typed = window.prompt('Type DELETE to confirm:');
    if (typed?.trim().toUpperCase() !== 'DELETE') return;
    try {
      const { error } = await supabase.rpc('delete_my_account');
      if (error) throw error;
      await supabase.auth.signOut();
      toast('Your account has been deleted');
      nav('/');
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not delete account', 'err');
    }
  };

  const row =
    'w-full flex items-center gap-3 px-4 py-3.5 bg-card rounded-2xl shadow-ios border border-border-subtle press text-left';

  return (
    <div className="pagein px-5 md:px-8 py-6 max-w-2xl mx-auto">
      {/* Identity card */}
      <div className="flex items-center gap-4 mb-8">
        <div className="w-16 h-16 rounded-full bg-brand-tint flex items-center justify-center">
          <Icon name="person" className="text-brand !text-[30px]" />
        </div>
        <div className="min-w-0">
          <h1 className="font-bold text-[20px] leading-tight truncate">
            {profile?.name || 'myMinto customer'}
          </h1>
          <p className="text-[13px] text-muted truncate">
            {profile?.email ?? session.user.email} {profile?.phone ? `· ${profile.phone}` : ''}
          </p>
        </div>
      </div>

      {/* Addresses */}
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-[17px] font-bold">Saved addresses</h2>
        <button
          onClick={() => setShowForm((v) => !v)}
          className="text-brand text-[13px] font-bold flex items-center gap-1 press"
        >
          <Icon name={showForm ? 'close' : 'add'} className="!text-[18px]" />
          {showForm ? 'Cancel' : 'Add new'}
        </button>
      </div>

      {showForm && (
        <div className="bg-card rounded-2xl shadow-ios border border-border-subtle p-4 mb-4 space-y-3">
          <div className="flex gap-2">
            {['Home', 'Work', 'Other'].map((l) => (
              <button
                key={l}
                onClick={() => setLabel(l)}
                className={`px-4 py-1.5 rounded-full text-[13px] font-semibold border press ${
                  label === l ? 'bg-ink text-white border-ink' : 'bg-surface text-ink-soft border-border-subtle'
                }`}
              >
                {l}
              </button>
            ))}
          </div>
          <textarea
            className="w-full min-h-[76px] px-4 py-3 bg-surface rounded-xl border border-border-subtle text-[14px] outline-none focus:ring-2 focus:ring-brand/25"
            placeholder="House, street, area, landmark, pincode"
            value={full}
            onChange={(e) => setFull(e.target.value)}
          />
          <div className="flex gap-2">
            <button
              onClick={useMyLocation}
              disabled={locating}
              className="flex-1 h-11 rounded-xl border border-border-subtle bg-surface text-[13px] font-semibold press flex items-center justify-center gap-1.5 disabled:opacity-50"
            >
              <Icon name="my_location" className="text-brand !text-[18px]" />
              {locating ? 'Locating…' : lat != null ? 'Pinned ✓' : 'Pin location'}
            </button>
            <button
              onClick={saveAddress}
              disabled={busy}
              className="flex-1 h-11 rounded-xl bg-brand text-white text-[13px] font-bold press disabled:opacity-50"
            >
              Save address
            </button>
          </div>
        </div>
      )}

      <div className="space-y-2.5 mb-8">
        {addresses === null ? (
          <Spinner />
        ) : addresses.length === 0 ? (
          <p className="text-[13px] text-muted">No saved addresses yet.</p>
        ) : (
          addresses.map((a) => (
            <div key={a.id} className="flex items-start gap-3 px-4 py-3.5 bg-card rounded-2xl shadow-ios border border-border-subtle">
              <Icon
                name={a.label === 'Work' ? 'apartment' : 'home'}
                className="text-brand !text-[20px] mt-0.5"
              />
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-bold text-[14px]">{a.label ?? 'Home'}</span>
                  {a.is_default && (
                    <span className="text-[10px] font-bold bg-success-tint text-success px-2 py-0.5 rounded-full">
                      DEFAULT
                    </span>
                  )}
                  {a.lat != null && (
                    <Icon name="location_on" className="!text-[14px] text-success" />
                  )}
                </div>
                <p className="text-[13px] text-ink-soft leading-snug">{a.full_address}</p>
                {!a.is_default && (
                  <button onClick={() => setDefault(a)} className="text-[12px] text-brand font-bold mt-1 press">
                    Set as default
                  </button>
                )}
              </div>
              <button onClick={() => deleteAddress(a)} className="text-muted press" aria-label="Delete address">
                <Icon name="delete" className="!text-[20px]" />
              </button>
            </div>
          ))
        )}
      </div>

      {/* Actions */}
      <div className="space-y-2.5">
        <a href={`mailto:${SUPPORT_EMAIL}`} className={row}>
          <Icon name="support_agent" className="text-ink-soft" />
          <span className="flex-1 text-[15px] font-medium">Help & support</span>
          <Icon name="chevron_right" className="text-muted" />
        </a>
        <button onClick={logout} className={row}>
          <Icon name="logout" className="text-danger" />
          <span className="flex-1 text-[15px] font-medium text-danger">Log out</span>
        </button>
        <button onClick={deleteAccount} className={row}>
          <Icon name="delete_forever" className="text-danger" />
          <div className="flex-1">
            <span className="block text-[15px] font-medium text-danger">Delete account</span>
            <span className="block text-[12px] text-muted">Permanently remove your account and data</span>
          </div>
        </button>
      </div>
    </div>
  );
}

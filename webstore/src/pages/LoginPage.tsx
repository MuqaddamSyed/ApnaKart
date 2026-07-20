import { useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { useToast, Icon } from '../components/Bits';
import { BrandMark } from '../components/AppShell';
import { getFix, isPrecise } from '../lib/geo';

/** Email-OTP sign-in + first-time onboarding (phone & address), matching the
 *  mobile app: verify OTP -> if users row has no role, collect phone/address
 *  -> register_user_profile RPC -> save default address on customers. */
export default function LoginPage() {
  const nav = useNavigate();
  const loc = useLocation();
  const dest = (loc.state as { from?: string } | null)?.from ?? '/';
  const { refreshProfile } = useAuth();
  const toast = useToast();

  const [step, setStep] = useState<'email' | 'otp' | 'onboard'>('email');
  const [email, setEmail] = useState('');
  const [otp, setOtp] = useState('');
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [address, setAddress] = useState('');
  const [lat, setLat] = useState<number | null>(null);
  const [lng, setLng] = useState<number | null>(null);
  const [locating, setLocating] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const sendOtp = async () => {
    const e = email.trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e)) {
      setError('Enter a valid email address');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const { error } = await supabase.auth.signInWithOtp({ email: e });
      if (error) throw error;
      setStep('otp');
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  const verify = async () => {
    setBusy(true);
    setError(null);
    try {
      const { data, error } = await supabase.auth.verifyOtp({
        email: email.trim().toLowerCase(),
        token: otp.trim(),
        type: 'email',
      });
      if (error) throw error;
      const uid = data.user?.id;
      if (!uid) throw new Error('Sign-in failed');
      // Existing customer? straight in. New? onboarding.
      const { data: row } = await supabase.from('users').select('role').eq('id', uid).maybeSingle();
      if (row?.role) {
        await refreshProfile();
        toast('Welcome back!');
        nav(dest, { replace: true });
      } else {
        setStep('onboard');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  const useMyLocation = async () => {
    setLocating(true);
    try {
      const fix = await getFix();
      setLat(fix.lat);
      setLng(fix.lng);
      toast(
        isPrecise(fix)
          ? 'Location pinned'
          : `Location is approximate (±${Math.round(fix.accuracyM)}m)`,
        isPrecise(fix) ? 'ok' : 'err',
      );
    } catch (err) {
      toast(err instanceof Error ? err.message : 'Could not get location', 'err');
    } finally {
      setLocating(false);
    }
  };

  const completeOnboarding = async () => {
    const p = phone.replace(/\D/g, '');
    if (p.length !== 10) {
      setError('Enter a valid 10-digit phone number');
      return;
    }
    if (address.trim().length < 8) {
      setError('Enter your full delivery address');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const { error } = await supabase.rpc('register_user_profile', {
        p_email: email.trim().toLowerCase(),
        p_phone: `+91${p}`,
        p_name: name.trim() || null,
        p_role: 'customer',
      });
      if (error) throw error;
      const uid = (await supabase.auth.getUser()).data.user?.id;
      if (uid) {
        await supabase
          .from('customers')
          .update({ default_address: address.trim(), default_lat: lat, default_lng: lng })
          .eq('id', uid);
      }
      await refreshProfile();
      toast('Account ready — happy shopping!');
      nav(dest, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  const input =
    'w-full h-[52px] px-4 bg-card rounded-2xl shadow-ios border border-border-subtle text-[15px] outline-none focus:ring-2 focus:ring-brand/25 placeholder:text-muted';
  const primaryBtn =
    'w-full h-[52px] rounded-2xl bg-brand text-white font-bold text-[15px] press shadow-md disabled:opacity-50 flex items-center justify-center gap-2';

  return (
    <div className="pagein min-h-dvh flex flex-col items-center justify-center px-6 py-10 max-w-md mx-auto">
      <BrandMark size="text-[30px]" />
      <p className="text-[14px] text-muted mt-1 mb-8">Delivered in minutes</p>

      <div className="w-full space-y-4">
        {step === 'email' && (
          <>
            <h1 className="font-bold text-[22px]">Sign in</h1>
            <p className="text-[14px] text-ink-soft -mt-2">
              We'll email you a one-time code — no password needed.
            </p>
            <input
              className={input}
              type="email"
              placeholder="Email address"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && !busy && sendOtp()}
              autoFocus
            />
            <button className={primaryBtn} onClick={sendOtp} disabled={busy}>
              {busy ? 'Sending…' : 'Send code'}
            </button>
          </>
        )}

        {step === 'otp' && (
          <>
            <h1 className="font-bold text-[22px]">Enter the code</h1>
            <p className="text-[14px] text-ink-soft -mt-2">
              We sent a 6-digit code to <strong>{email.trim()}</strong>
            </p>
            <input
              className={`${input} tracking-[0.4em] text-center font-bold text-[18px]`}
              inputMode="numeric"
              maxLength={6}
              placeholder="······"
              value={otp}
              onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
              onKeyDown={(e) => e.key === 'Enter' && !busy && verify()}
              autoFocus
            />
            <button className={primaryBtn} onClick={verify} disabled={busy || otp.length < 6}>
              {busy ? 'Verifying…' : 'Verify & continue'}
            </button>
            <button
              className="w-full text-[13px] text-ink-soft font-medium py-1"
              onClick={() => setStep('email')}
            >
              Change email
            </button>
          </>
        )}

        {step === 'onboard' && (
          <>
            <h1 className="font-bold text-[22px]">Almost there</h1>
            <p className="text-[14px] text-ink-soft -mt-2">
              A few details so shops and delivery partners can reach you.
            </p>
            <input
              className={input}
              placeholder="Your name"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
            <div className="relative">
              <span className="absolute left-4 top-1/2 -translate-y-1/2 text-[15px] text-ink-soft font-medium">
                +91
              </span>
              <input
                className={`${input} pl-14`}
                inputMode="numeric"
                maxLength={10}
                placeholder="Phone number"
                value={phone}
                onChange={(e) => setPhone(e.target.value.replace(/\D/g, ''))}
              />
            </div>
            <textarea
              className={`${input} h-auto min-h-[84px] py-3`}
              placeholder="Delivery address — house, street, area, landmark"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
            />
            <button
              onClick={useMyLocation}
              disabled={locating}
              className="w-full h-[48px] rounded-2xl border border-border-subtle bg-card shadow-sm text-[14px] font-semibold press flex items-center justify-center gap-2 disabled:opacity-50"
            >
              <Icon name="my_location" className="text-brand !text-[20px]" />
              {locating ? 'Locating…' : lat != null ? 'Location pinned ✓' : 'Use my current location'}
            </button>
            <button className={primaryBtn} onClick={completeOnboarding} disabled={busy}>
              {busy ? 'Setting up…' : 'Start shopping'}
            </button>
          </>
        )}

        {error && <p className="text-[13px] text-danger font-medium text-center">{error}</p>}
      </div>
    </div>
  );
}

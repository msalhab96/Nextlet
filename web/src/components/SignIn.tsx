import { useState, type FormEvent } from 'react';
import { useToday } from '../lib/today';
import { actions } from '../store/store';
import { LogoMark } from './Icon';

export function SignIn() {
  const today = useToday();
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!password || busy) return;
    setBusy(true);
    setError(null);
    const message = await actions.signIn(password, today);
    setBusy(false);
    if (message) {
      setError(message);
      setPassword('');
    }
  };

  return (
    <div className="splash">
      <LogoMark size={44} />
      <h1 className="splash__title">Nextlet is locked</h1>
      <p className="splash__text">Enter your Nextlet password to continue.</p>
      <form className="signin" onSubmit={submit}>
        <label className="sr-only" htmlFor="signin-password">
          Password
        </label>
        <input
          id="signin-password"
          className="signin__input"
          type="password"
          autoFocus
          autoComplete="current-password"
          placeholder="Password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
        />
        <button type="submit" className="btn btn--primary" disabled={!password || busy}>
          {busy ? 'Unlocking…' : 'Unlock'}
        </button>
      </form>
      {error && (
        <p className="signin__error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

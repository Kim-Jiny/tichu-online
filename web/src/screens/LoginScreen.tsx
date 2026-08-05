import { useState } from 'react';
import { useAppState, useStore } from '../state/useStore';

/**
 * Login, following login_screen.dart:288.
 *
 * Same portrait composition: brand block (dragon mark, TICHU wordmark,
 * subtitle), then the white card holding the two icon-prefixed fields, the
 * orange sign-in button, the register link, and the divided quick-login row.
 *
 * Registration is a dialog in the app rather than a tab, so it is one here too.
 * The social buttons are drawn but not wired — provider tokens are the second
 * phase — and say so when tapped rather than being hidden, which would leave
 * the card visibly different from the app's.
 */
export function LoginScreen() {
  const state = useAppState();
  const store = useStore();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [registerOpen, setRegisterOpen] = useState(false);

  const connected = state.connection === 'open';
  const busy = state.loginPending || !connected;
  const maintenance = state.maintenance?.maintenance ? state.maintenance.message : null;

  function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy) return;
    store.login(username, password, true);
  }

  return (
    <main className="screen screen--login">
      <div className="brand">
        <img className="brand__mark" src="dragonIcon.png" alt="" />
        <h1 className="brand__word">TICHU</h1>
        <p className="brand__sub">친구들과 함께하는 카드게임</p>
      </div>

      <form className="login-card" onSubmit={submit}>
        <label className="input">
          <PersonIcon />
          <input
            type="text"
            autoComplete="username"
            placeholder="아이디"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
            minLength={2}
          />
        </label>

        <label className="input">
          <LockIcon />
          <input
            type="password"
            autoComplete="current-password"
            placeholder="비밀번호"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={4}
          />
        </label>

        <button type="submit" className="login-submit" disabled={busy}>
          {state.loginPending ? '접속 중…' : '로그인'}
        </button>

        <button type="button" className="login-link" onClick={() => setRegisterOpen(true)}>
          회원가입
        </button>

        {maintenance ? (
          <div className="maintenance-box">
            <span aria-hidden="true">🛠</span>
            <span>{maintenance}</span>
          </div>
        ) : null}
        {state.kickedReason ? <p className="login-error">{state.kickedReason}</p> : null}
        {state.loginError ? <p className="login-error">{state.loginError}</p> : null}

        <div className="divider">
          <span>간편 로그인</span>
        </div>

        <div className="social-row">
          <button
            type="button"
            className="social social--google"
            aria-label="구글로 로그인"
            onClick={() => store.notImplemented('구글 로그인')}
          >
            <img src="icons/google_logo.png" alt="" />
          </button>
          <button
            type="button"
            className="social social--apple"
            aria-label="애플로 로그인"
            onClick={() => store.notImplemented('애플 로그인')}
          >
            <AppleIcon />
          </button>
          <button
            type="button"
            className="social social--kakao"
            aria-label="카카오로 로그인"
            onClick={() => store.notImplemented('카카오 로그인')}
          >
            <KakaoIcon />
          </button>
        </div>
      </form>

      {registerOpen ? <RegisterDialog onClose={() => setRegisterOpen(false)} /> : null}
    </main>
  );
}

function RegisterDialog({ onClose }: { onClose: () => void }) {
  const state = useAppState();
  const store = useStore();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [nickname, setNickname] = useState('');

  function submit(event: React.FormEvent) {
    event.preventDefault();
    store.register(username, password, nickname);
  }

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div className="modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        <h2>회원가입</h2>
        <form className="form" onSubmit={submit}>
          <label className="field">
            <span>아이디 (2자 이상, 공백 없이)</span>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              required
              minLength={2}
            />
          </label>
          <label className="field">
            <span>비밀번호 (4자 이상)</span>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={4}
            />
          </label>
          <label className="field">
            <span>닉네임 (2~10자, 중복 불가)</span>
            <input
              type="text"
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              required
              minLength={2}
              maxLength={10}
            />
          </label>
          {state.registerNotice ? <p className="notice">{state.registerNotice}</p> : null}
          <div className="modal__actions">
            <button type="button" className="btn btn--ghost" onClick={onClose}>
              닫기
            </button>
            <button type="submit" className="btn btn--primary">
              가입하기
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function PersonIcon() {
  return (
    <svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
      <circle cx="12" cy="8" r="3.6" />
      <path d="M5 20c0-3.6 3.1-5.6 7-5.6s7 2 7 5.6" strokeLinecap="round" />
    </svg>
  );
}

function LockIcon() {
  return (
    <svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
      <rect x="4.5" y="10.5" width="15" height="9.5" rx="2.4" />
      <path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" strokeLinecap="round" />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" width="1em" height="1em" fill="currentColor" aria-hidden="true">
      <path d="M16.2 12.7c0-2.2 1.8-3.3 1.9-3.3-1-1.5-2.7-1.7-3.3-1.7-1.4-.1-2.7.8-3.4.8-.7 0-1.8-.8-3-.8-1.5 0-2.9.9-3.7 2.3-1.6 2.7-.4 6.7 1.1 8.9.7 1.1 1.6 2.3 2.8 2.2 1.1 0 1.5-.7 2.9-.7 1.3 0 1.7.7 2.9.7 1.2 0 2-1.1 2.7-2.1.8-1.2 1.2-2.4 1.2-2.5 0 0-2.1-.8-2.1-3.8z" />
      <path d="M14.1 6.3c.6-.7 1-1.8.9-2.8-.9 0-2 .6-2.6 1.4-.6.6-1.1 1.7-.9 2.7 1 .1 2-.5 2.6-1.3z" />
    </svg>
  );
}

function KakaoIcon() {
  return (
    <svg viewBox="0 0 24 24" width="1em" height="1em" fill="currentColor" aria-hidden="true">
      <path d="M12 4C7.3 4 3.5 7 3.5 10.7c0 2.3 1.5 4.4 3.8 5.6l-.9 3.3c-.1.3.2.5.5.4l3.9-2.6c.4 0 .8.1 1.2.1 4.7 0 8.5-3 8.5-6.8S16.7 4 12 4z" />
    </svg>
  );
}

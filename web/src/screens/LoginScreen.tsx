import { useState } from 'react';
import { useAppState, useStore } from '../state/useStore';

type Mode = 'login' | 'register';

export function LoginScreen() {
  const state = useAppState();
  const store = useStore();
  const [mode, setMode] = useState<Mode>('login');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [nickname, setNickname] = useState('');
  const [remember, setRemember] = useState(true);

  const connected = state.connection === 'open';
  const maintenanceMessage = state.maintenance?.maintenance ? state.maintenance.message : null;

  function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!connected) return;
    if (mode === 'login') {
      store.login(username, password, remember);
    } else {
      store.register(username, password, nickname);
    }
  }

  return (
    <main className="screen screen--login">
      <div className="login-card">
        <h1 className="login-title">티츄 온라인</h1>
        <p className="login-subtitle">웹에서 바로 플레이</p>

        {maintenanceMessage ? (
          <p className="notice notice--warn">{maintenanceMessage}</p>
        ) : null}
        {state.kickedReason ? (
          <p className="notice notice--warn">{state.kickedReason}</p>
        ) : null}

        <div className="tabs" role="tablist">
          <button
            type="button"
            role="tab"
            aria-selected={mode === 'login'}
            className={mode === 'login' ? 'tab tab--active' : 'tab'}
            onClick={() => setMode('login')}
          >
            로그인
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={mode === 'register'}
            className={mode === 'register' ? 'tab tab--active' : 'tab'}
            onClick={() => setMode('register')}
          >
            회원가입
          </button>
        </div>

        <form className="form" onSubmit={submit}>
          <label className="field">
            <span>아이디</span>
            <input
              type="text"
              autoComplete="username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              required
              minLength={2}
            />
          </label>

          <label className="field">
            <span>비밀번호</span>
            <input
              type="password"
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={4}
            />
          </label>

          {mode === 'register' ? (
            <label className="field">
              <span>닉네임 (2~10자)</span>
              <input
                type="text"
                value={nickname}
                onChange={(e) => setNickname(e.target.value)}
                required
                minLength={2}
                maxLength={10}
              />
            </label>
          ) : (
            <label className="field field--check">
              <input
                type="checkbox"
                checked={remember}
                onChange={(e) => setRemember(e.target.checked)}
              />
              <span>로그인 상태 유지</span>
            </label>
          )}

          <button
            type="submit"
            className="btn btn--primary"
            disabled={!connected || state.loginPending}
          >
            {state.loginPending ? '접속 중…' : mode === 'login' ? '로그인' : '가입하기'}
          </button>
        </form>

        {state.loginError ? <p className="notice notice--error">{state.loginError}</p> : null}
        {state.registerNotice ? <p className="notice">{state.registerNotice}</p> : null}

        <p className="login-footnote">
          모바일 앱과 같은 계정을 사용합니다. 소셜 로그인은 준비 중입니다.
        </p>
      </div>
    </main>
  );
}

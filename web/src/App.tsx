import { Toasts } from './components/Toasts';
import { GameScreen } from './screens/GameScreen';
import { LobbyScreen } from './screens/LobbyScreen';
import { LoginScreen } from './screens/LoginScreen';
import { WaitingRoom } from './screens/WaitingRoom';
import { useAppState } from './state/useStore';

export default function App() {
  const state = useAppState();
  const offline = state.connection !== 'open';

  return (
    // .app is the container query root; .frame reads its width to derive --u,
    // the app design pixel. An element can't query itself, hence the pair.
    <div className="app">
      <div className="frame">
        {offline ? (
          <div className="connection-banner" role="status">
            {state.connection === 'reconnecting'
              ? '서버에 다시 연결하는 중…'
              : state.connection === 'connecting'
                ? '서버에 연결하는 중…'
                : '서버와 연결이 끊겼습니다.'}
          </div>
        ) : null}

        {state.screen === 'login' ? <LoginScreen /> : null}
        {state.screen === 'lobby' ? <LobbyScreen /> : null}
        {state.screen === 'waiting' ? <WaitingRoom /> : null}
        {state.screen === 'game' ? <GameScreen /> : null}

        <Toasts />
      </div>
    </div>
  );
}

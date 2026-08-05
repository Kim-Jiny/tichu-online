import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { GameStore } from './state/store';
import { StoreContext } from './state/useStore';
import './styles.css';

const store = new GameStore();
store.start();

const container = document.getElementById('root');
if (!container) throw new Error('#root is missing');

createRoot(container).render(
  <StrictMode>
    <StoreContext.Provider value={store}>
      <App />
    </StoreContext.Provider>
  </StrictMode>,
);

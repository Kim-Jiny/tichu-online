import { createContext, useContext, useSyncExternalStore } from 'react';
import type { AppState, GameStore } from './store';

export const StoreContext = createContext<GameStore | null>(null);

export function useStore(): GameStore {
  const store = useContext(StoreContext);
  if (!store) throw new Error('StoreContext is missing a provider');
  return store;
}

export function useAppState(): AppState {
  const store = useStore();
  return useSyncExternalStore(store.subscribe, store.getSnapshot);
}

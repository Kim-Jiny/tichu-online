import { useEffect, useRef, useState } from 'react';
import { useAppState, useStore } from '../state/useStore';

/** Room-scoped chat. There is no global lobby chat in the protocol. */
export function ChatPanel({ compact = false }: { compact?: boolean }) {
  const { chat } = useAppState();
  const store = useStore();
  const [draft, setDraft] = useState('');
  const logRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const log = logRef.current;
    if (log) log.scrollTop = log.scrollHeight;
  }, [chat.length]);

  function submit(event: React.FormEvent) {
    event.preventDefault();
    store.sendChat(draft);
    setDraft('');
  }

  return (
    <section className={compact ? 'chat chat--compact' : 'chat'}>
      <div className="chat__log" ref={logRef}>
        {chat.length === 0 ? (
          <p className="muted chat__empty">채팅이 없습니다.</p>
        ) : (
          chat.map((entry, index) => (
            <p key={`${entry.timestamp}-${index}`} className="chat__line">
              <strong>{entry.sender}</strong> {entry.message}
            </p>
          ))
        )}
      </div>
      <form className="chat__input" onSubmit={submit}>
        <input
          type="text"
          value={draft}
          maxLength={200}
          placeholder="메시지 입력"
          onChange={(e) => setDraft(e.target.value)}
        />
        <button type="submit" className="btn btn--sm btn--primary">
          전송
        </button>
      </form>
    </section>
  );
}

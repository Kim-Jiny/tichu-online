# Zero-Downtime Deploy 계획서

브랜치: `feat/zero-downtime-deploy`

---

## 배경

현재 배포 시 `docker compose down` 후 `up -d --build`로 컨테이너를 재시작.
그 사이 메모리에 있던 lobby/room/game 상태가 모두 소실되고 유저 WebSocket 연결도 끊긴다.

목표는 **배포 시점의 진행중 게임을 보존**하면서 유저들이 자연스럽게
새 컨테이너로 이주하도록 하는 것.

---

## 인프라 현황 (Contabo VPS)

```
[VPS]
└── Docker Engine
    ├── nginx (컨테이너, 호스트 :80/:443) — 도메인별 reverse proxy
    │   └── conf: /opt/services/proxy/conf/*.conf
    │   └── compose: /opt/services/proxy/docker-compose.yml
    ├── tichu-online (port 3000, app-network)
    │   └── 코드: /opt/services/tichu-online/app (git clone)
    │   └── 배포 스크립트: /opt/services/tichu-online/deploy.sh
    ├── tichu-db (postgres, internal :5432, app-network)
    └── 기타 앱들 (coach-desk, gto-playbook 등) 같은 nginx 공유

Docker network: app-network (외부 생성)
TLS: /etc/letsencrypt (호스트 → nginx 컨테이너 마운트)
```

### 중요한 발견

- 레포 루트의 `docker-compose.yml`에 `tichu-online` + `tichu-db` 서비스 정의됨.
- 서버 측 `deploy.sh`는 `git pull` → `docker compose down` → `up -d --build`.
- nginx 설정(`tichu.conf`)은 단순 `proxy_pass http://tichu-online:3000`. 도커 네트워크 안에서 컨테이너 이름으로 접근.

---

## 목표 구조

```
[app-network]
├── nginx → upstream tichu_backend → tichu-online-{ACTIVE}:3000
├── tichu-online-blue   (server-blue)   ← 둘 중 하나만 평소 실행
├── tichu-online-green  (server-green)  ← 배포 시 잠깐 둘 다 실행
└── tichu-db                             ← 항상 단일 인스턴스 (공유)
```

### 배포 흐름

1. inactive 슬롯에 새 이미지 띄움 → `/health` 통과 대기
2. nginx upstream 수정 (active 슬롯 변경) → reload
3. 옛 슬롯에 SIGTERM → drain 모드 진입
4. 옛 슬롯이 자기 책임 완수 후 자연 종료
5. active 슬롯 플래그 파일 갱신

### 옛 슬롯의 Drain 동작

- **로비/메뉴 유저**: WS close → 클라 reconnect → LB(nginx)가 새 슬롯으로 라우팅
- **대기방 유저**: 룸 메타데이터를 새 슬롯에 POST → 새 슬롯이 동일 ID로 룸 생성 + 재접속 대기 등록 → 옛 슬롯 WS close → 클라 reconnect → 자동 룸 입장
- **게임 중 유저**: 게임이 끝날 때까지 옛 슬롯에 머묾. 게임 종료 후 위 대기방 흐름 적용.
- **봇**: 룸이 새 슬롯으로 옮겨질 때 같은 슬롯에 새 봇 인스턴스 생성 (메모리 학습 상태는 손실되나 새 게임이라 무관).
- **30초 타임아웃** (또는 stop_grace_period 10분) 경과 시 강제 종료.

---

## 변경 사항

### 1. 서버 코드 (`server/`)

#### 1-1. `server.js` — drain & migration core

```js
// 신규 환경변수
const INSTANCE_NAME = process.env.INSTANCE_NAME || 'default';
const PEER_URL = process.env.PEER_URL || null;
const INTERNAL_TOKEN = process.env.INTERNAL_MIGRATE_TOKEN || null;

let isDraining = false;

// HTTP 서버 추가 (현재는 ws-only)
const httpServer = http.createServer(async (req, res) => {
  if (req.url === '/health') {
    if (isDraining) return res.writeHead(503).end('draining');
    return res.writeHead(200).end('ok');
  }
  if (req.method === 'POST' && req.url === '/internal/adopt-rooms') {
    return handleAdoptRooms(req, res);
  }
  res.writeHead(404).end();
});
const wss = new WebSocketServer({ server: httpServer });
httpServer.listen(PORT);

// SIGTERM 핸들러
process.on('SIGTERM', async () => {
  console.log(`[${INSTANCE_NAME}] SIGTERM — drain mode on`);
  isDraining = true;

  // 1) 게임 안 진행중 룸 → 즉시 마이그레이션
  for (const room of [...lobby.rooms.values()]) {
    if (room.game) continue;
    await maybeMigrateRoom(room.id);
  }

  // 2) 룸에 안 속한 클라 → 즉시 close (자동 reconnect → 새 인스턴스)
  for (const ws of wss.clients) {
    if (!ws.roomId) ws.close(1001);
  }

  // 3) 게임 진행중 룸은 자연 종료 후 game-end 훅이 마이그레이션
  // grace period (docker stop -t 600) 동안 대기
});
```

#### 1-2. `serializeRoom()` + `lobby.adoptRoom()`

룸 메타데이터:
- id, name, isPrivate, isRanked, password
- gameType, maxPlayers, hostId, hostNickname
- turnTimeLimit, targetScore
- skExpansions, blockedSlots, randomSeating
- 슬롯별 플레이어 (nickname, isBot, botSpeed, titleKey)

`adoptRoom`은 같은 ID로 룸 재구성, 봇은 즉시, 인간은 disconnected 상태로 자리 예약 + `playerSessions`에 재접속 대기 등록.

#### 1-3. `/internal/adopt-rooms` 엔드포인트

```js
async function handleAdoptRooms(req, res) {
  if (req.headers['x-internal-token'] !== INTERNAL_TOKEN) {
    return res.writeHead(403).end();
  }
  const body = await readBody(req);
  const { rooms } = JSON.parse(body);
  for (const data of rooms) {
    lobby.adoptRoom(data);
    for (const p of data.players) {
      if (p && !p.isBot) {
        playerSessions.set(p.nickname, {
          roomId: data.id,
          disconnectedAt: Date.now(),
        });
      }
    }
  }
  res.writeHead(200).end();
}
```

#### 1-4. `maybeMigrateRoom()` + 게임 종료 훅

```js
async function maybeMigrateRoom(roomId) {
  if (!isDraining) return;
  if (!PEER_URL || !INTERNAL_TOKEN) return;
  const room = lobby.getRoom(roomId);
  if (!room || room.game) return;

  // 봇만 있는 방은 그냥 정리
  if (room.players.every(p => !p || p.isBot)) {
    lobby.removeRoom(roomId);
    return;
  }

  const data = serializeRoom(room);
  try {
    const r = await fetch(`${PEER_URL}/internal/adopt-rooms`, {
      method: 'POST',
      headers: {
        'x-internal-token': INTERNAL_TOKEN,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ rooms: [data] }),
    });
    if (!r.ok) throw new Error(`adopt failed: ${r.status}`);
  } catch (err) {
    console.error(`[${INSTANCE_NAME}] migrate ${roomId} failed:`, err);
  }

  // 성공/실패 무관하게 close — 실패 시 클라는 새 슬롯의 빈 로비로
  for (const p of room.players) {
    if (p && !p.isBot) findWsByPlayerId(p.id)?.close(1001);
  }
  lobby.removeRoom(roomId);
}
```

훅 위치:
- `scheduleAutoReturnToRoom` (게임 종료 후 룸 복귀 전환 시점)
- 라운드/게임 종료 후 `nextRound` 처리 끝에서

---

### 2. `docker-compose.yml` (레포 루트)

```yaml
name: tichu

services:
  server-blue:
    profiles: ["blue"]
    build: ./server
    image: tichu-server:latest
    container_name: tichu-online-blue
    restart: unless-stopped
    stop_grace_period: 10m
    environment:
      - NODE_ENV=production
      - PORT=3000
      - INSTANCE_NAME=blue
      - PEER_URL=http://tichu-online-green:3000
      - INTERNAL_MIGRATE_TOKEN=${INTERNAL_MIGRATE_TOKEN}
      - DATABASE_URL=${DATABASE_URL}
      - FIREBASE_SERVICE_ACCOUNT=${FIREBASE_SERVICE_ACCOUNT}
    depends_on:
      db:
        condition: service_healthy
    dns:
      - 8.8.8.8
      - 8.8.4.4
    networks:
      - app-network

  server-green:
    profiles: ["green"]
    image: tichu-server:latest
    container_name: tichu-online-green
    restart: unless-stopped
    stop_grace_period: 10m
    environment:
      - NODE_ENV=production
      - PORT=3000
      - INSTANCE_NAME=green
      - PEER_URL=http://tichu-online-blue:3000
      - INTERNAL_MIGRATE_TOKEN=${INTERNAL_MIGRATE_TOKEN}
      - DATABASE_URL=${DATABASE_URL}
      - FIREBASE_SERVICE_ACCOUNT=${FIREBASE_SERVICE_ACCOUNT}
    depends_on:
      db:
        condition: service_healthy
    networks:
      - app-network

  db:  # 기존 그대로
    image: postgres:16-alpine
    container_name: tichu-db
    ...

volumes:
  pgdata:

networks:
  app-network:
    external: true
```

기동:
- 평상시: `docker compose --profile blue up -d` (또는 active slot에 따라 green)
- 배포 시: 비활성 슬롯도 함께 `--profile <slot> up -d`

---

### 3. nginx 설정 (`server/deploy/tichu.conf.template`)

레포에 템플릿만 두고, 실제 conf는 VPS에서 deploy.sh가 생성.

```nginx
# Template — {{ACTIVE}}는 배포 스크립트가 'blue' 또는 'green'으로 치환

server {
    listen 80;
    server_name tichu.jiny.shop;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

upstream tichu_backend {
    server tichu-online-{{ACTIVE}}:3000;
}

server {
    listen 443 ssl;
    server_name tichu.jiny.shop;

    ssl_certificate /etc/letsencrypt/live/tichu.jiny.shop/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tichu.jiny.shop/privkey.pem;

    resolver 127.0.0.11 valid=10s ipv6=off;

    # 외부에서 internal endpoint 접근 차단
    location /internal/ {
        deny all;
        return 403;
    }

    location / {
        proxy_pass http://tichu_backend;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

---

### 4. 새 `deploy.sh` (`server/deploy/deploy.sh`)

```bash
#!/bin/bash
set -e

BASE_DIR=/opt/services/tichu-online
APP_DIR=$BASE_DIR/app
ACTIVE_FILE=$BASE_DIR/active_slot
PROXY_CONF=/opt/services/proxy/conf/tichu.conf
TEMPLATE=$APP_DIR/server/deploy/tichu.conf.template
REPO_URL="https://github.com/Kim-Jiny/tichu-online.git"
BRANCH="main"

# 1. 코드 업데이트
mkdir -p "$APP_DIR"
if [ ! -d "$APP_DIR/.git" ]; then
  git clone -b "$BRANCH" "$REPO_URL" "$APP_DIR"
else
  cd "$APP_DIR"
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
fi

cd "$APP_DIR"

# 2. 슬롯 결정
ACTIVE=$(cat "$ACTIVE_FILE" 2>/dev/null || echo "blue")
INACTIVE=$([ "$ACTIVE" = "blue" ] && echo "green" || echo "blue")

echo "[deploy] active=$ACTIVE → switching to $INACTIVE"

# 3. 새 이미지 빌드 + 비활성 슬롯에 띄움
docker compose --profile $INACTIVE up -d --build server-$INACTIVE

# 4. 헬스체크 통과 대기 (최대 60초)
for i in {1..60}; do
  if docker exec nginx wget -q -O- "http://tichu-online-$INACTIVE:3000/health" 2>/dev/null | grep -q ok; then
    echo "[deploy] health check passed"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "[deploy] health check FAILED — abort"
    docker compose --profile $INACTIVE stop server-$INACTIVE
    exit 1
  fi
  sleep 1
done

# 5. nginx upstream 교체
sed "s|{{ACTIVE}}|$INACTIVE|g" "$TEMPLATE" > "$PROXY_CONF"
docker exec nginx nginx -t
docker exec nginx nginx -s reload
echo "[deploy] nginx switched to $INACTIVE"

# 6. 옛 슬롯 graceful shutdown (10분 grace = SIGTERM 후 drain 시간)
docker compose --profile $ACTIVE stop -t 600 server-$ACTIVE || true
docker compose --profile $ACTIVE rm -f server-$ACTIVE || true

# 7. active 슬롯 갱신
echo "$INACTIVE" > "$ACTIVE_FILE"

echo "[done] $INACTIVE 활성, $ACTIVE 정리 완료"
```

---

### 5. 환경변수 (VPS)

`/opt/services/tichu-online/app/.env`에 추가:
- `INTERNAL_MIGRATE_TOKEN=...` (랜덤 32자 이상)

기존:
- `DATABASE_URL`, `DB_PASSWORD`, `FIREBASE_SERVICE_ACCOUNT` 그대로

---

### 6. 1회성 셋업 (VPS)

```bash
# 1. 토큰 생성
echo "INTERNAL_MIGRATE_TOKEN=$(openssl rand -hex 32)" >> /opt/services/tichu-online/app/.env

# 2. 첫 배포 (blue 슬롯으로 시작)
echo "blue" > /opt/services/tichu-online/active_slot

# 3. 코드 풀
cd /opt/services/tichu-online/app
git fetch && git checkout main && git pull

# 4. 옛 단일 컨테이너 정리
docker rm -f tichu-online || true

# 5. blue 슬롯 시작
cd /opt/services/tichu-online/app
docker compose --profile blue up -d --build

# 6. nginx conf 갱신
cp /opt/services/proxy/conf/tichu.conf /opt/services/proxy/conf/tichu.conf.singleton-backup
sed "s|{{ACTIVE}}|blue|g" server/deploy/tichu.conf.template > /opt/services/proxy/conf/tichu.conf
docker exec nginx nginx -t && docker exec nginx nginx -s reload

# 이후 배포는 server/deploy/deploy.sh 사용
```

---

## 클라 호환성 검증 항목

서버 코드 작성 후 로컬에서 docker 2개 띄워 검증:

1. **Reconnect 트리거**: NetworkManager가 `close(1001)` 받으면 자동 재연결
2. **재로그인 자동화**: 토큰/세션 보존 → 자동 로그인
3. **playerSessions 기반 룸 자동 입장**: 재접속 시 `handleReconnection`이 룸 입장 처리

이 셋이 OK면 클라 변경 0줄.

---

## 작업 순서 (브랜치 내)

| # | 단계 | 파일 | 분량 | 커밋 |
|---|---|---|---|---|
| 1 | health endpoint + drain mode + SIGTERM 골격 | server.js | ~80줄 | "drain mode + health" |
| 2 | serializeRoom + LobbyManager.adoptRoom | server.js, lobby/LobbyManager.js | ~100줄 | "room migration helpers" |
| 3 | /internal/adopt-rooms endpoint | server.js | ~50줄 | "adopt-rooms endpoint" |
| 4 | maybeMigrateRoom + 게임 종료 훅 | server.js | ~80줄 | "migrate hook on room idle" |
| 5 | docker-compose blue/green | docker-compose.yml | ~50줄 | "compose blue/green services" |
| 6 | nginx template + deploy.sh | server/deploy/* | ~100줄 | "deploy infra: nginx template + deploy.sh" |
| 7 | 1회성 셋업 가이드 | server/deploy/README.md | ~150줄 | "deploy guide" |

각 단계 끝나면 dev로 머지 안 하고 브랜치에 누적. 전체 검증 후 dev → main 순서.

---

## 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| `/internal/` 토큰 누출 | 외부에서 임의 룸 생성 | nginx에서 `/internal/` 외부 차단 + 토큰 추가 검증 |
| adopt-rooms 실패 (네트워크 글리치) | 룸 손실 (게임은 안전) | fetch 실패 시 그냥 close → 유저는 새 슬롯 빈 로비로 |
| 봇 학습 상태 손실 | 새 게임 시 봇이 약간 약함 | 마이그레이션은 게임 종료 후라 무관 |
| 30초/10분 grace 초과 | 강제 종료 → 진행 중 게임 손실 | grace는 docker stop -t 600(10분)으로 충분히 길게 |
| 친구 초대 링크 race | 옛 슬롯 → 새 슬롯 사이 잠깐 못 찾음 | 같은 룸 ID 유지로 거의 즉시 복원 |
| 첫 배포 시 nginx 설정 swap | 다운타임 가능성 | 1회성 셋업 가이드대로 신중히 진행 |

---

## 클라 영향 가능성

목표: **0줄 변경**.

검증 필요 시나리오:
- WS close(1001) → 자동 reconnect → 자동 로그인 → 자동 룸 입장
- 모바일 IP 변경 시 nginx ip_hash 깨질 수 있음 (sticky cookie 옵션 추가 검토)
- 같은 닉네임으로 두 곳에서 동시 로그인 시 (옛 슬롯 + 새 슬롯) 충돌 처리 — 기존 코드의 single-session 강제 로직 점검 필요

---

## 배포 후 모니터링

- nginx access log에서 두 컨테이너로 분산되는지
- `/health` 응답 모니터링
- 옛 슬롯이 grace 시간 내 종료되는지
- 로그에서 `[INSTANCE_NAME] SIGTERM — drain mode on` 확인

---

## 롤백 시나리오

배포 실패 시:
1. nginx 설정을 옛 active로 되돌림: `sed "s|{{ACTIVE}}|$ACTIVE|g" template > tichu.conf`
2. nginx reload
3. 새로 띄운 슬롯 stop & rm
4. active_slot 파일 원복

active_slot 파일이 source of truth.

---

작성일: 2026-04-27 (feat/zero-downtime-deploy 브랜치)

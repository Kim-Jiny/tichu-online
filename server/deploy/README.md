# Tichu Online — Zero-Downtime Deploy

블루/그린 배포로 서버 재시작 시 진행 중인 게임을 보존하기 위한 인프라 가이드.

자세한 설계 배경과 코드 변경 내역은 같은 디렉토리의 [`PLAN.md`](./PLAN.md) 참고.

---

## 구조

```
[Contabo VPS]
└── Docker
    ├── nginx (컨테이너, 호스트 :80/:443)
    │   └── conf: /opt/services/proxy/conf/tichu.conf
    │       upstream tichu_backend → tichu-online-{ACTIVE}:3000
    │
    ├── tichu-online-blue   (포트 3000, 컨테이너 내부; 호스트 미노출)
    ├── tichu-online-green  (포트 3000, 컨테이너 내부)
    │   └── 둘 중 한 슬롯만 평소 실행. 배포 시 잠깐 둘 다.
    │
    └── tichu-db (postgres, app-network 내부)
```

배포 흐름:
1. 비활성 슬롯에 새 이미지 빌드 + 시작
2. 새 슬롯 `/health`가 200 반환할 때까지 대기
3. nginx upstream을 새 슬롯으로 swap + reload (기존 WS는 유지)
4. 옛 슬롯에 `SIGTERM` → drain 모드 진입
   - 대기 중인 룸은 `/internal/adopt-rooms`로 새 슬롯에 이관
   - 게임 진행 중인 룸은 자연 종료까지 옛 슬롯에 머묾
   - 종료 직후 같은 마이그레이션 트리거 → 모두 새 슬롯으로
5. 옛 슬롯 컨테이너 정리

---

## 환경변수

`/opt/services/tichu-online/app/.env`에 다음 키 필요 (기존 + 신규):

```bash
# 기존
DATABASE_URL=postgresql://tichu:<DB_PASSWORD>@tichu-db:5432/tichu?sslmode=disable
DB_NAME=tichu
DB_PASSWORD=<...>
FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'
ANDROID_APP_SHA256_FINGERPRINTS=<...>

# 신규 (블루/그린 마이그레이션)
INTERNAL_MIGRATE_TOKEN=<32바이트 이상 랜덤 hex>
```

`INTERNAL_MIGRATE_TOKEN`은 두 슬롯이 서로 마이그레이션 POST를 인증할 때 쓰는 공유 시크릿. 외부에 노출되면 안 됨 (nginx의 `/internal/` deny 차단이 1차 방어선).

---

## 1회성 셋업 (최초 한 번)

지금 production은 `tichu-online` 단일 컨테이너로 도는 상태. 이 변경 머지 후 VPS에서 다음 순서로 전환.

### 1. 코드 풀

```bash
cd /opt/services/tichu-online/app
git fetch origin
git checkout main
git pull origin main
```

### 2. 환경변수 추가

```bash
# 32바이트 랜덤 토큰 생성
TOKEN=$(openssl rand -hex 32)

# .env에 한 줄 추가 (기존 키는 보존)
echo "INTERNAL_MIGRATE_TOKEN=$TOKEN" >> /opt/services/tichu-online/app/.env

# 잘 들어갔는지 확인
grep INTERNAL_MIGRATE_TOKEN /opt/services/tichu-online/app/.env
```

### 3. 초기 슬롯 플래그

```bash
echo "blue" > /opt/services/tichu-online/active_slot
```

### 4. 옛 컨테이너 정리

옛 단일 컨테이너 `tichu-online`은 더 이상 compose에 정의되지 않으므로 직접 종료해야 함:

```bash
cd /opt/services/tichu-online/app
docker compose down  # 옛 'server' 서비스 + tichu-db 정지 (db는 자동 재가동됨)
docker rm -f tichu-online || true   # 혹시 남았다면 정리
```

DB는 변경 없으므로 자동으로 다시 살아남.

### 5. blue 슬롯 + db 시작

```bash
cd /opt/services/tichu-online/app
docker compose --profile blue up -d --build
```

이 명령은 `server-blue` + `db` (프로필 없으니 항상 시작)를 가동.

확인:
```bash
docker ps | grep -E 'tichu-online-blue|tichu-db'
docker logs --tail 20 tichu-online-blue
```

### 6. nginx 설정 교체

```bash
APP=/opt/services/tichu-online/app
PROXY=/opt/services/proxy/conf/tichu.conf

# 백업
cp "$PROXY" "$PROXY.singleton-backup"

# 템플릿 → blue 슬롯으로 치환
sed "s|{{ACTIVE}}|blue|g" "$APP/server/deploy/tichu.conf.template" > "$PROXY"

# 검증 + reload
docker exec nginx nginx -t
docker exec nginx nginx -s reload
```

이 시점부터 외부 트래픽이 `tichu-online-blue:3000`으로 라우팅됨. 옛 `tichu-online` 컨테이너 이름은 더 이상 안 씀.

### 7. 동작 확인

```bash
# 헬스체크
curl -fsS https://tichu.jiny.shop/health
# 'OK' 반환되어야 함

# WS 연결 (브라우저나 클라이언트로 직접 테스트)
```

### 8. 옛 deploy.sh 비활성화

옛 `/opt/services/tichu-online/deploy.sh`는 새 구조와 호환 안 됨. 백업 후 새 스크립트로 교체:

```bash
mv /opt/services/tichu-online/deploy.sh /opt/services/tichu-online/deploy.sh.legacy
ln -s /opt/services/tichu-online/app/server/deploy/deploy.sh /opt/services/tichu-online/deploy.sh
```

이후 배포는 `bash /opt/services/tichu-online/deploy.sh`로 동일하게 호출.

---

## 일반 배포

위 셋업이 끝나면 매 배포는 한 줄:

```bash
bash /opt/services/tichu-online/deploy.sh
```

내부 동작:
1. `git pull origin main`
2. 현재 슬롯 결정 — nginx conf의 upstream을 먼저 읽고, 못 읽으면 `active_slot` 폴백
3. 새 이미지 빌드 + 비활성 슬롯에 시작
4. 헬스체크 통과 대기 (최대 60초)
5. nginx 템플릿 치환 + reload → **곧바로 `active_slot` 갱신**
6. 옛 슬롯에 `SIGTERM` (`DRAIN_TIMEOUT_SEC` grace, 현재 15분) → drain → kill

`active_slot`을 drain 전에 쓰는 이유: 트래픽은 5단계에서 이미 옮겨간다.
drain 도중 스크립트가 죽었을 때 파일이 옛 슬롯을 가리키고 있으면, 다음
배포가 지금 서비스 중인 컨테이너를 rebuild/stop 해버린다. 2단계에서
nginx conf를 우선으로 보는 것도 같은 이유의 이중 안전장치다.

drain은 **한 라운드**만 기다린다. 라운드가 끝나는 순간 방이 누적 점수와
함께 새 슬롯으로 이관되고, 거기서 자동으로 다음 라운드가 시작된다
(매치 전체가 끝날 때까지 기다리지 않는다).

에러 시 자동 롤백 (헬스체크 실패하면 비활성 슬롯 컨테이너 정리하고 종료).

### 동시 배포 차단

`deploy.sh`는 `$BASE_DIR/.deploy.lock`에 `flock`을 잡는다. drain 대기(최대 `DRAIN_TIMEOUT_SEC`, 현재 15분) 도중 두 번째 실행은 즉시 거부된다. 직전 실행이 비정상 종료되어 lock이 남았다면 수동으로 `rm $BASE_DIR/.deploy.lock` 후 재시도.

---

## 모니터링

배포 진행 중 살펴볼 수 있는 신호:

```bash
# 두 슬롯 컨테이너 상태
docker ps | grep tichu-online

# 옛 슬롯의 SIGTERM 처리 로그
docker logs --tail 50 -f tichu-online-blue

# 새 슬롯의 adopt-rooms 수신 로그
docker logs --tail 50 -f tichu-online-green | grep adoptRoom

# nginx access log
docker logs --tail 50 -f nginx
```

기대 로그:
- `[blue] SIGTERM received — entering drain mode`
- `[blue] migrated room_NN to peer`
- `[adoptRoom] adopted room_NN (...) from peer`

---

## 롤백

배포가 잘못된 경우 옛 슬롯으로 되돌리기:

```bash
ACTIVE=$(cat /opt/services/tichu-online/active_slot)
[ "$ACTIVE" = "blue" ] && BAD=blue && GOOD=green || { BAD=green; GOOD=blue; }

# 옛 코드로 옛 슬롯 다시 띄우기 (이미 새 슬롯이 active이므로 옛 이미지로 되돌리려면 git에서 이전 태그 체크아웃 후 빌드 필요)
cd /opt/services/tichu-online/app
git checkout v2.3.1  # 이전 안정 태그
docker compose --profile $GOOD up -d --build server-$GOOD

# nginx 다시 옛 슬롯으로
sed "s|{{ACTIVE}}|$GOOD|g" server/deploy/tichu.conf.template > /opt/services/proxy/conf/tichu.conf
docker exec nginx nginx -t && docker exec nginx nginx -s reload

# 슬롯 갱신
echo "$GOOD" > /opt/services/tichu-online/active_slot

# 새 슬롯 정리 (-t 는 compose의 stop_grace_period와 맞춘다. 짧게 주면
# 방들이 옛 슬롯으로 되돌아가기 전에 SIGKILL 된다)
docker compose --profile $BAD stop -t 900 server-$BAD || true
docker compose --profile $BAD rm -f server-$BAD || true
```

---

## 트러블슈팅

### 헬스체크가 통과 안 함
- `docker logs tichu-online-<slot>`에서 부팅 에러 확인
- `.env` 파일 누락된 키 점검 (`DATABASE_URL`, `INTERNAL_MIGRATE_TOKEN` 등)
- `app-network` 외부 네트워크 존재 여부: `docker network ls | grep app-network`

### 새 슬롯에 룸이 안 옮겨감
- 옛 슬롯 로그에서 `migrate ... failed` 메시지 확인
- 양 컨테이너가 같은 docker network(`app-network`)에 있는지 확인
- `INTERNAL_MIGRATE_TOKEN`이 양쪽 같은 값인지 확인 (compose가 `.env`에서 읽어 양쪽 환경에 주입)

### nginx 503 응답
- 옛 슬롯이 drain 중이면 정상 (`/health`가 503). nginx가 새 슬롯으로 못 옮겼는지 확인
- `docker exec nginx nginx -T | grep upstream` 으로 현재 conf 확인

### 양쪽 컨테이너가 동시에 살아있음
- 정상 (배포 중 잠깐). 배포 완료 후 옛 슬롯이 자동 정리되어야 함
- drain grace(`DRAIN_TIMEOUT_SEC`, 현재 15분)를 넘겨도 살아있으면: `docker compose --profile <slot> stop -t 0 server-<slot>`로 강제 정리

### 옛 단일 deploy.sh가 다시 실행됨 (실수)
- 옛 `deploy.sh`는 `docker compose down/up`을 그대로 시도해서 새 구조의 프로필 기반 서비스를 못 띄움
- 1회성 셋업 8단계의 심볼릭 링크 작업으로 옛 스크립트 차단 권장

---

## 첫 배포 시 주의

- 2026-04-27 시점 production은 `tichu-online` 단일 컨테이너 구조. 이 변경을 main에 머지하면 옛 `deploy.sh`는 빌드를 깬다 (compose에 `server` 서비스 없음).
- 머지 직전에 1회성 셋업 1~6단계를 한 번에 수행하거나, 머지 후 즉시 수행해야 함.
- 실수 방지: 머지 후 첫 배포 전에 1회성 셋업 단계만 수행하고, 옛 `deploy.sh`는 절대 호출하지 않을 것.

---

## 참고 파일

- [`PLAN.md`](./PLAN.md) — 설계 문서
- [`deploy.sh`](./deploy.sh) — 자동 배포 스크립트
- [`tichu.conf.template`](./tichu.conf.template) — nginx 설정 템플릿
- [`docker-compose.yml`](../../docker-compose.yml) (레포 루트) — blue/green 서비스 정의
- [`server/server.js`](../server.js) — drain 모드 + 마이그레이션 코드
- [`server/lobby/LobbyManager.js`](../lobby/LobbyManager.js) — `adoptRoom` 구현

# 프로필 사진 (UGC) 기능 계획서

브랜치: `feat/profile-photo`

---

## 배경 & 목표

유저가 본인 프로필 사진을 업로드해 다른 유저에게 노출할 수 있게 한다.
무한 노출이 아닌 **7일짜리 상점 아이템(1000골드)** 으로 게이트한다.
표시 지점은 프로필 팝업, 게임 화면, 관전 화면.

핵심 의사결정 (확정):
- **저장소**: MinIO (HM Love 프로젝트와 동일 패턴)
- **모더레이션**: 수동 검수 + 신고 시스템. 자동 필터(Vision API 등)는 일단 보류, 신고량 보고 추후 결정.
- **재업로드**: 7일 내 무제한 자유.
- **사진 URL 방식**: Public bucket + 업로드마다 새 키 (`profile/{userId}/{timestamp}.jpg`) — CDN 캐시 무효화 자동.
- **즉시 노출**: 구매 후 업로드하면 바로 표시. 사전 승인 큐 없음.

---

## UGC 정책 대응 (Apple/Google)

### Apple App Review Guideline 1.2 (4가지 필수 조건)

| 조건 | 본 프로젝트 대응 |
|---|---|
| Objectionable content 필터링 메커니즘 | 운영자 수동 검수 + 어드민 "활성 사진" 탭에서 수시 모니터링 |
| Report 기능 | 프로필 팝업에 "부적절한 콘텐츠 신고" 옵션 추가 (기존 신고 인프라 확장) |
| Block abusive users | 기존 `blockUser` / `unblockUser` 인프라 재사용 — 차단 시 서버 사이드 serialize에서 사진 필터링 |
| 24시간 SLA + 운영자 연락처 | EULA에 "신고 24시간 내 검토" 명시 + 기존 운영자 연락처 유지 |

### Google Play User-Generated Content Policy

Apple 대응으로 사실상 같이 충족됨. 추가로:
- Data Safety form에 "user profile photos" 항목 추가
- 개인정보처리방침에 사진 수집/보관 명시

### 연령 등급

수동 모더레이션 명시로 12+ 유지 가능 (자동 모더레이션 없을 때 17+ 자동 점프 회피).

---

## 모더레이션 워크플로우

```
[유저 A 업로드] → MinIO 저장 → DB의 photo_key 업데이트 → 즉시 공개
                                                          ↓
                                                 [다른 유저들에게 표시]
                                                          ↓
                              [신고 발생]                    [어드민 수시 검수]
                                  ↓                           ↓
                          신고자에게 즉시 차단                  부적절 판정
                          (해당 유저 사진 안 보임)             ↓
                                  ↓                       사진 강제 hidden
                          운영자 푸시 알림                    ↓
                                  ↓                       tc_sanctions 레코드 생성
                          어드민 검수 → 처분                  ↓
                                  ↓                    유저 설정 > 제재내역에 표시
                          부적절 → hidden                    (읽지 않음 뱃지)
                          정당 → 신고 기각
```

### 신고 후 자기 차단

- 유저 A가 유저 B의 사진을 신고하면:
  1. 즉시 A의 클라/서버 응답에서 B의 사진을 hidden 처리
  2. 운영자에게 FCM 푸시 (기존 admin push 인프라 재사용)
  3. 어드민 페이지 신고 큐에 추가

### 운영자 처분

- **정당한 신고**: 사진 `hidden` 상태 변경 → 유저에게 `tc_sanctions` 레코드 + 설정 알림 뱃지
- **오신고**: 신고 기각, 사진 유지

### 자동 hidden threshold (선택 사항, 추후 도입 고려)

신고 N명 누적 시 자동 hidden + 어드민 검수 대기 — 처음엔 안 깔고 가다가 트래픽 보고 결정.

---

## 데이터 모델

### `tc_users` 컬럼 추가

```sql
ALTER TABLE tc_users
  ADD COLUMN profile_photo_key VARCHAR(255),           -- minio object key (NULL = 기본 아바타)
  ADD COLUMN profile_photo_expires_at TIMESTAMP,       -- 7일 후, NULL = 비활성
  ADD COLUMN profile_photo_status VARCHAR(20) DEFAULT 'none';
  -- status: 'none' | 'active' | 'hidden' | 'removed'
```

### `tc_sanctions` 신규 테이블

```sql
CREATE TABLE tc_sanctions (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES tc_users(id),
  type VARCHAR(40) NOT NULL,            -- 'profile_photo_removed' 등
  reason_summary TEXT,                  -- 유저에게 보일 요약 ("부적절한 콘텐츠로 사진이 제거됨")
  related_resource VARCHAR(255),        -- 관련 리소스 (예: 옛 photo_key)
  created_at TIMESTAMP DEFAULT NOW(),
  read_at TIMESTAMP                     -- 유저가 확인한 시각, NULL = 미확인
);

CREATE INDEX idx_sanctions_user_unread ON tc_sanctions(user_id) WHERE read_at IS NULL;
```

### `tc_reports` 확장 (기존 신고 테이블)

기존 `report_type` enum에 `'profile_photo'` 값 추가. 새 컬럼 불필요.

### `tc_shop_items` 신규 아이템

기존 상점 시스템에 7일짜리 프로필 사진 아이템 등록:
```json
{
  "key": "profile_photo_7d",
  "name_ko": "프로필 사진 등록 (7일)",
  "price_gold": 1000,
  "duration_days": 7,
  "category": "social"
}
```

구매 시점에 `profile_photo_expires_at = NOW() + INTERVAL '7 days'` 세팅. 업로드 안 한 상태라도 시간 카운트 시작 (구매 시점부터).

---

## MinIO 인프라

### docker-compose.yml 추가 (실제 적용된 형태)

VPS에 hmlove-minio / coach-minio가 이미 돌고 있어서 호스트 포트 충돌
방지 + hmlove 패턴(API는 도커 네트워크 내부만)을 따라간다.

기존 점유: 59000(coach-api), 59001(hmlove-console), 59002(coach-console).
티츄는 콘솔만 **59003**에 SSH 터널용으로 노출. API(9000)는 호스트에
안 내고 `http://tichu-minio:9000` 으로 컨테이너끼리만 통신.

```yaml
services:
  minio:
    profiles: ["storage"]    # 자동 시작 방지 — 명시적 시작만 허용
    image: minio/minio:latest
    container_name: tichu-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    expose:
      - "9000"
    ports:
      - "127.0.0.1:59003:9001"   # 콘솔만, SSH 터널로 접근
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
    volumes:
      - minio_data:/data
    healthcheck:
      test: ["CMD-SHELL", "mc ready local || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - app-network

volumes:
  pgdata:
  minio_data:    # 신규
```

### 기존 인프라 안전성

`deploy.sh`는 `docker compose --profile blue up -d server-blue` 같이 **서비스 이름을 명시**해서 호출하므로 MinIO에 영향 없음. db 컨테이너도 무관 (별도 볼륨).

### MinIO 1회성 셋업 (VPS) — 미실행 상태, 진행 시 따라갈 런북

> ⚠️ 이 절차는 **아직 실행 안 됨**. 다음에 작업 재개할 때 단계별로 그대로 따라간다.
> 코드/문서는 `feat/profile-photo` 브랜치에만 있고 dev/main은 무관해서
> VPS는 현재 100% 영향 없음. 어떤 단계에서도 멈추면 그 시점 상태로 안전.

#### Step 0 — 사전 안전 조치

```bash
# Contabo 콘솔에서 Snapshot 한 번 찍기 (체크포인트)
# (자동 백업 외에 수동 스냅샷 — 1개만 보유 가능)

# VPS에 SSH 접속해서 현재 docker 상태 확인
ssh root@<vps>
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
# - tichu-online-blue 또는 green 동작 중인지
# - hmlove-minio / coach-minio가 그대로 돌고 있는지
# - 59003 포트가 비어있는지 (`ss -tlnp | grep 59003` → 결과 없으면 OK)
```

#### Step 1 — .env에 MinIO 자격 추가

```bash
cd /opt/services/tichu-online/app
# 패스워드는 한 번만 생성해서 저장. 분실 시 컨테이너 reset 필요.
echo "" >> .env
echo "# MinIO (profile photos)" >> .env
echo "MINIO_ROOT_USER=tichu-admin" >> .env
echo "MINIO_ROOT_PASSWORD=$(openssl rand -hex 24)" >> .env

# 확인
grep MINIO_ .env
```

이 시점에서도 아직 MinIO는 안 뜬 상태. .env는 다음 step에서 읽힘.

#### Step 2 — 브랜치 코드 가져오기

deploy.sh는 main을 보지만 MinIO 셋업은 브랜치 단계라 수동으로 받음.
**중요**: 이 시점에 deploy.sh를 실행하면 안 됨 (main으로 다시 덮어쓰임).

```bash
cd /opt/services/tichu-online/app
git fetch origin
git checkout feat/profile-photo
git pull origin feat/profile-photo

# 현재 main과 다른지 확인
git log --oneline main..HEAD
```

#### Step 3 — MinIO 컨테이너 시작

```bash
cd /opt/services/tichu-online/app
docker compose --profile storage up -d minio

# 헬스체크 통과까지 대기 (약 10초)
docker ps | grep tichu-minio
docker logs tichu-minio | tail -20
# "API: http://...:9000" / "Console: http://...:9001" 보이면 OK
```

#### Step 4 — 버킷 생성 + 정책 설정

```bash
# mc client는 minio 이미지에 내장됨
docker exec tichu-minio mc alias set local http://localhost:9000 \
  "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

# 버킷 생성
docker exec tichu-minio mc mb local/profile-photos

# 익명 다운로드 허용 (GET만, 업로드는 SDK가 인증해서 처리)
docker exec tichu-minio mc anonymous set download local/profile-photos

# 확인
docker exec tichu-minio mc ls local/
docker exec tichu-minio mc anonymous get local/profile-photos
```

#### Step 5 — 콘솔 SSH 터널 접속 테스트 (선택)

```bash
# 로컬 머신에서
ssh -L 59003:127.0.0.1:59003 root@<vps>
# 브라우저: http://localhost:59003
# 로그인: MINIO_ROOT_USER / MINIO_ROOT_PASSWORD
# 콘솔에서 profile-photos 버킷이 보이는지 확인
```

#### Step 6 — nginx 라우트 활성화

```bash
# 현재 nginx conf 백업
cp /opt/services/proxy/conf/tichu.conf /opt/services/proxy/conf/tichu.conf.pre-minio

# 새 템플릿으로 conf 재생성 (active slot 유지)
cd /opt/services/tichu-online/app
ACTIVE=$(cat /opt/services/tichu-online/active_slot)
sed "s|{{ACTIVE}}|$ACTIVE|g" server/deploy/tichu.conf.template > /opt/services/proxy/conf/tichu.conf

# 검증 + 리로드
docker exec nginx nginx -t
docker exec nginx nginx -s reload

# 외부에서 테스트 (없는 키라 404 정상)
curl -I https://tichu.jiny.shop/media/profile-photos/test
# HTTP/2 404 가 나오면 라우트 OK (MinIO까지 도달은 한 것)
```

#### Step 7 — 동작 확인 후 main 머지 시점 결정

이 시점에서 MinIO는 뜨고 nginx 라우트는 살아있지만 **서버 코드는 아직
이 기능을 쓰지 않음** (다음 마일스톤에서 서버 코드 추가). 머지 시점은
서버 코드까지 완성된 후로 미뤄도 되고, 인프라만 먼저 main 머지해도 됨.
서버 코드가 minio 클라이언트 부재 시 자동 비활성화되도록 작성한다면
부분 머지도 안전.

#### 롤백 절차 (각 step별)

- **Step 1 후**: .env에서 MINIO_ 두 줄 삭제
- **Step 2 후**: `git checkout main` 으로 복귀
- **Step 3 후**: `docker compose --profile storage stop minio && docker compose --profile storage rm -f minio`
- **Step 4 후**: 위 + `docker volume rm tichu_minio_data` (데이터까지 삭제)
- **Step 6 후**: `cp tichu.conf.pre-minio tichu.conf && docker exec nginx nginx -s reload`
- **최후 수단**: Contabo Snapshot 복원 (Step 0에서 찍은 것)

### nginx 라우트 (같은 도메인 path 방식)

별도 서브도메인 대신 기존 `tichu.jiny.shop`의 path를 사용. 사유:
- 트래픽 추정 월 30GB 수준 (VPS 32TB 한도의 0.1%) — 분리 필요 없음
- DNS/TLS 추가 작업 0
- WebSocket(`/`)과 명확히 path 분리되어 충돌 없음
- 필요해질 시점에 도메인 분리해도 충분 (CDN 이전 등)

`server/deploy/tichu.conf.template`에 location 추가:
```nginx
location /media/profile-photos/ {
    limit_except GET HEAD { deny all; }
    proxy_pass http://tichu-minio:9000/profile-photos/;
    proxy_set_header Host tichu-minio:9000;
    proxy_set_header Cookie "";
    proxy_hide_header Set-Cookie;

    proxy_cache_valid 200 7d;
    expires 7d;
    add_header Cache-Control "public, immutable" always;
}
```

클라는 `https://tichu.jiny.shop/media/profile-photos/{userId}/{timestamp}.jpg` 접근.

---

## 서버 코드 변경 (`server/`)

### 1. MinIO SDK 통합

`server/package.json`:
```json
"dependencies": {
  "minio": "^8.0.0"
}
```

`server/storage/minioClient.js` (신규):
```js
const Minio = require('minio');

const client = new Minio.Client({
  endPoint: process.env.MINIO_ENDPOINT || 'tichu-minio',
  port: parseInt(process.env.MINIO_PORT) || 9000,
  useSSL: false,
  accessKey: process.env.MINIO_ROOT_USER,
  secretKey: process.env.MINIO_ROOT_PASSWORD,
});

const BUCKET = 'profile-photos';
const PUBLIC_BASE = process.env.MINIO_PUBLIC_BASE || 'https://media.tichu.jiny.shop/profile-photos';

async function uploadProfilePhoto(userId, buffer, mimeType) {
  const ext = mimeType === 'image/png' ? 'png' : 'jpg';
  const key = `${userId}/${Date.now()}.${ext}`;
  await client.putObject(BUCKET, key, buffer, buffer.length, {
    'Content-Type': mimeType,
  });
  return { key, url: `${PUBLIC_BASE}/${key}` };
}

async function deleteProfilePhoto(key) {
  if (!key) return;
  try { await client.removeObject(BUCKET, key); } catch (_) {}
}

module.exports = { uploadProfilePhoto, deleteProfilePhoto, PUBLIC_BASE };
```

### 2. 업로드 핸들러 (`server.js`)

신규 HTTP 엔드포인트 — WS가 아닌 멀티파트 업로드:
```js
// POST /upload/profile-photo
// Header: Authorization: Bearer <session-token>
// Body: multipart/form-data (file)
```

처리 단계:
1. 세션 토큰 검증 → user_id 획득
2. 활성 아이템 보유 + 만료 안 됨 검증
3. 이미지 검증: MIME 화이트리스트(JPG/PNG/WebP), 최대 5MB
4. **EXIF 스트리핑** (sharp 사용): `sharp(buffer).withMetadata({ exif: {} }).resize(512, 512, { fit: 'cover' }).toBuffer()`
5. MinIO 업로드 → 새 key 획득
6. 기존 photo_key 삭제 (cleanup)
7. DB의 `profile_photo_key` 업데이트
8. WS broadcast: 본인 + 같은 룸 유저들에게 `profile_photo_updated` 이벤트

### 3. 상점 아이템 핸들러 확장

기존 `buyItem` 핸들러에서 `profile_photo_7d` 키 분기:
- 골드 차감
- `profile_photo_expires_at = NOW() + 7일`
- `profile_photo_status = 'active'` (사진은 아직 NULL이라도 active 상태)
- 만료 시점에 status → 'none' + photo_key 삭제 (cleanup 잡)

### 4. 만료 cleanup 잡

서버 시작 시 + 매 시간마다:
```js
// 만료된 active 사진 → hidden(서버 응답에서 제외) + MinIO 오브젝트 삭제
const expired = await pool.query(`
  SELECT id, profile_photo_key FROM tc_users
  WHERE profile_photo_status = 'active' AND profile_photo_expires_at < NOW()
`);
for (const u of expired.rows) {
  await deleteProfilePhoto(u.profile_photo_key);
  await pool.query(`
    UPDATE tc_users SET profile_photo_key = NULL, profile_photo_status = 'none'
    WHERE id = $1
  `, [u.id]);
}
```

### 5. 신고 핸들러 확장

기존 `reportUser`에 `report_type = 'profile_photo'` 처리 추가:
- 신고자의 차단 목록에 자동 추가 (자기 차단)
- 운영자에게 FCM 푸시
- 어드민 신고 큐에 표시

### 6. Serialize 시 사진 필터링

`getUserProfile`, 룸/게임 페이로드 serialize 시:
- 상대방이 나를 차단한 경우: 내 photo_url 그대로 반환 (상대가 안 보면 됨)
- 내가 상대를 차단한 경우: 상대의 photo_url = null로 치환
- `profile_photo_status != 'active'` 또는 만료된 경우: null
- 신고 자기차단 목록: blockUser와 동일하게 처리

### 7. 어드민 엔드포인트

```
GET /admin/profile-photos/active       — 활성 사진 페이지네이션 (검수용)
GET /admin/profile-photos/reported     — 신고 누적 사진 큐
POST /admin/profile-photos/:id/hidden  — 강제 hidden + tc_sanctions 레코드 생성
POST /admin/sanctions/:id/clear        — 처분 취소
```

---

## 클라 변경 (Flutter)

### 1. 프로필 사진 표시 위젯

`flutter_app/lib/widgets/profile_avatar.dart` 신규:
- photoUrl 받아서 원형 클립 + 캐시드 이미지 렌더
- null이면 기본 아바타 fallback
- 차단된 유저면 기본 아바타로 자동 전환

### 2. 프로필 팝업

기존 프로필 팝업에:
- 상단에 둥근 아바타 영역 (기본 배너와 공존)
- 본인이면 "사진 변경" 버튼 (아이템 보유 시) / "프로필 사진 등록 구매" 버튼 (미보유)
- 타인이면 "부적절한 콘텐츠 신고" 옵션 (기존 신고 메뉴 안에 추가)

### 3. 사진 업로드 플로우

- image_picker로 갤러리/카메라 선택
- image_cropper로 정사각형 크롭
- 서버에 multipart 업로드
- 업로드 완료 → WS broadcast 받아서 자동 갱신

### 4. 게임 화면 / 관전 화면

각 플레이어 슬롯의 닉네임 옆 또는 위에 작은 원형 아바타 배치:
- 티츄: `game_screen.dart` 4방향 슬롯
- SK: `sk_game_screen.dart` 슬롯
- 마이티: `mighty_game_screen.dart` 슬롯
- LL: `ll_game_screen.dart` 슬롯
- 관전: `spectator_screen.dart` 슬롯

레이아웃 영향: 슬롯 높이 +20~28px. 최근 정리한 UI 다시 손봐야 함.

### 5. 설정 > 제재내역

`settings_screen.dart`에 신규 섹션:
- 제재내역 진입 버튼 (미확인 카운트 뱃지)
- 진입 시 `tc_sanctions` 목록 표시 + 진입 시점에 `read_at` 일괄 갱신
- 각 항목: 일시, 사유 요약, "왜 처분됐는지" 안내문구

### 6. 차단 유저 사진 필터링

기존 `BlockedUserService`에 통합 — 차단 목록에 있으면 ProfileAvatar가 자동 fallback.

---

## EULA / 개인정보처리방침 업데이트

### EULA 추가 조항

- "Users may upload profile photos via the in-app shop item. Anthropic content prohibited (nudity, hate, harassment, copyright infringement, etc.). Violations result in photo removal without refund."
- "Reports are reviewed within 24 hours."
- "We reserve the right to remove content at our discretion."

### 개인정보처리방침 추가 조항

- 수집 항목: "프로필 사진 (선택적 업로드)"
- 보관 기간: "활성 기간 7일 + 만료 후 즉시 삭제 (또는 위반 처분 시 즉시 삭제)"
- 제3자 제공: 없음
- 보관 위치: "MinIO 자체 호스팅 (EU 데이터센터)"

---

## 작업 순서 (브랜치 내)

| # | 단계 | 파일 | 분량 | 비고 |
|---|---|---|---|---|
| 1 | docker-compose에 MinIO 추가 | docker-compose.yml | ~30줄 | 자동 시작 X (profile=storage) |
| 2 | VPS에 MinIO 1회성 셋업 | (운영) | - | 수동 진행 |
| 3 | DB 마이그레이션 (tc_users 컬럼, tc_sanctions 테이블, 상점 아이템) | server/db/database.js | ~80줄 | 멱등 ALTER |
| 4 | MinIO SDK + 업로드 핸들러 | server/storage/, server.js | ~200줄 | sharp 의존성 추가 |
| 5 | 상점 아이템 구매 핸들러 분기 | server/server.js | ~40줄 | |
| 6 | 만료 cleanup 잡 | server/server.js | ~50줄 | 시작 시 + 매시간 |
| 7 | 신고 핸들러 확장 + 자기차단 | server/server.js | ~60줄 | |
| 8 | Serialize 시 사진 필터링 | server/db/database.js, 게임 serialize | ~50줄 | |
| 9 | 어드민 엔드포인트 | server/server.js | ~120줄 | |
| 10 | 클라: ProfileAvatar 위젯 | flutter_app/lib/widgets/ | ~80줄 | |
| 11 | 클라: 프로필 팝업 사진 영역 | flutter_app/lib/widgets/, screens/ | ~150줄 | |
| 12 | 클라: 사진 업로드 플로우 | image_picker, image_cropper, multipart | ~200줄 | |
| 13 | 클라: 게임/관전 슬롯에 아바타 통합 | game_screen, sk_game_screen, mighty_game_screen, ll_game_screen, spectator_screen | ~300줄 | UI 재배치 |
| 14 | 클라: 설정 > 제재내역 화면 | settings_screen.dart, 신규 screen | ~150줄 | |
| 15 | 클라: 차단 유저 사진 필터 | services/ | ~30줄 | |
| 16 | EULA / 개인정보처리방침 업데이트 | docs/, l10n/ | ~50줄 | 3개국어 |
| 17 | 어드민 UI (활성/신고 큐) | admin frontend | TBD | 별도 작업 |

### 진행 마일스톤

- **M1 인프라**: 1-2 완료 후 MinIO 운영 확인
- **M2 백엔드**: 3-9 완료 후 curl로 업로드/조회/신고 테스트
- **M3 프론트엔드**: 10-15 완료 후 로컬에서 전 플로우 동작
- **M4 정책 문서**: 16
- **M5 어드민**: 17

각 마일스톤 후 dev 머지 X, 브랜치에 누적. M3 끝나고 통합 검증 → dev → main.

---

## 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| Apple 1.2 리젝 | 출시 지연 | EULA에 24h SLA 명시 + 어드민 푸시 즉시 대응 + 신고/차단 UI 검수 화면 캡처 준비 |
| EXIF 위치정보 유출 | 개인정보 사고 | sharp로 업로드 시점에 강제 스트리핑 |
| MinIO 디스크 풀 | 업로드 실패 | 모니터링 + 정기 cleanup (만료/삭제된 오브젝트) |
| 신고 폭주 | 운영 부담 | 자동 hidden threshold 도입 (N명 신고 → 자동 가림) |
| 부적절 콘텐츠 노출 시간 | 평판 리스크 | 1차 자동 필터(Vision API) 추후 도입 검토 |
| 만료 시 환불 요청 | 정책 분쟁 | EULA에 "위반 시 환불 없음" 명시 |
| 슬롯 UI 깨짐 | 게임 화면 가독성 저하 | 단계별로 한 화면씩 적용 후 시각 검증 |

---

## 클라 호환성 / 출시 전략

- 신 클라(2.5.0+) 전용 기능: 구 클라는 photoUrl 필드를 무시하므로 영향 없음.
- 상점 아이템은 신 클라에서만 보이게 게이트 (`min_client_version`).
- 어드민 페이지는 별도 출시 사이클.

---

## 후속 검토 항목 (나중에 결정)

- 자동 모더레이션 도입 (Google Vision SafeSearch / AWS Rekognition / NSFW.js)
- 자동 hidden threshold (N명 신고 → 자동 가림) 도입 시점
- 사진 외 추가 콘텐츠 (자기소개 텍스트, 배경 등) 확장 여부

---

작성일: 2026-05-14 (feat/profile-photo 브랜치)

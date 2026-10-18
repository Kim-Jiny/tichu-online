-- 3.3.0 서버 배포 전에 운영 DB 에서 한 번 실행한다.
--
-- 서버는 부팅 때 이 인덱스들을 CREATE INDEX IF NOT EXISTS 로 만든다.
-- 일반 CREATE INDEX 는 빌드가 끝날 때까지 그 표의 쓰기를 막는다.
-- tc_gold_history 는 유저가 늘수록 가장 빠르게 커지는 표라, 크면
-- 배포 순간 골드 쓰기가 그만큼 멈춘다.
--
-- 미리 CONCURRENTLY 로 만들어 두면 쓰기를 막지 않고, 배포 때 서버의
-- IF NOT EXISTS 가 전부 건너뛴다. 코드는 손대지 않아도 된다.
--
-- CONCURRENTLY 는 트랜잭션 안에서 못 돈다. psql 에서 한 줄씩 실행할 것
-- (BEGIN 없이). 중간에 실패하면 invalid 인덱스가 남으므로 맨 아래
-- 확인 질의로 indisvalid 를 보고, false 면 DROP 후 다시 만든다.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_gold_history_created
  ON tc_gold_history(created_at);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_gold_history_nick_created
  ON tc_gold_history(nickname, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_created
  ON tc_users(created_at);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_missions_picked_day
  ON tc_user_missions(picked_day);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reports_reported
  ON tc_reports(reported_nickname, created_at DESC);

-- tc_daily_active / tc_push_campaigns 는 이번에 새로 생기는 표라
-- 비어 있다. 부팅 때 만들어도 막을 쓰기가 없으므로 미리 할 필요 없다.

-- 확인 — indisvalid 가 전부 t 여야 한다.
SELECT c.relname AS index_name, i.indisvalid
  FROM pg_class c
  JOIN pg_index i ON i.indexrelid = c.oid
 WHERE c.relname IN (
   'idx_gold_history_created', 'idx_gold_history_nick_created',
   'idx_users_created', 'idx_user_missions_picked_day', 'idx_reports_reported'
 );

-- 배포 전에 크기를 먼저 보고 싶다면:
--   SELECT count(*) FROM tc_gold_history;
-- 수십만 행 아래면 그냥 배포해도 체감이 없다.

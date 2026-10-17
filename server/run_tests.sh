#!/usr/bin/env bash
#
# 서버 테스트 러너.
#
# 이 묶음의 테스트는 요구하는 환경이 세 가지로 갈리는데, 그게 어디에도
# 적혀 있지 않아서 그냥 전부 돌리면 절반이 빨간 줄로 나온다. 실패처럼
# 보이지만 환경이 안 맞은 것이고, 그 구분을 매번 손으로 기억해야 했다.
#
#   자체기동(self)  — 테스트가 server.js 를 직접 띄우고 쓰고 버리는 DB 를
#                     만든다. 아무 준비 없이 돌아간다.
#   통합(integration) — 8080 에 서버가 이미 떠 있어야 하고, 그 서버는
#                     테스트의 db 모듈과 같은 DB 를 봐야 한다. 다른 DB 로
#                     띄우면 ws 로 만든 계정을 테스트가 못 찾아 실패한다.
#                     (이 스크립트가 띄워 준다)
#   봇(bots)        — 봇들이 실제로 한 판을 끝까지 둔다. 통합과 같은 서버를
#                     쓰지만 한 건에 몇 분씩 걸려서, 기본 실행에 넣으면
#                     전체 시간을 이것들이 다 먹는다.
#   느림(slow)      — 브루트포스 동등성 검사. 혼자 7분쯤 걸린다.
#
# 사용법:
#   ./run_tests.sh            자체기동 + 통합 (기본)
#   ./run_tests.sh self       자체기동만
#   ./run_tests.sh integration 통합만 (서버를 띄워 준다)
#   ./run_tests.sh bots       봇 대국만 (서버를 띄워 준다)
#   ./run_tests.sh slow       느린 것만
#   ./run_tests.sh all        전부
#
# 환경변수:
#   DATABASE_URL   통합 테스트용 서버와 테스트가 함께 볼 DB.
#                  비우면 db/database.js 의 기본값(로컬 minigame)을 쓴다.
#   TEST_TIMEOUT   한 테스트의 제한 시간(초). 기본 240.
set -uo pipefail
cd "$(dirname "$0")"

GROUP="${1:-default}"
TIMEOUT="${TEST_TIMEOUT:-240}"

# 8080 에 서버가 필요한 테스트 — spawn 없이 ws/http 로 붙는 것들.
INTEGRATION=(
  test_card_view_reconnect test_coupon_notice_gate test_coupon_ws
  test_join_probe test_mail_ws test_match_history_ws test_midleave_record
  test_midleave_timeout_exit test_midleave_version_gate test_photo_expiry
  test_reconnect_timer test_spectator_perm
)
# 봇이 한 판을 끝까지 두는 것 — 서버는 필요하고, 한 건에 몇 분씩 간다.
BOTS=( test_3bots_join test_4bots test_bots test_midjoin_smoke )
# 혼자 오래 걸리는 것 — 기본 실행에서 뺀다.
SLOW=( test_canfulfill_equiv )
# 봇·느림 묶음의 제한 시간. 기본값(240초)으로는 못 끝낸다.
LONG_TIMEOUT="${TEST_LONG_TIMEOUT:-600}"

is_in() { local n="$1"; shift; for x in "$@"; do [ "$x" = "$n" ] && return 0; done; return 1; }

SRV_PID=""
start_server() {
  if lsof -ti:8080 >/dev/null 2>&1; then
    echo "→ 8080 에 이미 서버가 있습니다. 그것을 씁니다."
    echo "  (테스트의 db 모듈과 같은 DB 를 보고 있어야 합니다)"
    return
  fi
  echo "→ 통합 테스트용 서버를 8080 에 띄웁니다"
  PORT=8080 node server.js >/tmp/run_tests_server.log 2>&1 &
  SRV_PID=$!
  for _ in $(seq 1 80); do lsof -ti:8080 >/dev/null 2>&1 && break; sleep 0.5; done
  sleep 3
  if ! lsof -ti:8080 >/dev/null 2>&1; then
    echo "  서버가 뜨지 않았습니다. /tmp/run_tests_server.log 를 보세요."
    tail -15 /tmp/run_tests_server.log
    exit 1
  fi
}
stop_server() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; }
trap stop_server EXIT

# 자체기동 테스트가 남긴 고아 서버를 치운다. 안 치우면 다음 테스트가
# 같은 포트를 못 잡고 EADDRINUSE 로 죽는다.
reap_orphans() {
  for port in 8090 8091 8092 8093 8094 8095 8096 8097 8098 8099 8123; do
    pids=$(lsof -ti:$port 2>/dev/null) && [ -n "$pids" ] && kill -9 $pids 2>/dev/null
  done
}

run_one() {
  local n="$1"
  printf "  %-32s " "$n"
  node "$n.js" >"/tmp/rt_$n.txt" 2>&1 &
  local pid=$!
  ( sleep "$TIMEOUT"; kill -9 $pid 2>/dev/null ) &
  local w=$!
  wait $pid; local rc=$?
  kill $w 2>/dev/null; wait $w 2>/dev/null
  if [ $rc -eq 0 ]; then echo "PASS"; return 0; fi
  if [ $rc -eq 137 ]; then echo "TIMEOUT (${TIMEOUT}s)"; else echo "FAIL"; fi
  sed -n '$p' "/tmp/rt_$n.txt" | sed 's/^/      /'
  echo "      → 전문: /tmp/rt_$n.txt"
  return 1
}

declare -a SELF_LIST=() INTEG_LIST=() BOTS_LIST=() SLOW_LIST=()
for f in test_*.js; do
  n="${f%.js}"
  if is_in "$n" "${SLOW[@]}"; then SLOW_LIST+=("$n")
  elif is_in "$n" "${BOTS[@]}"; then BOTS_LIST+=("$n")
  elif is_in "$n" "${INTEGRATION[@]}"; then INTEG_LIST+=("$n")
  else SELF_LIST+=("$n"); fi
done

pass=0; fail=0; failed=""
run_group() {
  local label="$1"; shift
  [ $# -eq 0 ] && return
  echo; echo "[$label — $# 개]"
  for n in "$@"; do
    if run_one "$n"; then pass=$((pass+1)); else fail=$((fail+1)); failed="$failed $n"; fi
    reap_orphans
  done
}

case "$GROUP" in
  self)        run_group "자체기동" "${SELF_LIST[@]}" ;;
  integration) start_server; run_group "통합" "${INTEG_LIST[@]}" ;;
  bots)        start_server; TIMEOUT="$LONG_TIMEOUT"
               run_group "봇 대국" "${BOTS_LIST[@]}" ;;
  slow)        TIMEOUT="$LONG_TIMEOUT"; run_group "느림" "${SLOW_LIST[@]}" ;;
  all)         run_group "자체기동" "${SELF_LIST[@]}"
               start_server; run_group "통합" "${INTEG_LIST[@]}"
               TIMEOUT="$LONG_TIMEOUT"
               run_group "봇 대국" "${BOTS_LIST[@]}"
               run_group "느림" "${SLOW_LIST[@]}" ;;
  default)     run_group "자체기동" "${SELF_LIST[@]}"
               start_server; run_group "통합" "${INTEG_LIST[@]}"
               echo
               echo "(봇 대국과 느린 묶음은 건너뜀 — 한 건에 몇 분씩 걸린다."
               echo " ./run_tests.sh bots / slow / all)" ;;
  *) echo "모르는 묶음: $GROUP (self|integration|bots|slow|all)"; exit 2 ;;
esac

echo
echo "통과 $pass / 실패 $fail"
[ -n "$failed" ] && { echo "실패:$failed"; exit 1; }
exit 0

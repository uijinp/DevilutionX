#!/usr/bin/env bash
# DevilutionX 웹 빌드를 홈서버에 배포한다. 로컬(맥)에서 실행.
#
#   ./deploy/deploy.sh
#
# 공개 URL: https://diablo2.honeyloved.com
# 소스를 서버로 보내 이미지 안에서 Emscripten 빌드한다(호스트에는 도커만 있다).
set -euo pipefail

HOST=homeserver
NAME=diablo2
REMOTE=/home/uijin/apps/$NAME
PORT=8110
URL=https://diablo2.honeyloved.com

cd "$(dirname "$0")/.."

echo "▸ 업로드 → $HOST:$REMOTE"
rsync -az --delete \
  --exclude /.git --exclude '/build*' --exclude /.omc --exclude /.claude \
  ./ "$HOST:$REMOTE/"

echo "▸ 이미지 빌드 + 컨테이너 교체 (첫 빌드는 20분 이상 걸릴 수 있다)"
# 원격에도 set -e. 빌드가 깨졌는데 옛 컨테이너로 다시 뜨면 성공처럼 보인다 — 그게 제일 나쁘다.
ssh "$HOST" "set -e
  cd $REMOTE
  DOCKER_BUILDKIT=1 docker build -f deploy/Dockerfile -t $NAME:latest .
  docker rm -f $NAME >/dev/null 2>&1 || true
  docker run -d --name $NAME --restart unless-stopped \
    -p 127.0.0.1:$PORT:80 \
    -l status.host=$NAME.honeyloved.com \
    -l status.port=$PORT \
    -l status.label='DevilutionX 웹' \
    -l status.path=/healthz \
    $NAME:latest"

echo "▸ 서버 안 확인"
for i in $(seq 1 15); do
  ssh "$HOST" "curl -sf -m 3 http://127.0.0.1:$PORT/healthz >/dev/null" && break
  [ "$i" = 15 ] && { echo "실패 — 로그:"; ssh "$HOST" "docker logs --tail 40 $NAME"; exit 1; }
  sleep 1
done

# 200 만 보지 않는다. wasm·데이터·mpq 가 실제로 있고 크기가 맞는지 센다.
echo "▸ 내용 확인"
ssh "$HOST" "set -e
  for f in devilutionx.wasm devilutionx.data spawn.mpq fonts.mpq; do
    sz=\$(curl -s -o /dev/null -I -w '%{http_code} %{size_download}' http://127.0.0.1:$PORT/\$f)
    len=\$(curl -sI http://127.0.0.1:$PORT/\$f | awk 'tolower(\$1)==\"content-length:\"{print \$2}' | tr -d '\r')
    printf '  %-18s %s bytes\n' \$f \"\$len\"
    [ \"\${len:-0}\" -gt 1000000 ] || { echo \"실패 — \$f 가 비었다\"; exit 1; }
  done
  curl -sI http://127.0.0.1:$PORT/ | grep -qi 'cross-origin-embedder-policy: require-corp' || { echo '실패 — COEP 헤더 없음'; exit 1; }"

echo "▸ 공개 URL 확인"
code=$(curl -s -m 25 -o /dev/null -w '%{http_code}' "$URL/")
echo "$URL/ → $code"
[ "$code" = "200" ] || { echo "실패 — 프록시 규칙(statusServer/proxy/sites/diablo2.caddy)과 Cloudflare 터널 Public Hostname 을 확인할 것"; exit 1; }
curl -sI -m 25 "$URL/" | grep -qi 'cross-origin-embedder-policy' || echo "경고 — 공개 URL 에 COEP 헤더가 없다. 게임이 뜨지 않으면 이것부터 본다."
echo "완료 → $URL"

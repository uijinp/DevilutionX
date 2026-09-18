#!/usr/bin/env bash
# DevilutionX 웹 빌드를 홈서버에 배포한다. 로컬(맥)에서 실행. 로컬 도커가 켜져 있어야 한다.
#
#   ./deploy/deploy.sh            # 로컬 빌드 → dist/ → 서버로 전송 → nginx 컨테이너 교체
#   SKIP_BUILD=1 ./deploy/deploy.sh   # dist/ 가 이미 최신일 때 전송만
#   JOBS=2 ./deploy/deploy.sh         # 병렬 컴파일 수 (기본: 코어의 절반). 맥이 버벅이면 낮춘다
#
# 공개 URL: https://diablo2.honeyloved.com
# 서버(4C/14G)는 Emscripten 빌드를 견디지 못한다. 빌드는 반드시 여기서 하고 산출물만 보낸다.
set -euo pipefail

HOST=homeserver
NAME=diablo2
REMOTE=/home/uijin/apps/$NAME
PORT=8110
URL=https://diablo2.honeyloved.com
ASSETS=https://github.com/diasurgical/devilutionx-assets/releases

cd "$(dirname "$0")/.."

if [ "${SKIP_BUILD:-}" != "1" ]; then
  echo "▸ 로컬 도커에서 Emscripten 빌드 → dist/"
  docker build -f deploy/Dockerfile.build --target out --output type=local,dest=dist \
    --build-arg JOBS="${JOBS:-}" .
fi
for f in devilutionx.js devilutionx.wasm devilutionx.data; do
  [ -s "dist/$f" ] || { echo "실패 — dist/$f 가 없다"; exit 1; }
done

# 페이지 셸과 파일 매니저는 빌드 산출물이 아니라 그대로 복사되는 파일이다. 항상 소스에서 다시 가져와
# UI 만 고칠 때 재빌드가 필요 없게 하고, 빌드 ID 를 박아 CDN 캐시를 무력화한다.
echo "▸ 페이지 셸 갱신 + 캐시 무력화 ID"
BUILD_ID="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)-$(date +%Y%m%d%H%M%S)"
cp Packaging/emscripten/index.html Packaging/emscripten/file-manager.js dist/
sed -i '' "s/__BUILD_ID__/$BUILD_ID/g" dist/index.html
grep -q "$BUILD_ID" dist/index.html || { echo "실패 — BUILD_ID 치환 안 됨"; exit 1; }
echo "  BUILD_ID=$BUILD_ID"

echo "▸ 게임 데이터 (없을 때만 받는다)"
[ -s dist/spawn.mpq ] || curl -fL --progress-bar -o dist/spawn.mpq "$ASSETS/download/v2/spawn.mpq"
[ -s dist/fonts.mpq ] || curl -fL --progress-bar -o dist/fonts.mpq "$ASSETS/latest/download/fonts.mpq"
chmod 644 dist/*

echo "▸ 업로드 → $HOST:$REMOTE (deploy/ 와 dist/ 만)"
ssh "$HOST" "mkdir -p $REMOTE"
rsync -az --delete deploy/ "$HOST:$REMOTE/deploy/"
rsync -az --delete dist/   "$HOST:$REMOTE/dist/"

echo "▸ 런타임 이미지 조립 + 컨테이너 교체"
# 원격에도 set -e. 실패했는데 옛 컨테이너로 다시 뜨면 성공처럼 보인다 — 그게 제일 나쁘다.
ssh "$HOST" "set -e
  cd $REMOTE
  docker build -f deploy/Dockerfile -t $NAME:latest .
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

# 200 만 보지 않는다. wasm·데이터·mpq 가 실제로 있고 크기가 맞는지, MIME 과 격리 헤더까지 센다.
echo "▸ 내용 확인"
ssh "$HOST" "set -e
  for f in devilutionx.wasm devilutionx.data spawn.mpq fonts.mpq; do
    len=\$(curl -sI http://127.0.0.1:$PORT/\$f | awk 'tolower(\$1)==\"content-length:\"{print \$2}' | tr -d '\r')
    printf '  %-18s %s bytes\n' \$f \"\$len\"
    [ \"\${len:-0}\" -gt 1000000 ] || { echo \"실패 — \$f 가 비었다\"; exit 1; }
  done
  curl -sI http://127.0.0.1:$PORT/ | grep -qi 'content-type: text/html' || { echo '실패 — index MIME'; exit 1; }
  curl -sI http://127.0.0.1:$PORT/devilutionx.wasm | grep -qi 'content-type: application/wasm' || { echo '실패 — wasm MIME'; exit 1; }
  curl -sI http://127.0.0.1:$PORT/ | grep -qi 'cross-origin-embedder-policy: require-corp' || { echo '실패 — COEP 헤더 없음'; exit 1; }"

echo "▸ 공개 URL 확인"
code=$(curl -s -m 25 -o /dev/null -w '%{http_code}' "$URL/")
echo "$URL/ → $code"
[ "$code" = "200" ] || { echo "실패 — 프록시 규칙(statusServer/proxy/sites/diablo2.caddy)과 Cloudflare 터널 Public Hostname 을 확인할 것"; exit 1; }
# CDN 이 옛 파일을 주지 않는지: 공개 index.html 이 이번 BUILD_ID 를 담고, 그 ID 로 받은 js 가 서버 것과 같은지 본다.
curl -s -m 25 "$URL/" | grep -q "$BUILD_ID" || { echo "실패 — 공개 index.html 이 이번 빌드가 아니다 (CDN 캐시?)"; exit 1; }
pub=$(curl -s -m 60 "$URL/devilutionx.js?v=$BUILD_ID" | shasum -a 256 | cut -c1-16)
loc=$(shasum -a 256 dist/devilutionx.js | cut -c1-16)
[ "$pub" = "$loc" ] || { echo "실패 — 공개 devilutionx.js($pub) ≠ 로컬($loc)"; exit 1; }
echo "  공개 js 해시 일치 ($loc)"
curl -sI -m 25 "$URL/" | grep -qi 'cross-origin-embedder-policy' || echo "경고 — 공개 URL 에 COEP 헤더가 없다. 게임이 뜨지 않으면 이것부터 본다."
echo "완료 → $URL"

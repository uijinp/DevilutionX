# HANDOFF — DevilutionX 홈서버 웹 배포
> 최종 갱신: 2026-09-18 21:40 / by Claude Code

## 목표
diasurgical/devilutionX 를 포크(`uijinp/DevilutionX`, 브랜치 `homeserver-web`)해서
브라우저(Emscripten)로 빌드하고 홈서버 https://diablo2.honeyloved.com 에 공개한다.
이후 이 포크를 확장하며 가지고 논다.

## 상태
- [x] GitHub 포크 + 로컬 클론 (`upstream` 리모트 = diasurgical)
- [x] `deploy/Dockerfile.build`(emsdk 4.0.15, **로컬 도커에서만**) → `dist/` → `deploy/Dockerfile`(nginx) / `deploy/nginx.conf`(COOP/COEP) / `deploy/deploy.sh`(포트 8110)
- [x] `Packaging/emscripten/emscripten_pre.js` 에 `fonts.mpq` 프리로드 추가 (한국어 글꼴)
- [x] 엣지 프록시 규칙 `statusServer/proxy/sites/diablo2.caddy` 작성
- [x] 배포 완료. https://diablo2.honeyloved.com 에서 인트로 → 메인 메뉴(Shareware)까지 헤드리스 Chromium 으로 확인, 콘솔 오류 0
- [x] 프록시 규칙 반영(`deploy-proxy.sh`), 상태 페이지 라벨 등록
- [ ] **← 다음 작업**: 사용자가 실제 브라우저로 플레이(한글 설정 시 fonts.mpq 글꼴 표시, 저장 후 새로고침해 IDBFS 복원) 확인
- [ ] 확장 아이디어: `Packaging/emscripten/index.html` UI 한글화·모바일 터치, `mods/` 로 밸런스 모드, 정품 DIABDAT.MPQ 파일 매니저 업로드 안내

## 핵심 결정
| 결정 | 이유 | 대안(기각) |
|---|---|---|
| Emscripten 웹 빌드로 서빙 | 도메인으로 "올린다"의 자연스러운 형태. 업스트림에 공식 포트 존재 | Xvfb+noVNC 스트리밍(무겁고 동시접속 불가) |
| 셰어웨어 `spawn.mpq` 동봉 | 재배포 가능한 공식 데모 데이터. 정품 DIABDAT.MPQ 는 파일 매니저로 사용자가 직접 업로드 | 정품 데이터 동봉(라이선스 위반) |
| **로컬 도커에서 빌드, 산출물(dist/)만 서버로** | 사용자 지시: 서버(4C/14G)가 Emscripten 빌드를 못 견딘다 | 서버 컨테이너 안 빌드(첫 시도, 사용자가 중단 요청) |
| 포트 8110 | 8100~8109 사용 중 | — |

## 방금 한 일과 이유
- 업스트림 문서는 "Emscripten 은 빌드만 된다"고 하지만 PR #8312 이후 IDBFS 저장·MPQ 로더·파일 매니저가 들어가 실제로 플레이 가능하다고 판단.
- SDL2 가 `USE_PTHREADS=1` 이라 SharedArrayBuffer 필요 → nginx 에서 COOP/COEP 헤더를 항상 붙인다. 이 헤더가 Cloudflare 를 통과해 공개 URL 에서도 보여야 한다.

## 주의사항 / 실패한 시도
- **서버에서 빌드하지 말 것.** 첫 배포는 서버 도커 안에서 빌드했는데 사용자가 "서버가 못 견딘다"고 중단. 이후 로컬 빌드로 전환.
- `ADD <url>` 로 받은 mpq 는 mode 600 → nginx 403. 지금은 `deploy.sh` 가 curl 로 받고 `chmod 644` 한다.
- nginx `server{}` 안에 `types { application/wasm wasm; }` 를 쓰면 기본 MIME 표 전체가 덮여 index.html 이 octet-stream 이 된다. nginx 1.27 은 wasm 을 기본 포함하므로 쓰지 않는다.
- 헤드리스 검증 스크립트가 캔버스에 WebGL 컨텍스트를 먼저 잡으면 SDL 의 2D 컨텍스트가 null 이 되어 `createImageData` 오류가 난다. 검증은 스크린샷으로만 한다.
- emsdk 공식 이미지는 amd64 만 있어 애플 실리콘에서 로제타로 돈다(약 4~5분). `--platform=linux/amd64` 명시.
- 내장 브라우저·Chrome 확장 둘 다 이 세션에서 연결 불가였음. 검증 스크립트: `~/IdeaProjects/opt/game/diablo/node_modules/playwright` 재사용.

## 환경 메모
- 배포: `./deploy/deploy.sh` (맥, 로컬 도커 필요). `SKIP_BUILD=1` 이면 전송만. 서버 `~/apps/diablo2`(deploy/, dist/ 만), 컨테이너 `diablo2`, `127.0.0.1:8110`
- 업스트림 동기화: `git fetch upstream && git rebase upstream/master` (브랜치 `homeserver-web`)
- 프록시: `~/IdeaProjects/opt/statusServer/proxy/sites/diablo2.caddy` → `./deploy/deploy-proxy.sh`
- 터널: 기존 와일드카드성 규칙이 8099 로 연결돼 있어 diablo(8108) 때는 대시보드 변경 없이 공개됐음. 안 되면 사용자가 Public Hostname 추가
- 기존 `diablo.honeyloved.com`(8108, `~/apps/diablo`)은 별개의 자작 캔버스 게임. 건드리지 말 것

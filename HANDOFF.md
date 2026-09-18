# HANDOFF — DevilutionX 홈서버 웹 배포
> 최종 갱신: 2026-09-18 21:10 / by Claude Code

## 목표
diasurgical/devilutionX 를 포크(`uijinp/DevilutionX`, 브랜치 `homeserver-web`)해서
브라우저(Emscripten)로 빌드하고 홈서버 https://diablo2.honeyloved.com 에 공개한다.
이후 이 포크를 확장하며 가지고 논다.

## 상태
- [x] GitHub 포크 + 로컬 클론 (`upstream` 리모트 = diasurgical)
- [x] `deploy/Dockerfile`(emsdk 4.0.15 멀티스테이지 → nginx), `deploy/nginx.conf`(COOP/COEP), `deploy/deploy.sh`(포트 8110)
- [x] `Packaging/emscripten/emscripten_pre.js` 에 `fonts.mpq` 프리로드 추가 (한국어 글꼴)
- [x] 엣지 프록시 규칙 `statusServer/proxy/sites/diablo2.caddy` 작성
- [ ] **← 다음 작업**: `deploy/deploy.sh` 첫 실행 결과 확인(`../deploy.log`). 빌드 실패 시 Dockerfile 의 emsdk 태그·cmake 옵션 수정
- [ ] `statusServer/deploy/deploy-proxy.sh` 실행해 프록시 규칙 반영
- [ ] 공개 URL 에서 실제 플레이(캔버스 렌더, 한글 표시, 저장 IDBFS) 브라우저 검증
- [ ] 확장 아이디어 정리 (모드 시스템 `mods/`, 화면 UI 개선 등)

## 핵심 결정
| 결정 | 이유 | 대안(기각) |
|---|---|---|
| Emscripten 웹 빌드로 서빙 | 도메인으로 "올린다"의 자연스러운 형태. 업스트림에 공식 포트 존재 | Xvfb+noVNC 스트리밍(무겁고 동시접속 불가) |
| 셰어웨어 `spawn.mpq` 동봉 | 재배포 가능한 공식 데모 데이터. 정품 DIABDAT.MPQ 는 파일 매니저로 사용자가 직접 업로드 | 정품 데이터 동봉(라이선스 위반) |
| 서버 컨테이너 안에서 빌드 | 홈서버 정책: 호스트에 툴체인 설치 금지. 로컬 맥 도커 데몬도 꺼져 있음 | 로컬 빌드 후 산출물 업로드 |
| 포트 8110 | 8100~8109 사용 중 | — |

## 방금 한 일과 이유
- 업스트림 문서는 "Emscripten 은 빌드만 된다"고 하지만 PR #8312 이후 IDBFS 저장·MPQ 로더·파일 매니저가 들어가 실제로 플레이 가능하다고 판단.
- SDL2 가 `USE_PTHREADS=1` 이라 SharedArrayBuffer 필요 → nginx 에서 COOP/COEP 헤더를 항상 붙인다. 이 헤더가 Cloudflare 를 통과해 공개 URL 에서도 보여야 한다.

## 주의사항 / 실패한 시도
- (아직 없음) 첫 빌드 결과에 따라 갱신할 것.

## 환경 메모
- 배포: `./deploy/deploy.sh` (맥에서). 서버 `~/apps/diablo2`, 컨테이너 `diablo2`, `127.0.0.1:8110`
- 프록시: `~/IdeaProjects/opt/statusServer/proxy/sites/diablo2.caddy` → `./deploy/deploy-proxy.sh`
- 터널: 기존 와일드카드성 규칙이 8099 로 연결돼 있어 diablo(8108) 때는 대시보드 변경 없이 공개됐음. 안 되면 사용자가 Public Hostname 추가
- 기존 `diablo.honeyloved.com`(8108, `~/apps/diablo`)은 별개의 자작 캔버스 게임. 건드리지 말 것

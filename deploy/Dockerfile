# DevilutionX 웹(Emscripten) 빌드 → nginx 정적 서빙.
# 홈서버에는 도커만 있으므로 툴체인 설치 없이 이미지 안에서 빌드한다.
FROM emscripten/emsdk:4.0.15 AS build
WORKDIR /src
COPY . .
RUN emcmake cmake -S . -B build-em -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build-em -j"$(nproc)"

# 셰어웨어 데이터(spawn.mpq)와 한국어 글꼴(fonts.mpq)은 공식 배포본에서 받는다.
FROM alpine:3.20 AS assets
ADD --chmod=644 https://github.com/diasurgical/devilutionx-assets/releases/download/v2/spawn.mpq /out/spawn.mpq
ADD --chmod=644 https://github.com/diasurgical/devilutionx-assets/releases/latest/download/fonts.mpq /out/fonts.mpq

FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build-em/index.html /src/build-em/file-manager.js \
                  /src/build-em/devilutionx.js /src/build-em/devilutionx.wasm \
                  /src/build-em/devilutionx.data /usr/share/nginx/html/
COPY --from=assets /out/ /usr/share/nginx/html/
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1/healthz >/dev/null || exit 1

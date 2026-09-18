# 런타임 이미지. dist/ (로컬 빌드 산출물 + mpq) 를 nginx 에 담기만 한다. 서버에서 빌드하지 않는다.
FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/ /usr/share/nginx/html/
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1/healthz >/dev/null || exit 1

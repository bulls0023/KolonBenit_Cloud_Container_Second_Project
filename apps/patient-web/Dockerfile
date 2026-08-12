# =====================================================================
# patient-web Dockerfile
# 계약: README v3.1 §11.0 / §16-4
#
# ⚠️ nginx-unprivileged 를 쓴다. 일반 nginx 이미지는 root 로 시작해
#    워커만 내리므로 PSA restricted 의 runAsNonRoot 를 만족하지 못한다.
#    이 이미지는 uid 101 로 실행되고 기본 포트가 8080 이다 (계약과 일치).
#
# ⚠️ digest 는 자리표시자다. prepare 또는 수동 치환 대상.
#      docker pull nginxinc/nginx-unprivileged:1.27-alpine
#      docker inspect --format='{{index .RepoDigests 0}}' nginxinc/nginx-unprivileged:1.27-alpine
#
# ⚠️ 빌드는 --platform linux/amd64 필수 (deploy.ps1 이 검증한다).
# =====================================================================
FROM nginxinc/nginx-unprivileged@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0

# 기본 설정을 통째로 교체한다. include 로 얹으면 default.conf 의
# listen 80 이 살아남아 포트가 둘이 된다.
COPY --chown=101:101 nginx.conf /etc/nginx/nginx.conf
COPY --chown=101:101 html/      /usr/share/nginx/html/

USER 101

EXPOSE 8080

# 헬스체크는 Kubernetes probe 가 담당한다. HEALTHCHECK 를 두지 않는다.

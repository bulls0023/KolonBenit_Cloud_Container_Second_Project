# =====================================================================
# Hybrid Toy Project - WAS Dockerfile
# 계약: README v3.1 §16-4 (digest 핀 필수. :latest 금지)
#
# ⚠️ 아래 sha256 은 자리표시자다. 빌드 전 반드시 실제 digest 로 교체한다.
#      docker pull amazoncorretto:25-alpine
#      docker inspect --format='{{index .RepoDigests 0}}' amazoncorretto:25-alpine
#    조회한 값을 README §21 digest 표에 기록한 뒤 여기 반영한다 (구축설명서 §3.3-3).
#
# ⚠️ EKS 노드는 amd64 다. Windows/ARM 에서 빌드할 때 --platform 을 빠뜨리면
#    exec format error 로 CrashLoopBackOff 가 난다.
#      docker build --platform linux/amd64 -t <ECR>/hybrid-toy/was:0.1.0 .
# =====================================================================

# ---------- build stage ----------
FROM amazoncorretto:25-alpine@sha256:027310590da693629c2cf704d2f87e9359c33ee2f02bcaa777680b2f4b94f4c7 AS builder

WORKDIR /build

# 의존성 레이어를 소스와 분리한다. 소스만 바뀌면 의존성 다운로드를 건너뛴다.
COPY gradlew settings.gradle.kts build.gradle.kts gradle.properties ./
COPY gradle gradle
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon || true

COPY src src
RUN ./gradlew bootJar --no-daemon -x test

# ---------- runtime stage ----------
FROM amazoncorretto:25-alpine@sha256:027310590da693629c2cf704d2f87e9359c33ee2f02bcaa777680b2f4b94f4c7

# non-root 실행. UID 를 고정해야 Pod Security Admission 의 runAsNonRoot 와 정합한다.
RUN addgroup -g 10001 app && adduser -u 10001 -G app -S -H app

WORKDIR /app
COPY --from=builder --chown=10001:10001 /build/build/libs/app.jar /app/app.jar

USER 10001

EXPOSE 8080

ENV TZ=Asia/Seoul \
    JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+UseSerialGC -Duser.timezone=Asia/Seoul"

# 헬스체크는 Kubernetes probe 가 담당한다. Docker HEALTHCHECK 는 두지 않는다.
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]

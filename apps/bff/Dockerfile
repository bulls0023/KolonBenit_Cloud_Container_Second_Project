# =====================================================================
# Hybrid Toy Project - BFF Dockerfile
# 계약: README v3.1 §16-4 (digest 핀 필수. :latest 금지)
#
# ⚠️ sha256 은 자리표시자다. local/prepare.ps1 이 실제 digest 로 치환한다.
# ⚠️ EKS 노드는 amd64 다. 배포용 빌드는 --platform linux/amd64 필수.
# =====================================================================

FROM amazoncorretto:25-alpine@sha256:027310590da693629c2cf704d2f87e9359c33ee2f02bcaa777680b2f4b94f4c7 AS builder

WORKDIR /build

COPY gradlew settings.gradle.kts build.gradle.kts gradle.properties ./
COPY gradle gradle
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon || true

COPY src src
RUN ./gradlew bootJar --no-daemon -x test

FROM amazoncorretto:25-alpine@sha256:027310590da693629c2cf704d2f87e9359c33ee2f02bcaa777680b2f4b94f4c7

RUN addgroup -g 10001 app && adduser -u 10001 -G app -S -H app

WORKDIR /app
COPY --from=builder --chown=10001:10001 /build/build/libs/app.jar /app/app.jar

USER 10001

EXPOSE 8080

ENV TZ=Asia/Seoul \
    JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+UseSerialGC -Duser.timezone=Asia/Seoul"

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]

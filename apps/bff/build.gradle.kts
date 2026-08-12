// =====================================================================
// Hybrid Toy Project - apps/bff/build.gradle.kts
// 계약: README v3.1 §5.3 / §6.5
//
// WAS 와의 차이
//   - spring-boot-starter-security 를 넣는다. BFF 가 인증·인가의 유일한 지점이다.
//   - Nimbus JOSE+JWT 로 HS256 JWT 를 직접 발급·검증한다 (§21).
//   - spring-boot-starter-data-jpa 를 넣지 않는다. BFF 는 DB 에 접근하지 않는다.
//     의존성 차원에서 §6.5 "BFF 의 DB 직접 접근 금지" 를 강제한다.
// =====================================================================
plugins {
    java
    id("org.springframework.boot") version "4.1.0"
}

group = "org.kuspital"
version = "0.1.0"

val springBootVersion = "4.1.0"
val nimbusVersion     = "10.9.1"    // BOM 미관리. 직접 핀한다.

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(25)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(platform("org.springframework.boot:spring-boot-dependencies:$springBootVersion"))

    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-validation")

    // ⚠️ Spring Boot 4 는 자동 구성을 기능별 모듈로 분리했다.
    //    RestClient.Builder 자동 구성이 spring-boot-restclient 로 이동했고,
    //    starter-web 은 더 이상 이를 가져오지 않는다.
    //    누락 시 기동에서 다음으로 실패한다:
    //        No qualifying bean of type 'RestClient$Builder' available
    //    (Boot 3 에서는 starter-web 만으로 주입됐다.)
    implementation("org.springframework.boot:spring-boot-starter-restclient")

    // JWT 발급·검증. Spring Security 의 oauth2-resource-server 를 쓰지 않는 이유:
    // 자체 발급 HS256 대칭키 하나뿐이라 JWK/introspection 인프라가 과하다.
    // ⚠️ Spring Boot 4.1.0 BOM 은 nimbus-jose-jwt 를 관리하지 않는다.
    //    (Boot 3.x 는 관리했다. spring-security-oauth2-jose 를 쓰지 않으므로
    //     전이 의존으로도 들어오지 않는다.)
    //    버전을 생략하면 다음으로 실패한다:
    //        Could not find com.nimbusds:nimbus-jose-jwt:
    //    §5.3 "버전 전량 핀" 원칙대로 명시한다.
    //    10.9.1 = 2026-05-31 릴리스. 갱신 시 이 줄만 고친다.
    implementation("com.nimbusds:nimbus-jose-jwt:$nimbusVersion")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.springframework.security:spring-security-test")
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
    options.compilerArgs.add("-parameters")
}

tasks.withType<Test> {
    useJUnitPlatform()
    systemProperty("user.timezone", "Asia/Seoul")
    systemProperty("file.encoding", "UTF-8")
    defaultCharacterEncoding = "UTF-8"
    testLogging {
        events("passed", "skipped", "failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
        showCauses = true
        showStackTraces = true
    }
}

tasks.named<org.springframework.boot.gradle.tasks.bundling.BootJar>("bootJar") {
    archiveFileName.set("app.jar")
}

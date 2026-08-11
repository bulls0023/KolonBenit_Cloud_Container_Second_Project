// =====================================================================
// Hybrid Toy Project - apps/was/build.gradle.kts
// 계약: README v3.1 §5.3 (버전 전량 핀) / §21-23
//
//   Java           25
//   Spring Boot    4.1.0   (GA 2026-06-10)
//   Gradle         9.5.1   (9.7.0 미채택 - README §21)
//
// Spring Boot 4.1.0 이 끌어오는 주요 버전 (release notes 기준)
//   Spring Framework 7.0.8 / Spring Security 7.1.0 / Spring Data BOM 2026.0.0
// =====================================================================
//
// [설계] io.spring.dependency-management 플러그인을 쓰지 않는다.
//   Gradle 네이티브 platform() BOM 으로 충분하고, 플러그인 하나가 줄어든다.
//   버전은 아래 springBootVersion 한 곳에서만 관리된다.
//
plugins {
    java
    id("org.springframework.boot") version "4.1.0"
}

group = "org.kuspital"
version = "0.1.0"

val springBootVersion = "4.1.0"

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
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-validation")

    // BCryptPasswordEncoder 만 사용한다.
    // WAS 는 JWT 를 발급하지도 검증하지도 않는다 (README §16-12).
    // 인증 필터 체인은 BFF 가 담당한다. 여기서는 SecurityFilterChain 을 무력화한다.
    implementation("org.springframework.security:spring-security-crypto")

    runtimeOnly("com.mysql:mysql-connector-j")

    // 부트스트랩 검증 테스트용. @Query JPQL 은 컴파일러가 보지 않으므로
    // EntityManagerFactory 생성까지 가는 테스트가 반드시 필요하다.
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testRuntimeOnly("com.h2database:h2")
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
    options.compilerArgs.add("-parameters")
}

tasks.withType<Test> {
    useJUnitPlatform()
    systemProperty("user.timezone", "Asia/Seoul")

    // Windows 콘솔에서 테스트 로그의 한글이 깨지지 않도록 강제한다.
    systemProperty("file.encoding", "UTF-8")
    defaultCharacterEncoding = "UTF-8"

    // 실패 원인을 콘솔에 그대로 찍는다.
    // 기본 설정은 예외 클래스명만 보여줘서 근본 원인 메시지가 사라진다.
    // 이번 Jackson 3 바인딩 실패가 정확히 그 경우였다.
    testLogging {
        events("passed", "skipped", "failed")
        showStandardStreams = false
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
        showCauses = true
        showStackTraces = true
    }
}

tasks.named<org.springframework.boot.gradle.tasks.bundling.BootJar>("bootJar") {
    archiveFileName.set("app.jar")
}

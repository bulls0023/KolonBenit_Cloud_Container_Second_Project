package org.kuspital.bff.config;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * 애플리케이션 설정. README v3.1 §6.5 / §6.6
 *
 * @Validated 로 기동 시점에 검증한다. 잘못된 설정은 첫 요청이 아니라
 * 기동에서 드러나야 한다.
 */
public final class AppProperties {

    private AppProperties() {
    }

    @Validated
    @ConfigurationProperties(prefix = "app.jwt")
    public record Jwt(
            /**
             * ⚠️ 기본값 없음. 미주입 시 기동 실패.
             *    HS256 은 32바이트(256비트) 이상을 요구한다. 짧으면 Nimbus 가 거부한다.
             */
            @NotBlank String signingKey,
            @NotBlank String issuer,
            @NotBlank String audience,
            @Positive int patientTtlMinutes,
            @Positive int staffTtlHours) {
    }

    @Validated
    @ConfigurationProperties(prefix = "app.cookie")
    public record Cookie(
            boolean secure,
            @NotBlank String patientTokenName,
            @NotBlank String csrfTokenName,
            @NotBlank String path) {
    }

    @Validated
    @ConfigurationProperties(prefix = "app.was")
    public record Was(
            @NotBlank String baseUrl,
            @Positive int connectTimeoutMs,
            @Positive int readTimeoutMs) {
    }
}

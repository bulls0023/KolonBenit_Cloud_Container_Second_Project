package org.kuspital.bff.security;

import org.kuspital.bff.config.AppProperties;
import org.springframework.http.ResponseCookie;
import org.springframework.stereotype.Component;


/**
 * 환자 쿠키 생성. README v3.1 §6.5
 *
 * | 쿠키           | 속성 |
 * |---------------|------|
 * | PATIENT_TOKEN | HttpOnly ✅ / Secure ✅ / SameSite=Lax / Path=/api/bff/patient / Max-Age=1800 |
 * | XSRF-TOKEN    | HttpOnly ❌ / Secure ✅ / SameSite=Lax / Path=/api/bff/patient |
 *
 * ⚠️ 환자 JWT 를 응답 JSON 이나 localStorage 에 넣지 않는다.
 *    HttpOnly 쿠키의 의미가 사라진다 - XSS 로 탈취 가능해진다.
 *
 * ⚠️ Path 를 /api/bff/patient 로 좁힌다.
 *    루트로 두면 직원 경로 요청에도 환자 쿠키가 자동으로 실려 나간다.
 *
 * ⚠️ SameSite=Lax 는 Strict 보다 느슨하지만, 외부 링크로 진입하는
 *    정상 흐름을 막지 않으면서 CSRF 의 주요 경로는 차단한다.
 *    CSRF 토큰과 이중으로 방어한다.
 */
@Component
public class CookieFactory {

    private final AppProperties.Cookie props;
    private final AppProperties.Jwt jwtProps;

    public CookieFactory(AppProperties.Cookie props, AppProperties.Jwt jwtProps) {
        this.props = props;
        this.jwtProps = jwtProps;
    }

    public ResponseCookie patientToken(String token) {
        return ResponseCookie.from(props.patientTokenName(), token)
                .httpOnly(true)
                .secure(props.secure())
                .sameSite("Lax")
                .path(props.path())
                // 쿠키 수명과 토큰 TTL 을 일치시킨다. 어긋나면 쿠키는 살아있는데
                // 토큰이 만료돼 401 이 나거나, 그 반대가 된다.
                .maxAge(jwtProps.patientTtl())
                .build();
    }

    /** 로그아웃. 값을 비우고 Max-Age=0 으로 즉시 만료시킨다. */
    public ResponseCookie expiredPatientToken() {
        return ResponseCookie.from(props.patientTokenName(), "")
                .httpOnly(true)
                .secure(props.secure())
                .sameSite("Lax")
                .path(props.path())
                .maxAge(0)
                .build();
    }
}

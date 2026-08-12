package org.kuspital.bff.security;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import org.kuspital.bff.config.AppProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 전달수단 ↔ actor_type 바인딩. README v3.1 §6.5
 *
 * [왜 필요한가] 서명 검증만으로는 불충분하다.
 *   직원 JWT 는 서명이 유효하다. 그것을 쿠키에 넣어 환자 경로로 보내면
 *   서명·만료·발급자 검증을 전부 통과한다. 전달수단과 actor_type 을
 *   함께 보지 않으면 뚫린다.
 *
 * | 전달수단                | 허용 actor_type | 허용 경로                |
 * |------------------------|----------------|-------------------------|
 * | PATIENT_TOKEN 쿠키      | PATIENT 만     | /api/bff/patient/**     |
 * | Authorization: Bearer  | STAFF 만       | /api/bff/staff/**       |
 *
 * 검증 순서 (§6.5):
 *   Bearer 확인 → 없으면 쿠키 확인 → 둘 다 없으면 401
 *   → 서명/iss/aud/exp → 전달수단 바인딩 → role→권한 변환
 *
 * 불일치·누락·미상은 전부 401 이다. 403 이 아니다 -
 * "인증은 됐는데 권한이 없다" 가 아니라 "인증 자체가 성립하지 않는다".
 */
@Component
public class TokenResolver {

    private static final Logger log = LoggerFactory.getLogger(TokenResolver.class);

    private static final String BEARER_PREFIX = "Bearer ";
    private static final String PATIENT_PATH_PREFIX = "/api/bff/patient";
    private static final String STAFF_PATH_PREFIX = "/api/bff/staff";

    private final JwtIssuer jwtIssuer;
    private final AppProperties.Cookie cookieProps;

    public TokenResolver(JwtIssuer jwtIssuer, AppProperties.Cookie cookieProps) {
        this.jwtIssuer = jwtIssuer;
        this.cookieProps = cookieProps;
    }

    /**
     * 요청에서 신원을 해석한다. 실패 시 null (호출부가 401 처리).
     */
    public AuthenticatedActor resolve(HttpServletRequest request) {

        String path = request.getRequestURI();

        // --- 1. Bearer 우선 ---
        String bearer = request.getHeader("Authorization");
        if (bearer != null && bearer.startsWith(BEARER_PREFIX)) {

            String token = bearer.substring(BEARER_PREFIX.length()).trim();
            AuthenticatedActor actor = jwtIssuer.verify(token);
            if (actor == null) {
                return null;
            }

            // Bearer 는 STAFF 전용이다.
            if (actor.actorType() != ActorType.STAFF) {
                log.warn("binding rejected: Bearer with actorType={} path={}",
                        actor.actorType(), path);
                return null;
            }
            if (!path.startsWith(STAFF_PATH_PREFIX)) {
                log.warn("binding rejected: staff token on non-staff path={}", path);
                return null;
            }
            return actor;
        }

        // --- 2. 쿠키 ---
        String cookieToken = readCookie(request, cookieProps.patientTokenName());
        if (cookieToken != null) {

            AuthenticatedActor actor = jwtIssuer.verify(cookieToken);
            if (actor == null) {
                return null;
            }

            // 쿠키는 PATIENT 전용이다. 직원 토큰을 쿠키에 실어도 여기서 막힌다.
            if (actor.actorType() != ActorType.PATIENT) {
                log.warn("binding rejected: cookie with actorType={} path={}",
                        actor.actorType(), path);
                return null;
            }
            if (!path.startsWith(PATIENT_PATH_PREFIX)) {
                log.warn("binding rejected: patient token on non-patient path={}", path);
                return null;
            }
            return actor;
        }

        // --- 3. 둘 다 없음 ---
        return null;
    }

    private String readCookie(HttpServletRequest request, String name) {
        Cookie[] cookies = request.getCookies();
        if (cookies == null) {
            return null;
        }
        for (Cookie c : cookies) {
            if (name.equals(c.getName()) && c.getValue() != null && !c.getValue().isBlank()) {
                return c.getValue();
            }
        }
        return null;
    }
}

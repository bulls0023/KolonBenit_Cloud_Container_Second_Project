package org.kuspital.bff;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.kuspital.bff.config.AppProperties;
import org.kuspital.bff.security.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.test.context.ActiveProfiles;

import com.nimbusds.jwt.SignedJWT;

import static org.junit.jupiter.api.Assertions.*;

/**
 * JWT 계약 검증. README v3.1 §6.5
 *
 * 이 테스트가 존재하는 이유:
 *   JWT 규격 위반은 런타임에 조용히 통과한다. TTL 이 8시간이어야 할
 *   환자 토큰이 30분이어도, roles 배열이 섞여 들어가도, 금지 claim 이
 *   들어가도 동작 자체는 한다. 계약 위반은 테스트로만 잡힌다.
 */
@SpringBootTest
@ActiveProfiles("test")
@DisplayName("JWT 및 보안 구성 계약")
class JwtContractTest {

    @Autowired JwtIssuer jwtIssuer;
    @Autowired SecurityFilterChain securityFilterChain;
    @Autowired AppProperties.Jwt jwtProps;
    @Autowired AppProperties.Cookie cookieProps;
    @Autowired AppProperties.Was wasProps;

    @Test
    @DisplayName("컨텍스트가 기동되고 설정이 바인딩된다")
    void contextLoads() {
        assertNotNull(securityFilterChain);
        assertEquals(30, jwtProps.patientTtl().toMinutes());
        assertEquals(8, jwtProps.staffTtl().toHours());
        // 계약값이다. hybrid-toy 가 아니다 (README §6.2)
        assertEquals("hybrid-toy-bff", jwtProps.issuer());
        assertEquals("hybrid-toy-api", jwtProps.audience());
        assertEquals("PATIENT_TOKEN", cookieProps.patientTokenName());
        assertEquals("/api/bff/patient", cookieProps.path());
        assertEquals(2000, wasProps.connectTimeoutMs());
        assertEquals(5000, wasProps.readTimeoutMs());
    }

    @Test
    @DisplayName("환자 토큰: HS256 / role 단수 / TTL 30분 / 금지 claim 없음")
    void patientToken() throws Exception {
        String token = jwtIssuer.issuePatient(42L);
        SignedJWT jwt = SignedJWT.parse(token);
        var c = jwt.getJWTClaimsSet();

        assertEquals("HS256", jwt.getHeader().getAlgorithm().getName());
        assertEquals("42", c.getSubject());
        assertEquals("PATIENT", c.getClaim("actor_type"));
        assertEquals("PATIENT", c.getClaim("role"));
        assertNull(c.getClaim("roles"), "roles 배열 사용 금지");

        long ttlMin = (c.getExpirationTime().getTime() - c.getIssueTime().getTime()) / 60000;
        assertEquals(30, ttlMin);

        for (String forbidden : new String[]{"name", "birth_date", "phone", "password"}) {
            assertNull(c.getClaim(forbidden), "금지 claim: " + forbidden);
        }
    }

    @Test
    @DisplayName("직원 토큰: TTL 8시간 / role 유지")
    void staffToken() throws Exception {
        String token = jwtIssuer.issueStaff(7L, Role.DOCTOR);
        var c = SignedJWT.parse(token).getJWTClaimsSet();

        assertEquals("STAFF", c.getClaim("actor_type"));
        assertEquals("DOCTOR", c.getClaim("role"));

        long ttlHours = (c.getExpirationTime().getTime() - c.getIssueTime().getTime()) / 3600000;
        assertEquals(8, ttlHours);
    }

    @Test
    @DisplayName("검증: 정상 토큰은 통과, 위조 토큰은 거부")
    void verify() {
        AuthenticatedActor actor = jwtIssuer.verify(jwtIssuer.issuePatient(1L));
        assertNotNull(actor);
        assertEquals(ActorType.PATIENT, actor.actorType());
        assertEquals(Role.PATIENT, actor.role());
        assertEquals("ROLE_PATIENT", actor.authority());

        assertNull(jwtIssuer.verify(null));
        assertNull(jwtIssuer.verify(""));
        assertNull(jwtIssuer.verify("not.a.jwt"));

        // 서명부만 바꾼 토큰
        String tampered = jwtIssuer.issuePatient(1L);
        tampered = tampered.substring(0, tampered.lastIndexOf('.') + 1) + "AAAAAAAA";
        assertNull(jwtIssuer.verify(tampered), "위조 서명이 통과했다");
    }

    @Test
    @DisplayName("환자 역할로 직원 토큰을 발급할 수 없다")
    void staffTokenRejectsPatientRole() {
        assertThrows(IllegalArgumentException.class,
                () -> jwtIssuer.issueStaff(1L, Role.PATIENT));
        assertThrows(IllegalArgumentException.class,
                () -> jwtIssuer.issueStaff(1L, null));
    }
}

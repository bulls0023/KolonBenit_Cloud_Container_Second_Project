package org.kuspital.bff;

import jakarta.servlet.http.Cookie;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.kuspital.bff.security.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.context.ActiveProfiles;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 전달수단 ↔ actor_type 바인딩 검증. README v3.1 §6.5
 *
 * 이 테스트가 존재하는 이유:
 *   서명 검증만으로는 뚫린다. 직원 JWT 를 쿠키에 넣어 환자 경로로 보내면
 *   서명·발급자·만료 검증을 전부 통과한다. 바인딩 규칙이 유일한 방어선이며,
 *   그 규칙은 런타임에 조용히 깨질 수 있다.
 *
 * WAS 없이 돈다. TokenResolver 는 외부 호출을 하지 않는다.
 */
@SpringBootTest
@ActiveProfiles("test")
@DisplayName("전달수단 바인딩 계약")
class BindingContractTest {

    @Autowired TokenResolver tokenResolver;
    @Autowired JwtIssuer jwtIssuer;

    private MockHttpServletRequest req(String path) {
        MockHttpServletRequest r = new MockHttpServletRequest();
        r.setRequestURI(path);
        return r;
    }

    private MockHttpServletRequest withBearer(String path, String token) {
        MockHttpServletRequest r = req(path);
        r.addHeader("Authorization", "Bearer " + token);
        return r;
    }

    private MockHttpServletRequest withCookie(String path, String token) {
        MockHttpServletRequest r = req(path);
        r.setCookies(new Cookie("PATIENT_TOKEN", token));
        return r;
    }

    @Test
    @DisplayName("정상: 환자 쿠키 + 환자 경로")
    void patientCookieOnPatientPath() {
        String token = jwtIssuer.issuePatient(1L);
        AuthenticatedActor actor = tokenResolver.resolve(
                withCookie("/api/bff/patient/appointments", token));

        assertNotNull(actor);
        assertEquals(ActorType.PATIENT, actor.actorType());
        assertEquals(1L, actor.id());
    }

    @Test
    @DisplayName("정상: 직원 Bearer + 직원 경로")
    void staffBearerOnStaffPath() {
        String token = jwtIssuer.issueStaff(7L, Role.DOCTOR);
        AuthenticatedActor actor = tokenResolver.resolve(
                withBearer("/api/bff/staff/patients", token));

        assertNotNull(actor);
        assertEquals(ActorType.STAFF, actor.actorType());
        assertEquals(Role.DOCTOR, actor.role());
    }

    @Test
    @DisplayName("차단: 직원 토큰을 쿠키로 - 서명은 유효하다")
    void staffTokenInCookieRejected() {
        String staffToken = jwtIssuer.issueStaff(7L, Role.DOCTOR);

        // 서명 자체는 통과한다. 바인딩만이 막는다.
        assertNotNull(jwtIssuer.verify(staffToken));

        assertNull(tokenResolver.resolve(
                withCookie("/api/bff/patient/appointments", staffToken)));
        assertNull(tokenResolver.resolve(
                withCookie("/api/bff/staff/patients", staffToken)));
    }

    @Test
    @DisplayName("차단: 환자 토큰을 Bearer 로")
    void patientTokenInBearerRejected() {
        String patientToken = jwtIssuer.issuePatient(1L);
        assertNotNull(jwtIssuer.verify(patientToken));

        assertNull(tokenResolver.resolve(
                withBearer("/api/bff/staff/patients", patientToken)));
        assertNull(tokenResolver.resolve(
                withBearer("/api/bff/patient/appointments", patientToken)));
    }

    @Test
    @DisplayName("차단: 경로 교차 - 환자 쿠키로 직원 경로")
    void crossPathRejected() {
        String patientToken = jwtIssuer.issuePatient(1L);
        assertNull(tokenResolver.resolve(
                withCookie("/api/bff/staff/patients", patientToken)));
    }

    @Test
    @DisplayName("차단: 토큰 없음 / 위조 / 빈 쿠키")
    void noTokenRejected() {
        assertNull(tokenResolver.resolve(req("/api/bff/patient/appointments")));
        assertNull(tokenResolver.resolve(
                withBearer("/api/bff/staff/patients", "forged.token.value")));
        assertNull(tokenResolver.resolve(
                withCookie("/api/bff/patient/appointments", "")));
    }

    @Test
    @DisplayName("Bearer 가 쿠키보다 우선한다")
    void bearerTakesPrecedence() {
        MockHttpServletRequest r = req("/api/bff/staff/patients");
        r.addHeader("Authorization", "Bearer " + jwtIssuer.issueStaff(9L, Role.NURSE));
        r.setCookies(new Cookie("PATIENT_TOKEN", jwtIssuer.issuePatient(1L)));

        AuthenticatedActor actor = tokenResolver.resolve(r);
        assertNotNull(actor);
        assertEquals(9L, actor.id());
        assertEquals(Role.NURSE, actor.role());
    }
}

package org.kuspital.bff.patient;

import jakarta.validation.Valid;
import org.kuspital.bff.client.WasClient;
import org.kuspital.bff.client.WasDtos;
import org.kuspital.bff.error.ApiException;
import org.kuspital.bff.error.ErrorCode;
import org.kuspital.bff.security.CookieFactory;
import org.kuspital.bff.security.JwtIssuer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.*;

/**
 * 환자 인증. README v3.1 §6.5 / §6.6
 *
 * 흐름: GET /auth/csrf → 쿠키 수신 → register/login 에 X-XSRF-TOKEN 헤더
 *       → 성공 시 PATIENT_TOKEN 쿠키 수신
 *
 * ⚠️ 요청 본문 전체를 로깅하지 않는다. 비밀번호가 로그에 남는다 (§6.1-11).
 */
@RestController
@RequestMapping("/api/bff/patient/auth")
public class PatientAuthController {

    private static final Logger log = LoggerFactory.getLogger(PatientAuthController.class);

    private final WasClient wasClient;
    private final JwtIssuer jwtIssuer;
    private final CookieFactory cookieFactory;

    public PatientAuthController(WasClient wasClient, JwtIssuer jwtIssuer,
                                 CookieFactory cookieFactory) {
        this.wasClient = wasClient;
        this.jwtIssuer = jwtIssuer;
        this.cookieFactory = cookieFactory;
    }

    /**
     * CSRF 토큰 발급.
     *
     * CsrfToken 을 파라미터로 받아 getToken() 을 호출해야 실제로 생성되고
     * 쿠키가 내려간다. Spring Security 6+ 는 토큰 생성을 지연시키므로,
     * 이 호출이 없으면 쿠키가 만들어지지 않는다.
     *
     * 본문을 주지 않는다. Web 은 XSRF-TOKEN 쿠키(HttpOnly=false)를 읽는다.
     */
    @GetMapping("/csrf")
    public ResponseEntity<Void> csrf(CsrfToken csrfToken) {
        csrfToken.getToken();
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/register")
    public ResponseEntity<PatientDtos.AuthResponse> register(
            @Valid @RequestBody PatientDtos.RegisterRequest request) {

        WasDtos.ActorResponse actor = wasClient.postAuth(
                "/internal/patient/auth/register",
                new WasDtos.PatientRegisterRequest(
                        request.loginId(), request.password(), request.name(),
                        request.birthDate(), request.phone()),
                WasDtos.ActorResponse.class);

        return issueCookie(actor, HttpStatus.CREATED);
    }

    @PostMapping("/login")
    public ResponseEntity<PatientDtos.AuthResponse> login(
            @Valid @RequestBody PatientDtos.LoginRequest request) {

        WasDtos.ActorResponse actor = wasClient.postAuth(
                "/internal/patient/auth/login",
                new WasDtos.LoginRequest(request.loginId(), request.password()),
                WasDtos.ActorResponse.class);

        return issueCookie(actor, HttpStatus.OK);
    }

    /**
     * 로그아웃. 쿠키를 만료시킨다.
     *
     * WAS 를 호출하지 않는다. WAS 는 토큰을 발급하지도 보관하지도 않으므로
     * 폐기할 상태가 없다. 로그아웃은 쿠키 제거로 완결된다.
     *
     * ⚠️ 토큰 폐기 목록(blocklist)은 미채택이다 (§6.5 백로그).
     *    만료 전 탈취된 토큰은 TTL(30분) 동안 유효하다. 알려진 한계다.
     */
    @PostMapping("/logout")
    public ResponseEntity<Void> logout() {
        return ResponseEntity.noContent()
                .header(HttpHeaders.SET_COOKIE, cookieFactory.expiredPatientToken().toString())
                .build();
    }

    private ResponseEntity<PatientDtos.AuthResponse> issueCookie(
            WasDtos.ActorResponse actor, HttpStatus status) {

        if (actor == null || actor.actorId() == null) {
            // WAS 가 2xx 를 주면서 신원을 비운 경우. 계약 위반이므로 500 이 맞다.
            log.error("WAS 인증 응답에 actor_id 가 없다");
            throw ApiException.of(ErrorCode.INTERNAL_ERROR, "처리 중 오류가 발생했습니다.");
        }

        String token = jwtIssuer.issuePatient(actor.actorId());

        return ResponseEntity.status(status)
                .header(HttpHeaders.SET_COOKIE, cookieFactory.patientToken(token).toString())
                .body(new PatientDtos.AuthResponse(actor.actorId(), actor.name()));
    }
}

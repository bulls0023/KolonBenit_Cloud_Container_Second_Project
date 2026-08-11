package org.kuspital.was.auth;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/**
 * 인증 API. README §6.6
 *
 *   POST /internal/patient/auth/register
 *   POST /internal/patient/auth/login
 *   POST /internal/staff/auth/login
 *
 * 이 3개 경로는 ActorHeaderFilter 의 검증 대상에서 제외된다.
 * 아직 신원이 없는 요청이기 때문이다.
 *
 * ⚠️ 로그아웃 API 가 없다. 토큰을 발급하지 않으므로 폐기할 것도 없다.
 *    로그아웃은 BFF 가 쿠키를 지우는 것으로 완결된다.
 * ⚠️ 요청 본문 전체를 로깅하지 않는다 (README §6.1-11). 비밀번호가 남는다.
 */
@RestController
public class AuthController {

    private final PatientAuthService patientAuthService;
    private final StaffAuthService staffAuthService;

    public AuthController(PatientAuthService patientAuthService,
                          StaffAuthService staffAuthService) {
        this.patientAuthService = patientAuthService;
        this.staffAuthService = staffAuthService;
    }

    @PostMapping("/internal/patient/auth/register")
    @ResponseStatus(HttpStatus.CREATED)
    public AuthDtos.ActorResponse registerPatient(
            @Valid @RequestBody AuthDtos.PatientRegisterRequest request) {
        return patientAuthService.register(request);
    }

    @PostMapping("/internal/patient/auth/login")
    public AuthDtos.ActorResponse loginPatient(
            @Valid @RequestBody AuthDtos.LoginRequest request) {
        return patientAuthService.login(request);
    }

    @PostMapping("/internal/staff/auth/login")
    public AuthDtos.ActorResponse loginStaff(
            @Valid @RequestBody AuthDtos.LoginRequest request) {
        return staffAuthService.login(request);
    }
}

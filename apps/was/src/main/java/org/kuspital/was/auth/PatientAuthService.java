package org.kuspital.was.auth;

import org.kuspital.was.domain.PatientUser;
import org.kuspital.was.error.ApiException;
import org.kuspital.was.error.ErrorCode;
import org.kuspital.was.repository.PatientUserRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Service
public class PatientAuthService {

    private final PatientUserRepository repository;
    private final PasswordEncoder passwordEncoder;
    private final int maxFailed;
    private final int lockMinutes;

    public PatientAuthService(PatientUserRepository repository,
                              PasswordEncoder passwordEncoder,
                              @Value("${app.auth.max-failed-login}") int maxFailed,
                              @Value("${app.auth.lock-minutes}") int lockMinutes) {
        this.repository = repository;
        this.passwordEncoder = passwordEncoder;
        this.maxFailed = maxFailed;
        this.lockMinutes = lockMinutes;
    }

    @Transactional
    public AuthDtos.ActorResponse register(AuthDtos.PatientRegisterRequest req) {

        if (req.birthDate() == null || !req.birthDate().isBefore(LocalDate.now())) {
            throw ApiException.of(ErrorCode.FUTURE_BIRTH_DATE, "생년월일을 확인해주세요.");
        }

        PatientUser user = new PatientUser(
                req.loginId(),
                passwordEncoder.encode(req.password()),
                req.name(),
                req.birthDate(),
                req.phone());

        try {
            repository.saveAndFlush(user);
        } catch (DataIntegrityViolationException e) {
            // 사전 existsByLoginId 체크만으로는 동시 요청 2건이 둘 다 통과한다.
            // DB UNIQUE 위반을 잡아 변환하는 것이 유일하게 옳다.
            throw ApiException.of(ErrorCode.PATIENT_EXISTS, "이미 사용 중인 아이디입니다.");
        }

        return AuthDtos.ActorResponse.patient(user.getPatientId(), user.getName());
    }

    @Transactional
    public AuthDtos.ActorResponse login(AuthDtos.LoginRequest req) {

        LocalDateTime now = LocalDateTime.now();

        PatientUser user = repository.findByLoginId(req.loginId())
                .orElseThrow(() -> ApiException.of(
                        ErrorCode.INVALID_CREDENTIALS,
                        "아이디 또는 비밀번호가 올바르지 않습니다."));

        if (user.isLocked(now)) {
            throw ApiException.of(ErrorCode.ACCOUNT_LOCKED,
                    "로그인 시도 초과로 잠겼습니다. 잠시 후 다시 시도해주세요.");
        }

        if (!passwordEncoder.matches(req.password(), user.getPasswordHash())) {
            user.recordLoginFailure(maxFailed, lockMinutes, now);
            // 계정 없음과 비밀번호 오류를 구분하지 않는다 (README §6.7)
            throw ApiException.of(ErrorCode.INVALID_CREDENTIALS,
                    "아이디 또는 비밀번호가 올바르지 않습니다.");
        }

        user.recordLoginSuccess();
        return AuthDtos.ActorResponse.patient(user.getPatientId(), user.getName());
    }
}

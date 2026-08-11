package org.kuspital.was.auth;

import org.kuspital.was.domain.StaffUser;
import org.kuspital.was.error.ApiException;
import org.kuspital.was.error.ErrorCode;
import org.kuspital.was.repository.StaffUserRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

@Service
public class StaffAuthService {

    private final StaffUserRepository repository;
    private final PasswordEncoder passwordEncoder;
    private final int maxFailed;
    private final int lockMinutes;

    public StaffAuthService(StaffUserRepository repository,
                            PasswordEncoder passwordEncoder,
                            @Value("${app.auth.max-failed-login}") int maxFailed,
                            @Value("${app.auth.lock-minutes}") int lockMinutes) {
        this.repository = repository;
        this.passwordEncoder = passwordEncoder;
        this.maxFailed = maxFailed;
        this.lockMinutes = lockMinutes;
    }

    /** 직원 가입 API 는 존재하지 않는다. seed 로만 생성된다 (README §6.8). */
    @Transactional
    public AuthDtos.ActorResponse login(AuthDtos.LoginRequest req) {

        LocalDateTime now = LocalDateTime.now();

        StaffUser user = repository.findByLoginId(req.loginId())
                .orElseThrow(() -> ApiException.of(
                        ErrorCode.INVALID_CREDENTIALS,
                        "아이디 또는 비밀번호가 올바르지 않습니다."));

        if (user.isLocked(now)) {
            throw ApiException.of(ErrorCode.ACCOUNT_LOCKED,
                    "로그인 시도 초과로 잠겼습니다. 잠시 후 다시 시도해주세요.");
        }

        // 비활성 계정도 invalid_credentials 로 응답한다.
        // "존재하지만 정지됨" 을 알려주면 계정 열거에 쓰인다.
        if (!user.isActive() || !passwordEncoder.matches(req.password(), user.getPasswordHash())) {
            if (user.isActive()) {
                user.recordLoginFailure(maxFailed, lockMinutes, now);
            }
            throw ApiException.of(ErrorCode.INVALID_CREDENTIALS,
                    "아이디 또는 비밀번호가 올바르지 않습니다.");
        }

        user.recordLoginSuccess();
        return AuthDtos.ActorResponse.staff(
                user.getStaffId(), user.getRole().name(),
                user.getName(), user.isMustChangePassword());
    }
}

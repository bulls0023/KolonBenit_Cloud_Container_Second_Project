package org.kuspital.was.auth;

import org.kuspital.was.domain.PatientUser;
import org.kuspital.was.domain.StaffUser;
import org.kuspital.was.repository.PatientUserRepository;
import org.kuspital.was.repository.StaffUserRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

/**
 * 로그인 실패 카운터. README v3.1 §6.5 (5회 실패 시 30분 잠금)
 *
 * [왜 별도 서비스인가]
 *   인증 실패는 예외로 응답한다. 그런데 예외는 트랜잭션을 롤백한다.
 *   같은 트랜잭션 안에서 카운터를 올리고 예외를 던지면
 *   **카운터 증가가 함께 사라진다.** 잠금이 영원히 작동하지 않는다.
 *   조용히 실패하는 유형이라 테스트 없이는 드러나지 않는다 (실측 확인).
 *
 *   REQUIRES_NEW 로 독립 트랜잭션을 열어 즉시 커밋한다.
 *   바깥 트랜잭션이 롤백돼도 카운터는 남는다.
 *
 * [자기호출 금지]
 *   같은 클래스 안의 메서드를 호출하면 프록시를 타지 않아
 *   REQUIRES_NEW 가 무시된다. 반드시 별도 빈이어야 한다.
 */
@Service
public class LoginAttemptService {

    private final PatientUserRepository patientRepository;
    private final StaffUserRepository staffRepository;
    private final int maxFailed;
    private final int lockMinutes;

    public LoginAttemptService(PatientUserRepository patientRepository,
                               StaffUserRepository staffRepository,
                               @Value("${app.auth.max-failed-login}") int maxFailed,
                               @Value("${app.auth.lock-minutes}") int lockMinutes) {
        this.patientRepository = patientRepository;
        this.staffRepository = staffRepository;
        this.maxFailed = maxFailed;
        this.lockMinutes = lockMinutes;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordPatientFailure(Long patientId) {
        PatientUser user = patientRepository.findById(patientId).orElse(null);
        if (user != null) {
            user.recordLoginFailure(maxFailed, lockMinutes, LocalDateTime.now());
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordStaffFailure(Long staffId) {
        StaffUser user = staffRepository.findById(staffId).orElse(null);
        if (user != null) {
            user.recordLoginFailure(maxFailed, lockMinutes, LocalDateTime.now());
        }
    }
}

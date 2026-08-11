package org.kuspital.was.domain;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * 직원 계정. README §6.8
 *   - 셀프 가입 없음. seed SQL 로만 생성된다.
 *   - app_was 에는 이 테이블의 INSERT / DELETE 권한이 없다 (§12.3).
 *     UPDATE 는 잠금 카운터 갱신 용도로만 부여되어 있다.
 */
@Entity
@Table(name = "staff_user")
public class StaffUser {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "staff_id")
    private Long staffId;

    @Column(name = "login_id", nullable = false, length = 50, unique = true)
    private String loginId;

    @Column(name = "password_hash", nullable = false, length = 60)
    private String passwordHash;

    @Column(name = "name", nullable = false, length = 50)
    private String name;

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false)
    private StaffRole role;

    @Column(name = "department", length = 50)
    private String department;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private StaffStatus status;

    @Column(name = "must_change_password", nullable = false)
    private boolean mustChangePassword;

    @Column(name = "failed_login_count", nullable = false)
    private int failedLoginCount;

    @Column(name = "locked_until")
    private LocalDateTime lockedUntil;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    protected StaffUser() {
    }

    /** 로그인 가능 상태인가. ACTIVE 만 허용한다. */
    public boolean isActive() {
        return status == StaffStatus.ACTIVE;
    }

    public boolean isLocked(LocalDateTime now) {
        return lockedUntil != null && lockedUntil.isAfter(now);
    }

    public void recordLoginFailure(int maxFailed, int lockMinutes, LocalDateTime now) {
        this.failedLoginCount++;
        if (this.failedLoginCount >= maxFailed) {
            this.lockedUntil = now.plusMinutes(lockMinutes);
        }
    }

    public void recordLoginSuccess() {
        this.failedLoginCount = 0;
        this.lockedUntil = null;
    }

    public Long getStaffId()             { return staffId; }
    public String getLoginId()           { return loginId; }
    public String getPasswordHash()      { return passwordHash; }
    public String getName()              { return name; }
    public StaffRole getRole()           { return role; }
    public String getDepartment()        { return department; }
    public StaffStatus getStatus()       { return status; }
    public boolean isMustChangePassword(){ return mustChangePassword; }
    public int getFailedLoginCount()     { return failedLoginCount; }
    public LocalDateTime getLockedUntil(){ return lockedUntil; }
}

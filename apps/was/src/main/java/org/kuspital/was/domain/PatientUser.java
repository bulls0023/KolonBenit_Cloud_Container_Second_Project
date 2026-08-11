package org.kuspital.was.domain;

import jakarta.persistence.*;
import java.time.LocalDate;
import java.time.LocalDateTime;

/** 환자 계정. README §6.8 - PK 는 patient_id (id 아님). */
@Entity
@Table(name = "patient_user")
public class PatientUser {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "patient_id")
    private Long patientId;

    @Column(name = "login_id", nullable = false, length = 50, unique = true)
    private String loginId;

    /** BCrypt 해시만 저장한다. 평문 컬럼은 존재하지 않는다. */
    @Column(name = "password_hash", nullable = false, length = 60)
    private String passwordHash;

    @Column(name = "name", nullable = false, length = 50)
    private String name;

    @Column(name = "birth_date", nullable = false)
    private LocalDate birthDate;

    @Column(name = "phone", length = 20)
    private String phone;

    @Column(name = "failed_login_count", nullable = false)
    private int failedLoginCount;

    @Column(name = "locked_until")
    private LocalDateTime lockedUntil;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime updatedAt;

    protected PatientUser() {
    }

    public PatientUser(String loginId, String passwordHash, String name,
                       LocalDate birthDate, String phone) {
        this.loginId = loginId;
        this.passwordHash = passwordHash;
        this.name = name;
        this.birthDate = birthDate;
        this.phone = phone;
        this.failedLoginCount = 0;
    }

    /** 잠금 여부. README §6.5 - 잠금 중 요청은 423. */
    public boolean isLocked(LocalDateTime now) {
        return lockedUntil != null && lockedUntil.isAfter(now);
    }

    /** 로그인 실패 누적. 임계치 도달 시 잠금 시각을 설정한다. */
    public void recordLoginFailure(int maxFailed, int lockMinutes, LocalDateTime now) {
        this.failedLoginCount++;
        if (this.failedLoginCount >= maxFailed) {
            this.lockedUntil = now.plusMinutes(lockMinutes);
        }
    }

    /** 로그인 성공. 카운트 0, 잠금 해제. */
    public void recordLoginSuccess() {
        this.failedLoginCount = 0;
        this.lockedUntil = null;
    }

    public Long getPatientId()          { return patientId; }
    public String getLoginId()          { return loginId; }
    public String getPasswordHash()     { return passwordHash; }
    public String getName()             { return name; }
    public LocalDate getBirthDate()     { return birthDate; }
    public String getPhone()            { return phone; }
    public int getFailedLoginCount()    { return failedLoginCount; }
    public LocalDateTime getLockedUntil(){ return lockedUntil; }
    public LocalDateTime getCreatedAt() { return createdAt; }
}

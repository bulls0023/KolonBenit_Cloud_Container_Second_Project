package org.kuspital.was.domain;

/**
 * 직원 역할. README v3.1 §6.5 - 이 3종만 사용한다.
 * PATIENT 는 patient_user 계층에서 부여하므로 여기 없다.
 * RECEPTION / BILLING / ADMIN 은 미사용 (계약에서 폐기됨).
 */
public enum StaffRole {
    DOCTOR,
    NURSE,
    ADMIN_STAFF;

    /** 차트·처방 작성 권한. README §6.5 - DOCTOR 전용. */
    public boolean canWriteChart() {
        return this == DOCTOR;
    }
}

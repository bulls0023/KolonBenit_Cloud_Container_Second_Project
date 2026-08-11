package org.kuspital.was.web;

import org.kuspital.was.domain.StaffRole;

/**
 * BFF 가 전달한 인증 신원. README §6.6
 *
 * 이 값은 BFF 가 JWT 검증 후 새로 생성한 헤더에서 온다.
 * 외부가 보낸 X-Actor-* 는 BFF 가 먼저 제거한다.
 * WAS 는 이 값을 인증된 사용자로 사용하며, body 의 patient_id 를 신뢰하지 않는다.
 */
public record Actor(Type type, Long id, String role) {

    public enum Type { PATIENT, STAFF }

    /** 요청 속성 키. ActorHeaderFilter 가 설정하고 컨트롤러가 읽는다. */
    public static final String ATTRIBUTE = "kuspital.actor";

    public boolean isPatient() {
        return type == Type.PATIENT;
    }

    public boolean isStaff() {
        return type == Type.STAFF;
    }

    public StaffRole staffRole() {
        return isStaff() ? StaffRole.valueOf(role) : null;
    }

    public boolean isDoctor() {
        return isStaff() && StaffRole.DOCTOR.name().equals(role);
    }
}

package org.kuspital.bff.security;

/**
 * 역할. README §6.5 - 이 4종만 사용한다.
 * RECEPTION / BILLING / ADMIN 미사용.
 */
public enum Role {

    PATIENT(ActorType.PATIENT),
    DOCTOR(ActorType.STAFF),
    NURSE(ActorType.STAFF),
    ADMIN_STAFF(ActorType.STAFF);

    private final ActorType actorType;

    Role(ActorType actorType) {
        this.actorType = actorType;
    }

    public ActorType actorType() {
        return actorType;
    }

    /** Spring Security 권한명. ROLE_ 접두사 필수. */
    public String authority() {
        return "ROLE_" + name();
    }

    public static Role parse(String value) {
        if (value == null) {
            return null;
        }
        for (Role r : values()) {
            if (r.name().equals(value)) {
                return r;
            }
        }
        return null;   // 미상 역할은 null. 호출부가 401 로 처리한다.
    }
}

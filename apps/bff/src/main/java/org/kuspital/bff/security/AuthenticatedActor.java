package org.kuspital.bff.security;

/**
 * 검증이 끝난 신원. JWT claim 에서만 만들어진다.
 *
 * ⚠️ 이름·생년월일 등 개인정보를 담지 않는다.
 *    JWT 금지 claim 목록과 동일하다 (README §6.5).
 */
public record AuthenticatedActor(Long id, ActorType actorType, Role role) {

    public String authority() {
        return role.authority();
    }
}

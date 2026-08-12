package org.kuspital.bff.staff;

import jakarta.validation.constraints.NotBlank;

public final class StaffDtos {

    private StaffDtos() {
    }

    public record LoginRequest(
            @NotBlank String loginId,
            @NotBlank String password) {
    }

    /**
     * 직원 인증 응답.
     *
     * 직원 토큰은 Bearer 로 전달한다. OKD Web 이 서버사이드에 보관하며
     * 브라우저에 노출하지 않는다 (§6.5 책임 분리표).
     */
    public record LoginResponse(
            String accessToken,
            String tokenType,
            long expiresIn,
            Long actorId,
            String role,
            String name,
            Boolean mustChangePassword) {
    }
}

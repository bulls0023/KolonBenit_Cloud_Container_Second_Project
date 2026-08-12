package org.kuspital.bff.patient;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 환자 API 요청·응답 DTO.
 *
 * 요청은 BFF 에서 1차 검증한 뒤 WAS 로 넘긴다. WAS 가 2차 검증한다.
 * 응답 중 업무 데이터는 WAS 응답을 그대로 통과시키므로 DTO 가 없다.
 */
public final class PatientDtos {

    private PatientDtos() {
    }

    public record RegisterRequest(
            @NotBlank @Size(min = 4, max = 50) String loginId,
            @NotBlank @Size(min = 8, max = 72) String password,
            @NotBlank @Size(max = 50) String name,
            @NotBlank String birthDate,
            @Size(max = 20) String phone) {
    }

    public record LoginRequest(
            @NotBlank String loginId,
            @NotBlank String password) {
    }

    /**
     * 환자 인증 응답.
     *
     * ⚠️ 토큰 필드가 없다. 환자 JWT 는 HttpOnly 쿠키로만 전달한다.
     *    응답 JSON 이나 localStorage 에 넣으면 HttpOnly 의 의미가 사라진다 (§6.5).
     */
    public record AuthResponse(Long actorId, String name) {
    }
}

package org.kuspital.was.auth;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Past;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;

/**
 * 인증 요청·응답 DTO.
 *
 * ⚠️ 응답에 토큰이 없다. README §16-12 / §21-13 -
 *    WAS 는 JWT 를 발급하지 않는다. BFF 가 이 응답을 받아 토큰을 만든다.
 *    여기에 accessToken 같은 필드를 추가하면 계약 위반이다.
 *
 * JSON 은 SNAKE_CASE 전역 설정으로 변환된다 (birthDate -> birth_date).
 */
public final class AuthDtos {

    private AuthDtos() {
    }

    public record PatientRegisterRequest(
            @NotBlank @Size(min = 4, max = 50) String loginId,
            @NotBlank @Size(min = 8, max = 72) String password,
            @NotBlank @Size(max = 50) String name,
            @Past LocalDate birthDate,
            @Size(max = 20) String phone) {
    }

    public record LoginRequest(
            @NotBlank String loginId,
            @NotBlank String password) {
    }

    /** 로그인 성공 응답. 토큰 없음. BFF 가 이 정보로 JWT 를 만든다. */
    public record ActorResponse(
            Long actorId,
            String actorType,
            String role,
            String name,
            Boolean mustChangePassword) {

        public static ActorResponse patient(Long id, String name) {
            return new ActorResponse(id, "PATIENT", "PATIENT", name, null);
        }

        public static ActorResponse staff(Long id, String role, String name,
                                          boolean mustChangePassword) {
            return new ActorResponse(id, "STAFF", role, name, mustChangePassword);
        }
    }
}

package org.kuspital.bff.client;

/**
 * WAS 와 주고받는 최소 DTO.
 *
 * ⚠️ 여기에는 **인증에 필요한 것만** 둔다.
 *    업무 API 응답은 문자열로 통과시킨다. BFF 가 예약·차트·처방 DTO 를
 *    다시 정의하면 WAS 와 두 곳에서 관리하게 되고, 필드 하나가 추가될 때마다
 *    양쪽을 고쳐야 한다. 반드시 어긋난다.
 *
 * JSON snake_case <-> Java camelCase 는 전역 SNAKE_CASE 설정이 처리한다.
 */
public final class WasDtos {

    private WasDtos() {
    }

    /**
     * WAS 인증 API 응답. README §6.5
     *
     * ⚠️ 토큰이 없다. WAS 는 JWT 를 발급하지 않는다 (§16-12).
     *    BFF 가 이 정보로 JWT 를 만든다.
     */
    public record ActorResponse(
            Long actorId,
            String actorType,
            String role,
            String name,
            Boolean mustChangePassword) {
    }

    /** WAS 로 그대로 전달하는 환자 가입 요청. */
    public record PatientRegisterRequest(
            String loginId,
            String password,
            String name,
            String birthDate,
            String phone) {
    }

    public record LoginRequest(
            String loginId,
            String password) {
    }
}

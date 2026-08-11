package org.kuspital.was.error;

/**
 * 공통 오류 형식. README §6.7 - 예외 없음.
 *   { "error": "...", "message": "...", "trace_id": "..." }
 *
 * traceId -> trace_id 변환은 spring.jackson.property-naming-strategy=SNAKE_CASE 가
 * 전역으로 처리한다. @JsonProperty 를 개별 부착하지 않는다.
 *
 * 성공 응답에는 trace_id 를 넣지 않는다.
 */
public record ApiErrorResponse(String error, String message, String traceId) {
}

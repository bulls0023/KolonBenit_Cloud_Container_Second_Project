package org.kuspital.bff.error;

/**
 * 공통 오류 형식. README §6.7
 *   { "error": "...", "message": "...", "trace_id": "..." }
 *
 * 성공 응답에는 trace_id 를 넣지 않는다.
 */
public record ApiErrorResponse(String error, String message, String traceId) {
}

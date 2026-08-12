package org.kuspital.bff.error;

import org.springframework.http.HttpStatus;

/**
 * 오류 코드. README v3.1 §6.7 - WAS 와 동일한 표를 쓴다.
 *
 * BFF 는 WAS 의 400/401/404/409/423 을 계약된 상태·본문 그대로 전달하고,
 * WAS 의 500·연결 실패·타임아웃만 503 upstream_unavailable 로 변환한다 (§6.6).
 */
public enum ErrorCode {

    VALIDATION_ERROR("validation_error", HttpStatus.BAD_REQUEST),
    INVALID_STATUS("invalid_status", HttpStatus.BAD_REQUEST),
    INVALID_DATE("invalid_date", HttpStatus.BAD_REQUEST),
    FUTURE_BIRTH_DATE("future_birth_date", HttpStatus.BAD_REQUEST),

    UNAUTHORIZED("unauthorized", HttpStatus.UNAUTHORIZED),
    INVALID_CREDENTIALS("invalid_credentials", HttpStatus.UNAUTHORIZED),

    FORBIDDEN("forbidden", HttpStatus.FORBIDDEN),
    NOT_FOUND("not_found", HttpStatus.NOT_FOUND),

    DUPLICATE_BOOKING("duplicate_booking", HttpStatus.CONFLICT),
    SLOT_TAKEN("slot_taken", HttpStatus.CONFLICT),
    PATIENT_EXISTS("patient_exists", HttpStatus.CONFLICT),
    DUPLICATE_PRESCRIPTION("duplicate_prescription", HttpStatus.CONFLICT),

    ACCOUNT_LOCKED("account_locked", HttpStatus.LOCKED),
    RATE_LIMITED("rate_limited", HttpStatus.TOO_MANY_REQUESTS),

    INTERNAL_ERROR("internal_error", HttpStatus.INTERNAL_SERVER_ERROR),
    EXTERNAL_API_ERROR("external_api_error", HttpStatus.BAD_GATEWAY),
    UPSTREAM_UNAVAILABLE("upstream_unavailable", HttpStatus.SERVICE_UNAVAILABLE);

    private final String code;
    private final HttpStatus status;

    ErrorCode(String code, HttpStatus status) {
        this.code = code;
        this.status = status;
    }

    public String code()       { return code; }
    public HttpStatus status() { return status; }
}

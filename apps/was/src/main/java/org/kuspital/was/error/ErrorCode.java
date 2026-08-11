package org.kuspital.was.error;

import org.springframework.http.HttpStatus;

/**
 * 오류 코드. README v3.1 §6.7 - 계약된 코드만 존재한다.
 * 새 코드를 추가하려면 README §6.7 표를 먼저 고친다.
 */
public enum ErrorCode {

    VALIDATION_ERROR("validation_error", HttpStatus.BAD_REQUEST),
    INVALID_STATUS("invalid_status", HttpStatus.BAD_REQUEST),
    INVALID_DATE("invalid_date", HttpStatus.BAD_REQUEST),
    FUTURE_BIRTH_DATE("future_birth_date", HttpStatus.BAD_REQUEST),

    UNAUTHORIZED("unauthorized", HttpStatus.UNAUTHORIZED),
    /** 계정 없음과 비밀번호 오류를 구분하지 않는다 (README §6.7). */
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

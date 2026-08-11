package org.kuspital.was.error;

/** 계약된 오류를 던지는 유일한 예외 타입. */
public class ApiException extends RuntimeException {

    private final ErrorCode errorCode;

    public ApiException(ErrorCode errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public ErrorCode errorCode() {
        return errorCode;
    }

    public static ApiException of(ErrorCode code, String message) {
        return new ApiException(code, message);
    }
}

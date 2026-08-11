package org.kuspital.was.error;

import org.kuspital.was.web.TraceIdFilter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingRequestHeaderException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * 모든 오류 응답을 단일 형식으로 통일한다.
 *
 * ⚠️ 스택트레이스·SQL·테이블명·내부 호스트명을 응답에 포함하지 않는다 (README §6.7).
 *    메시지는 상수 또는 사용자 대상 문구만 쓴다. 예외의 getMessage() 를 그대로
 *    내보내면 Hibernate 가 SQL 을 통째로 담아 보내는 경우가 있다.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiErrorResponse> handleApi(ApiException e) {
        return build(e.errorCode(), e.getMessage());
    }

    /** @Valid 실패. 어떤 필드가 틀렸는지는 로그로만 남긴다. */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiErrorResponse> handleInvalid(MethodArgumentNotValidException e) {
        log.info("validation failed: {}", e.getBindingResult().getAllErrors());
        return build(ErrorCode.VALIDATION_ERROR, "입력값이 올바르지 않습니다.");
    }

    @ExceptionHandler(HandlerMethodValidationException.class)
    public ResponseEntity<ApiErrorResponse> handleParamInvalid(HandlerMethodValidationException e) {
        return build(ErrorCode.VALIDATION_ERROR, "입력값이 올바르지 않습니다.");
    }

    /** 본문 파싱 실패 / 타입 불일치. */
    @ExceptionHandler({ HttpMessageNotReadableException.class,
                        MethodArgumentTypeMismatchException.class })
    public ResponseEntity<ApiErrorResponse> handleUnreadable(Exception e) {
        return build(ErrorCode.VALIDATION_ERROR, "요청 형식이 올바르지 않습니다.");
    }

    /** 필수 헤더 누락. ActorHeaderFilter 가 먼저 막지만 이중 방어로 둔다. */
    @ExceptionHandler(MissingRequestHeaderException.class)
    public ResponseEntity<ApiErrorResponse> handleMissingHeader(MissingRequestHeaderException e) {
        return build(ErrorCode.FORBIDDEN, "요청 권한을 확인할 수 없습니다.");
    }

    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<ApiErrorResponse> handleNoResource(NoResourceFoundException e) {
        return build(ErrorCode.NOT_FOUND, "요청한 리소스를 찾을 수 없습니다.");
    }

    /** 최후 방어선. 원인은 로그에만 남긴다. */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiErrorResponse> handleAny(Exception e) {
        log.error("unhandled exception", e);
        return build(ErrorCode.INTERNAL_ERROR, "처리 중 오류가 발생했습니다.");
    }

    private ResponseEntity<ApiErrorResponse> build(ErrorCode code, String message) {
        String traceId = MDC.get(TraceIdFilter.MDC_KEY);
        return ResponseEntity.status(code.status())
                .body(new ApiErrorResponse(code.code(), message, traceId));
    }
}

package org.kuspital.bff.error;

import org.kuspital.bff.filter.TraceIdFilter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * 오류 응답 통일. README v3.1 §6.6 / §6.7
 *
 * [WAS 오류 전달 원칙]
 *   4xx  계약된 오류다. **상태와 본문을 그대로 올린다.**
 *        BFF 가 본문을 다시 만들면 메시지를 두 곳에서 관리하게 되어 어긋난다.
 *        WAS 본문의 trace_id 는 BFF 가 전달한 값과 같다 - WasClient 가
 *        X-Trace-Id 를 넘기기 때문이다. 그래서 그대로 올려도 추적이 이어진다.
 *   5xx / 연결 실패 / 타임아웃  503 upstream_unavailable 로 변환한다.
 *        WAS 의 내부 사정을 외부에 노출하지 않는다.
 *
 * ⚠️ 스택트레이스·SQL·내부 호스트명을 응답에 포함하지 않는다.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    /**
     * WAS 오류. status 가 -1 이면 연결 실패·타임아웃·5xx 다.
     */
    @ExceptionHandler(UpstreamException.class)
    public ResponseEntity<String> handleUpstream(UpstreamException e) {

        if (e.status() < 0 || e.body() == null) {
            return raw(ErrorCode.UPSTREAM_UNAVAILABLE,
                    "일시적으로 서비스를 이용할 수 없습니다.");
        }

        // 계약된 4xx - 있는 그대로 전달한다
        return ResponseEntity.status(e.status())
                .contentType(MediaType.APPLICATION_JSON)
                .body(e.body());
    }

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<String> handleApi(ApiException e) {
        return raw(e.errorCode(), e.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<String> handleInvalid(MethodArgumentNotValidException e) {
        log.info("validation failed: {}", e.getBindingResult().getAllErrors());
        return raw(ErrorCode.VALIDATION_ERROR, "입력값이 올바르지 않습니다.");
    }

    @ExceptionHandler({ HandlerMethodValidationException.class,
                        HttpMessageNotReadableException.class,
                        MethodArgumentTypeMismatchException.class,
                        MissingServletRequestParameterException.class })
    public ResponseEntity<String> handleBadRequest(Exception e) {
        return raw(ErrorCode.VALIDATION_ERROR, "요청 형식이 올바르지 않습니다.");
    }

    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<String> handleNoResource(NoResourceFoundException e) {
        return raw(ErrorCode.NOT_FOUND, "요청한 리소스를 찾을 수 없습니다.");
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<String> handleAny(Exception e) {
        log.error("unhandled exception", e);
        return raw(ErrorCode.INTERNAL_ERROR, "처리 중 오류가 발생했습니다.");
    }

    /**
     * 계약 형식 JSON 을 직접 만든다.
     *
     * 컨트롤러 반환형이 ResponseEntity<String>(통과 전달) 이므로,
     * 오류도 같은 타입으로 맞춘다. 타입이 갈리면 @ExceptionHandler 가
     * 통과 전달 경로와 충돌한다.
     */
    private ResponseEntity<String> raw(ErrorCode code, String message) {

        String traceId = MDC.get(TraceIdFilter.MDC_KEY);

        String json = "{\"error\":\"" + code.code() + "\","
                    + "\"message\":\"" + escape(message) + "\","
                    + "\"trace_id\":" + (traceId == null ? "null" : "\"" + traceId + "\"") + "}";

        return ResponseEntity.status(code.status())
                .contentType(MediaType.APPLICATION_JSON)
                .body(json);
    }

    private String escape(String s) {
        if (s == null) {
            return "";
        }
        return s.replace("\\", "\\\\").replace("\"", "\\\"")
                .replace("\n", " ").replace("\r", " ");
    }
}

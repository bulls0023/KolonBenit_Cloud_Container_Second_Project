package org.kuspital.was.web;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

/**
 * trace_id 전파. README §6.7
 *
 * BFF 가 요청마다 UUID 를 생성한다. WAS 는 그 값을 이어받아 로그와 오류 JSON 에
 * 동일하게 실어 BFF·WAS 로그 대조가 가능하게 한다.
 *
 * 헤더가 없으면 (BFF 를 거치지 않은 직접 호출) 자체 생성한다. 정상 경로에서는
 * 발생하지 않아야 하며, 발생한다면 BFF 구성이 잘못된 것이다.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class TraceIdFilter extends OncePerRequestFilter {

    public static final String HEADER  = "X-Trace-Id";
    public static final String MDC_KEY = "trace_id";

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {

        String traceId = request.getHeader(HEADER);
        if (traceId == null || traceId.isBlank()) {
            traceId = UUID.randomUUID().toString();
        }

        MDC.put(MDC_KEY, traceId);
        response.setHeader(HEADER, traceId);

        try {
            chain.doFilter(request, response);
        } finally {
            // 가상 스레드는 요청마다 새로 만들어지지만, 캐리어 스레드 재사용 시
            // MDC 가 남을 수 있다. 반드시 지운다.
            MDC.remove(MDC_KEY);
        }
    }
}

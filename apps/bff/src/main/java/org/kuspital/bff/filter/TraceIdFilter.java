package org.kuspital.bff.filter;

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
 * trace_id 생성. README v3.1 §6.7
 *
 * ⚠️ BFF 가 요청마다 UUID 를 생성한다.
 *    **외부가 보낸 X-Trace-Id 는 신뢰하지 않는다.** 무조건 새로 만든다.
 *    외부 값을 이어받으면 공격자가 로그를 오염시키거나 다른 사용자의
 *    요청과 뒤섞어 추적을 방해할 수 있다.
 *    WAS 쪽 TraceIdFilter 는 BFF 가 준 값을 이어받는다 - 역할이 다르다.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class TraceIdFilter extends OncePerRequestFilter {

    public static final String HEADER = "X-Trace-Id";
    public static final String MDC_KEY = "trace_id";

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {

        String traceId = UUID.randomUUID().toString();

        MDC.put(MDC_KEY, traceId);
        response.setHeader(HEADER, traceId);

        try {
            chain.doFilter(request, response);
        } finally {
            MDC.remove(MDC_KEY);
        }
    }
}

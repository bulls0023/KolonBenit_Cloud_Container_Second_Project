package org.kuspital.bff.filter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.*;

/**
 * 외부가 보낸 X-Actor-* 제거. README v3.1 §6.6 위조 방어 1번 원칙.
 *
 * [공격 시나리오] 공격자가 직접 아래를 보낸다.
 *     GET /api/bff/staff/patients
 *     X-Actor-Type: STAFF
 *     X-Actor-Id: 1
 *     X-Actor-Role: DOCTOR
 *   BFF 가 이 헤더를 그대로 WAS 로 흘리면 WAS 는 정상 요청으로 본다.
 *   JWT 검증을 아무리 잘해도 헤더가 통과하면 무의미하다.
 *
 * [구현] 제거는 요청 래핑으로 한다. Servlet API 는 요청 헤더 삭제를
 *   지원하지 않으므로, 해당 헤더가 존재하지 않는 것처럼 보이는 래퍼를 씌운다.
 *
 * ⚠️ 순서가 중요하다. TraceIdFilter 다음, 인증 필터보다 앞이어야 한다.
 *   이 필터 뒤의 모든 코드는 X-Actor-* 를 볼 수 없다.
 *   WAS 로 나가는 헤더는 WasClient 가 JWT 검증 결과로 새로 만든다.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 5)
public class InboundActorHeaderStripFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(InboundActorHeaderStripFilter.class);

    private static final Set<String> STRIPPED = Set.of(
            "x-actor-type", "x-actor-id", "x-actor-role");

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {

        boolean found = false;
        for (String h : STRIPPED) {
            if (request.getHeader(h) != null) {
                found = true;
                break;
            }
        }

        if (found) {
            // 정상 클라이언트는 이 헤더를 보내지 않는다. 보냈다면 기록한다.
            log.warn("inbound X-Actor-* stripped: path={} remote={}",
                    request.getRequestURI(), request.getRemoteAddr());
        }

        chain.doFilter(new StrippingRequest(request), response);
    }

    private static final class StrippingRequest extends HttpServletRequestWrapper {

        StrippingRequest(HttpServletRequest request) {
            super(request);
        }

        @Override
        public String getHeader(String name) {
            return isStripped(name) ? null : super.getHeader(name);
        }

        @Override
        public Enumeration<String> getHeaders(String name) {
            return isStripped(name)
                    ? Collections.emptyEnumeration()
                    : super.getHeaders(name);
        }

        @Override
        public Enumeration<String> getHeaderNames() {
            List<String> names = new ArrayList<>();
            Enumeration<String> original = super.getHeaderNames();
            while (original.hasMoreElements()) {
                String n = original.nextElement();
                if (!isStripped(n)) {
                    names.add(n);
                }
            }
            return Collections.enumeration(names);
        }

        private boolean isStripped(String name) {
            return name != null && STRIPPED.contains(name.toLowerCase(Locale.ROOT));
        }
    }
}

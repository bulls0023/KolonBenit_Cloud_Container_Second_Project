package org.kuspital.was.web;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.kuspital.was.domain.StaffRole;
import org.kuspital.was.error.ErrorCode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

/**
 * 신원 헤더 2차 검증. README §6.6 - "BFF 가 1차 방어선, WAS 가 최종 방어선이다."
 *
 * 검증 항목
 *   1. 필수 헤더 3종 존재
 *   2. 경로 <-> actor_type 일치  (/internal/patient/** 는 PATIENT 만)
 *   3. 경로 <-> role 일치        (/internal/staff/admin/** 는 ADMIN_STAFF 만)
 *   위반 시 전부 403 forbidden.
 *
 * 제외 경로
 *   /healthz, /readyz  - probe
 *   /internal/*&#47;auth/*  - 인증 API. 아직 신원이 없다 (README §6.6-6)
 *
 * [구현 주의] 여기서 Jackson 을 쓰지 않고 JSON 을 직접 만든다.
 *   필터는 MVC 메시지 컨버터 밖에서 동작하므로 ObjectMapper 주입이 불필요한
 *   결합을 만든다. 응답 형식이 3필드 고정이라 문자열 조립으로 충분하다.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class ActorHeaderFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(ActorHeaderFilter.class);

    private static final String H_TYPE = "X-Actor-Type";
    private static final String H_ID   = "X-Actor-Id";
    private static final String H_ROLE = "X-Actor-Role";

    private static final String PATIENT_PREFIX     = "/internal/patient/";
    private static final String STAFF_PREFIX       = "/internal/staff/";
    private static final String STAFF_ADMIN_PREFIX = "/internal/staff/admin/";

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();

        if ("/healthz".equals(path) || "/readyz".equals(path)) {
            return true;
        }
        // 인증 API 는 신원 헤더 없이 도달한다
        return path.startsWith("/internal/patient/auth/")
            || path.startsWith("/internal/staff/auth/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {

        String path = request.getRequestURI();

        String rawType = request.getHeader(H_TYPE);
        String rawId   = request.getHeader(H_ID);
        String rawRole = request.getHeader(H_ROLE);

        if (isBlank(rawType) || isBlank(rawId) || isBlank(rawRole)) {
            deny(response, path, "필수 신원 헤더 누락");
            return;
        }

        Actor.Type type;
        Long id;
        try {
            type = Actor.Type.valueOf(rawType.trim());
            id   = Long.valueOf(rawId.trim());
        } catch (IllegalArgumentException e) {
            deny(response, path, "신원 헤더 형식 오류");
            return;
        }

        String role = rawRole.trim();

        // --- 경로 <-> actor_type 일치 ---
        if (path.startsWith(PATIENT_PREFIX)) {
            if (type != Actor.Type.PATIENT || !"PATIENT".equals(role)) {
                deny(response, path, "환자 경로에 비환자 신원");
                return;
            }
        } else if (path.startsWith(STAFF_PREFIX)) {
            if (type != Actor.Type.STAFF || !isStaffRole(role)) {
                deny(response, path, "직원 경로에 비직원 신원");
                return;
            }
            if (path.startsWith(STAFF_ADMIN_PREFIX)
                    && !StaffRole.ADMIN_STAFF.name().equals(role)) {
                deny(response, path, "관리자 경로에 일반 직원 신원");
                return;
            }
        } else {
            deny(response, path, "알 수 없는 내부 경로");
            return;
        }

        request.setAttribute(Actor.ATTRIBUTE, new Actor(type, id, role));
        chain.doFilter(request, response);
    }

    private boolean isStaffRole(String role) {
        for (StaffRole r : StaffRole.values()) {
            if (r.name().equals(role)) {
                return true;
            }
        }
        return false;
    }

    private static boolean isBlank(String s) {
        return s == null || s.isBlank();
    }

    /**
     * 403 응답. 왜 거부됐는지는 로그에만 남긴다.
     * 응답 본문에 담으면 공격자에게 헤더 규칙을 알려주는 셈이 된다.
     */
    private void deny(HttpServletResponse response, String path, String reason)
            throws IOException {

        log.warn("actor header rejected: path={} reason={}", path, reason);

        String traceId = MDC.get(TraceIdFilter.MDC_KEY);

        String json = "{\"error\":\"" + ErrorCode.FORBIDDEN.code() + "\","
                    + "\"message\":\"요청 권한을 확인할 수 없습니다.\","
                    + "\"trace_id\":" + (traceId == null ? "null" : "\"" + traceId + "\"") + "}";

        // ⚠️ getWriter() + 암묵 flush 에 의존하지 않는다.
        //    필터는 DispatcherServlet 밖에서 응답을 직접 만든다. 인코딩 협상과
        //    커밋 시점이 컨테이너 구현에 좌우되어, 상태코드는 403 인데
        //    본문이 비어 나가는 경우가 생긴다.
        //    바이트를 직접 만들고 Content-Length 를 명시한 뒤 즉시 flush 한다.
        byte[] body = json.getBytes(StandardCharsets.UTF_8);

        // reset() 은 TraceIdFilter 가 넣은 X-Trace-Id 헤더까지 지운다. 다시 넣는다.
        response.reset();
        if (traceId != null) {
            response.setHeader(TraceIdFilter.HEADER, traceId);
        }
        response.setStatus(ErrorCode.FORBIDDEN.status().value());
        response.setContentType("application/json");
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.setContentLength(body.length);
        response.getOutputStream().write(body);
        response.flushBuffer();
    }
}

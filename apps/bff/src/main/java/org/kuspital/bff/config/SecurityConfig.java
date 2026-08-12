package org.kuspital.bff.config;

import org.kuspital.bff.error.ErrorCode;
import org.kuspital.bff.filter.JwtAuthenticationFilter;
import org.kuspital.bff.filter.TraceIdFilter;
import org.kuspital.bff.security.Role;
import org.slf4j.MDC;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;
import org.springframework.security.web.csrf.CsrfTokenRequestAttributeHandler;

import java.nio.charset.StandardCharsets;

/**
 * Spring Security 정책. README v3.1 §6.5 / §6.6
 *
 * | 경로                                    | 정책          |
 * |----------------------------------------|--------------|
 * | /healthz, /readyz                      | permitAll    |
 * | GET  /api/bff/patient/auth/csrf        | permitAll    |
 * | POST /api/bff/patient/auth/register    | permitAll + CSRF |
 * | POST /api/bff/patient/auth/login       | permitAll + CSRF |
 * | POST /api/bff/staff/auth/login         | permitAll    |
 * | /api/bff/patient/**                    | PATIENT      |
 * | /api/bff/staff/admin/**                | ADMIN_STAFF  |
 * | /api/bff/staff/**                      | DOCTOR/NURSE/ADMIN_STAFF |
 * | 나머지                                  | 거부          |
 *
 * [CSRF] 환자 경로에만 적용한다. 직원 Bearer 경로는 대상 제외 (§6.5).
 *   쿠키 기반 인증만 CSRF 에 취약하다. Bearer 는 브라우저가 자동으로
 *   실어보내지 않으므로 CSRF 가 성립하지 않는다.
 *
 * [세션] STATELESS. BFF 는 세션을 만들지 않는다. 상태는 JWT 에만 있다.
 *
 * [CORS] 구성하지 않는다. 환자 Web 과 API 가 동일 도메인이다 (§6.9 / §21-25).
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final AppProperties.Cookie cookieProps;

    public SecurityConfig(JwtAuthenticationFilter jwtAuthenticationFilter,
                          AppProperties.Cookie cookieProps) {
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
        this.cookieProps = cookieProps;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {

        http
            .csrf(csrf -> {
                CookieCsrfTokenRepository repo = CookieCsrfTokenRepository.withHttpOnlyFalse();
                repo.setCookieName(cookieProps.csrfTokenName());
                repo.setCookiePath(cookieProps.path());
                repo.setCookieCustomizer(c -> {
                    c.secure(cookieProps.secure());
                    c.sameSite("Lax");
                });

                // ⚠️ AntPathRequestMatcher / MvcRequestMatcher 는 Spring Security 7 에서
                //    제거됐다. 대체는 PathPatternRequestMatcher 지만, 문자열 오버로드로
                //    충분한 경우 굳이 matcher 객체를 만들지 않는다.
                //    (Security 7 의 Java DSL 은 URI 가 절대경로일 것을 요구한다.
                //     아래는 전부 / 로 시작하므로 조건을 만족한다.)
                csrf.csrfTokenRepository(repo)
                    .csrfTokenRequestHandler(new CsrfTokenRequestAttributeHandler())
                    // 직원 경로는 Bearer 전용이므로 CSRF 대상이 아니다 (§6.5).
                    .ignoringRequestMatchers("/api/bff/staff/**", "/healthz", "/readyz");
            })
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .httpBasic(b -> b.disable())
            .formLogin(f -> f.disable())
            .logout(l -> l.disable())
            .anonymous(a -> a.disable())

            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/healthz", "/readyz").permitAll()

                .requestMatchers(HttpMethod.GET,  "/api/bff/patient/auth/csrf").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/bff/patient/auth/register").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/bff/patient/auth/login").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/bff/patient/auth/logout").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/bff/staff/auth/login").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/bff/staff/auth/logout").permitAll()

                // 순서가 중요하다. admin 을 staff 보다 먼저 선언해야 한다.
                .requestMatchers("/api/bff/staff/admin/**")
                        .hasAuthority(Role.ADMIN_STAFF.authority())
                .requestMatchers("/api/bff/staff/**")
                        .hasAnyAuthority(Role.DOCTOR.authority(),
                                         Role.NURSE.authority(),
                                         Role.ADMIN_STAFF.authority())
                .requestMatchers("/api/bff/patient/**")
                        .hasAuthority(Role.PATIENT.authority())

                .anyRequest().denyAll())

            .exceptionHandling(e -> e
                .authenticationEntryPoint((req, res, ex) ->
                        write(res, ErrorCode.UNAUTHORIZED, "인증이 필요합니다."))
                .accessDeniedHandler((req, res, ex) ->
                        write(res, ErrorCode.FORBIDDEN, "접근 권한이 없습니다.")))

            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    /**
     * Security 계층의 오류도 §6.7 공통 형식으로 낸다.
     *
     * ⚠️ Security 는 DispatcherServlet 밖에서 응답을 만들므로
     *    @RestControllerAdvice 가 개입하지 못한다. 여기서 직접 써야 한다.
     *    WAS 의 ActorHeaderFilter 와 동일한 이유·동일한 방식이다.
     */
    private void write(jakarta.servlet.http.HttpServletResponse res,
                       ErrorCode code, String message) throws java.io.IOException {

        // ⚠️ trace_id 확보 순서: MDC -> 응답 헤더 -> 신규 생성.
        //    어느 경로로든 null 을 내보내지 않는다.
        //    추적 불가 오류 응답은 장애 대응에서 가장 비싼 형태다.
        String traceId = MDC.get(TraceIdFilter.MDC_KEY);
        if (traceId == null) {
            traceId = res.getHeader(TraceIdFilter.HEADER);
        }
        if (traceId == null) {
            traceId = java.util.UUID.randomUUID().toString();
        }

        String json = "{\"error\":\"" + code.code() + "\","
                    + "\"message\":\"" + message + "\","
                    + "\"trace_id\":\"" + traceId + "\"}";

        byte[] body = json.getBytes(StandardCharsets.UTF_8);

        // ⚠️ res.reset() 을 호출하지 않는다.
        //    reset() 은 이미 설정된 모든 헤더를 지운다. TraceIdFilter 의
        //    X-Trace-Id 와 Spring Security 가 큐에 넣은 Set-Cookie 가 함께 사라진다.
        //    실측: CSRF 403 응답에 X-Trace-Id 가 없고 trace_id 가 null 이었다.
        //    상태와 본문만 덮어쓰면 충분하다.
        res.setHeader(TraceIdFilter.HEADER, traceId);
        res.setStatus(code.status().value());
        res.setContentType("application/json");
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        res.setContentLength(body.length);
        res.getOutputStream().write(body);
        res.flushBuffer();
    }
}

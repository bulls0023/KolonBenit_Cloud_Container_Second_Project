package org.kuspital.bff.filter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.kuspital.bff.security.AuthenticatedActor;
import org.kuspital.bff.security.TokenResolver;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * JWT → SecurityContext 변환. README v3.1 §6.5
 *
 * 이 필터는 판정하지 않는다. TokenResolver 가 서명·바인딩까지 끝낸 결과를
 * Spring Security 가 이해하는 형태로 옮길 뿐이다.
 *
 * ⚠️ 인증 실패 시 여기서 401 을 던지지 않는다.
 *    SecurityContext 를 비워둔 채 통과시키고, 접근 판정은
 *    SecurityConfig 의 authorizeHttpRequests 가 한다.
 *    permitAll 경로(로그인·헬스체크)는 토큰이 없는 것이 정상이므로,
 *    여기서 막으면 로그인 자체가 불가능해진다.
 *
 * ⚠️ Principal 로 AuthenticatedActor 를 그대로 넣는다.
 *    컨트롤러가 @AuthenticationPrincipal 로 바로 받는다.
 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final TokenResolver tokenResolver;

    public JwtAuthenticationFilter(TokenResolver tokenResolver) {
        this.tokenResolver = tokenResolver;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {

        AuthenticatedActor actor = tokenResolver.resolve(request);

        if (actor != null) {
            var auth = new UsernamePasswordAuthenticationToken(
                    actor,
                    null,
                    List.of(new SimpleGrantedAuthority(actor.authority())));
            auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
            SecurityContextHolder.getContext().setAuthentication(auth);
        }

        try {
            chain.doFilter(request, response);
        } finally {
            // 가상 스레드 환경에서 컨텍스트가 남지 않도록 명시적으로 비운다.
            SecurityContextHolder.clearContext();
        }
    }
}

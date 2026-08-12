package org.kuspital.bff.staff;

import jakarta.validation.Valid;
import org.kuspital.bff.client.WasClient;
import org.kuspital.bff.client.WasDtos;
import org.kuspital.bff.config.AppProperties;
import org.kuspital.bff.error.ApiException;
import org.kuspital.bff.error.ErrorCode;
import org.kuspital.bff.security.JwtIssuer;
import org.kuspital.bff.security.Role;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * 직원 인증. README v3.1 §6.5 / §6.6
 *
 * 직원 토큰은 Bearer 로 전달한다. 쿠키를 쓰지 않는다.
 * OKD Web 이 서버사이드에 보관하고 브라우저에 노출하지 않는다.
 *
 * ⚠️ 이 경로는 Cloudflare Access + Tunnel 을 통해서만 도달한다.
 *    ALB 에 등록하지 않는다 (§6.9). Access JWT 검증은 대시보드 설정으로
 *    cloudflared 가 수행하며, 애플리케이션 코드가 아니다 (§7.10).
 */
@RestController
@RequestMapping("/api/bff/staff/auth")
public class StaffAuthController {

    private static final Logger log = LoggerFactory.getLogger(StaffAuthController.class);

    private final WasClient wasClient;
    private final JwtIssuer jwtIssuer;
    private final AppProperties.Jwt jwtProps;

    public StaffAuthController(WasClient wasClient, JwtIssuer jwtIssuer,
                               AppProperties.Jwt jwtProps) {
        this.wasClient = wasClient;
        this.jwtIssuer = jwtIssuer;
        this.jwtProps = jwtProps;
    }

    @PostMapping("/login")
    public StaffDtos.LoginResponse login(@Valid @RequestBody StaffDtos.LoginRequest request) {

        WasDtos.ActorResponse actor = wasClient.postAuth(
                "/internal/staff/auth/login",
                new WasDtos.LoginRequest(request.loginId(), request.password()),
                WasDtos.ActorResponse.class);

        if (actor == null || actor.actorId() == null) {
            log.error("WAS 인증 응답에 actor_id 가 없다");
            throw ApiException.of(ErrorCode.INTERNAL_ERROR, "처리 중 오류가 발생했습니다.");
        }

        Role role = Role.parse(actor.role());
        if (role == null) {
            // WAS 가 계약에 없는 역할을 줬다. 토큰을 만들면 안 된다.
            log.error("WAS 가 알 수 없는 역할을 반환했다: {}", actor.role());
            throw ApiException.of(ErrorCode.INTERNAL_ERROR, "처리 중 오류가 발생했습니다.");
        }

        String token = jwtIssuer.issueStaff(actor.actorId(), role);

        return new StaffDtos.LoginResponse(
                token,
                "Bearer",
                jwtProps.staffTtlHours() * 3600L,
                actor.actorId(),
                role.name(),
                actor.name(),
                actor.mustChangePassword());
    }

    /**
     * 로그아웃.
     *
     * 서버가 할 일이 없다. 폐기 목록이 미채택이므로 토큰은 TTL(8시간)까지
     * 유효하다. OKD Web 이 보관 중인 토큰을 버리는 것이 실제 로그아웃이다.
     * 클라이언트가 명시적으로 호출할 수 있도록 경로만 유지한다 (§6.6).
     */
    @PostMapping("/logout")
    public ResponseEntity<Map<String, String>> logout() {
        return ResponseEntity.ok(Map.of("message", "로그아웃 되었습니다."));
    }
}

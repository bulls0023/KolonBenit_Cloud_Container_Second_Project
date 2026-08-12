package org.kuspital.bff.health;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * 헬스 체크. README v3.1 §6.1 / §7.9
 *
 *   /healthz  프로세스 생존
 *   /readyz   BFF 자체 준비 상태
 *
 * ⚠️ readyz 는 WAS 상태를 확인하지 않는다. 이것이 핵심이다.
 *    상위 서비스의 readiness 에 하위 서비스 상태를 넣으면 종속이 전파된다.
 *    WAS 가 잠깐 죽으면 BFF 파드가 전부 NotReady 로 빠지고,
 *    WAS 가 살아나도 BFF 가 트래픽을 받기까지 추가 지연이 생긴다.
 *    WAS 장애는 요청 시점에 503 upstream_unavailable 로 처리한다 (§6.6).
 *
 * ⚠️ BFF 는 DB 커넥션이 없다. 확인할 하위 자원 자체가 없다.
 */
@RestController
public class HealthController {

    @GetMapping("/healthz")
    public Map<String, String> healthz() {
        return Map.of("status", "ok");
    }

    @GetMapping("/readyz")
    public Map<String, String> readyz() {
        return Map.of("status", "ok");
    }
}

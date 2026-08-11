package org.kuspital.was.health;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.sql.DataSource;
import java.sql.Connection;
import java.util.Map;

/**
 * 헬스 체크. README §6.1
 *
 *   /healthz  프로세스 생존만 본다. liveness probe 대상.
 *   /readyz   DB 커넥션까지 본다. readiness probe 대상.
 *
 * ⚠️ /readyz 에 외부 API 나 상위 서비스 상태를 넣지 않는다.
 *    README §7.9 / §7.11 - 종속 전파를 만들면 하나가 죽을 때 전부 죽는다.
 * ⚠️ actuator 를 쓰지 않는다. 노출 범위 통제가 더 단순하다.
 */
@RestController
public class HealthController {

    private final DataSource dataSource;

    public HealthController(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @GetMapping("/healthz")
    public Map<String, String> healthz() {
        return Map.of("status", "ok");
    }

    @GetMapping("/readyz")
    public ResponseEntity<Map<String, String>> readyz() {
        try (Connection conn = dataSource.getConnection()) {
            if (conn.isValid(2)) {
                return ResponseEntity.ok(Map.of("status", "ok", "db", "up"));
            }
        } catch (Exception e) {
            // 예외 내용을 응답에 담지 않는다. JDBC URL 과 호스트명이 새어나간다.
        }
        return ResponseEntity.status(503).body(Map.of("status", "unavailable", "db", "down"));
    }
}

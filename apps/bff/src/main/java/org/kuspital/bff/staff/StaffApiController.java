package org.kuspital.bff.staff;

import org.kuspital.bff.client.WasClient;
import org.kuspital.bff.security.AuthenticatedActor;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * 직원 업무 API. README v3.1 §6.6
 *
 * 경로 4개로 진료·처방 시나리오가 완결된다. 신규 경로를 추가하지 않는다 (§7.12).
 *
 * [권한] SecurityConfig 가 경로 단위로 1차 판정한다.
 *   DOCTOR 전용인 차트 작성은 WAS 의 ChartService 가 최종 판정한다.
 *   BFF 에서 role 을 다시 검사하지 않는다 - 판정 지점이 둘이면 어긋난다.
 */
@RestController
@RequestMapping("/api/bff/staff")
public class StaffApiController {

    private final WasClient wasClient;

    public StaffApiController(WasClient wasClient) {
        this.wasClient = wasClient;
    }

    @GetMapping("/patients")
    public ResponseEntity<String> patients(
            @AuthenticationPrincipal AuthenticatedActor actor,
            @RequestParam(required = false) String date) {

        if (date == null) {
            return json(wasClient.get("/internal/staff/patients", actor));
        }
        return json(wasClient.get("/internal/staff/patients?date={date}", actor, date));
    }

    @GetMapping("/patients/{visitNo}/chart")
    public ResponseEntity<String> chart(
            @AuthenticationPrincipal AuthenticatedActor actor,
            @PathVariable String visitNo) {

        return json(wasClient.get("/internal/staff/patients/{visitNo}/chart", actor, visitNo));
    }

    /**
     * 상병코드 검색.
     *
     * ⚠️ q 를 직접 인코딩하지 않는다. URI 템플릿 변수로 넘긴다.
     *    UriUtils.encodeQueryParam 으로 미리 인코딩하면 RestClient 가 한 번 더
     *    인코딩해 '%' 가 '%25' 가 된다. WAS 는 '%EB%8B%B9...' 라는 리터럴로
     *    검색하게 되어 한글 검색이 조용히 0건이 된다 (실측 확인).
     */
    @GetMapping("/icd-codes")
    public ResponseEntity<String> icdCodes(
            @AuthenticationPrincipal AuthenticatedActor actor,
            @RequestParam(name = "q") String q) {

        return json(wasClient.get("/internal/staff/icd-codes?q={q}", actor, q));
    }

    @PostMapping("/charts")
    public ResponseEntity<String> createChart(
            @AuthenticationPrincipal AuthenticatedActor actor,
            @RequestBody Map<String, Object> body) {

        return json(wasClient.post("/internal/staff/charts", body, actor), 201);
    }

    private ResponseEntity<String> json(String body) {
        return json(body, 200);
    }

    private ResponseEntity<String> json(String body, int status) {
        return ResponseEntity.status(status)
                .contentType(MediaType.APPLICATION_JSON)
                .body(body == null ? "null" : body);
    }
}

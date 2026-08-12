package org.kuspital.bff.patient;

import org.kuspital.bff.client.WasClient;
import org.kuspital.bff.security.AuthenticatedActor;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * 환자 업무 API. README v3.1 §6.6
 *
 * [통과 전달] WAS 응답 JSON 을 그대로 내보낸다.
 *   BFF 가 DTO 를 다시 정의하면 필드 추가마다 양쪽을 고쳐야 하고 반드시 어긋난다.
 *   BFF 의 책임은 인증·인가·라우팅이지 도메인 모델링이 아니다.
 *
 * [신원] @AuthenticationPrincipal 로 검증된 신원을 받는다.
 *   요청 파라미터의 patient_id 를 받지 않는다. WasClient 가 X-Actor-Id 를
 *   만들어 보내고, WAS 가 그것으로 필터한다 (§6.6 위조 방어 4번).
 */
@RestController
@RequestMapping("/api/bff/patient")
public class PatientApiController {

    private final WasClient wasClient;

    public PatientApiController(WasClient wasClient) {
        this.wasClient = wasClient;
    }

    @GetMapping("/doctors")
    public ResponseEntity<String> doctors(@AuthenticationPrincipal AuthenticatedActor actor) {
        return json(wasClient.get("/internal/patient/doctors", actor));
    }

    @GetMapping("/slots")
    public ResponseEntity<String> slots(
            @AuthenticationPrincipal AuthenticatedActor actor,
            @RequestParam Long doctorId,
            @RequestParam(required = false) String date) {

        if (date == null) {
            return json(wasClient.get("/internal/patient/slots?doctorId={d}", actor, doctorId));
        }
        return json(wasClient.get("/internal/patient/slots?doctorId={d}&date={dt}",
                actor, doctorId, date));
    }

    @PostMapping("/appointments")
    public ResponseEntity<String> book(
            @AuthenticationPrincipal AuthenticatedActor actor,
            @RequestBody Map<String, Object> body) {

        return json(wasClient.post("/internal/patient/appointments", body, actor), 201);
    }

    @GetMapping("/appointments")
    public ResponseEntity<String> appointments(@AuthenticationPrincipal AuthenticatedActor actor) {
        return json(wasClient.get("/internal/patient/appointments", actor));
    }

    @PatchMapping("/appointments/{visitNo}")
    public ResponseEntity<String> updateAppointment(
            @AuthenticationPrincipal AuthenticatedActor actor,
            @PathVariable String visitNo,
            @RequestBody Map<String, Object> body) {

        return json(wasClient.patch("/internal/patient/appointments/{visitNo}", body, actor, visitNo));
    }

    @GetMapping("/records")
    public ResponseEntity<String> records(@AuthenticationPrincipal AuthenticatedActor actor) {
        return json(wasClient.get("/internal/patient/records", actor));
    }

    @GetMapping("/prescriptions")
    public ResponseEntity<String> prescriptions(@AuthenticationPrincipal AuthenticatedActor actor) {
        return json(wasClient.get("/internal/patient/prescriptions", actor));
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

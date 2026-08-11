package org.kuspital.was.biz;

import jakarta.validation.Valid;
import org.kuspital.was.web.Actor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;

/**
 * 직원 업무 API. README §6.6 - 이 4개 경로로 진료·처방 시나리오가 완결된다.
 * 신규 경로를 추가하지 않는다 (README §7.12 / §16-20).
 */
@RestController
@RequestMapping("/internal/staff")
public class StaffApiController {

    private final AppointmentService appointmentService;
    private final ChartService chartService;
    private final IcdSearchService icdSearchService;

    public StaffApiController(AppointmentService appointmentService,
                              ChartService chartService,
                              IcdSearchService icdSearchService) {
        this.appointmentService = appointmentService;
        this.chartService = chartService;
        this.icdSearchService = icdSearchService;
    }

    /** 당일 예약 목록. DOCTOR / NURSE 공통. */
    @GetMapping("/patients")
    public List<BizDtos.StaffPatientResponse> patients(
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        return appointmentService.findDailyPatients(date);
    }

    /** 차트 + 처방 + 항목을 한 번에 반환. 미작성이면 404. */
    @GetMapping("/patients/{visitNo}/chart")
    public BizDtos.ChartResponse chart(@PathVariable String visitNo) {
        return chartService.getByVisitNo(visitNo);
    }

    /** 상병코드 검색. q 는 2자 이상. 상한 50건. */
    @GetMapping("/icd-codes")
    public List<BizDtos.IcdCodeResponse> icdCodes(@RequestParam(name = "q") String q) {
        return icdSearchService.search(q);
    }

    /**
     * 차트 + 처방 발급. DOCTOR 전용.
     * 권한 판정은 ChartService 안에서 한다 - 서비스 단독 호출에도 방어가 걸리도록.
     */
    @PostMapping("/charts")
    @ResponseStatus(HttpStatus.CREATED)
    public BizDtos.ChartResponse createChart(
            @RequestAttribute(Actor.ATTRIBUTE) Actor actor,
            @Valid @RequestBody BizDtos.CreateChartRequest request) {
        return chartService.create(actor, request);
    }
}

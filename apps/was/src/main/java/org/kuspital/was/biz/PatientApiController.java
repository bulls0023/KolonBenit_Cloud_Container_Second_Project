package org.kuspital.was.biz;

import jakarta.validation.Valid;
import org.kuspital.was.web.Actor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;

/**
 * 환자 업무 API. README §6.6
 *
 * ⚠️ 모든 조회는 Actor.id() 로 필터한다. 요청 파라미터의 patient_id 를 받지 않는다.
 *    Actor 는 ActorHeaderFilter 가 검증 후 넣은 값이다.
 */
@RestController
@RequestMapping("/internal/patient")
public class PatientApiController {

    private final AppointmentService appointmentService;
    private final ChartService chartService;

    public PatientApiController(AppointmentService appointmentService,
                                ChartService chartService) {
        this.appointmentService = appointmentService;
        this.chartService = chartService;
    }

    @GetMapping("/doctors")
    public List<BizDtos.DoctorResponse> doctors() {
        return appointmentService.findDoctors();
    }

    @GetMapping("/slots")
    public List<BizDtos.SlotResponse> slots(
            @RequestParam Long doctorId,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        return appointmentService.findSlots(doctorId, date);
    }

    @PostMapping("/appointments")
    @ResponseStatus(HttpStatus.CREATED)
    public BizDtos.AppointmentResponse book(
            @RequestAttribute(Actor.ATTRIBUTE) Actor actor,
            @Valid @RequestBody BizDtos.CreateAppointmentRequest request) {
        return appointmentService.book(actor.id(), request);
    }

    @GetMapping("/appointments")
    public List<BizDtos.AppointmentResponse> myAppointments(
            @RequestAttribute(Actor.ATTRIBUTE) Actor actor) {
        return appointmentService.findMyAppointments(actor.id());
    }

    /**
     * 예약 변경. 현재는 취소만 지원한다.
     * status 에 CANCELLED 외의 값이 오면 400 invalid_status.
     */
    @PatchMapping("/appointments/{visitNo}")
    public BizDtos.AppointmentResponse cancel(
            @RequestAttribute(Actor.ATTRIBUTE) Actor actor,
            @PathVariable String visitNo,
            @Valid @RequestBody BizDtos.UpdateAppointmentRequest request) {

        if (!"CANCELLED".equalsIgnoreCase(request.status())) {
            throw org.kuspital.was.error.ApiException.of(
                    org.kuspital.was.error.ErrorCode.INVALID_STATUS,
                    "지원하지 않는 상태 변경입니다.");
        }
        return appointmentService.cancel(actor.id(), visitNo);
    }

    @GetMapping("/records")
    public List<BizDtos.ChartResponse> records(
            @RequestAttribute(Actor.ATTRIBUTE) Actor actor) {
        return chartService.findRecords(actor.id());
    }

    @GetMapping("/prescriptions")
    public List<BizDtos.ChartResponse> prescriptions(
            @RequestAttribute(Actor.ATTRIBUTE) Actor actor) {
        return chartService.findPrescriptions(actor.id());
    }
}

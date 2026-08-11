package org.kuspital.was.biz;

import org.kuspital.was.domain.*;
import org.kuspital.was.error.ApiException;
import org.kuspital.was.error.ErrorCode;
import org.kuspital.was.repository.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * 예약. README §6.8
 *
 * [동시성] DB UNIQUE 제약이 본선이다.
 *   uk_appt_active_slot    -> 409 slot_taken
 *   uk_appt_active_patient -> 409 duplicate_booking
 *   두 제약 모두 "취소되면 NULL 이 되는 생성 컬럼" 에 걸려 있어
 *   취소 후 재예약이 정상 동작한다.
 */
@Service
public class AppointmentService {

    private static final DateTimeFormatter VISIT_DATE = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final AppointmentRepository appointmentRepository;
    private final DoctorSlotRepository slotRepository;
    private final DoctorRepository doctorRepository;
    private final PatientUserRepository patientRepository;
    private final ChartRepository chartRepository;
    private final String visitNoPrefix;

    public AppointmentService(AppointmentRepository appointmentRepository,
                              DoctorSlotRepository slotRepository,
                              DoctorRepository doctorRepository,
                              PatientUserRepository patientRepository,
                              ChartRepository chartRepository,
                              @Value("${app.appointment.visit-no-prefix}") String visitNoPrefix) {
        this.appointmentRepository = appointmentRepository;
        this.slotRepository = slotRepository;
        this.doctorRepository = doctorRepository;
        this.patientRepository = patientRepository;
        this.chartRepository = chartRepository;
        this.visitNoPrefix = visitNoPrefix;
    }

    // -----------------------------------------------------------------
    // 환자
    // -----------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<BizDtos.DoctorResponse> findDoctors() {
        return doctorRepository.findAllActiveWithStaff().stream()
                .map(d -> new BizDtos.DoctorResponse(
                        d.getDoctorId(), d.getStaff().getName(), d.getDepartment(),
                        d.getSpecialty(), d.getRoomNo()))
                .toList();
    }

    /**
     * 예약 가능 슬롯.
     *
     * ⚠️ 시작점은 "그날 00:00" 이 아니라 "그날 00:00 과 지금 중 늦은 쪽" 이다.
     *    날짜 범위로만 자르면 오늘 조회 시 이미 지나간 시간대가 목록에 뜬다.
     *    화면에는 예약 가능으로 보이는데 누르면 400 invalid_date 가 나는 상태가 된다.
     *    book() 의 과거 시각 검증과 판정 기준을 반드시 일치시킨다.
     */
    @Transactional(readOnly = true)
    public List<BizDtos.SlotResponse> findSlots(Long doctorId, LocalDate date) {

        LocalDate target = date == null ? LocalDate.now() : date;
        LocalDateTime now = LocalDateTime.now();

        LocalDateTime from = target.atStartOfDay();
        if (from.isBefore(now)) {
            from = now;
        }
        LocalDateTime to = target.plusDays(1).atStartOfDay();

        // 지난 날짜를 조회하면 from > to 가 되어 빈 목록이 나온다. 정상 동작이다.
        if (!from.isBefore(to)) {
            return List.of();
        }

        return slotRepository.findAvailable(doctorId, from, to).stream()
                .map(s -> new BizDtos.SlotResponse(s.getSlotId(), s.getSlotAt()))
                .toList();
    }

    @Transactional
    public BizDtos.AppointmentResponse book(Long patientId,
                                            BizDtos.CreateAppointmentRequest req) {

        PatientUser patient = patientRepository.findById(patientId)
                .orElseThrow(() -> ApiException.of(ErrorCode.NOT_FOUND, "환자를 찾을 수 없습니다."));

        DoctorSlot slot = slotRepository.findById(req.slotId())
                .orElseThrow(() -> ApiException.of(ErrorCode.NOT_FOUND, "진료 슬롯을 찾을 수 없습니다."));

        if (!slot.isOpen()) {
            throw ApiException.of(ErrorCode.INVALID_STATUS, "예약할 수 없는 시간입니다.");
        }
        if (slot.getSlotAt().isBefore(LocalDateTime.now())) {
            throw ApiException.of(ErrorCode.INVALID_DATE, "지난 시간은 예약할 수 없습니다.");
        }

        Appointment appointment =
                new Appointment(nextVisitNo(), patient, slot, req.symptom());

        try {
            appointmentRepository.saveAndFlush(appointment);
        } catch (DataIntegrityViolationException e) {
            throw translateBookingConflict(e);
        }

        return toResponse(appointment);
    }

    @Transactional
    public BizDtos.AppointmentResponse cancel(Long patientId, String visitNo) {

        Appointment appointment = appointmentRepository.findByVisitNo(visitNo)
                .orElseThrow(() -> ApiException.of(ErrorCode.NOT_FOUND, "예약을 찾을 수 없습니다."));

        // 본인 예약이 아니면 존재 자체를 알리지 않는다. 403 이 아니라 404 다.
        if (!appointment.getPatient().getPatientId().equals(patientId)) {
            throw ApiException.of(ErrorCode.NOT_FOUND, "예약을 찾을 수 없습니다.");
        }
        if (appointment.getStatus() != AppointmentStatus.BOOKED) {
            throw ApiException.of(ErrorCode.INVALID_STATUS, "취소할 수 없는 상태입니다.");
        }

        appointment.cancel();
        return toResponse(appointment);
    }

    @Transactional(readOnly = true)
    public List<BizDtos.AppointmentResponse> findMyAppointments(Long patientId) {
        return appointmentRepository.findByPatientWithDoctor(patientId).stream()
                .map(this::toResponse)
                .toList();
    }

    // -----------------------------------------------------------------
    // 직원
    // -----------------------------------------------------------------

    /** GET /internal/staff/patients - 당일 예약 목록. */
    @Transactional(readOnly = true)
    public List<BizDtos.StaffPatientResponse> findDailyPatients(LocalDate date) {

        LocalDate target = date == null ? LocalDate.now() : date;

        return appointmentRepository.findDailyForStaff(
                        target.atStartOfDay(), target.plusDays(1).atStartOfDay())
                .stream()
                .map(a -> new BizDtos.StaffPatientResponse(
                        a.getVisitNo(),
                        a.getPatient().getPatientId(),
                        a.getPatient().getName(),
                        a.getPatient().getBirthDate(),
                        a.getSlotAt(),
                        a.getStatus().name(),
                        a.getSymptom(),
                        chartRepository.existsByVisitNo(a.getVisitNo())))
                .toList();
    }

    // -----------------------------------------------------------------

    /**
     * 접수번호 채번. V20260810-0007
     *
     * ⚠️ count 기반이므로 동시 생성 시 충돌할 수 있다.
     *    visit_no 의 UNIQUE 제약이 최종 방어선이며, 충돌 시 409 로 응답된다.
     *    시연 규모에서는 충분하다. 시퀀스 테이블 도입은 백로그.
     */
    private String nextVisitNo() {
        String prefix = visitNoPrefix + LocalDate.now().format(VISIT_DATE) + "-";
        long seq = appointmentRepository.countByVisitNoStartingWith(prefix) + 1;
        return prefix + String.format("%04d", seq);
    }

    /**
     * 어떤 UNIQUE 제약이 깨졌는지로 오류 코드를 가른다.
     * 제약명은 01_schema.sql 에 정의된 값이다. 스키마와 동기화가 필요하다.
     */
    private ApiException translateBookingConflict(DataIntegrityViolationException e) {

        String detail = e.getMostSpecificCause().getMessage();
        String lower = detail == null ? "" : detail.toLowerCase();

        if (lower.contains("uk_appt_active_patient")) {
            return ApiException.of(ErrorCode.DUPLICATE_BOOKING,
                    "같은 시간에 이미 예약이 있습니다.");
        }
        if (lower.contains("uk_appt_active_slot")) {
            return ApiException.of(ErrorCode.SLOT_TAKEN,
                    "방금 다른 분이 예약했습니다.");
        }
        // 제약명을 특정하지 못하면 슬롯 경합으로 본다. 가장 흔한 경우다.
        return ApiException.of(ErrorCode.SLOT_TAKEN, "방금 다른 분이 예약했습니다.");
    }

    private BizDtos.AppointmentResponse toResponse(Appointment a) {
        return new BizDtos.AppointmentResponse(
                a.getVisitNo(),
                a.getDoctor().getDoctorId(),
                a.getDoctor().getStaff().getName(),
                a.getDoctor().getDepartment(),
                a.getSlotAt(),
                // 표준 enum 으로 반환한다. DB 원본값도 한글 라벨도 아니다 (README §6.8).
                a.getStatus().name(),
                a.getSymptom());
    }
}

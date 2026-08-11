package org.kuspital.was.biz;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/** 업무 API DTO. JSON 은 SNAKE_CASE 전역 설정으로 변환된다. */
public final class BizDtos {

    private BizDtos() {
    }

    // ---------- 조회 응답 ----------

    public record DoctorResponse(Long doctorId, String name, String department,
                                 String specialty, String roomNo) {
    }

    public record SlotResponse(Long slotId, LocalDateTime slotAt) {
    }

    public record AppointmentResponse(String visitNo, Long doctorId, String doctorName,
                                      String department, LocalDateTime slotAt,
                                      String status, String symptom) {
    }

    /** GET /internal/staff/patients - 당일 예약 목록. */
    public record StaffPatientResponse(String visitNo, Long patientId, String patientName,
                                       LocalDate birthDate, LocalDateTime slotAt,
                                       String status, String symptom,
                                       boolean chartWritten) {
    }

    public record IcdCodeResponse(String code, String nameKr, String nameEn,
                                  String infectiousClass) {
    }

    public record PrescriptionItemResponse(int lineNo, String drugName, String dosage,
                                           String frequency, int durationDays) {
    }

    public record ChartResponse(Long chartId, String visitNo, Long patientId,
                                String icdCode, String icdName,
                                String chiefComplaint, String note,
                                LocalDateTime createdAt,
                                LocalDateTime prescriptionIssuedAt,
                                List<PrescriptionItemResponse> prescriptionItems) {
    }

    // ---------- 요청 ----------

    public record CreateAppointmentRequest(
            @NotNull Long slotId,
            @Size(max = 500) String symptom) {
    }

    public record UpdateAppointmentRequest(
            @NotBlank String status) {
    }

    public record PrescriptionItemRequest(
            @NotBlank @Size(max = 200) String drugName,
            @NotBlank @Size(max = 50) String dosage,
            @NotBlank @Size(max = 50) String frequency,
            @Min(1) @Max(365) int durationDays) {
    }

    /**
     * POST /internal/staff/charts - 차트 + 처방 단일 트랜잭션. README §6.6
     *
     * ⚠️ patient_id 를 받지 않는다. visit_no -> appointment 조인으로 서버가 결정한다.
     *    필드를 추가하면 위조 방어 4번 원칙 위반이다.
     * ⚠️ prescriptionItems 가 null 이거나 빈 배열이면 처방 없는 차트로 저장한다.
     */
    public record CreateChartRequest(
            @NotBlank @Size(max = 32) String visitNo,
            @NotBlank @Size(max = 6) String icdCode,
            @Size(max = 500) String chiefComplaint,
            String note,
            @Valid List<PrescriptionItemRequest> prescriptionItems) {
    }
}

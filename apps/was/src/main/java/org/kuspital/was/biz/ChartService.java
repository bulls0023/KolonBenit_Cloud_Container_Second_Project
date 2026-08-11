package org.kuspital.was.biz;

import org.kuspital.was.domain.*;
import org.kuspital.was.error.ApiException;
import org.kuspital.was.error.ErrorCode;
import org.kuspital.was.repository.AppointmentRepository;
import org.kuspital.was.repository.ChartRepository;
import org.kuspital.was.repository.IcdCodeRepository;
import org.kuspital.was.web.Actor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

/**
 * 진료 차트 + 처방. README v3.1 §6.6 / §7.12
 *
 * [단일 트랜잭션] 차트·처방·처방항목을 한 번에 저장한다. 부분 저장은 없다.
 *   차트 없는 처방은 의료 기록으로 성립하지 않으므로 두 리소스의 생명주기는
 *   애초에 분리되지 않는다.
 *
 * [중복 방어] 사전 SELECT 로 판정하지 않는다.
 *   "먼저 조회해서 있으면 409" 는 동시 요청 2건에서 둘 다 통과한다.
 *   chart.visit_no 의 UNIQUE 위반을 잡아 409 로 변환하는 것이 유일하게 옳다.
 *   예약의 slot_taken 과 동일 원칙 (README §6.8).
 */
@Service
public class ChartService {

    private final ChartRepository chartRepository;
    private final AppointmentRepository appointmentRepository;
    private final IcdCodeRepository icdCodeRepository;

    public ChartService(ChartRepository chartRepository,
                        AppointmentRepository appointmentRepository,
                        IcdCodeRepository icdCodeRepository) {
        this.chartRepository = chartRepository;
        this.appointmentRepository = appointmentRepository;
        this.icdCodeRepository = icdCodeRepository;
    }

    // -----------------------------------------------------------------
    // 생성
    // -----------------------------------------------------------------

    @Transactional
    public BizDtos.ChartResponse create(Actor actor, BizDtos.CreateChartRequest req) {

        // 1. 권한 - DOCTOR 전용. BFF 가 이미 막지만 WAS 가 최종 방어선이다.
        //    NURSE 는 처방 항목 포함 여부와 무관하게 403 이다 (README §6.5).
        if (!actor.isDoctor()) {
            throw ApiException.of(ErrorCode.FORBIDDEN, "차트 작성 권한이 없습니다.");
        }

        // 2. 예약 확인 - 여기서 patient_id 를 결정한다.
        //    요청 본문에 patient_id 가 없는 이유다 (위조 방어 4번 원칙).
        Appointment appointment = appointmentRepository.findByVisitNo(req.visitNo())
                .orElseThrow(() -> ApiException.of(
                        ErrorCode.NOT_FOUND, "예약을 찾을 수 없습니다."));

        if (appointment.isCancelled()) {
            throw ApiException.of(ErrorCode.INVALID_STATUS, "취소된 예약입니다.");
        }

        // 3. 상병코드 확인 - 마스터에 없으면 400
        IcdCode icd = icdCodeRepository.findById(req.icdCode())
                .orElseThrow(() -> ApiException.of(
                        ErrorCode.VALIDATION_ERROR, "존재하지 않는 상병코드입니다."));

        // 4. 차트 생성. 상병명은 발급 시점 값을 복사 보관한다 (소급 변경 방지).
        Chart chart = new Chart(
                appointment.getVisitNo(),
                appointment.getPatient().getPatientId(),
                actor.id(),
                icd,
                req.chiefComplaint(),
                req.note());

        // 5. 처방 - 항목이 있을 때만 만든다. 빈 배열/null 은 처방 없는 차트다.
        List<BizDtos.PrescriptionItemRequest> items =
                req.prescriptionItems() == null ? List.of() : req.prescriptionItems();

        if (!items.isEmpty()) {
            Prescription prescription = chart.attachPrescription(actor.id());
            for (BizDtos.PrescriptionItemRequest i : items) {
                prescription.addItem(i.drugName(), i.dosage(), i.frequency(), i.durationDays());
            }
        }

        // 6. 저장. saveAndFlush 로 제약 위반을 이 try 안에서 터뜨린다.
        //    save() 만 쓰면 트랜잭션 커밋 시점에 예외가 나서 여기서 잡히지 않는다.
        try {
            chartRepository.saveAndFlush(chart);
        } catch (DataIntegrityViolationException e) {
            throw ApiException.of(ErrorCode.DUPLICATE_PRESCRIPTION,
                    "이미 진료 기록이 등록된 예약입니다.");
        }

        // 7. 예약을 진료 완료로 전환한다.
        appointment.complete();

        return toResponse(chart);
    }

    // -----------------------------------------------------------------
    // 조회
    // -----------------------------------------------------------------

    /** GET /internal/staff/patients/{visit_no}/chart */
    @Transactional(readOnly = true)
    public BizDtos.ChartResponse getByVisitNo(String visitNo) {
        Chart chart = chartRepository.findByVisitNoWithPrescription(visitNo)
                .orElseThrow(() -> ApiException.of(
                        ErrorCode.NOT_FOUND, "진료 기록이 없습니다."));
        return toResponse(chart);
    }

    /** GET /internal/patient/records - 본인 것만. patientId 는 서버가 결정한 값이다. */
    @Transactional(readOnly = true)
    public List<BizDtos.ChartResponse> findRecords(Long patientId) {
        return chartRepository.findByPatientId(patientId).stream()
                .map(this::toResponse)
                .toList();
    }

    /** GET /internal/patient/prescriptions - 처방이 있는 것만. */
    @Transactional(readOnly = true)
    public List<BizDtos.ChartResponse> findPrescriptions(Long patientId) {
        return chartRepository.findPrescribedByPatientId(patientId).stream()
                .map(this::toResponse)
                .toList();
    }

    // -----------------------------------------------------------------

    private BizDtos.ChartResponse toResponse(Chart chart) {

        List<BizDtos.PrescriptionItemResponse> items = new ArrayList<>();
        Prescription prescription = chart.getPrescription();

        if (prescription != null) {
            for (PrescriptionItem i : prescription.getItems()) {
                items.add(new BizDtos.PrescriptionItemResponse(
                        i.getLineNo(), i.getDrugName(), i.getDosage(),
                        i.getFrequency(), i.getDurationDays()));
            }
        }

        return new BizDtos.ChartResponse(
                chart.getChartId(),
                chart.getVisitNo(),
                chart.getPatientId(),
                chart.getIcdCode(),
                // 마스터를 조인하지 않는다. 발급 시점 스냅샷을 그대로 반환한다.
                chart.getIcdNameSnapshot(),
                chart.getChiefComplaint(),
                chart.getNote(),
                chart.getCreatedAt(),
                prescription == null ? null : prescription.getIssuedAt(),
                items);
    }
}

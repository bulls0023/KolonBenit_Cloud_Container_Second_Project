package org.kuspital.was.domain;

import jakarta.persistence.*;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * 진료 차트. 예약 1건당 1건. README §6.8
 *
 * [중복 방어] visit_no 의 UNIQUE 제약이 처방 중복 발급의 최종 방어선이다.
 *   -> 409 duplicate_prescription 의 판정 근거.
 *   사전 SELECT 로 판정하지 않는다. 동시 요청 2건이면 둘 다 통과한다.
 *   DataIntegrityViolationException 을 잡아서 변환하는 것이 유일하게 옳다.
 *
 * [스냅샷] icdNameSnapshot 은 발급 시점 명칭의 사본이다.
 *   KCD 는 연 1~2회 개정된다. 마스터를 조인해 명칭을 보여주면
 *   과거 처방전의 상병명이 소급 변경되어 의료 기록으로서 무효가 된다.
 *   소급 수정 금지 (README §16-21).
 */
@Entity
@Table(name = "chart")
public class Chart {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "chart_id")
    private Long chartId;

    /**
     * appointment.visit_no 를 FK 로 참조한다.
     * 연관 엔티티가 아니라 값으로 들고 있는 이유:
     * 참조 대상이 appointment 의 PK 가 아니라 UNIQUE 컬럼이기 때문이다.
     */
    @Column(name = "visit_no", nullable = false, length = 32, unique = true)
    private String visitNo;

    /** appointment 에서 파생한다. 요청 본문 값을 신뢰하지 않는다 (README §6.6). */
    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** 작성자. X-Actor-Id 에서 파생한다. */
    @Column(name = "doctor_staff_id", nullable = false)
    private Long doctorStaffId;

    @Column(name = "icd_code", nullable = false, length = 6)
    private String icdCode;

    @Column(name = "icd_name_snapshot", nullable = false, length = 200)
    private String icdNameSnapshot;

    @Column(name = "chief_complaint", length = 500)
    private String chiefComplaint;

    /**
     * DB 는 TEXT 다.
     *
     * ⚠️ @Lob 만 붙이면 안 된다. MySQL 방언은 CLOB 의 실제 타입을
     *    컬럼 길이로 고른다:
     *        ~255        tinytext   <- @Column 의 length 기본값
     *        ~65535      text       <- DDL 이 이것이다
     *        ~16777215   mediumtext
     *        그 이상      longtext
     *    length 를 생략하면 255 가 적용되어 tinytext 를 기대하게 되고,
     *    ddl-auto: validate 가 wrong column type 으로 기동을 막는다.
     *    (실측 확인: MySQL 8.0 / Hibernate 7)
     */
    @Lob
    @Column(name = "note", length = 65535)
    private String note;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    /**
     * 차트 1건당 처방 최대 1건. 처방 없는 차트가 정상이므로 0..1 이다.
     * 단일 트랜잭션 저장을 위해 cascade 를 건다 (README §7.12).
     */
    @OneToOne(mappedBy = "chart", cascade = CascadeType.ALL, orphanRemoval = true,
              fetch = FetchType.LAZY)
    private Prescription prescription;

    protected Chart() {
    }

    public Chart(String visitNo, Long patientId, Long doctorStaffId,
                 IcdCode icd, String chiefComplaint, String note) {
        this.visitNo = visitNo;
        this.patientId = patientId;
        this.doctorStaffId = doctorStaffId;
        this.icdCode = icd.getCode();
        this.icdNameSnapshot = icd.getNameKr();   // 발급 시점 명칭 복사
        this.chiefComplaint = chiefComplaint;
        this.note = note;
    }

    /** 처방을 붙인다. 항목이 비어 있으면 처방을 만들지 않는다. */
    public Prescription attachPrescription(Long issuedByStaffId) {
        Prescription p = new Prescription(this, this.patientId, issuedByStaffId);
        this.prescription = p;
        return p;
    }

    public boolean hasPrescription() {
        return prescription != null;
    }

    public Long getChartId()             { return chartId; }
    public String getVisitNo()           { return visitNo; }
    public Long getPatientId()           { return patientId; }
    public Long getDoctorStaffId()       { return doctorStaffId; }
    public String getIcdCode()           { return icdCode; }
    public String getIcdNameSnapshot()   { return icdNameSnapshot; }
    public String getChiefComplaint()    { return chiefComplaint; }
    public String getNote()              { return note; }
    public LocalDateTime getCreatedAt()  { return createdAt; }
    public Prescription getPrescription(){ return prescription; }

    /** 처방 항목 목록. 처방이 없으면 빈 리스트. */
    public List<PrescriptionItem> getPrescriptionItems() {
        return prescription == null ? new ArrayList<>() : prescription.getItems();
    }
}

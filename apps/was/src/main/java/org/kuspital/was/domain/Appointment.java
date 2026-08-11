package org.kuspital.was.domain;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * 예약. README §6.8
 *
 * [동시성] 애플리케이션 사전 체크는 보조다. DB UNIQUE 제약이 본선이다.
 *   uk_appt_active_slot    -> 409 slot_taken
 *   uk_appt_active_patient -> 409 duplicate_booking
 *
 * [주의] DB 의 생성 컬럼 active_slot_id / active_patient_slot 은 매핑하지 않는다.
 *        DB 가 status 로부터 자동 계산한다. 엔티티가 건드릴 대상이 아니다.
 */
@Entity
@Table(name = "appointment")
public class Appointment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "appointment_id")
    private Long appointmentId;

    /** 접수번호. 예 V20260810-0007. chart 가 이 값을 FK 로 참조한다. */
    @Column(name = "visit_no", nullable = false, length = 32, unique = true)
    private String visitNo;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "patient_id", nullable = false)
    private PatientUser patient;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "doctor_id", nullable = false)
    private Doctor doctor;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "slot_id", nullable = false)
    private DoctorSlot slot;

    /** doctor_slot.slot_at 사본. 조회와 중복 판정에 쓴다. */
    @Column(name = "slot_at", nullable = false)
    private LocalDateTime slotAt;

    @Convert(converter = AppointmentStatusConverter.class)
    @Column(name = "status", nullable = false)
    private AppointmentStatus status;

    @Column(name = "symptom", length = 500)
    private String symptom;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime updatedAt;

    protected Appointment() {
    }

    public Appointment(String visitNo, PatientUser patient, DoctorSlot slot, String symptom) {
        this.visitNo = visitNo;
        this.patient = patient;
        this.doctor = slot.getDoctor();
        this.slot = slot;
        this.slotAt = slot.getSlotAt();
        this.status = AppointmentStatus.BOOKED;
        this.symptom = symptom;
    }

    public void cancel() {
        this.status = AppointmentStatus.CANCELLED;
    }

    public void complete() {
        this.status = AppointmentStatus.DONE;
    }

    public boolean isCancelled() {
        return status == AppointmentStatus.CANCELLED;
    }

    public Long getAppointmentId()      { return appointmentId; }
    public String getVisitNo()          { return visitNo; }
    public PatientUser getPatient()     { return patient; }
    public Doctor getDoctor()           { return doctor; }
    public DoctorSlot getSlot()         { return slot; }
    public LocalDateTime getSlotAt()    { return slotAt; }
    public AppointmentStatus getStatus(){ return status; }
    public String getSymptom()          { return symptom; }
}

package org.kuspital.was.domain;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * 진료 슬롯. GET /internal/patient/slots 의 원본.
 * 슬롯이 없으면 예약 자체가 불가능하다 (appointment.slot_id 는 NOT NULL FK).
 */
@Entity
@Table(name = "doctor_slot")
public class DoctorSlot {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "slot_id")
    private Long slotId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "doctor_id", nullable = false)
    private Doctor doctor;

    @Column(name = "slot_at", nullable = false)
    private LocalDateTime slotAt;

    /** false = 휴진. 예약 점유 여부와는 별개다. */
    @Column(name = "is_open", nullable = false)
    private boolean open;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    protected DoctorSlot() {
    }

    public Long getSlotId()        { return slotId; }
    public Doctor getDoctor()      { return doctor; }
    public LocalDateTime getSlotAt(){ return slotAt; }
    public boolean isOpen()        { return open; }
}

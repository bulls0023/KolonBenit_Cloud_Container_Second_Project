package org.kuspital.was.domain;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/** 의사 프로필. GET /internal/patient/doctors 의 원본. */
@Entity
@Table(name = "doctor")
public class Doctor {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "doctor_id")
    private Long doctorId;

    /**
     * staff_user 와 1:1. 지연 로딩으로 두어 목록 조회에서 N+1 을 만들지 않는다.
     * 이름이 필요한 조회는 Repository 의 fetch join 쿼리를 쓴다.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "staff_id", nullable = false, unique = true)
    private StaffUser staff;

    @Column(name = "department", nullable = false, length = 50)
    private String department;

    @Column(name = "specialty", length = 100)
    private String specialty;

    @Column(name = "room_no", length = 20)
    private String roomNo;

    @Column(name = "is_active", nullable = false)
    private boolean active;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime createdAt;

    protected Doctor() {
    }

    public Long getDoctorId()    { return doctorId; }
    public StaffUser getStaff()  { return staff; }
    public String getDepartment(){ return department; }
    public String getSpecialty() { return specialty; }
    public String getRoomNo()    { return roomNo; }
    public boolean isActive()    { return active; }
}

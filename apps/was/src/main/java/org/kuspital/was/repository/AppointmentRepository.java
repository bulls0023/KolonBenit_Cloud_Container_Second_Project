package org.kuspital.was.repository;

import org.kuspital.was.domain.Appointment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface AppointmentRepository extends JpaRepository<Appointment, Long> {

    Optional<Appointment> findByVisitNo(String visitNo);

    /** GET /internal/patient/appointments - 본인 것만. */
    @Query("""
           SELECT a FROM Appointment a
             JOIN FETCH a.doctor d
             JOIN FETCH d.staff
            WHERE a.patient.patientId = :patientId
            ORDER BY a.slotAt DESC
           """)
    List<Appointment> findByPatientWithDoctor(@Param("patientId") Long patientId);

    /**
     * GET /internal/staff/patients - 당일 예약 목록.
     * 취소분은 제외한다.
     */
    @Query("""
           SELECT a FROM Appointment a
             JOIN FETCH a.patient
             JOIN FETCH a.doctor d
             JOIN FETCH d.staff
            WHERE a.slotAt >= :from
              AND a.slotAt <  :to
              AND a.status <> org.kuspital.was.domain.AppointmentStatus.CANCELLED
            ORDER BY a.slotAt
           """)
    List<Appointment> findDailyForStaff(@Param("from") LocalDateTime from,
                                        @Param("to") LocalDateTime to);

    /**
     * visit_no 채번용 당일 시퀀스.
     * 형식이 V{yyyyMMdd}-{0000} 이므로 접두사로 카운트한다.
     * 동시 생성 시 충돌 가능성이 있으나 visit_no UNIQUE 가 최종 방어선이다.
     */
    long countByVisitNoStartingWith(String prefix);
}

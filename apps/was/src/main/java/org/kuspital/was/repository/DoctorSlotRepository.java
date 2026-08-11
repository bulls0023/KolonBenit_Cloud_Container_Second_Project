package org.kuspital.was.repository;

import org.kuspital.was.domain.DoctorSlot;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

public interface DoctorSlotRepository extends JpaRepository<DoctorSlot, Long> {

    /**
     * GET /internal/patient/slots - 예약 가능 슬롯.
     *
     * 취소된 예약은 슬롯을 점유하지 않는다. DB 의 생성 컬럼 UNIQUE 와 동일한 기준
     * (status <> CANCELLED) 을 여기서도 써야 한다. 어긋나면 화면에는 예약 가능으로
     * 보이는데 실제 예약은 409 가 나는 상태가 된다.
     */
    @Query("""
           SELECT s FROM DoctorSlot s
            WHERE s.doctor.doctorId = :doctorId
              AND s.open = true
              AND s.slotAt >= :from
              AND s.slotAt <  :to
              AND NOT EXISTS (
                    SELECT 1 FROM Appointment a
                     WHERE a.slot = s
                       AND a.status <> org.kuspital.was.domain.AppointmentStatus.CANCELLED
              )
            ORDER BY s.slotAt
           """)
    List<DoctorSlot> findAvailable(@Param("doctorId") Long doctorId,
                                   @Param("from") LocalDateTime from,
                                   @Param("to") LocalDateTime to);
}

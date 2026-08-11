package org.kuspital.was.repository;

import org.kuspital.was.domain.Chart;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface ChartRepository extends JpaRepository<Chart, Long> {

    /**
     * GET /internal/staff/patients/{visit_no}/chart
     * 차트 + 처방 + 항목을 한 번에 가져온다.
     *
     * ⚠️ items 는 컬렉션이므로 fetch join 을 두 단계로 걸면 곱집합이 된다.
     *    여기서는 컬렉션이 하나뿐이라 안전하다.
     */
    @Query("""
           SELECT c FROM Chart c
             LEFT JOIN FETCH c.prescription p
             LEFT JOIN FETCH p.items
            WHERE c.visitNo = :visitNo
           """)
    Optional<Chart> findByVisitNoWithPrescription(@Param("visitNo") String visitNo);

    /**
     * GET /internal/patient/records - 본인 진료 기록.
     * patientId 로 필터한다. 요청자가 보낸 값이 아니라 서버가 결정한 값이어야 한다.
     */
    @Query("""
           SELECT c FROM Chart c
            WHERE c.patientId = :patientId
            ORDER BY c.createdAt DESC
           """)
    List<Chart> findByPatientId(@Param("patientId") Long patientId);

    /**
     * GET /internal/patient/prescriptions - 처방이 있는 차트만.
     */
    @Query("""
           SELECT DISTINCT c FROM Chart c
             JOIN FETCH c.prescription p
             LEFT JOIN FETCH p.items
            WHERE c.patientId = :patientId
            ORDER BY c.createdAt DESC
           """)
    List<Chart> findPrescribedByPatientId(@Param("patientId") Long patientId);

    boolean existsByVisitNo(String visitNo);
}

package org.kuspital.was.repository;

import org.kuspital.was.domain.Doctor;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface DoctorRepository extends JpaRepository<Doctor, Long> {

    /**
     * GET /internal/patient/doctors
     * staff 를 fetch join 한다. 지연 로딩이면 의사 수만큼 추가 쿼리가 나간다 (N+1).
     */
    @Query("""
           SELECT d FROM Doctor d
             JOIN FETCH d.staff s
            WHERE d.active = true
            ORDER BY d.department, s.name
           """)
    List<Doctor> findAllActiveWithStaff();
}

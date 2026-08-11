package org.kuspital.was.repository;

import org.kuspital.was.domain.PatientUser;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface PatientUserRepository extends JpaRepository<PatientUser, Long> {

    Optional<PatientUser> findByLoginId(String loginId);

    /** 가입 시 중복 판정 -> 409 patient_exists. 최종 방어는 DB UNIQUE. */
    boolean existsByLoginId(String loginId);
}

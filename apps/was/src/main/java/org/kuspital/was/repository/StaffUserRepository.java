package org.kuspital.was.repository;

import org.kuspital.was.domain.StaffUser;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface StaffUserRepository extends JpaRepository<StaffUser, Long> {

    Optional<StaffUser> findByLoginId(String loginId);
}

package org.kuspital.was;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.kuspital.was.repository.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.context.ActiveProfiles;

import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertNotNull;

/**
 * 부트스트랩 검증.
 *
 * 이 테스트가 존재하는 이유:
 *   ./gradlew build 는 Java 컴파일만 검증한다. @Query 의 JPQL 은
 *   문자열이므로 컴파일러가 보지 않는다. Hibernate 가 EntityManagerFactory
 *   생성 시점에 파싱하며, 그때 처음 오류가 드러난다.
 *   테스트가 없으면 그 시점은 EKS 파드의 첫 기동이 된다.
 *
 * 검증 항목:
 *   1. 스프링 컨텍스트 기동 (전 빈 주입 성공)
 *   2. 모든 @Query JPQL 파싱 성공
 *   3. 각 쿼리의 실제 실행 (SQL 생성까지 확인)
 */
@SpringBootTest
@ActiveProfiles("test")
@DisplayName("JPA 부트스트랩 및 JPQL 검증")
class JpaBootstrapTest {

    @Autowired PatientUserRepository patientUserRepository;
    @Autowired StaffUserRepository staffUserRepository;
    @Autowired DoctorRepository doctorRepository;
    @Autowired DoctorSlotRepository doctorSlotRepository;
    @Autowired AppointmentRepository appointmentRepository;
    @Autowired ChartRepository chartRepository;
    @Autowired IcdCodeRepository icdCodeRepository;
    @Autowired IcdCodeSynonymRepository icdCodeSynonymRepository;

    @Test
    @DisplayName("컨텍스트가 기동되고 리포지토리가 전부 주입된다")
    void contextLoads() {
        assertNotNull(patientUserRepository);
        assertNotNull(staffUserRepository);
        assertNotNull(doctorRepository);
        assertNotNull(doctorSlotRepository);
        assertNotNull(appointmentRepository);
        assertNotNull(chartRepository);
        assertNotNull(icdCodeRepository);
        assertNotNull(icdCodeSynonymRepository);
    }

    /**
     * 모든 커스텀 쿼리를 한 번씩 실행한다.
     * 결과가 비어 있어도 상관없다. SQL 이 생성되고 실행되는지만 본다.
     */
    @Test
    @DisplayName("모든 @Query 가 파싱되고 실행된다")
    void allQueriesExecute() {

        LocalDate today = LocalDate.now();
        LocalDateTime from = today.atStartOfDay();
        LocalDateTime to = today.plusDays(1).atStartOfDay();

        patientUserRepository.findByLoginId("none");
        patientUserRepository.existsByLoginId("none");

        staffUserRepository.findByLoginId("none");

        doctorRepository.findAllActiveWithStaff();

        doctorSlotRepository.findAvailable(1L, from, to);

        appointmentRepository.findByVisitNo("V-NONE");
        appointmentRepository.findByPatientWithDoctor(1L);
        appointmentRepository.findDailyForStaff(from, to);
        appointmentRepository.countByVisitNoStartingWith("V20260810-");

        chartRepository.findByVisitNoWithPrescription("V-NONE");
        chartRepository.findByPatientId(1L);
        chartRepository.findPrescribedByPatientId(1L);
        chartRepository.existsByVisitNo("V-NONE");

        icdCodeRepository.findById("E1140");
        icdCodeSynonymRepository.search("당뇨", PageRequest.of(0, 50));
    }
}

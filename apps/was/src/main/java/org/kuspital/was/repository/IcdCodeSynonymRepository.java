package org.kuspital.was.repository;

import org.kuspital.was.domain.IcdCodeSynonym;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

/**
 * 상병코드 검색 - 읽기 전용.
 *
 * [검색 전략] 동의어 테이블만 조회한다. 대표명도 여기 포함되어 있으므로
 *   마스터와의 UNION 이 불필요하다.
 *
 * [성능 실측] 37,543행 / ANALYZE 후 / 상한 50건
 *   code LIKE 'E11%'      range 스캔 630행    1.3ms
 *   name_kr LIKE '%당뇨%'  풀스캔  39,675행   6.6ms
 *   부분일치는 인덱스를 타지 않으나 이 규모에서는 10ms 미만이다.
 *   FULLTEXT 전환은 백로그 (README §17.3).
 */
public interface IcdCodeSynonymRepository extends JpaRepository<IcdCodeSynonym, Long> {

    /**
     * 코드 prefix 또는 명칭 부분일치.
     * 같은 코드가 동의어 여러 건으로 중복 매칭되므로 코드 단위로 묶는다.
     * 대표명은 마스터에서 가져온다 - 검색어에 걸린 동의어가 아니라
     * 공식 분류명을 보여줘야 한다.
     */
    @Query("""
           SELECT DISTINCT m FROM IcdCodeSynonym s
             JOIN IcdCode m ON m.code = s.code
            WHERE UPPER(s.code) LIKE UPPER(CONCAT(:q, '%'))
               OR s.nameKr LIKE CONCAT('%', :q, '%')
            ORDER BY m.code
           """)
    List<org.kuspital.was.domain.IcdCode> search(@Param("q") String q, Pageable pageable);
}

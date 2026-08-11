package org.kuspital.was.domain;

import jakarta.persistence.*;

/**
 * 상병코드 동의어 색인. GET /internal/staff/icd-codes 의 검색 대상.
 *
 * 원본은 한 상병기호에 명칭이 여러 건 달린 구조다 (E1140 에 60건).
 * 대표명도 이 테이블에 포함되어 있으므로 검색 시 UNION 이 불필요하다.
 *
 * [참조 전용] IcdCode 와 동일. SELECT 만 가능하다.
 */
@Entity
@Table(name = "icd_code_synonym")
public class IcdCodeSynonym {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "synonym_id")
    private Long synonymId;

    @Column(name = "code", nullable = false, length = 6)
    private String code;

    @Column(name = "name_kr", nullable = false, length = 200)
    private String nameKr;

    @Column(name = "name_en", length = 255)
    private String nameEn;

    protected IcdCodeSynonym() {
    }

    public Long getSynonymId(){ return synonymId; }
    public String getCode()   { return code; }
    public String getNameKr() { return nameKr; }
    public String getNameEn() { return nameEn; }
}

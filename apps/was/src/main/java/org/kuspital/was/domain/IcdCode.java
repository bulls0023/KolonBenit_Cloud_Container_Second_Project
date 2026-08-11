package org.kuspital.was.domain;

import jakarta.persistence.*;

/**
 * 상병코드 마스터. README §6.10
 *
 * [참조 전용] app_was 에는 SELECT 권한만 있다 (§12.3).
 *   INSERT / UPDATE / DELETE 코드를 작성하면 런타임에 권한 오류가 난다.
 *   이것은 실수가 아니라 §7.11 "WAS 런타임 외부 적재 금지"의 권한 차원 강제다.
 *   적재는 db/04_icd_seed.sql 이 admin 권한으로 수행한다.
 */
@Entity
@Table(name = "icd_code")
public class IcdCode {

    @Id
    @Column(name = "code", length = 6)
    private String code;

    /** 대표 한글명. 원본 최대 170자. */
    @Column(name = "name_kr", nullable = false, length = 200)
    private String nameKr;

    @Column(name = "name_en", length = 255)
    private String nameEn;

    @Column(name = "gender_restriction", length = 1)
    private String genderRestriction;

    @Column(name = "age_min")
    private Integer ageMin;

    @Column(name = "age_max")
    private Integer ageMax;

    /** 법정감염병 등급. 보유 코드 486종. */
    @Column(name = "infectious_class", length = 8)
    private String infectiousClass;

    @Column(name = "oriental_medicine", length = 16)
    private String orientalMedicine;

    protected IcdCode() {
    }

    public String getCode()             { return code; }
    public String getNameKr()           { return nameKr; }
    public String getNameEn()           { return nameEn; }
    public String getGenderRestriction(){ return genderRestriction; }
    public Integer getAgeMin()          { return ageMin; }
    public Integer getAgeMax()          { return ageMax; }
    public String getInfectiousClass()  { return infectiousClass; }
    public String getOrientalMedicine() { return orientalMedicine; }
}

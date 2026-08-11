package org.kuspital.was.domain;

import jakarta.persistence.*;

/**
 * 처방 약품 항목.
 * drugName 은 이번 단계에서 자유 텍스트다.
 * 의약품 표준코드 연동은 백로그 (README §17.3).
 */
@Entity
@Table(name = "prescription_item")
public class PrescriptionItem {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "item_id")
    private Long itemId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "prescription_id", nullable = false)
    private Prescription prescription;

    @Column(name = "drug_name", nullable = false, length = 200)
    private String drugName;

    /** 1회 투여량. 예 "1정" */
    @Column(name = "dosage", nullable = false, length = 50)
    private String dosage;

    /** 예 "1일 2회" */
    @Column(name = "frequency", nullable = false, length = 50)
    private String frequency;

    /** DB CHECK 제약: 1 ~ 365. 범위를 벗어나면 적재 자체가 거부된다. */
    @Column(name = "duration_days", nullable = false)
    private int durationDays;

    @Column(name = "line_no", nullable = false)
    private int lineNo;

    protected PrescriptionItem() {
    }

    PrescriptionItem(Prescription prescription, String drugName, String dosage,
                     String frequency, int durationDays, int lineNo) {
        this.prescription = prescription;
        this.drugName = drugName;
        this.dosage = dosage;
        this.frequency = frequency;
        this.durationDays = durationDays;
        this.lineNo = lineNo;
    }

    public Long getItemId()        { return itemId; }
    public String getDrugName()    { return drugName; }
    public String getDosage()      { return dosage; }
    public String getFrequency()   { return frequency; }
    public int getDurationDays()   { return durationDays; }
    public int getLineNo()         { return lineNo; }
}

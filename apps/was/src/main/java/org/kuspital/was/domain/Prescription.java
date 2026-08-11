package org.kuspital.was.domain;

import jakarta.persistence.*;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/** 처방전 헤더. 차트 1건당 최대 1건 (chart_id UNIQUE). */
@Entity
@Table(name = "prescription")
public class Prescription {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "prescription_id")
    private Long prescriptionId;

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "chart_id", nullable = false, unique = true)
    private Chart chart;

    /** chart 에서 파생한다. */
    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "issued_by_staff_id", nullable = false)
    private Long issuedByStaffId;

    @Column(name = "issued_at", nullable = false, insertable = false, updatable = false)
    private LocalDateTime issuedAt;

    @OneToMany(mappedBy = "prescription", cascade = CascadeType.ALL,
               orphanRemoval = true, fetch = FetchType.LAZY)
    @OrderBy("lineNo ASC")
    private List<PrescriptionItem> items = new ArrayList<>();

    protected Prescription() {
    }

    Prescription(Chart chart, Long patientId, Long issuedByStaffId) {
        this.chart = chart;
        this.patientId = patientId;
        this.issuedByStaffId = issuedByStaffId;
    }

    /** 약품 항목 추가. lineNo 는 추가 순서로 자동 부여한다. */
    public PrescriptionItem addItem(String drugName, String dosage,
                                    String frequency, int durationDays) {
        PrescriptionItem item = new PrescriptionItem(
                this, drugName, dosage, frequency, durationDays, items.size() + 1);
        items.add(item);
        return item;
    }

    public Long getPrescriptionId()      { return prescriptionId; }
    public Chart getChart()              { return chart; }
    public Long getPatientId()           { return patientId; }
    public Long getIssuedByStaffId()     { return issuedByStaffId; }
    public LocalDateTime getIssuedAt()   { return issuedAt; }
    public List<PrescriptionItem> getItems() { return items; }
}

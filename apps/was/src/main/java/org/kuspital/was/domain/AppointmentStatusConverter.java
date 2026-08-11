package org.kuspital.was.domain;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * 예약 상태 DB <-> enum 변환기. README §6.8 - "변환 매퍼는 1개만 유지한다".
 *
 * DB 컬럼은 ENUM('booked','cancelled','done') 소문자다.
 * autoApply=false 로 두고 필드에 명시 부착한다 - 암묵 적용은 추적을 어렵게 한다.
 */
@Converter
public class AppointmentStatusConverter
        implements AttributeConverter<AppointmentStatus, String> {

    @Override
    public String convertToDatabaseColumn(AppointmentStatus attribute) {
        return attribute == null ? null : attribute.dbValue();
    }

    @Override
    public AppointmentStatus convertToEntityAttribute(String dbData) {
        return AppointmentStatus.fromDb(dbData);
    }
}

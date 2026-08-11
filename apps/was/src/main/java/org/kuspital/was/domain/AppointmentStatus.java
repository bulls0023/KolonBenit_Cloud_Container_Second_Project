package org.kuspital.was.domain;

/**
 * 예약 상태 - WAS 표준 enum.
 *
 * README §6.8 계약:
 *   DB 원본값(소문자) -> API 표준 enum(대문자) -> 화면 한글 라벨
 *   변환 매퍼는 1개만 유지한다. 화면 라벨은 각 Web 이 처리한다.
 *   WAS 는 DB 원본값도, 한글 라벨도 반환하지 않는다.
 *
 * DB <-> enum 변환은 {@link AppointmentStatusConverter} 단 하나가 담당한다.
 */
public enum AppointmentStatus {

    BOOKED("booked"),
    CANCELLED("cancelled"),
    DONE("done");

    private final String dbValue;

    AppointmentStatus(String dbValue) {
        this.dbValue = dbValue;
    }

    public String dbValue() {
        return dbValue;
    }

    public static AppointmentStatus fromDb(String value) {
        if (value == null) {
            return null;
        }
        for (AppointmentStatus s : values()) {
            if (s.dbValue.equals(value)) {
                return s;
            }
        }
        throw new IllegalArgumentException("알 수 없는 예약 상태 DB 값: " + value);
    }
}

package org.kuspital.was.domain;

/** 직원 계정 상태. WAS 는 ACTIVE 만 로그인을 허용한다 (README §6.8). */
public enum StaffStatus {
    ACTIVE,
    INACTIVE,
    SUSPENDED
}

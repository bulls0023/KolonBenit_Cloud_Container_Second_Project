// src/api/doctors.ts
// API-CONTRACT-patient.md §3 — 의사 · 슬롯

import { apiClient } from "./client";
import type { DoctorsResponse, SlotsResponse } from "./types";

export const doctorsApi = {
  /**
   * 의사 목록 조회
   * dept 없이 호출 시 전체 의사 반환
   * 없는 dept를 넘겨도 200 + 빈 배열 (에러 아님)
   */
  getDoctors: (dept?: string) => {
    const query = dept ? `?dept=${encodeURIComponent(dept)}` : "";
    return apiClient.get<DoctorsResponse>(`/doctors${query}`);
  },

  /**
   * 특정 의사의 특정 날짜 예약 가능 슬롯 조회
   * 캐시하지 않음 — 매번 최신 상태 조회 필요
   * 실패: 400 past_date / 404 doctor_not_found
   */
  getSlots: (doctorId: number, date: string) =>
    apiClient.get<SlotsResponse>(`/slots?doctor_id=${doctorId}&date=${date}`),
};
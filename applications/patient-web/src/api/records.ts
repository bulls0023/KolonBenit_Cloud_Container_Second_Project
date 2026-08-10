// src/api/records.ts
// API-CONTRACT-patient.md §5 — 진료기록 · 처방전 🔒

import { apiClient } from "./client";
import type { PrescriptionResponse, RecordsResponse } from "./types";

export const recordsApi = {
  /**
   * 🔒 진료기록 목록 조회 — 진료일 내림차순
   * note(의사 소견 원문)는 응답에 없음 — 상세 조회는 별도 엔드포인트(미제공, 백로그)
   * has_prescription: false면 화면에서 처방전 버튼 숨김
   * 캐시 금지 — 서버가 Cache-Control: no-store로 응답
   */
  getRecords: () => apiClient.get<RecordsResponse>("/records"),

  /**
   * 🔒 처방전 조회
   * ⚠️ IDOR 방지: record_id 소유자와 인증 주체가 다르면 서버가 404 반환
   *    (403 아님 — "그 번호가 존재한다"는 사실 자체를 은폐)
   * 캐시 금지
   */
  getPrescription: (recordId: number) =>
    apiClient.get<PrescriptionResponse>(`/prescriptions?record_id=${recordId}`),
};
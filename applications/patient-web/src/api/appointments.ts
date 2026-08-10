// src/api/appointments.ts
// API-CONTRACT-patient.md §4 — 예약

import { apiClient } from "./client";
import type {
  AppointmentResponse,
  AppointmentsResponse,
  CreateAppointmentRequest,
} from "./types";

export const appointmentsApi = {
  /**
   * 예약 생성
   * ⚠️ patient_id는 절대 body에 넣지 않는다 — BFF가 토큰에서 추출 (IDOR 방지)
   * 검증 순서(서버): 필수값 → 환자존재 → 의사존재 → 시각유효 → 슬롯격자 →
   *                   근무시간 → 중복예약 → DB유니크제약
   * 실패: 400 validation_error/past_time/invalid_slot/outside_hours
   *       404 patient_not_found/doctor_not_found
   *       409 duplicate_booking/slot_taken
   *
   * 409 slot_taken 수신 시 화면에서 /slots 자동 재조회 권장 (계약서 §4.1)
   */
  create: (data: CreateAppointmentRequest) =>
    apiClient.post<AppointmentResponse>("/appointments", data),

  /**
   * 본인 예약 목록 조회 — 취소 건 포함, 예약일시 내림차순
   * cancellable은 서버가 계산한 값 그대로 사용 (재구현 금지)
   */
  list: () => apiClient.get<AppointmentsResponse>("/appointments"),

  /**
   * 예약 취소 — 허용 전이는 예약→취소 하나뿐
   * 실패: 400 invalid_status/already_cancelled/too_late_to_cancel
   *       403 forbidden (진료완료/미방문 전이 시도 — 관리자 API 영역)
   *       404 not_found (다른 환자의 예약 ID — 403 아님, 존재 은폐)
   */
  cancel: (id: number) =>
    apiClient.patch<AppointmentResponse>(`/appointments/${id}`, {
      status: "취소" as const,
    }),
};
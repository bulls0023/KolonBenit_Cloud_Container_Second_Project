// src/api/types.ts
// API-CONTRACT-patient.md v3 기준 타입 정의

// ── 인증 ──────────────────────────────
export interface Patient {
  id: number;
  login_id: string;
  name: string;
  birth_date: string; // YYYY-MM-DD
}

export interface RegisterRequest {
  login_id: string;
  password: string;
  name: string;
  birth_date: string;
}

export interface LoginRequest {
  login_id: string;
  password: string;
}

export interface AuthResponse {
  patient: Patient;
}

// ── 의사 · 슬롯 ──────────────────────────
export interface Doctor {
  id: number;
  name: string;
  dept: string;
  slot_minutes: number;
  available_weekdays: number[]; // 0=월 ... 6=일
}

export interface DoctorsResponse {
  doctors: Doctor[];
}

export interface Slot {
  time: string; // "HH:MM"
  available: boolean;
}

export interface SlotsResponse {
  doctor_id: number;
  date: string; // YYYY-MM-DD
  slot_minutes: number;
  slots: Slot[];
}

// ── 예약 ────────────────────────────────
export type AppointmentStatus = "예약" | "취소" | "진료완료" | "미방문";

export interface Appointment {
  id: number;
  visit_no: string;
  date: string;
  time: string;
  doctor_id: number;
  doctor_name: string;
  dept: string;
  status: AppointmentStatus;
  cancellable: boolean; // 서버가 계산 — 프론트에서 재구현 금지
}

export interface CreateAppointmentRequest {
  doctor_id: number;
  date: string;
  time: string;
  // ⚠️ patient_id는 절대 포함하지 않는다 — BFF가 토큰에서 추출 (IDOR 방지)
}

export interface AppointmentResponse {
  appointment: Appointment;
}

export interface AppointmentsResponse {
  appointments: Appointment[];
}

export interface CancelAppointmentRequest {
  status: "취소";
}

// ── 진료기록 · 처방전 🔒 ───────────────────
export interface MedicalRecord {
  id: number;
  date: string;
  doctor_name: string;
  dept: string;
  chief_complaint: string;
  diagnosis: string;
  has_prescription: boolean;
}

export interface RecordsResponse {
  records: MedicalRecord[];
}

export interface PrescriptionItem {
  drug_name: string;
  dosage: string;
  frequency: string;
  duration_days: number;
  instruction: string;
}

export interface Prescription {
  id: number;
  record_id: number;
  issued_at: string;
  valid_days: number;
  doctor_name: string;
  dept: string;
  diagnosis: string;
  items: PrescriptionItem[];
}

export interface PrescriptionResponse {
  prescription: Prescription;
}
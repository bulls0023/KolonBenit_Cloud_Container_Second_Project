// src/api/auth.ts
// API-CONTRACT-patient.md §2 — 인증

import { apiClient } from "./client";
import type { AuthResponse, LoginRequest, RegisterRequest } from "./types";

export const authApi = {
  /**
   * 회원가입 → 성공 시 즉시 로그인 상태로 전환 (Set-Cookie)
   * 실패: 400 validation_error / invalid_date / future_birth_date
   *       409 patient_exists
   */
  register: (data: RegisterRequest) =>
    apiClient.post<AuthResponse>("/auth/register", data),

  /**
   * 로그인
   * 실패: 401 invalid_credentials
   *       423 account_locked (5회 실패 시 30분 잠금)
   */
  login: (data: LoginRequest) =>
    apiClient.post<AuthResponse>("/auth/login", data),

  /**
   * 로그아웃 → 쿠키 만료(maxAge=0)
   */
  logout: () => apiClient.post<void>("/auth/logout"),
};
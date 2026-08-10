// src/mocks/handlers.ts
import { http, HttpResponse } from "msw";

const BASE = "/api/bff/patient";

export const handlers = [
  http.get(`${BASE}/auth/csrf`, () => {
    return HttpResponse.json(
      { header_name: "X-XSRF-TOKEN", token: "mock-csrf-token" },
      { headers: { "Set-Cookie": "XSRF-TOKEN=mock-csrf-token; Path=/api/bff/patient" } }
    );
  }),

  http.post(`${BASE}/auth/login`, () => {
    return HttpResponse.json({
      patient: { id: 1, login_id: "testuser", name: "홍길동", birth_date: "1990-01-01" },
    });
  }),

  http.get(`${BASE}/doctors`, () => {
    return HttpResponse.json({
      doctors: [
        { id: 1, name: "이영희", dept: "내과", slot_minutes: 30, available_weekdays: [0, 1, 2, 3, 4] },
        { id: 2, name: "김철수", dept: "정형외과", slot_minutes: 20, available_weekdays: [0, 1, 2, 3, 4] },
      ],
    });
  }),

  http.get(`${BASE}/slots`, () => {
    return HttpResponse.json({
      doctor_id: 1,
      date: "2026-08-12",
      slot_minutes: 30,
      slots: [
        { time: "09:00", available: true },
        { time: "09:30", available: false },
        { time: "10:00", available: true },
      ],
    });
  }),

  http.get(`${BASE}/appointments`, () => {
    return HttpResponse.json({
      appointments: [
        {
          id: 88, visit_no: "P202608120001", date: "2026-08-12", time: "09:00",
          doctor_id: 1, doctor_name: "이영희", dept: "내과", status: "예약", cancellable: true,
        },
      ],
    });
  }),

  http.get(`${BASE}/records`, () => {
    return HttpResponse.json({
      records: [
        {
          id: 51, date: "2026-07-02", doctor_name: "이영희", dept: "내과",
          chief_complaint: "인후통, 발열", diagnosis: "급성 상기도염", has_prescription: true,
        },
      ],
    });
  }),

  http.get(`${BASE}/prescriptions`, () => {
    return HttpResponse.json({
      prescription: {
        id: 7, record_id: 51, issued_at: "2026-07-02", valid_days: 3,
        doctor_name: "이영희", dept: "내과", diagnosis: "급성 상기도염",
        items: [{ drug_name: "아목시실린", dosage: "500mg", frequency: "1일 3회", duration_days: 5, instruction: "식후 30분" }],
      },
    });
  }),
];
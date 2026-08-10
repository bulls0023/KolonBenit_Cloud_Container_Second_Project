// src/hooks/useAppointments.ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ApiError } from "../api/client";
import { appointmentsApi } from "../api/appointments";
import type { CreateAppointmentRequest } from "../api/types";

export function useAppointments() {
  return useQuery({
    queryKey: ["appointments"],
    queryFn: () => appointmentsApi.list(),
  });
}

export function useCreateAppointment() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateAppointmentRequest) => appointmentsApi.create(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["appointments"] });
    },
    onError: (error, variables) => {
      // 계약서 §4.1 권장 — slot_taken 수신 시 슬롯 목록 자동 재조회
      if (error instanceof ApiError && error.error === "slot_taken") {
        queryClient.invalidateQueries({
          queryKey: ["slots", variables.doctor_id, variables.date],
        });
      }
    },
  });
}

export function useCancelAppointment() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: number) => appointmentsApi.cancel(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["appointments"] });
    },
  });
}
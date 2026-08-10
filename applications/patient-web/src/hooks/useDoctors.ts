// src/hooks/useDoctors.ts
import { useQuery } from "@tanstack/react-query";
import { doctorsApi } from "../api/doctors";

export function useDoctors(dept?: string) {
  return useQuery({
    queryKey: ["doctors", dept ?? "all"],
    queryFn: () => doctorsApi.getDoctors(dept),
  });
}

export function useSlots(doctorId: number | undefined, date: string | undefined) {
  return useQuery({
    queryKey: ["slots", doctorId, date],
    queryFn: () => doctorsApi.getSlots(doctorId!, date!),
    enabled: !!doctorId && !!date, // 둘 다 있을 때만 요청
    staleTime: 0, // 계약서 §3.2 — 캐시 금지, 매번 최신 조회
  });
}
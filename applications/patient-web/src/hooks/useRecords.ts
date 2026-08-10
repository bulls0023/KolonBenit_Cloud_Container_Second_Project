// src/hooks/useRecords.ts
import { useQuery } from "@tanstack/react-query";
import { recordsApi } from "../api/records";

export function useRecords() {
  return useQuery({
    queryKey: ["records"],
    queryFn: () => recordsApi.getRecords(),
    staleTime: 0,
    gcTime: 0, // 🔒 민감정보 — 캐시에 남기지 않음(WEB-GUIDE §12)
  });
}

export function usePrescription(recordId: number | undefined) {
  return useQuery({
    queryKey: ["prescription", recordId],
    queryFn: () => recordsApi.getPrescription(recordId!),
    enabled: !!recordId,
    staleTime: 0,
    gcTime: 0, // 🔒 민감정보
  });
}
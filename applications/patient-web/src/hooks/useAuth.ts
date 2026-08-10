// src/hooks/useAuth.ts
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { authApi } from "../api/auth";
import type { LoginRequest, RegisterRequest } from "../api/types";

export function useLogin() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: LoginRequest) => authApi.login(data),
    onSuccess: () => {
      // 로그인 성공 시 캐시된 이전 사용자 데이터 전부 무효화
      queryClient.invalidateQueries();
      navigate("/");
    },
  });
}

export function useRegister() {
  const navigate = useNavigate();

  return useMutation({
    mutationFn: (data: RegisterRequest) => authApi.register(data),
    // 계약서 §2.1 — 회원가입 성공 시 즉시 로그인 상태로 전환됨(Set-Cookie)
    onSuccess: () => {
      navigate("/");
    },
  });
}

export function useLogout() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: () => authApi.logout(),
    onSuccess: () => {
      queryClient.clear(); // 로그아웃 시 캐시 전체 삭제 — 🔒 데이터 잔존 방지
      navigate("/login");
    },
  });
}
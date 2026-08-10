// src/pages/RegisterPage.tsx
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Link } from "react-router-dom";
import { Box, TextField, Button, Alert, Typography, Link as MuiLink } from "@mui/material";
import { useRegister } from "../hooks/useAuth";
import { ApiError } from "../api/client";

// API-CONTRACT-patient.md §2.1 검증 규칙 반영 (최종 판단은 서버, 프론트는 UX 보조)
const registerSchema = z.object({
  login_id: z
    .string()
    .min(4, "아이디는 4~50자여야 합니다.")
    .max(50, "아이디는 4~50자여야 합니다.")
    .regex(/^[a-zA-Z0-9]+$/, "아이디는 영문/숫자만 사용할 수 있습니다."),
  password: z
    .string()
    .min(8, "비밀번호는 8~100자여야 합니다.")
    .max(100, "비밀번호는 8~100자여야 합니다."),
  name: z.string().trim().min(1, "이름을 입력해주세요.").max(50, "이름은 50자 이내여야 합니다."),
  birth_date: z
    .string()
    .min(1, "생년월일을 입력해주세요.")
    .refine((v) => !isNaN(Date.parse(v)), "생년월일 형식이 올바르지 않습니다.")
    .refine((v) => new Date(v) <= new Date(), "생년월일은 오늘 이후일 수 없습니다."),
});

type RegisterFormValues = z.infer<typeof registerSchema>;

export default function RegisterPage() {
  const registerMutation = useRegister();
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<RegisterFormValues>({
    resolver: zodResolver(registerSchema),
  });

  const onSubmit = (data: RegisterFormValues) => {
    registerMutation.mutate(data);
  };

  return (
    <Box component="form" onSubmit={handleSubmit(onSubmit)} sx={{ mt: 2 }}>
      {registerMutation.isError && registerMutation.error instanceof ApiError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {registerMutation.error.message}
        </Alert>
      )}

      <TextField
        label="아이디"
        fullWidth
        margin="normal"
        autoComplete="username"
        {...register("login_id")}
        error={!!errors.login_id}
        helperText={errors.login_id?.message}
      />

      <TextField
        label="비밀번호"
        type="password"
        fullWidth
        margin="normal"
        autoComplete="new-password"
        {...register("password")}
        error={!!errors.password}
        helperText={errors.password?.message}
      />

      <TextField
        label="이름"
        fullWidth
        margin="normal"
        {...register("name")}
        error={!!errors.name}
        helperText={errors.name?.message}
      />

      <TextField
        label="생년월일"
        type="date"
        fullWidth
        margin="normal"
        slotProps={{ inputLabel: { shrink: true } }}
        {...register("birth_date")}
        error={!!errors.birth_date}
        helperText={errors.birth_date?.message}
      />

      <Button
        type="submit"
        variant="contained"
        fullWidth
        size="large"
        sx={{ mt: 3 }}
        disabled={registerMutation.isPending}
      >
        {registerMutation.isPending ? "가입 중..." : "회원가입"}
      </Button>

      <Typography align="center" sx={{ mt: 2 }}>
        이미 계정이 있으신가요?{" "}
        <MuiLink component={Link} to="/login">
          로그인
        </MuiLink>
      </Typography>
    </Box>
  );
}
// src/pages/LoginPage.tsx
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Link } from "react-router-dom";
import { Box, TextField, Button, Alert, Typography, Link as MuiLink } from "@mui/material";
import { useLogin } from "../hooks/useAuth";
import { ApiError } from "../api/client";

const loginSchema = z.object({
  login_id: z.string().min(1, "아이디를 입력해주세요."),
  password: z.string().min(1, "비밀번호를 입력해주세요."),
});

type LoginFormValues = z.infer<typeof loginSchema>;

export default function LoginPage() {
  const login = useLogin();
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
  });

  const onSubmit = (data: LoginFormValues) => {
    login.mutate(data);
  };

  return (
    <Box component="form" onSubmit={handleSubmit(onSubmit)} sx={{ mt: 2 }}>
      {login.isError && login.error instanceof ApiError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {login.error.status === 423
            ? "로그인 시도가 많아 계정이 잠겼습니다. 30분 후 다시 시도해주세요."
            : login.error.message}
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
        autoComplete="current-password"
        {...register("password")}
        error={!!errors.password}
        helperText={errors.password?.message}
      />

      <Button
        type="submit"
        variant="contained"
        fullWidth
        size="large"
        sx={{ mt: 3 }}
        disabled={login.isPending}
      >
        {login.isPending ? "로그인 중..." : "로그인"}
      </Button>

      <Typography align="center" sx={{ mt: 2 }}>
        계정이 없으신가요?{" "}
        <MuiLink component={Link} to="/register">
          회원가입
        </MuiLink>
      </Typography>
    </Box>
  );
}
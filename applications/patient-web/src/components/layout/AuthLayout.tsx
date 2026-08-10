// src/components/layout/AuthLayout.tsx
import { Box, Container, Paper, Typography } from "@mui/material";
import { Outlet } from "react-router-dom";

export default function AuthLayout() {
  return (
    <Box
      sx={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        minHeight: "100vh",
        bgcolor: "grey.50",
      }}
    >
      <Container maxWidth="xs">
        <Paper elevation={2} sx={{ p: 4 }}>
          <Typography variant="h5" align="center" gutterBottom>
            병원 예약 시스템
          </Typography>
          <Outlet />
        </Paper>
      </Container>
    </Box>
  );
}
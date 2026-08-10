// src/components/layout/AppLayout.tsx
import { AppBar, Toolbar, Typography, Button, Box, Container } from "@mui/material";
import { Link, Outlet } from "react-router-dom";
import { useLogout } from "../../hooks/useAuth";

export default function AppLayout() {
  const logout = useLogout();

  return (
    <Box sx={{ display: "flex", flexDirection: "column", minHeight: "100vh" }}>
      <AppBar position="static">
        <Toolbar sx={{ gap: 2 }}>
          <Typography
            variant="h6"
            component={Link}
            to="/"
            sx={{ flexGrow: 1, color: "inherit", textDecoration: "none" }}
          >
            병원 예약
          </Typography>
          <Button color="inherit" component={Link} to="/doctors">
            진료 예약
          </Button>
          <Button color="inherit" component={Link} to="/appointments">
            내 예약
          </Button>
          <Button color="inherit" component={Link} to="/records">
            진료기록
          </Button>
          <Button
            color="inherit"
            onClick={() => logout.mutate()}
            disabled={logout.isPending}
          >
            로그아웃
          </Button>
        </Toolbar>
      </AppBar>

      <Container component="main" sx={{ flexGrow: 1, py: 4 }}>
        <Outlet />
      </Container>
    </Box>
  );
}
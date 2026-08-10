// src/App.tsx
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import AppLayout from "./components/layout/AppLayout";
import AuthLayout from "./components/layout/AuthLayout";
import LoginPage from "./pages/LoginPage";
import RegisterPage from "./pages/RegisterPage";
import HomePage from "./pages/HomePage";
import DoctorsPage from "./pages/DoctorsPage";
import AppointmentsPage from "./pages/AppointmentsPage";
import RecordsPage from "./pages/RecordsPage";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: false },
  },
});

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          <Route element={<AuthLayout />}>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/register" element={<RegisterPage />} />
          </Route>

          <Route element={<AppLayout />}>
            <Route path="/" element={<HomePage />} />
            <Route path="/doctors" element={<DoctorsPage />} />
            <Route path="/appointments" element={<AppointmentsPage />} />
            <Route path="/records" element={<RecordsPage />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}

export default App;
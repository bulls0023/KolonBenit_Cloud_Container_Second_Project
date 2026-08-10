// src/pages/AppointmentsPage.tsx
import {
  Box,
  Typography,
  List,
  ListItem,
  ListItemText,
  Chip,
  Button,
  CircularProgress,
  Alert,
} from "@mui/material";
import { useAppointments, useCancelAppointment } from "../hooks/useAppointments";
import { ApiError } from "../api/client";

export default function AppointmentsPage() {
  const { data, isLoading } = useAppointments();
  const cancelAppointment = useCancelAppointment();

  const handleCancel = (id: number) => {
    if (!confirm("예약을 취소하시겠습니까?")) return;
    cancelAppointment.mutate(id);
  };

  if (isLoading) return <CircularProgress />;

  return (
    <Box>
      <Typography variant="h5" gutterBottom>
        내 예약 목록
      </Typography>

      {cancelAppointment.isError && cancelAppointment.error instanceof ApiError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {cancelAppointment.error.message}
        </Alert>
      )}

      {data?.appointments.length === 0 && (
        <Typography color="text.secondary">예약 내역이 없습니다.</Typography>
      )}

      <List>
        {data?.appointments.map((appt) => (
          <ListItem
            key={appt.id}
            divider
            secondaryAction={
              appt.cancellable && (
                <Button
                  color="error"
                  size="small"
                  disabled={cancelAppointment.isPending}
                  onClick={() => handleCancel(appt.id)}
                >
                  취소
                </Button>
              )
            }
          >
            <ListItemText
              primary={`${appt.date} ${appt.time} — ${appt.doctor_name} (${appt.dept})`}
              secondary={`예약번호 ${appt.visit_no}`}
            />
            <Chip
              label={appt.status}
              size="small"
              color={
                appt.status === "예약"
                  ? "primary"
                  : appt.status === "취소"
                  ? "default"
                  : "success"
              }
              sx={{ mr: appt.cancellable ? 10 : 0 }}
            />
          </ListItem>
        ))}
      </List>
    </Box>
  );
}
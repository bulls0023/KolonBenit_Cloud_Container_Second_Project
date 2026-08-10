// src/pages/DoctorsPage.tsx
import { useState } from "react";
import {
  Box,
  Typography,
  List,
  ListItemButton,
  ListItemText,
  Chip,
  TextField,
  Button,
  Alert,
  CircularProgress,
} from "@mui/material";
import { useDoctors, useSlots } from "../hooks/useDoctors";
import { useCreateAppointment } from "../hooks/useAppointments";
import { ApiError } from "../api/client";
import type { Doctor } from "../api/types";

export default function DoctorsPage() {
  const [selectedDoctor, setSelectedDoctor] = useState<Doctor | null>(null);
  const [date, setDate] = useState<string>("");
  const [selectedTime, setSelectedTime] = useState<string | null>(null);

  const { data: doctorsData, isLoading: doctorsLoading } = useDoctors();
  const { data: slotsData, isLoading: slotsLoading } = useSlots(
    selectedDoctor?.id,
    date || undefined
  );
  const createAppointment = useCreateAppointment();

  const handleSelectDoctor = (doctor: Doctor) => {
    setSelectedDoctor(doctor);
    setSelectedTime(null);
  };

  const handleBook = () => {
    if (!selectedDoctor || !date || !selectedTime) return;
    createAppointment.mutate(
      { doctor_id: selectedDoctor.id, date, time: selectedTime },
      {
        onSuccess: () => {
          setSelectedTime(null);
          alert("예약이 완료되었습니다.");
        },
      }
    );
  };

  return (
    <Box>
      <Typography variant="h5" gutterBottom>
        진료 예약
      </Typography>

      <Box sx={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
        {/* 1. 의사 목록 */}
        <Box sx={{ minWidth: 280 }}>
          <Typography variant="subtitle1" gutterBottom>
            의사 선택
          </Typography>
          {doctorsLoading ? (
            <CircularProgress size={24} />
          ) : (
            <List>
              {doctorsData?.doctors.map((doctor) => (
                <ListItemButton
                  key={doctor.id}
                  selected={selectedDoctor?.id === doctor.id}
                  onClick={() => handleSelectDoctor(doctor)}
                >
                  <ListItemText
                    primary={`${doctor.name} (${doctor.dept})`}
                    secondary={`진료시간 ${doctor.slot_minutes}분`}
                  />
                </ListItemButton>
              ))}
            </List>
          )}
        </Box>

        {/* 2. 날짜/슬롯 선택 */}
        {selectedDoctor && (
          <Box sx={{ minWidth: 280 }}>
            <Typography variant="subtitle1" gutterBottom>
              날짜 및 시간 선택
            </Typography>
            <TextField
              type="date"
              fullWidth
              value={date}
              onChange={(e) => {
                setDate(e.target.value);
                setSelectedTime(null);
              }}
              slotProps={{ inputLabel: { shrink: true } }}
              sx={{ mb: 2 }}
            />

            {slotsLoading && date && <CircularProgress size={24} />}

            {slotsData && (
              <Box sx={{ display: "flex", flexWrap: "wrap", gap: 1 }}>
                {slotsData.slots.length === 0 && (
                  <Typography color="text.secondary">
                    해당 날짜는 휴진입니다.
                  </Typography>
                )}
                {slotsData.slots.map((slot) => (
                  <Chip
                    key={slot.time}
                    label={slot.time}
                    color={selectedTime === slot.time ? "primary" : "default"}
                    disabled={!slot.available}
                    onClick={() => slot.available && setSelectedTime(slot.time)}
                    clickable={slot.available}
                  />
                ))}
              </Box>
            )}

            {selectedTime && (
              <Box sx={{ mt: 3 }}>
                {createAppointment.isError &&
                  createAppointment.error instanceof ApiError && (
                    <Alert severity="error" sx={{ mb: 2 }}>
                      {createAppointment.error.message}
                    </Alert>
                  )}
                <Button
                  variant="contained"
                  fullWidth
                  size="large"
                  disabled={createAppointment.isPending}
                  onClick={handleBook}
                >
                  {createAppointment.isPending
                    ? "예약 중..."
                    : `${date} ${selectedTime} 예약하기`}
                </Button>
              </Box>
            )}
          </Box>
        )}
      </Box>
    </Box>
  );
}
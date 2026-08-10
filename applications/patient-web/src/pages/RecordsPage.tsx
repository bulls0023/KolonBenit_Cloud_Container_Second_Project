// src/pages/RecordsPage.tsx
import { useState } from "react";
import {
  Box,
  Typography,
  List,
  ListItemButton,
  ListItemText,
  Chip,
  CircularProgress,
  Dialog,
  DialogTitle,
  DialogContent,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
} from "@mui/material";
import { useRecords, usePrescription } from "../hooks/useRecords";

export default function RecordsPage() {
  const { data, isLoading } = useRecords();
  const [selectedRecordId, setSelectedRecordId] = useState<number | null>(null);

  const { data: prescriptionData, isLoading: prescriptionLoading } =
    usePrescription(selectedRecordId ?? undefined);

  if (isLoading) return <CircularProgress />;

  return (
    <Box>
      <Typography variant="h5" gutterBottom>
        진료기록
      </Typography>

      {data?.records.length === 0 && (
        <Typography color="text.secondary">진료기록이 없습니다.</Typography>
      )}

      <List>
        {data?.records.map((record) => (
          <ListItemButton
            key={record.id}
            disabled={!record.has_prescription}
            onClick={() => record.has_prescription && setSelectedRecordId(record.id)}
          >
            <ListItemText
              primary={`${record.date} — ${record.doctor_name} (${record.dept})`}
              secondary={`${record.chief_complaint} / ${record.diagnosis}`}
            />
            {record.has_prescription && <Chip label="처방전 보기" size="small" color="primary" />}
          </ListItemButton>
        ))}
      </List>

      <Dialog
        open={selectedRecordId !== null}
        onClose={() => setSelectedRecordId(null)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>처방전</DialogTitle>
        <DialogContent>
          {prescriptionLoading && <CircularProgress size={24} />}
          {prescriptionData && (
            <Box>
              <Typography gutterBottom>
                {prescriptionData.prescription.doctor_name} (
                {prescriptionData.prescription.dept}) —{" "}
                {prescriptionData.prescription.diagnosis}
              </Typography>
              <Typography variant="body2" color="text.secondary" gutterBottom>
                발행일 {prescriptionData.prescription.issued_at} · 유효기간{" "}
                {prescriptionData.prescription.valid_days}일
              </Typography>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>약품명</TableCell>
                    <TableCell>용량</TableCell>
                    <TableCell>횟수</TableCell>
                    <TableCell>일수</TableCell>
                    <TableCell>복약안내</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {prescriptionData.prescription.items.map((item, idx) => (
                    <TableRow key={idx}>
                      <TableCell>{item.drug_name}</TableCell>
                      <TableCell>{item.dosage}</TableCell>
                      <TableCell>{item.frequency}</TableCell>
                      <TableCell>{item.duration_days}일</TableCell>
                      <TableCell>{item.instruction}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </Box>
          )}
        </DialogContent>
      </Dialog>
    </Box>
  );
}
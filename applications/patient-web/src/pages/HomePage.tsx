// src/pages/HomePage.tsx
import { Box, Typography, Card, CardActionArea, CardContent } from "@mui/material";
import { useNavigate } from "react-router-dom";
import EventAvailableIcon from "@mui/icons-material/EventAvailable";
import ListAltIcon from "@mui/icons-material/ListAlt";
import DescriptionIcon from "@mui/icons-material/Description";

const menuItems = [
  {
    to: "/doctors",
    icon: <EventAvailableIcon fontSize="large" color="primary" />,
    title: "진료 예약",
    description: "의사와 날짜를 선택해 예약하세요",
  },
  {
    to: "/appointments",
    icon: <ListAltIcon fontSize="large" color="primary" />,
    title: "내 예약 확인",
    description: "예약 내역을 확인하고 취소할 수 있어요",
  },
  {
    to: "/records",
    icon: <DescriptionIcon fontSize="large" color="primary" />,
    title: "진료기록·처방전",
    description: "지난 진료 내역과 처방전을 확인하세요",
  },
];

export default function HomePage() {
  const navigate = useNavigate();

  return (
    <Box>
      <Typography variant="h5" gutterBottom>
        환영합니다
      </Typography>
      <Typography color="text.secondary" sx={{ mb: 4 }}>
        아래 메뉴에서 원하는 서비스를 선택하세요.
      </Typography>

      <Box sx={{ display: "flex", gap: 3, flexWrap: "wrap" }}>
        {menuItems.map((item) => (
          <Card key={item.to} sx={{ width: 240 }}>
            <CardActionArea onClick={() => navigate(item.to)}>
              <CardContent sx={{ textAlign: "center", py: 4 }}>
                {item.icon}
                <Typography variant="h6" sx={{ mt: 1 }}>
                  {item.title}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  {item.description}
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        ))}
      </Box>
    </Box>
  );
}
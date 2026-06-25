import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import AdminView from './views/AdminView';
import SpeakerView from './views/SpeakerView';

const adminLayout: React.CSSProperties = {
  maxWidth: 800,
  margin: '40px auto',
  padding: '0 16px',
};

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/admin" element={<div style={adminLayout}><AdminView /></div>} />
        <Route path="/speaker" element={<SpeakerView />} />
        <Route path="*" element={<Navigate to="/admin" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

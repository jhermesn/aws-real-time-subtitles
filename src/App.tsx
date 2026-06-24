import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import AdminView from './views/AdminView';
import SpeakerView from './views/SpeakerView';

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/admin" element={<AdminView />} />
        <Route path="/speaker" element={<SpeakerView />} />
        <Route path="*" element={<Navigate to="/admin" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

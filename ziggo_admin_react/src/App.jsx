import { Routes, Route, Navigate } from 'react-router-dom'
import { useEffect, useState } from 'react'
import { api } from './api'
import Login from './pages/Login.jsx'
import Layout from './components/Layout.jsx'
import Dashboard from './pages/Dashboard.jsx'
import Referrals from './pages/Referrals.jsx'

export default function App() {
  const [auth, setAuth] = useState(null) // null = loading, false = logged out, object = user

  useEffect(() => {
    api.me().then(setAuth).catch(() => setAuth(false))
  }, [])

  if (auth === null) {
    return <div className="h-screen flex items-center justify-center text-ziggo-muted font-bold">Loading…</div>
  }

  return (
    <Routes>
      <Route path="/login" element={auth ? <Navigate to="/" replace /> : <Login onLogin={setAuth} />} />
      <Route path="/" element={auth ? <Layout user={auth} /> : <Navigate to="/login" replace />}>
        <Route index element={<Dashboard />} />
        <Route path="referrals" element={<Referrals />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

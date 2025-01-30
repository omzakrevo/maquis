import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';
import { useAuth } from './lib/auth';
import { LicenseCheck } from './components/LicenseCheck';
import { OfflineIndicator } from './components/OfflineIndicator';
import Login from './pages/Login';
import License from './pages/License';
import Dashboard from './pages/Dashboard';
import Products from './pages/Products';
import Orders from './pages/Orders';
import Users from './pages/Users';
import Payments from './pages/Payments';
import Reports from './pages/Reports';
import Layout from './components/Layout';
import Settings from './pages/Settings';

function PrivateRoute({ children, requireAdmin = false }: { children: React.ReactNode, requireAdmin?: boolean }) {
  const { user } = useAuth();
  
  if (!user) return <Navigate to="/login" />;
  if (requireAdmin && user.role !== 'admin') return <Navigate to="/orders" />;
  
  return <>{children}</>;
}

function App() {
  const { user } = useAuth();

  return (
    <BrowserRouter>
      <Toaster position="top-right" />
      <OfflineIndicator />
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/license" element={<License />} />
        
        <Route path="/" element={
          <LicenseCheck>
            <PrivateRoute>
              <Layout />
            </PrivateRoute>
          </LicenseCheck>
        }>
          <Route index element={
            <Navigate to={user?.role === 'admin' ? "/dashboard" : "/orders"} replace />
          } />
          <Route path="dashboard" element={
            <PrivateRoute requireAdmin>
              <Dashboard />
            </PrivateRoute>
          } />
          <Route path="products" element={<Products />} />
          <Route path="orders" element={<Orders />} />
          <Route path="payments" element={
            <PrivateRoute requireAdmin>
              <Payments />
            </PrivateRoute>
          } />
          <Route path="reports" element={
            <PrivateRoute requireAdmin>
              <Reports />
            </PrivateRoute>
          } />
          <Route path="users" element={
            <PrivateRoute requireAdmin>
              <Users />
            </PrivateRoute>
          } />
          <Route path="settings" element={
            <PrivateRoute requireAdmin>
              <Settings />
            </PrivateRoute>
          } />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default App;
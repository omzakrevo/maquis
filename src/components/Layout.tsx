import React from 'react';
import { Outlet, Link, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../lib/auth';
import { 
  LayoutDashboard, 
  Package, 
  ClipboardList, 
  Users,
  LogOut,
  GlassesIcon,
  DollarSign,
  Settings as SettingsIcon,
  FileText
} from 'lucide-react';
import { cn } from '../lib/utils';

function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const navigation = [
    ...(user?.role === 'admin' ? [
      { name: 'Tableau de bord', href: '/dashboard', icon: LayoutDashboard }
    ] : []),
    { name: 'Commandes', href: '/orders', icon: ClipboardList },
    { name: 'Produits', href: '/products', icon: Package },
    ...(user?.role === 'admin' ? [
      { name: 'Paiements', href: '/payments', icon: DollarSign },
      { name: 'Rapports', href: '/reports', icon: FileText },
      { name: 'Utilisateurs', href: '/users', icon: Users },
      { name: 'Paramètres', href: '/settings', icon: SettingsIcon }
    ] : [])
  ];

  return (
    <div className="min-h-screen bg-background">
      {/* Mobile header */}
      <div className="lg:hidden bg-card border-b border-border px-4 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center">
            <GlassesIcon className="w-8 h-8 text-primary mr-2" />
            <span className="text-xl font-semibold text-foreground">Maquis Manager</span>
          </div>
          <div className="flex items-center space-x-4">
            <span className="text-sm text-muted-foreground">{user?.username}</span>
            <button
              onClick={handleLogout}
              className="p-2 text-muted-foreground hover:text-foreground"
            >
              <LogOut className="h-5 w-5" />
            </button>
          </div>
        </div>
        
        {/* Mobile navigation */}
        <nav className="flex overflow-x-auto py-3 -mb-3">
          {navigation.map((item) => {
            const Icon = item.icon;
            return (
              <Link
                key={item.name}
                to={item.href}
                className={cn(
                  location.pathname === item.href
                    ? 'text-primary border-primary'
                    : 'text-muted-foreground border-transparent hover:text-foreground',
                  'flex items-center px-3 py-2 text-sm font-medium border-b-2 min-w-fit'
                )}
              >
                <Icon className="h-5 w-5 mr-2" />
                {item.name}
              </Link>
            );
          })}
        </nav>
      </div>

      <div className="flex h-screen bg-background">
        {/* Desktop Sidebar */}
        <div className="hidden lg:flex lg:flex-shrink-0">
          <div className="flex flex-col w-64">
            <div className="flex flex-col flex-grow pt-5 pb-4 overflow-y-auto bg-card border-r border-border">
              <div className="flex items-center flex-shrink-0 px-4 mb-5">
                <GlassesIcon className="w-8 h-8 text-primary mr-2" />
                <span className="text-xl font-semibold text-foreground">Maquis Manager</span>
              </div>
              
              <div className="flex-grow flex flex-col">
                <nav className="flex-1 px-2 space-y-1">
                  {navigation.map((item) => {
                    const Icon = item.icon;
                    return (
                      <Link
                        key={item.name}
                        to={item.href}
                        className={cn(
                          location.pathname === item.href
                            ? 'bg-secondary text-foreground'
                            : 'text-muted-foreground hover:bg-secondary hover:text-foreground',
                          'group flex items-center px-2 py-2 text-sm font-medium rounded-md'
                        )}
                      >
                        <Icon className="mr-3 h-6 w-6" />
                        {item.name}
                      </Link>
                    );
                  })}
                </nav>
              </div>

              <div className="flex-shrink-0 flex border-t border-border p-4">
                <div className="flex items-center w-full">
                  <div>
                    <p className="text-sm font-medium text-foreground">{user?.username}</p>
                    <p className="text-xs font-medium text-muted-foreground capitalize">
                      {user?.role === 'admin' ? 'Administrateur' : 'Serveur'}
                    </p>
                  </div>
                  <button
                    onClick={handleLogout}
                    className="ml-auto flex items-center justify-center h-10 w-10 rounded-full hover:bg-secondary"
                  >
                    <LogOut className="h-5 w-5 text-muted-foreground" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Main content */}
        <div className="flex flex-col flex-1 overflow-hidden">
          <main className="flex-1 relative overflow-y-auto focus:outline-none">
            <div className="py-6">
              <div className="max-w-7xl mx-auto px-4 sm:px-6 md:px-8">
                <Outlet />
              </div>
            </div>
          </main>
        </div>
      </div>
    </div>
  );
}

export default Layout;
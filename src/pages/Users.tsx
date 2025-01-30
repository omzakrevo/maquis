import React from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Plus, Pencil, Trash2, X, Search } from 'lucide-react';
import toast from 'react-hot-toast';
import bcrypt from 'bcryptjs';
import db from '../lib/db';
import { useAuth } from '../lib/auth';
import type { User } from '../lib/db';

const userSchema = z.object({
  username: z.string()
    .min(3, 'Le nom d\'utilisateur doit contenir au moins 3 caractères')
    .max(50, 'Le nom d\'utilisateur ne peut pas dépasser 50 caractères'),
  password: z.string()
    .min(6, 'Le mot de passe doit contenir au moins 6 caractères')
    .max(100, 'Le mot de passe ne peut pas dépasser 100 caractères'),
  role: z.enum(['admin', 'server'], {
    errorMap: () => ({ message: 'Rôle invalide' })
  })
});

type UserFormData = z.infer<typeof userSchema>;

function UserForm({ 
  onSubmit, 
  initialData = null,
  onCancel 
}: { 
  onSubmit: (data: UserFormData) => void;
  initialData?: Omit<User, 'created_at'> | null;
  onCancel: () => void;
}) {
  const { register, handleSubmit, formState: { errors } } = useForm<UserFormData>({
    resolver: zodResolver(userSchema),
    defaultValues: initialData || {
      username: '',
      password: '',
      role: 'server'
    }
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 bg-white p-6 rounded-lg shadow">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-medium">
          {initialData ? 'Modifier l\'utilisateur' : 'Nouvel utilisateur'}
        </h3>
        <button
          type="button"
          onClick={onCancel}
          className="p-2 text-gray-400 hover:text-gray-500"
        >
          <X className="h-5 w-5" />
        </button>
      </div>

      <div className="grid grid-cols-1 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">
            Nom d'utilisateur
          </label>
          <input
            type="text"
            {...register('username')}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
          />
          {errors.username && (
            <p className="mt-1 text-sm text-red-600">{errors.username.message}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">
            {initialData ? 'Nouveau mot de passe (laisser vide pour ne pas changer)' : 'Mot de passe'}
          </label>
          <input
            type="password"
            {...register('password')}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
          />
          {errors.password && (
            <p className="mt-1 text-sm text-red-600">{errors.password.message}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">
            Rôle
          </label>
          <select
            {...register('role')}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
          >
            <option value="server">Serveur</option>
            <option value="admin">Administrateur</option>
          </select>
          {errors.role && (
            <p className="mt-1 text-sm text-red-600">{errors.role.message}</p>
          )}
        </div>
      </div>

      <div className="flex justify-end space-x-3">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          Annuler
        </button>
        <button
          type="submit"
          className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          {initialData ? 'Modifier' : 'Créer'}
        </button>
      </div>
    </form>
  );
}

function Users() {
  const { user: currentUser } = useAuth();
  const [users, setUsers] = React.useState<User[]>([]);
  const [showForm, setShowForm] = React.useState(false);
  const [editingUser, setEditingUser] = React.useState<User | null>(null);
  const [searchTerm, setSearchTerm] = React.useState('');

  const loadUsers = React.useCallback(async () => {
    try {
      const results = await db.users
        .filter(user => 
          user.username.toLowerCase().includes(searchTerm.toLowerCase())
        )
        .toArray();
      setUsers(results.sort((a, b) => 
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      ));
    } catch (error) {
      console.error('Error loading users:', error);
      toast.error('Erreur lors du chargement des utilisateurs');
    }
  }, [searchTerm]);

  React.useEffect(() => {
    loadUsers();
  }, [loadUsers]);

  const handleCreateUser = async (data: UserFormData) => {
    try {
      // Check if username already exists
      const existing = await db.users
        .where('username')
        .equals(data.username)
        .count();

      if (existing > 0) {
        toast.error('Ce nom d\'utilisateur existe déjà');
        return;
      }

      const hashedPassword = await bcrypt.hash(data.password, 10);
      await db.users.add({
        username: data.username,
        password: hashedPassword,
        role: data.role,
        created_at: new Date().toISOString()
      });

      toast.success('Utilisateur créé avec succès');
      setShowForm(false);
      loadUsers();
    } catch (error) {
      console.error('Error creating user:', error);
      toast.error('Erreur lors de la création de l\'utilisateur');
    }
  };

  const handleUpdateUser = async (data: UserFormData) => {
    if (!editingUser?.id) return;

    try {
      // Check if username already exists for other users
      const existing = await db.users
        .where('username')
        .equals(data.username)
        .filter(u => u.id !== editingUser.id)
        .count();
      
      if (existing > 0) {
        toast.error('Ce nom d\'utilisateur existe déjà');
        return;
      }

      const updateData: Partial<User> = {
        username: data.username,
        role: data.role
      };

      if (data.password) {
        updateData.password = await bcrypt.hash(data.password, 10);
      }

      await db.users.update(editingUser.id, updateData);

      toast.success('Utilisateur mis à jour avec succès');
      setEditingUser(null);
      loadUsers();
    } catch (error) {
      console.error('Error updating user:', error);
      toast.error('Erreur lors de la mise à jour de l\'utilisateur');
    }
  };

  const handleDeleteUser = async (userId: number) => {
    if (userId === currentUser?.id) {
      toast.error('Vous ne pouvez pas supprimer votre propre compte');
      return;
    }

    const user = await db.users.get(userId);
    if (!user) return;

    if (user.role === 'admin') {
      const adminCount = await db.users
        .where('role')
        .equals('admin')
        .count();

      if (adminCount <= 1) {
        toast.error('Impossible de supprimer le dernier administrateur');
        return;
      }
    }

    if (!window.confirm('Êtes-vous sûr de vouloir supprimer cet utilisateur ?')) return;

    try {
      await db.users.delete(userId);
      toast.success('Utilisateur supprimé avec succès');
      loadUsers();
    } catch (error) {
      console.error('Error deleting user:', error);
      toast.error('Erreur lors de la suppression de l\'utilisateur');
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-semibold text-gray-900">Utilisateurs</h1>
        <button
          onClick={() => setShowForm(true)}
          className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          <Plus className="h-5 w-5 inline-block mr-2" />
          Nouvel utilisateur
        </button>
      </div>

      <div className="flex justify-between items-center bg-white p-4 rounded-lg shadow">
        <div className="relative flex-1 max-w-xs">
          <input
            type="text"
            placeholder="Rechercher un utilisateur..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
          />
          <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            <Search className="h-5 w-5 text-gray-400" />
          </div>
        </div>
      </div>

      {(showForm || editingUser) && (
        <UserForm
          onSubmit={editingUser ? handleUpdateUser : handleCreateUser}
          initialData={editingUser}
          onCancel={() => {
            setShowForm(false);
            setEditingUser(null);
          }}
        />
      )}

      <div className="bg-white shadow rounded-lg">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Utilisateur
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Rôle
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Date de création
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {users.map((user) => (
              <tr key={user.id}>
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  {user.username}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${
                    user.role === 'admin' 
                      ? 'bg-purple-100 text-purple-800' 
                      : 'bg-green-100 text-green-800'
                  }`}>
                    {user.role === 'admin' ? 'Administrateur' : 'Serveur'}
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {new Date(user.created_at).toLocaleString()}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <button
                    onClick={() => setEditingUser(user)}
                    className="text-blue-600 hover:text-blue-900 mr-4"
                  >
                    <Pencil className="h-5 w-5 inline-block" />
                  </button>
                  {user.id !== currentUser?.id && (
                    <button
                      onClick={() => handleDeleteUser(user.id!)}
                      className="text-red-600 hover:text-red-900"
                    >
                      <Trash2 className="h-5 w-5 inline-block" />
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default Users;
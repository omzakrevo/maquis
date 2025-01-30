import React from 'react';
import { useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Key, ShieldCheck, AlertTriangle } from 'lucide-react';
import toast from 'react-hot-toast';
import { useLicense } from '../lib/license';

const licenseSchema = z.object({
  key: z.string()
    .min(1, 'La clé de licence est requise')
});

type LicenseForm = z.infer<typeof licenseSchema>;

function License() {
  const navigate = useNavigate();
  const { license, validateLicense } = useLicense();
  const { register, handleSubmit, formState: { errors } } = useForm<LicenseForm>({
    resolver: zodResolver(licenseSchema)
  });

  const onSubmit = async (data: LicenseForm) => {
    try {
      const isValid = await validateLicense(data.key);
      if (isValid) {
        toast.success('Licence activée avec succès');
        navigate('/');
      } else {
        toast.error('Clé de licence invalide ou expirée');
      }
    } catch (error) {
      console.error('Error validating license:', error);
      toast.error('Erreur lors de la validation de la licence');
    }
  };

  return (
    <div className="min-h-screen bg-gray-100 flex items-center justify-center">
      <div className="bg-white p-8 rounded-lg shadow-md w-full max-w-md">
        <div className="flex flex-col items-center mb-8">
          <Key className="w-12 h-12 text-blue-600 mb-2" />
          <h1 className="text-2xl font-bold text-gray-900">Activation de la licence</h1>
          <p className="text-gray-600 text-center mt-2">
            Entrez votre clé de licence pour activer le logiciel
          </p>
        </div>

        {license && (
          <div className="mb-6 p-4 bg-blue-50 rounded-lg">
            <div className="flex items-center mb-2">
              <ShieldCheck className="h-5 w-5 text-blue-600 mr-2" />
              <h2 className="text-sm font-medium text-blue-900">Licence actuelle</h2>
            </div>
            <div className="space-y-2 text-sm text-blue-800">
              <p>Clé: {license.key}</p>
              <p>Expire le: {new Date(license.expiresAt).toLocaleDateString()}</p>
              <p>Période: {license.period}</p>
              <p>Statut: {license.status === 'active' ? 'Active' : 'Expirée'}</p>
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700">
              Clé de licence
            </label>
            <input
              type="text"
              {...register('key')}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
            />
            {errors.key && (
              <p className="mt-1 text-sm text-red-600">{errors.key.message}</p>
            )}
          </div>

          <div className="bg-yellow-50 rounded-lg p-4">
            <div className="flex">
              <AlertTriangle className="h-5 w-5 text-yellow-400 mr-2" />
              <div>
                <h3 className="text-sm font-medium text-yellow-800">
                  Information
                </h3>
                <p className="text-sm text-yellow-700 mt-1">
                  Utilisez une clé de licence valide depuis Google Sheets
                </p>
              </div>
            </div>
          </div>

          <button
            type="submit"
            className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
          >
            Activer la licence
          </button>
        </form>
      </div>
    </div>
  );
}

export default License;
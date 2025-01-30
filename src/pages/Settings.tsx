import React from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Save, Moon, Sun, Palette, User, Mail, Phone } from 'lucide-react';
import toast from 'react-hot-toast';
import db from '../lib/db';
import type { Settings } from '../lib/db';
import { useTheme, type Theme } from '../lib/theme';

const settingsSchema = z.object({
  name: z.string()
    .min(1, 'Le nom est requis')
    .max(100, 'Le nom ne peut pas dépasser 100 caractères'),
  phone: z.string()
    .min(1, 'Le numéro de téléphone est requis')
    .max(20, 'Le numéro de téléphone ne peut pas dépasser 20 caractères')
});

type SettingsFormData = z.infer<typeof settingsSchema>;

const themes: { value: Theme; label: string; icon: typeof Sun }[] = [
  { value: 'light', label: 'Clair', icon: Sun },
  { value: 'dark', label: 'Sombre', icon: Moon },
  { value: 'blue', label: 'Bleu', icon: Palette },
  { value: 'green', label: 'Vert', icon: Palette },
];

function ColorPicker({ onChange }: { onChange: (color: string) => void }) {
  const [color, setColor] = React.useState('#000000');

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newColor = e.target.value;
    setColor(newColor);
    onChange(newColor);
  };

  return (
    <div className="flex items-center space-x-4">
      <input
        type="color"
        value={color}
        onChange={handleChange}
        className="w-12 h-12 p-1 rounded border border-gray-300 cursor-pointer"
      />
      <span className="text-sm text-gray-600">{color}</span>
    </div>
  );
}

function Settings() {
  const [settings, setSettings] = React.useState<Settings | null>(null);
  const { theme, setTheme, setPrimaryColor } = useTheme();
  const { register, handleSubmit, formState: { errors, isDirty } } = useForm<SettingsFormData>({
    resolver: zodResolver(settingsSchema),
    defaultValues: {
      name: '',
      phone: ''
    }
  });

  React.useEffect(() => {
    async function loadSettings() {
      try {
        const allSettings = await db.settings.toArray();
        const currentSettings = allSettings[0];
        if (currentSettings) {
          setSettings(currentSettings);
        }
      } catch (error) {
        console.error('Error loading settings:', error);
        toast.error('Erreur lors du chargement des paramètres');
      }
    }

    loadSettings();
  }, []);

  React.useEffect(() => {
    if (settings) {
      // Update form values when settings are loaded
      const form = document.querySelector('form');
      if (form) {
        const nameInput = form.querySelector('input[name="name"]') as HTMLInputElement;
        const phoneInput = form.querySelector('input[name="phone"]') as HTMLInputElement;
        if (nameInput) nameInput.value = settings.name;
        if (phoneInput) phoneInput.value = settings.phone;
      }
    }
  }, [settings]);

  const onSubmit = async (data: SettingsFormData) => {
    try {
      if (settings?.id) {
        await db.settings.update(settings.id, {
          ...data,
          updated_at: new Date().toISOString()
        });
      } else {
        await db.settings.add({
          ...data,
          updated_at: new Date().toISOString()
        });
      }

      toast.success('Paramètres mis à jour avec succès');
    } catch (error) {
      console.error('Error updating settings:', error);
      toast.error('Erreur lors de la mise à jour des paramètres');
    }
  };

  const handleColorChange = (color: string) => {
    setPrimaryColor(color);
    toast.success('Couleur principale mise à jour');
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">Paramètres</h1>
      </div>

      <div className="bg-white shadow rounded-lg">
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-6 p-6">
          <div>
            <label className="block text-sm font-medium text-gray-700">
              Nom du maquis
            </label>
            <input
              type="text"
              {...register('name')}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
            />
            {errors.name && (
              <p className="mt-1 text-sm text-red-600">{errors.name.message}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">
              Numéro de téléphone
            </label>
            <input
              type="text"
              {...register('phone')}
              className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
            />
            {errors.phone && (
              <p className="mt-1 text-sm text-red-600">{errors.phone.message}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Thème
            </label>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              {themes.map(({ value, label, icon: Icon }) => (
                <button
                  key={value}
                  type="button"
                  onClick={() => {
                    setTheme(value);
                    toast.success(`Thème ${label} appliqué`);
                  }}
                  className={`flex items-center justify-center space-x-2 p-4 rounded-lg border-2 transition-colors ${
                    theme === value
                      ? 'border-blue-500 bg-blue-50 text-blue-700'
                      : 'border-gray-200 hover:border-gray-300'
                  }`}
                >
                  <Icon className="h-5 w-5" />
                  <span>{label}</span>
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Couleur personnalisée
            </label>
            <ColorPicker onChange={handleColorChange} />
            <p className="mt-2 text-sm text-gray-500">
              Choisissez une couleur personnalisée pour l'interface
            </p>
          </div>

          <div className="flex justify-end">
            <button
              type="submit"
              disabled={!isDirty}
              className="flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
            >
              <Save className="h-5 w-5 mr-2" />
              Enregistrer
            </button>
          </div>
        </form>
      </div>

      <div className="bg-white shadow rounded-lg p-6">
        <h2 className="text-lg font-medium text-gray-900 mb-4">À propos</h2>
        <div className="space-y-4">
          <div className="flex items-center space-x-3">
            <User className="h-5 w-5 text-gray-400" />
            <div>
              <p className="text-sm font-medium text-gray-900">Développeur</p>
              <p className="text-sm text-gray-500">SOME ZACHARI</p>
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <Phone className="h-5 w-5 text-gray-400" />
            <div>
              <p className="text-sm font-medium text-gray-900">Contact</p>
              <p className="text-sm text-gray-500">+22655643842</p>
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <Mail className="h-5 w-5 text-gray-400" />
            <div>
              <p className="text-sm font-medium text-gray-900">Email</p>
              <p className="text-sm text-gray-500">omzakrevo@gmail.com</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default Settings;
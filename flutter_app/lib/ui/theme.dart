// Identité visuelle sobre : surfaces claires, texte encre, un seul accent orange.
// Les photos des produits apportent la couleur ; l'interface reste calme.
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/models.dart';

class AppColors {
  // Couleurs de marque : elles changent avec le type d'établissement
  // (Paramètres > Type d'établissement), voir [apply].
  static Color ink = const Color(0xFF2A2420); // texte principal, éléments sombres
  static Color get brick => ink; // (ancien nom) titres et textes forts
  static Color orange = const Color(0xFFE8590C); // accent unique (vert en pharmacie)
  static const red = Color(0xFFC92A2A);
  static const amber = Color(0xFFF2A65A); // accent doux (paiement partiel)
  static Color gold = const Color(0xFFFFEDE0); // fond pâle des pastilles de prix
  static const green = Color(0xFF2F9E44); // succès uniquement
  static Color night = const Color(0xFF1F1B18); // barre latérale
  static Color cream = const Color(0xFFF6F4F1); // fond des écrans
  static const paper = Colors.white;
  static Color line = const Color(0xFFE7E2DC); // bordures fines
  static Color muted = const Color(0xFF7A716B); // texte secondaire

  static LinearGradient get headerGradient => LinearGradient(colors: [ink, Color.lerp(ink, Colors.white, 0.1)!], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static LinearGradient get warmGradient => headerGradient;

  static BusinessMode _mode = BusinessMode.restaurant;
  static BusinessMode get mode => _mode;

  /// Prévient l'application qu'il faut tout redessiner avec la nouvelle palette.
  static final notifier = ValueNotifier<BusinessMode>(BusinessMode.restaurant);

  /// Applique la palette du type d'établissement : chaude (maquis, boutique)
  /// ou sobre et verte (pharmacie). Reconstruire l'application ensuite.
  static void apply(BusinessMode m) {
    _mode = m;
    notifier.value = m;
    if (m == BusinessMode.pharmacy) {
      ink = const Color(0xFF1F2D2B);
      orange = const Color(0xFF0B8A62);
      gold = const Color(0xFFE3F4EC);
      night = const Color(0xFF14211F);
      cream = const Color(0xFFF3F7F6);
      line = const Color(0xFFDCE6E3);
      muted = const Color(0xFF667673);
    } else {
      ink = const Color(0xFF2A2420);
      orange = const Color(0xFFE8590C);
      gold = const Color(0xFFFFEDE0);
      night = const Color(0xFF1F1B18);
      cream = const Color(0xFFF6F4F1);
      line = const Color(0xFFE7E2DC);
      muted = const Color(0xFF7A716B);
    }
  }
}

/// Identité affichée (nom, logo) selon le type d'établissement.
class Brand {
  static bool get pharmacy => AppColors.mode == BusinessMode.pharmacy;

  /// Nom général de l'application (maquis, boutique, pharmacie…).
  static const appName = 'CAISSE PRO';
  static String get name => appName;
  static String get logo => pharmacy ? 'assets/brand/logo_pharma_256.png' : 'assets/brand/logo_256.png';
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.orange,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    primary: AppColors.orange,
    onPrimary: Colors.white,
    surface: AppColors.paper,
    onSurface: AppColors.ink,
  );
  final shape12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.cream,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.line),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: shape12)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape12,
        foregroundColor: AppColors.ink,
        side: BorderSide(color: AppColors.line),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.orange)),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: AppColors.line),
      backgroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.line),
      ),
    ),
    dialogTheme: DialogThemeData(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: AppColors.line),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.night,
      indicatorColor: AppColors.orange,
      selectedIconTheme: const IconThemeData(color: Colors.white),
      unselectedIconTheme: IconThemeData(color: Colors.white.withValues(alpha: 0.6)),
      selectedLabelTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.orange.withValues(alpha: 0.14),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.orange : AppColors.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontSize: 12, color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : null),
      ),
    ),
    snackBarTheme: SnackBarThemeData(backgroundColor: AppColors.ink, behavior: SnackBarBehavior.floating),
  );
  // Titres de boîtes de dialogue lisibles mais sans retour à la ligne sur petit écran.
  return theme.copyWith(
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: theme.textTheme.titleLarge!.copyWith(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink),
    ),
  );
}

/// Couleur et icône d'une catégorie (catégories inconnues : couleur stable dérivée du nom).
class CategoryStyle {
  const CategoryStyle(this.color, this.icon);
  final Color color;
  final IconData icon;

  static const _known = <String, CategoryStyle>{
    'bières': CategoryStyle(Color(0xFFE8890C), Icons.sports_bar),
    'biere': CategoryStyle(Color(0xFFE8890C), Icons.sports_bar),
    'sodas': CategoryStyle(Color(0xFFE03131), Icons.local_drink),
    'eaux': CategoryStyle(Color(0xFF1C7ED6), Icons.water_drop),
    'jus': CategoryStyle(Color(0xFFAE3EC9), Icons.emoji_food_beverage),
    'plats': CategoryStyle(Color(0xFF2F9E44), Icons.restaurant),
    'grillades': CategoryStyle(Color(0xFFC2410C), Icons.outdoor_grill),
    'vins': CategoryStyle(Color(0xFF862E9C), Icons.wine_bar),
    'liqueurs': CategoryStyle(Color(0xFF5F3DC4), Icons.liquor),
    'desserts': CategoryStyle(Color(0xFFD6336C), Icons.icecream),
    'café': CategoryStyle(Color(0xFF7C4A2D), Icons.coffee),
    // pharmacie
    'antalgiques': CategoryStyle(Color(0xFF0B8A62), Icons.medication),
    'antibiotiques': CategoryStyle(Color(0xFF1971C2), Icons.medication_liquid),
    'antipaludiques': CategoryStyle(Color(0xFF0C8599), Icons.coronavirus_outlined),
    'sirops': CategoryStyle(Color(0xFF7048E8), Icons.local_drink_outlined),
    'vitamines': CategoryStyle(Color(0xFFF08C00), Icons.spa_outlined),
    'pansements': CategoryStyle(Color(0xFFC2255C), Icons.healing),
    'hygiène': CategoryStyle(Color(0xFF1098AD), Icons.soap_outlined),
    'bébé': CategoryStyle(Color(0xFFE64980), Icons.child_care),
    'matériel médical': CategoryStyle(Color(0xFF495057), Icons.medical_services_outlined),
    'anti-inflammatoires': CategoryStyle(Color(0xFFE8590C), Icons.medication),
    'digestif': CategoryStyle(Color(0xFF5C940D), Icons.medication),
    'réhydratation': CategoryStyle(Color(0xFF1C7ED6), Icons.water_drop_outlined),
    'antiseptiques': CategoryStyle(Color(0xFF7048E8), Icons.sanitizer_outlined),
    // pièces détachées moto
    'allumage': CategoryStyle(Color(0xFFF08C00), Icons.bolt),
    'transmission': CategoryStyle(Color(0xFF495057), Icons.settings),
    'freinage': CategoryStyle(Color(0xFFC92A2A), Icons.do_not_disturb_on_outlined),
    'câbles': CategoryStyle(Color(0xFF343A40), Icons.cable),
    'filtres': CategoryStyle(Color(0xFF5C940D), Icons.filter_alt_outlined),
    'huiles': CategoryStyle(Color(0xFFE67700), Icons.oil_barrel_outlined),
    'électricité': CategoryStyle(Color(0xFF1971C2), Icons.battery_charging_full),
    'pneus': CategoryStyle(Color(0xFF212529), Icons.tire_repair),
    'roues': CategoryStyle(Color(0xFF495057), Icons.album_outlined),
    'moteur': CategoryStyle(Color(0xFF862E9C), Icons.two_wheeler),
    'accessoires': CategoryStyle(Color(0xFF0B7285), Icons.build_outlined),
  };
  static const _palette = [Color(0xFF0B7285), Color(0xFF5C940D), Color(0xFFC2255C), Color(0xFF364FC7), Color(0xFFE67700), Color(0xFF087F5B)];

  static CategoryStyle of(String category) {
    final k = category.trim().toLowerCase();
    final known = _known[k] ?? _known[k.endsWith('s') ? k.substring(0, k.length - 1) : '${k}s'];
    if (known != null) return known;
    final h = k.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    return CategoryStyle(_palette[h % _palette.length], Brand.pharmacy ? Icons.medication_outlined : (AppColors.mode == BusinessMode.shop ? Icons.inventory_2_outlined : Icons.local_offer));
  }
}

/// Photo du produit : asset embarqué, fichier de l'appareil, ou vignette colorée
/// avec l'icône de la catégorie si aucune photo.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.image, required this.category, required this.name, this.fit = BoxFit.cover});
  final String? image;
  final String category;
  final String name;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final img = image;
    Widget fallback() => _Placeholder(category: category, name: name);
    if (img == null || img.isEmpty) return fallback();
    if (img.startsWith('asset:')) {
      return Image.asset(img.substring(6), fit: fit, errorBuilder: (_, _, _) => fallback(), cacheWidth: 400);
    }
    if (img.startsWith('file:')) {
      final f = File(img.substring(5));
      return Image.file(f, fit: fit, errorBuilder: (_, _, _) => fallback(), cacheWidth: 400);
    }
    return fallback();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.category, required this.name});
  final String category;
  final String name;
  @override
  Widget build(BuildContext context) {
    final s = CategoryStyle.of(category);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [s.color, Color.lerp(s.color, Colors.black, 0.35)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: WaxPatternPainter(color: Colors.white.withValues(alpha: 0.10), spacing: 26)),
          Center(child: Icon(s.icon, size: 40, color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
  }
}

/// Motif géométrique discret inspiré des pagnes (losanges + points).
class WaxPatternPainter extends CustomPainter {
  WaxPatternPainter({required this.color, this.spacing = 46});
  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final dot = Paint()..color = color;
    final s = spacing;
    for (double y = -s; y < size.height + s; y += s) {
      final shift = ((y / s).round().isOdd) ? s / 2 : 0.0;
      for (double x = -s; x < size.width + s; x += s) {
        final cx = x + shift, cy = y;
        final path = Path()
          ..moveTo(cx, cy - s * 0.32)
          ..lineTo(cx + s * 0.32, cy)
          ..lineTo(cx, cy + s * 0.32)
          ..lineTo(cx - s * 0.32, cy)
          ..close();
        canvas.drawPath(path, p);
        canvas.drawCircle(Offset(cx, cy), s * 0.06, dot);
      }
    }
  }

  @override
  bool shouldRepaint(WaxPatternPainter old) => old.color != color || old.spacing != spacing;
}

/// Fond des écrans : uni et clair. Version sombre (écran de scan) avec motif discret.
class PatternBackground extends StatelessWidget {
  const PatternBackground({super.key, required this.child, this.dark = false});
  final Widget child;
  final bool dark;
  @override
  Widget build(BuildContext context) {
    if (!dark) {
      return ColoredBox(
        color: AppColors.cream,
        child: SizedBox.expand(child: child),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.headerGradient),
      child: CustomPaint(
        painter: WaxPatternPainter(color: Colors.white.withValues(alpha: 0.05)),
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

/// Barre d'en-tête claire avec logo (nom historique conservé).
PreferredSizeWidget gradientAppBar(BuildContext context, {required Widget title, List<Widget>? actions, bool showLogo = true, PreferredSizeWidget? bottom}) => AppBar(
  title: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showLogo && Navigator.of(context).canPop() == false) ...[ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset(Brand.logo, width: 32, height: 32)), const SizedBox(width: 10)],
      Flexible(
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontWeight: FontWeight.w800),
          child: title,
        ),
      ),
    ],
  ),
  actions: actions,
  bottom: bottom,
);

/// Logo + nom, pour l'écran de connexion.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96, this.shopName});
  final double size;
  final String? shopName;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.23),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.23),
          child: Image.asset(Brand.logo, width: size, height: size),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        Brand.name,
        style: TextStyle(color: AppColors.brick, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 15),
      ),
      if (shopName != null && shopName != Brand.name && shopName != 'MAQUIS & RESTO PRO')
        Text(
          shopName!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
    ],
  );
}

/// Carte d'indicateur : fond blanc, pastille d'icône teintée, valeur animée.
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, required this.icon, required this.color, this.width = 210});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double width;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // Petit écran : deux indicateurs par ligne au lieu d'un seul tronqué.
    builder: (context, c) => _card(c.maxWidth.isFinite && c.maxWidth < 500 ? (c.maxWidth - 8) / 2 : width, c.maxWidth.isFinite && c.maxWidth < 500),
  );

  Widget _card(double width, bool compact) => SizedBox(
    width: width,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 30 : 40,
            height: compact ? 30 : 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(compact ? 9 : 12)),
            child: Icon(icon, color: color, size: compact ? 17 : 22),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (c, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a),
                      child: c,
                    ),
                  ),
                  child: Text(
                    value,
                    key: ValueKey(value),
                    style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: compact ? 15 : 17),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Color stationColor(Station s) => s == Station.kitchen ? AppColors.green : AppColors.orange;

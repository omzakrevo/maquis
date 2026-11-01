import 'package:flutter/material.dart';

import 'data/models.dart';
import 'data/pos_repository.dart';
import 'printing/print_service.dart';
import 'ui/common.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';
import 'ui/theme.dart';

class PosApp extends StatefulWidget {
  const PosApp({super.key, required this.repo});
  final PosRepository repo;
  @override
  State<PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<PosApp> {
  final session = SessionController();
  late final printer = PrintService(widget.repo);

  @override
  void initState() {
    super.initState();
    // Palette, logo et nom selon le type d'établissement (pharmacie : vert sobre).
    widget.repo.businessMode().then(AppColors.apply);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessMode>(valueListenable: AppColors.notifier, builder: (context, mode, _) => _app(mode));
  }

  Widget _app(BusinessMode mode) {
    return AppScope(
      repo: widget.repo,
      printer: printer,
      session: session,
      child: MaterialApp(
        // Nouvelle clé = tout l'arbre est reconstruit avec les nouvelles couleurs.
        key: ValueKey(mode),
        title: Brand.name,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final u = session.user;
            if (u == null) return const LoginScreen();
            if (u.mustChangePin) return const ChangePinScreen();
            return const HomeShell();
          },
        ),
      ),
    );
  }
}

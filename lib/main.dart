import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_shell.dart';
import 'state/app_state.dart';
import 'state/theme_controller.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PokedexTcgApp());
}

class PokedexTcgApp extends StatelessWidget {
  const PokedexTcgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..load()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeController, _) => MaterialApp(
          title: 'Pokédex TCG Collection',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: themeController.mode,
          home: const AppShell(),
        ),
      ),
    );
  }
}

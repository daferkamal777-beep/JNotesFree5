import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JNotesFreeApp());
}

class JNotesFreeApp extends StatefulWidget {
  const JNotesFreeApp({super.key});

  @override
  State<JNotesFreeApp> createState() => _JNotesFreeAppState();
}

class _JNotesFreeAppState extends State<JNotesFreeApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode');
    if (!mounted) return;
    if (saved == 'dark') {
      setState(() => _themeMode = ThemeMode.dark);
    } else if (saved == 'light') {
      setState(() => _themeMode = ThemeMode.light);
    }
  }

  Future<void> toggleTheme() async {
    final systemDark = WidgetsBinding.instance.platformDispatcher
            .platformBrightness ==
        Brightness.dark;
    final currentlyDark = _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system && systemDark);
    final next = currentlyDark ? ThemeMode.light : ThemeMode.dark;
    setState(() => _themeMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      next == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JNotes Free',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: HomeScreen(onToggleTheme: () {
        toggleTheme();
      }),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme.dart';
import 'screens/login_screen.dart';
import 'screens/navigation_screen.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // INICIALIZACIÓN DE SUPABASE
  // Reemplaza [TU-SUPABASE-ANON-KEY] con tu clave pública anónima de Supabase.
  // =========================================================================
  await Supabase.initialize(
    // Tu host de Supabase (determinado a partir del esquema PostgreSQL)
    url: 'https://ovatryxuymnmceyiiuph.supabase.co',
    // Coloca aquí la Anon Key de tu proyecto Supabase (Project Settings -> API)
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im92YXRyeXh1eW1ubWNleWlpdXBoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNzQ5MTIsImV4cCI6MjA5NDk1MDkxMn0.NmjTlIOXYWYDRQ3Q0VJj2JC2BFmduw5sFmid436PDVc', 
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Determinar si hay una sesión activa de Supabase en el dispositivo
    final bool isUserLoggedIn = SupabaseService.instance.isAuthenticated;

    return MaterialApp(
      title: 'UPSGlam',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // Si el usuario ya está autenticado en el dispositivo, salta directo al Feed
      home: isUserLoggedIn ? const NavigationScreen() : const LoginScreen(),
    );
  }
}

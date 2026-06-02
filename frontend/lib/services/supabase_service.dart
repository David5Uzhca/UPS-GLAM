import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();

  SupabaseService._internal();

  final SupabaseClient client = Supabase.instance.client;

  // Verificar si el usuario está autenticado
  bool get isAuthenticated => client.auth.currentSession != null;

  // Obtener el ID del usuario actual
  String? get currentUserId => client.auth.currentUser?.id;

  // Obtener el correo del usuario actual
  String? get currentUserEmail => client.auth.currentUser?.email;

  // Obtener el token JWT (access_token) para autenticar contra Spring Boot
  String? get currentAccessToken => client.auth.currentSession?.accessToken;

  // Registrar un nuevo usuario
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    required String fullName,
  }) async {
    // Al registrarse, pasamos full_name en los metadatos para que el trigger de Supabase cree el perfil automáticamente
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'username': username,
      },
    );
    return response;
  }

  // Iniciar sesión
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response;
  }

  // Cerrar sesión
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // Obtener la información del perfil del usuario actual desde public.user_profiles
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final data = await client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return data;
    } catch (e) {
      print('Error al obtener perfil: $e');
      return null;
    }
  }

  // Actualizar el perfil del usuario (nombre completo, descripción y avatar)
  Future<void> updateUserProfile({
    required String fullName,
    required String? description,
    required String? avatarUrl,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuario no autenticado.');

    await client.from('user_profiles').update({
      'full_name': fullName,
      'description': description,
      'avatar_url': avatarUrl,
    }).eq('id', userId);
  }
}


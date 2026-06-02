import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/post.dart';

class BackendService {
  static final BackendService instance = BackendService._internal();

  BackendService._internal();

  // Si estás probando en un celular físico (por ejemplo, con datos móviles o en otra red),
  // genera una URL pública para tu backend usando localtunnel o ngrok, y pégala aquí.
  // De lo contrario, déjala vacía ('') para usar la detección local automática.
  static const String _publicTunnelUrl = '';

  // Web/desktop: localhost. Emulador Android: 10.0.2.2 apunta al host.
  static String get baseUrl {
    if (_publicTunnelUrl.isNotEmpty) {
      return _publicTunnelUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:8080';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8080';
      default:
        return 'http://localhost:8080';
    }
  }

  final SupabaseClient _supabase = SupabaseService.instance.client;

  // Crear una nueva publicación pasando por la orquestación GPU de Spring Boot
  Future<Post> createPost({
    required String originalImageUrl,
    required int filterId,
    required String description,
  }) async {
    final token = SupabaseService.instance.currentAccessToken;
    if (token == null) {
      throw Exception('Usuario no autenticado en Supabase.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/posts'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'originalImageUrl': originalImageUrl,
        'filterId': filterId,
        'description': description,
      }),
    );

    if (response.statusCode == 201) {
      final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return Post.fromJson(data);
    }

    throw Exception(_parseBackendError(response));
  }

  // Obtener todas las publicaciones (Feed) directamente desde Supabase con un JOIN relacional
  // Filtrado estricto: solo muestra imágenes de personas a las que sigues y las tuyas propias
  Future<List<Post>> getFeed() async {
    try {
      final currentUserId = SupabaseService.instance.currentUserId;
      if (currentUserId == null) return [];

      // 1. Obtener la lista de IDs de usuarios seguidos
      final followsResp = await _supabase
          .from('follows')
          .select('followed_id')
          .eq('follower_id', currentUserId);

      final List<String> followedIds = (followsResp as List)
          .map((f) => f['followed_id'] as String)
          .toList();

      if (followedIds.isEmpty) return [];

      // 2. Realizamos la consulta filtrando por los creadores en followedIds
      final List<dynamic> response = await _supabase
          .from('posts')
          .select('''
            id,
            original_image_url,
            processed_image_url,
            description,
            created_at,
            filter_id,
            user_profiles (username, avatar_url),
            gpu_metrics (image_width, image_height, block_dim_x, grid_dim_x, total_threads, execution_time_ms, status),
            likes (user_id)
          ''')
          .inFilter('user_id', followedIds)
          .order('created_at', ascending: false);

      return response.map((item) {
        // Mapeamos el formato plano de Supabase a nuestro DTO compatible con Post.fromJson
        final profile = item['user_profiles'] as Map<String, dynamic>?;
        final metricsList = item['gpu_metrics'] as List<dynamic>?;
        final Map<String, dynamic>? metrics = metricsList != null && metricsList.isNotEmpty 
            ? metricsList.first as Map<String, dynamic> 
            : null;

        final likesList = item['likes'] as List<dynamic>? ?? [];
        final int likesCount = likesList.length;
        final bool likedByMe = likesList.any((l) => l['user_id'] == currentUserId);

        return Post(
          id: item['id'] as String,
          originalImageUrl: item['original_image_url'] as String,
          processedImageUrl: item['processed_image_url'] as String,
          description: item['description'] as String?,
          createdAt: DateTime.parse(item['created_at'] as String),
          username: profile?['username'] as String? ?? 'usuario',
          userAvatarUrl: profile?['avatar_url'] as String?,
          filterName: _getFilterNameById(item['filter_id'] as int?),
          likesCount: likesCount,
          likedByMe: likedByMe,
          metrics: metrics != null ? GpuMetrics.fromJson(metrics) : null,
        );
      }).toList();
    } catch (e) {
      print('Error al obtener feed: $e');
      rethrow;
    }
  }

  // Obtener las publicaciones de un usuario específico para la cuadrícula del perfil
  Future<List<Post>> getUserPosts(String userId) async {
    try {
      final currentUserId = SupabaseService.instance.currentUserId;
      final List<dynamic> response = await _supabase
          .from('posts')
          .select('''
            id,
            original_image_url,
            processed_image_url,
            description,
            created_at,
            filter_id,
            user_profiles (username, avatar_url),
            gpu_metrics (image_width, image_height, block_dim_x, grid_dim_x, total_threads, execution_time_ms, status),
            likes (user_id)
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return response.map((item) {
        final profile = item['user_profiles'] as Map<String, dynamic>?;
        final metricsList = item['gpu_metrics'] as List<dynamic>?;
        final Map<String, dynamic>? metrics = metricsList != null && metricsList.isNotEmpty 
            ? metricsList.first as Map<String, dynamic> 
            : null;

        final likesList = item['likes'] as List<dynamic>? ?? [];
        final int likesCount = likesList.length;
        final bool likedByMe = currentUserId != null && likesList.any((l) => l['user_id'] == currentUserId);

        return Post(
          id: item['id'] as String,
          originalImageUrl: item['original_image_url'] as String,
          processedImageUrl: item['processed_image_url'] as String,
          description: item['description'] as String?,
          createdAt: DateTime.parse(item['created_at'] as String),
          username: profile?['username'] as String? ?? 'usuario',
          userAvatarUrl: profile?['avatar_url'] as String?,
          filterName: _getFilterNameById(item['filter_id'] as int?),
          likesCount: likesCount,
          likedByMe: likedByMe,
          metrics: metrics != null ? GpuMetrics.fromJson(metrics) : null,
        );
      }).toList();
    } catch (e) {
      print('Error al obtener posts del usuario: $e');
      rethrow;
    }
  }


  String _parseBackendError(http.Response response) {
    final body = utf8.decode(response.bodyBytes).trim();
    if (body.isNotEmpty) {
      try {
        final errorData = jsonDecode(body) as Map<String, dynamic>;
        return errorData['message']?.toString() ??
            errorData['error']?.toString() ??
            body;
      } catch (_) {
        return body;
      }
    }
    return switch (response.statusCode) {
      401 =>
        'No autorizado (401). Verifica que el JWT Secret del backend coincida con Supabase y vuelve a iniciar sesión.',
      403 => 'Acceso denegado (403).',
      _ => 'Error del backend (${response.statusCode}).',
    };
  }

  Future<GpuPreviewResponse> previewPostFilter({
    required String filePath,
    required Uint8List? webBytes,
    required int filterId,
  }) async {
    final token = SupabaseService.instance.currentAccessToken;
    final uri = Uri.parse('$baseUrl/api/posts/preview?filterId=$filterId');
    final request = http.MultipartRequest('POST', uri);

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (kIsWeb && webBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          webBytes,
          filename: 'image.jpg',
        ),
      );
    } else {
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
        ),
      );
    }

    final response = await http.Response.fromStream(await request.send());

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return GpuPreviewResponse.fromJson(data);
    }

    throw Exception(_parseBackendError(response));
  }

  String _getFilterNameById(int? filterId) {
    switch (filterId) {
      case 1:
        return 'Filtro Bordes';
      case 2:
        return 'Filtro Enfoque';
      case 3:
        return 'Filtro Cartoon';
      case 4:
        return 'Filtro Sepia';
      case 5:
        return 'Filtro Invertido';
      case 6:
        return 'Filtro Pixelado';
      case 7:
        return 'Filtro Burbujas Isotipo';
      default:
        return 'Filtro Original';
    }
  }
}

class GpuPreviewResponse {
  final String status;
  final String imageBase64;
  final GpuMetrics? metrics;
  final String? message;

  GpuPreviewResponse({
    required this.status,
    required this.imageBase64,
    this.metrics,
    this.message,
  });

  factory GpuPreviewResponse.fromJson(Map<String, dynamic> json) {
    return GpuPreviewResponse(
      status: json['status'] as String? ?? 'success',
      imageBase64: json['image_base64'] ?? json['imageBase64'] as String? ?? '',
      metrics: json['metrics'] != null
          ? GpuMetrics.fromJson(json['metrics'] as Map<String, dynamic>)
          : null,
      message: json['message'] as String?,
    );
  }
}

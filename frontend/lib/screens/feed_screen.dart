import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend_service.dart';
import '../services/supabase_service.dart';
import '../models/post.dart';
import '../widgets/post_card.dart';
import '../core/theme.dart';
import 'notifications_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({Key? key}) : super(key: key);

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<List<Post>> _feedFuture;
  final _supabase = SupabaseService.instance.client;
  RealtimeChannel? _feedChannel;
  RealtimeChannel? _notificationsChannel;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _refreshFeed();
    _subscribeToFeedChanges();
    _loadUnreadNotifications();
    _subscribeToNotifications();
  }

  @override
  void dispose() {
    if (_feedChannel != null) {
      _supabase.removeChannel(_feedChannel!);
    }
    if (_notificationsChannel != null) {
      _supabase.removeChannel(_notificationsChannel!);
    }
    super.dispose();
  }

  void _refreshFeed() {
    if (mounted) {
      setState(() {
        _feedFuture = BackendService.instance.getFeed();
      });
    }
  }

  // Suscripción a cambios en posts, likes y comentarios para actualizar el Feed instantáneamente ante inserciones/borrados/interacciones
  void _subscribeToFeedChanges() {
    _feedChannel = _supabase.channel('public:posts_realtime');

    // Escuchar cambios en posts
    _feedChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'posts',
      callback: (payload) {
        _refreshFeed();
      },
    );

    // Escuchar cambios en likes
    _feedChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'likes',
      callback: (payload) {
        _refreshFeed();
      },
    );

    // Escuchar cambios en comentarios
    _feedChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'comments',
      callback: (payload) {
        _refreshFeed();
      },
    );

    _feedChannel!.subscribe();
  }

  // Carga cantidad de notificaciones sin leer (por simplicidad, contamos todas las notificaciones recibidas en Supabase)
  Future<void> _loadUnreadNotifications() async {
    final currentUserId = SupabaseService.instance.currentUserId;
    if (currentUserId == null) return;

    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('receiver_id', currentUserId);

      if (mounted) {
        setState(() {
          _unreadNotifications = response?.length ?? 0;
        });
      }
    } catch (e) {
      print('Error al cargar conteo de notificaciones: $e');
    }
  }

  // Suscripción a notificaciones en tiempo real
  void _subscribeToNotifications() {
    _notificationsChannel = _supabase.channel('public:notifications_count').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      callback: (payload) {
        _loadUnreadNotifications();
      },
    );
    _notificationsChannel!.subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'UPSGlam',
          style: GoogleFonts.outfit(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            foreground: Paint()
              ..shader = const LinearGradient(
                colors: [AppTheme.primary, AppTheme.secondary],
              ).createShader(const Rect.fromLTWH(0.0, 0.0, 150.0, 50.0)),
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          // Icono de Notificaciones interactivo con Badge
          IconButton(
            icon: Badge(
              label: Text('$_unreadNotifications'),
              isLabelVisible: _unreadNotifications > 0,
              child: const Icon(Icons.notifications_rounded, color: AppTheme.textPrimary),
            ),
            onPressed: () {
              // Limpiar contador local visual al abrir notificaciones
              setState(() {
                _unreadNotifications = 0;
              });
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textPrimary),
            onPressed: _refreshFeed,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: AppTheme.surface,
        onRefresh: () async {
          _refreshFeed();
          await _feedFuture;
        },
        child: FutureBuilder<List<Post>>(
          future: _feedFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              );
            } else if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off, size: 64, color: Colors.redAccent),
                      const SizedBox(height: 16),
                      Text(
                        'Error de Conexión',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Asegúrate de que tu backend de Spring Boot y base de datos estén activos.\n\nDetalles: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _refreshFeed,
                        icon: const Icon(Icons.replay),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              );
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 64,
                            color: AppTheme.primary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'El Feed está vacío',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Actualmente solo ves las fotos de personas a las que sigues. ¡Sigue a tus amigos en Buscar para ver sus publicaciones aquí! 🚀',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            final posts = snapshot.data!;
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                // Al pasar una callback o usar stream, podemos refrescar el feed ante cambios
                return PostCard(post: posts[index]);
              },
            );
          },
        ),
      ),
    );
  }
}

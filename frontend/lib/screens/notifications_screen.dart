import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../core/theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _supabase = SupabaseService.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeToNotifications();
  }

  // Carga todas las notificaciones del usuario de Supabase
  Future<void> _loadNotifications() async {
    final currentUserId = SupabaseService.instance.currentUserId;
    if (currentUserId == null) return;

    try {
      final response = await _supabase
          .from('notifications')
          .select('''
            id,
            type,
            content,
            created_at,
            post_id,
            sender:user_profiles!notifications_sender_id_fkey(username, avatar_url)
          ''')
          .eq('receiver_id', currentUserId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(response ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error al cargar notificaciones: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Se suscribe a notificaciones en tiempo real
  void _subscribeToNotifications() {
    _supabase.channel('public:notifications_realtime').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      callback: (payload) {
        _loadNotifications();
      },
    ).subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notificaciones',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _loadNotifications,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _notifications.isEmpty
                ? _buildEmptyState()
                : _buildNotificationsList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none_rounded, size: 64, color: AppTheme.textSecondary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'Sin notificaciones',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Las interacciones en tus publicaciones como likes y comentarios aparecerán aquí en tiempo real.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E293B), height: 1),
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        final sender = notification['sender'] as Map<String, dynamic>?;
        final username = sender?['username'] as String? ?? 'usuario';
        final avatarUrl = sender?['avatar_url'] as String?;
        final type = notification['type'] as String;
        final content = notification['content'] as String? ?? '';
        final timeStr = _formatRelativeTime(DateTime.parse(notification['created_at'] as String));

        IconData icon;
        Color iconColor;
        if (type == 'LIKE') {
          icon = Icons.favorite_rounded;
          iconColor = Colors.redAccent;
        } else if (type == 'COMMENT') {
          icon = Icons.comment_rounded;
          iconColor = AppTheme.primary;
        } else {
          icon = Icons.person_add_rounded;
          iconColor = AppTheme.secondary;
        }

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          leading: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primary.withOpacity(0.1),
                backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F111E),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 12, color: iconColor),
              ),
            ],
          ),
          title: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              children: [
                TextSpan(
                  text: '@$username ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: type == 'LIKE' ? 'le dio me gusta a tu publicación.' : 'comentó: "$content"',
                ),
              ],
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              timeStr,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ),
        );
      },
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays >= 7) {
      return '${(diff.inDays / 7).floor()} sem';
    } else if (diff.inDays >= 1) {
      return '${diff.inDays} d';
    } else if (diff.inHours >= 1) {
      return '${diff.inHours} h';
    } else if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} m';
    } else {
      return 'Ahora mismo';
    }
  }
}

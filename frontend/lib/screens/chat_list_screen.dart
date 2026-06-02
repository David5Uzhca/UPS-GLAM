import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../core/theme.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _supabase = SupabaseService.instance.client;
  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _loadChats();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    if (_messagesChannel != null) {
      _supabase.removeChannel(_messagesChannel!);
    }
    super.dispose();
  }

  void _subscribeToMessages() {
    _messagesChannel = _supabase.channel('public:chat_list_messages').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        _loadChats();
      },
    );
    _messagesChannel!.subscribe();
  }

  // Carga e identifica todas las conversaciones agrupadas por el último mensaje
  Future<void> _loadChats() async {
    final currentUserId = SupabaseService.instance.currentUserId;
    if (currentUserId == null) return;

    try {
      // Obtenemos los mensajes donde participa el usuario actual
      final response = await _supabase
          .from('messages')
          .select('''
            id,
            content,
            post_id,
            created_at,
            sender_id,
            receiver_id,
            sender:user_profiles!messages_sender_id_fkey(id, username, avatar_url, full_name),
            receiver:user_profiles!messages_receiver_id_fkey(id, username, avatar_url, full_name)
          ''')
          .or('sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId')
          .order('created_at', ascending: false);

      if (mounted) {
        // Agrupamos por usuario de conversación
        final Map<String, Map<String, dynamic>> uniqueChats = {};

        if (response != null) {
          for (var item in response) {
            final sender = item['sender'] as Map<String, dynamic>?;
            final receiver = item['receiver'] as Map<String, dynamic>?;

            if (sender == null || receiver == null) continue;

            // Determinar quién es el "otro" usuario en la conversación
            final bool isSenderMe = item['sender_id'] == currentUserId;
            final otherUser = isSenderMe ? receiver : sender;
            final otherUserId = otherUser['id'] as String;

            if (!uniqueChats.containsKey(otherUserId)) {
              uniqueChats[otherUserId] = {
                'userId': otherUserId,
                'username': otherUser['username'],
                'fullName': otherUser['full_name'],
                'avatarUrl': otherUser['avatar_url'],
                'lastMessage': item['post_id'] != null ? '📷 Publicación compartida' : item['content'],
                'createdAt': DateTime.parse(item['created_at'] as String),
              };
            }
          }
        }

        setState(() {
          _chats = uniqueChats.values.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error al cargar chats: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Abre la selección de un nuevo usuario para iniciar chat
  void _showNewChatBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (context) {
        final currentUserId = SupabaseService.instance.currentUserId;
        return FutureBuilder<List<dynamic>>(
          future: _supabase.from('user_profiles').select().neq('id', currentUserId ?? ''),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 300,
                child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              );
            } else if (snapshot.hasError) {
              return SizedBox(
                height: 300,
                child: Center(
                  child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                ),
              );
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SizedBox(
                height: 300,
                child: Center(
                  child: Text('No hay otros usuarios registrados', style: TextStyle(color: AppTheme.textSecondary)),
                ),
              );
            }

            final users = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Iniciar nueva conversación',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E293B)),
                      itemBuilder: (context, index) {
                        final user = users[index] as Map<String, dynamic>;
                        final username = user['username'] as String? ?? 'usuario';
                        final fullName = user['full_name'] as String? ?? 'Usuario';
                        final avatarUrl = user['avatar_url'] as String?;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: AppTheme.primary.withOpacity(0.1),
                            backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                            child: avatarUrl == null
                                ? Text(
                                    username.substring(0, 1).toUpperCase(),
                                    style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          title: Text('@$username', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(fullName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          onTap: () {
                            Navigator.of(context).pop(); // Cerrar modal
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatDetailScreen(
                                  receiverId: user['id'] as String,
                                  receiverUsername: username,
                                  receiverAvatarUrl: avatarUrl,
                                ),
                              ),
                            ).then((_) => _loadChats()); // Recargar chats al volver
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mensajes',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _loadChats,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _chats.isEmpty
                ? _buildEmptyState()
                : _buildChatsList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewChatBottomSheet,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
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
            Icon(Icons.forum_outlined, size: 64, color: AppTheme.textSecondary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'No hay mensajes aún',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pulsa el botón flotante inferior para chatear o comparte fotos directamente desde el Feed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _chats.length,
      separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E293B), height: 1),
      itemBuilder: (context, index) {
        final chat = _chats[index];
        final username = chat['username'] as String? ?? 'usuario';
        final fullName = chat['fullName'] as String? ?? 'Usuario';
        final avatarUrl = chat['avatarUrl'] as String?;
        final lastMsg = chat['lastMessage'] as String? ?? '';
        final timeStr = _formatRelativeTime(chat['createdAt'] as DateTime);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.primary.withOpacity(0.1),
            backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    username.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  )
                : null,
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                fullName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                timeStr,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    lastMsg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '@$username',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.textSecondary),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatDetailScreen(
                  receiverId: chat['userId'] as String,
                  receiverUsername: username,
                  receiverAvatarUrl: avatarUrl,
                ),
              ),
            ).then((_) => _loadChats());
          },
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
      return 'Ahora';
    }
  }
}

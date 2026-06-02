import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/supabase_service.dart';
import '../models/post.dart';
import '../widgets/post_card.dart';
import '../core/theme.dart';

class ChatDetailScreen extends StatefulWidget {
  final String receiverId;
  final String receiverUsername;
  final String? receiverAvatarUrl;

  const ChatDetailScreen({
    Key? key,
    required this.receiverId,
    required this.receiverUsername,
    this.receiverAvatarUrl,
  }) : super(key: key);

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _supabase = SupabaseService.instance.client;
  late final String _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = SupabaseService.instance.currentUserId ?? '';
    _markMessagesAsRead();
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('sender_id', widget.receiverId)
          .eq('receiver_id', _currentUserId)
          .eq('is_read', false);
    } catch (e) {
      print('Error al marcar mensajes como leídos: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Envía un mensaje de texto
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await _supabase.from('messages').insert({
        'sender_id': _currentUserId,
        'receiver_id': widget.receiverId,
        'content': text,
      });
      _scrollToBottom();
    } catch (e) {
      print('Error al enviar mensaje: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.primary.withOpacity(0.1),
              backgroundImage: widget.receiverAvatarUrl != null
                  ? CachedNetworkImageProvider(widget.receiverAvatarUrl!)
                  : null,
              child: widget.receiverAvatarUrl == null
                  ? Text(
                      widget.receiverUsername.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 14),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.receiverUsername,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  'En línea',
                  style: TextStyle(fontSize: 10, color: const Color(0xFF10B981).withOpacity(0.8)),
                ),
              ],
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Stream de mensajes filtrado en tiempo real
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase.from('messages').stream(primaryKey: ['id']).order('created_at', ascending: true),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error al cargar mensajes: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                  );
                }

                final messages = snapshot.data ?? [];
                
                // Filtramos en memoria los mensajes de esta conversación específica
                final chatMessages = messages.where((msg) {
                  final sender = msg['sender_id'] as String;
                  final receiver = msg['receiver_id'] as String;
                  return (sender == _currentUserId && receiver == widget.receiverId) ||
                         (sender == widget.receiverId && receiver == _currentUserId);
                }).toList();

                // Si hay algún mensaje recibido no leído, lo marcamos como leído reactivamente
                final hasUnread = chatMessages.any((msg) => msg['receiver_id'] == _currentUserId && msg['is_read'] == false);
                if (hasUnread) {
                  _markMessagesAsRead();
                }

                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                if (chatMessages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppTheme.textSecondary.withOpacity(0.3)),
                        const SizedBox(height: 12),
                        const Text(
                          'Di "Hola" 👋',
                          style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Inicia la conversación en tiempo real con este usuario.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  itemCount: chatMessages.length,
                  itemBuilder: (context, index) {
                    final message = chatMessages[index];
                    final isMe = message['sender_id'] == _currentUserId;

                    return _buildMessageBubble(message, isMe);
                  },
                );
              },
            ),
          ),

          // Barra de entrada de mensajes
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF020617),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Burbuja de mensaje individual (Soporta texto y posts compartidos)
  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final hasPost = message['post_id'] != null;
    final content = message['content'] as String?;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: hasPost ? 8 : 16,
          vertical: hasPost ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: isMe 
              ? AppTheme.primary.withOpacity(0.85) 
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Si el mensaje es una publicación compartida
            if (hasPost) ...[
              _SharedPostBubble(postId: message['post_id'] as String),
              if (content != null && content.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    content,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ] else ...[
              // Mensaje de texto plano
              Text(
                content ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Widget auxiliar para renderizar el post compartido dentro de la burbuja
class _SharedPostBubble extends StatelessWidget {
  final String postId;
  static final _supabase = SupabaseService.instance.client;

  const _SharedPostBubble({Key? key, required this.postId}) : super(key: key);

  Future<Map<String, dynamic>?> _fetchSharedPost() async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            id,
            processed_image_url,
            original_image_url,
            description,
            created_at,
            filter_id,
            user_profiles (username, avatar_url),
            gpu_metrics (image_width, image_height, block_dim_x, grid_dim_x, total_threads, execution_time_ms, status)
          ''')
          .eq('id', postId)
          .maybeSingle();

      return response as Map<String, dynamic>?;
    } catch (e) {
      print('Error al consultar post compartido: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchSharedPost(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 150,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
          );
        }

        final postData = snapshot.data;
        if (postData == null) {
          return Container(
            height: 80,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                SizedBox(width: 8),
                Text('Publicación no disponible', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          );
        }

        final profile = postData['user_profiles'] as Map<String, dynamic>?;
        final username = profile?['username'] as String? ?? 'usuario';
        final processedUrl = postData['processed_image_url'] as String;

        return GestureDetector(
          onTap: () {
            // Mapeamos a objeto Post de Flutter
            final metricsList = postData['gpu_metrics'] as List<dynamic>?;
            final Map<String, dynamic>? metrics = metricsList != null && metricsList.isNotEmpty 
                ? metricsList.first as Map<String, dynamic> 
                : null;

            final post = Post(
              id: postData['id'] as String,
              originalImageUrl: postData['original_image_url'] as String,
              processedImageUrl: processedUrl,
              description: postData['description'] as String?,
              createdAt: DateTime.parse(postData['created_at'] as String),
              username: username,
              userAvatarUrl: profile?['avatar_url'] as String?,
              filterName: _getFilterNameById(postData['filter_id'] as int?),
              likesCount: 0,
              likedByMe: false,
              metrics: metrics != null ? GpuMetrics.fromJson(metrics) : null,
            );

            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => Scaffold(
                  appBar: AppBar(
                    title: const Text('Publicación Compartida'),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  body: SingleChildScrollView(
                    child: PostCard(post: post),
                  ),
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: processedUrl,
                    height: 140,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt, color: AppTheme.accent, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'De @$username',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textSecondary, size: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getFilterNameById(int? filterId) {
    switch (filterId) {
      case 1:
        return 'Filtro Bordes';
      case 2:
        return 'Filtro Enfoque';
      case 3:
        return 'Filtro Cartoon';
      default:
        return 'Filtro Original';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post.dart';
import '../services/supabase_service.dart';
import 'metric_dashboard.dart';
import '../core/theme.dart';

class PostCard extends StatefulWidget {
  final Post post;

  const PostCard({
    Key? key,
    required this.post,
  }) : super(key: key);

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _showMetrics = false;
  bool _viewOriginal = false;
  bool _isLiked = false;
  int _likesCount = 0;
  String _descriptionText = '';
  bool _isOwner = false;
  bool _isDeleted = false;
  String? _postOwnerId;
  final _supabase = SupabaseService.instance.client;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.likedByMe;
    _likesCount = widget.post.likesCount;
    _descriptionText = widget.post.description ?? '';

    // Consulta el creador de la publicación para habilitar el menú de tres puntitos al dueño
    final currentUserId = SupabaseService.instance.currentUserId;
    if (currentUserId != null) {
      _supabase.from('posts').select('user_id').eq('id', widget.post.id).maybeSingle().then((val) {
        if (mounted && val != null) {
          setState(() {
            _postOwnerId = val['user_id'] as String?;
            _isOwner = _postOwnerId == currentUserId;
          });
        }
      });
    }
  }

  // Maneja la interacción de dar/quitar like reactivamente e inserta notificaciones
  Future<void> _handleLike() async {
    final currentUserId = SupabaseService.instance.currentUserId;
    if (currentUserId == null) return;

    final wasLiked = _isLiked;

    setState(() {
      if (_isLiked) {
        _isLiked = false;
        _likesCount = (_likesCount - 1).clamp(0, 999999);
      } else {
        _isLiked = true;
        _likesCount++;
      }
    });

    try {
      if (!wasLiked) {
        // Guardar me gusta en Supabase
        await _supabase.from('likes').insert({
          'post_id': widget.post.id,
          'user_id': currentUserId,
        });

        // Registrar Notificación en tiempo real para el receptor si no es uno mismo
        if (_postOwnerId != null && _postOwnerId != currentUserId) {
          await _supabase.from('notifications').insert({
            'receiver_id': _postOwnerId!,
            'sender_id': currentUserId,
            'type': 'LIKE',
            'post_id': widget.post.id,
            'content': 'le dio me gusta a tu publicación.',
          });
        }
      } else {
        // Quitar me gusta en Supabase
        await _supabase
            .from('likes')
            .delete()
            .eq('post_id', widget.post.id)
            .eq('user_id', currentUserId);
      }
    } catch (e) {
      print('Error al procesar like en DB: $e');
      // Revertir UI local ante error
      setState(() {
        if (_isLiked) {
          _isLiked = false;
          _likesCount = (_likesCount - 1).clamp(0, 999999);
        } else {
          _isLiked = true;
          _likesCount++;
        }
      });
    }
  }

  // Abre la sección de comentarios reales mediante modal bottom sheet y envía notificaciones
  void _showCommentsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (context) {
        final commentController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header sutil
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Comentarios',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF1E293B)),
                    
                    // Lista de comentarios
                    Expanded(
                      child: FutureBuilder<List<dynamic>>(
                        future: _supabase
                            .from('comments')
                            .select('*, user_profiles (username, avatar_url)')
                            .eq('post_id', widget.post.id)
                            .order('created_at', ascending: true),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                          }
                          
                          if (snapshot.hasError) {
                            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
                          }
                          
                          final comments = snapshot.data ?? [];
                          if (comments.isEmpty) {
                            return const Center(
                              child: Text('No hay comentarios aún. ¡Sé el primero!', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                            );
                          }
                          
                          return ListView.builder(
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              final comment = comments[index];
                              final profile = comment['user_profiles'] as Map<String, dynamic>?;
                              final username = profile?['username'] as String? ?? 'usuario';
                              final avatarUrl = profile?['avatar_url'] as String?;
                              final content = comment['content'] as String;
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: AppTheme.primary.withOpacity(0.1),
                                      backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                                      child: avatarUrl == null
                                          ? Text(username.substring(0, 1).toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold))
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          RichText(
                                            text: TextSpan(
                                              style: const TextStyle(color: Colors.white, fontSize: 13),
                                              children: [
                                                TextSpan(text: '@$username ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                                TextSpan(text: content),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _timeAgo(DateTime.parse(comment['created_at'] as String)),
                                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    
                    // Entrada de texto
                    Container(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: commentController,
                              decoration: InputDecoration(
                                hintText: 'Añadir un comentario...',
                                hintStyle: const TextStyle(fontSize: 13),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF020617),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
                            onPressed: () async {
                              final text = commentController.text.trim();
                              if (text.isEmpty) return;
                              
                              final currentUserId = SupabaseService.instance.currentUserId;
                              if (currentUserId == null) return;
                              
                              try {
                                await _supabase.from('comments').insert({
                                  'post_id': widget.post.id,
                                  'user_id': currentUserId,
                                  'content': text,
                                });

                                // Notificación instantánea en Supabase al creador
                                if (_postOwnerId != null && _postOwnerId != currentUserId) {
                                  await _supabase.from('notifications').insert({
                                    'receiver_id': _postOwnerId!,
                                    'sender_id': currentUserId,
                                    'type': 'COMMENT',
                                    'post_id': widget.post.id,
                                    'content': text,
                                  });
                                }

                                commentController.clear();
                                setModalState(() {}); // Refrescar el FutureBuilder
                              } catch (e) {
                                print('Error al comentar: $e');
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Abre la hoja de compartir para enviar posts a chats existentes
  void _showShareBottomSheet() {
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
            }
            
            final users = snapshot.data ?? [];
            if (users.isEmpty) {
              return const SizedBox(
                height: 300,
                child: Center(child: Text('No hay usuarios para compartir', style: TextStyle(color: AppTheme.textSecondary))),
              );
            }
            
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enviar publicación',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
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
                                ? Text(username.substring(0, 1).toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold))
                                : null,
                          ),
                          title: Text('@$username', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(fullName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          trailing: const Text('Enviar', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                          onTap: () async {
                            Navigator.of(context).pop(); // Cerrar modal
                            
                            try {
                              await _supabase.from('messages').insert({
                                'sender_id': currentUserId,
                                'receiver_id': user['id'] as String,
                                'content': '📷 He compartido una publicación contigo.',
                                'post_id': widget.post.id,
                              });
                              
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('¡Publicación enviada a @$username! 🚀'),
                                    backgroundColor: AppTheme.accent,
                                  ),
                                );
                              }
                            } catch (e) {
                              print('Error al compartir post: $e');
                            }
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

  // Menú de opciones para el dueño de la publicación (Editar/Eliminar)
  void _showPostOptionsMenu() {
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
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: AppTheme.primary),
                  title: const Text('Editar descripción', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showEditDescriptionDialog();
                  },
                ),
                const Divider(color: Color(0xFF1E293B)),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                  title: const Text('Eliminar publicación', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showDeleteConfirmationDialog();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Diálogo interactivo para editar descripción
  void _showEditDescriptionDialog() {
    final editController = TextEditingController(text: _descriptionText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar descripción', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: editController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Nueva descripción...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () async {
              final newDesc = editController.text.trim();
              try {
                await _supabase.from('posts').update({
                  'description': newDesc,
                }).eq('id', widget.post.id);

                if (mounted) {
                  setState(() {
                    _descriptionText = newDesc;
                  });
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('¡Descripción actualizada con éxito! 🎉'), backgroundColor: AppTheme.accent),
                  );
                }
              } catch (e) {
                print('Error al editar descripción: $e');
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // Diálogo para confirmar borrado definitivo
  void _showDeleteConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar publicación?'),
        content: const Text('Esta acción eliminará de forma permanente tu foto y toda su telemetría en GPU. No se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              try {
                await _supabase.from('posts').delete().eq('id', widget.post.id);
                if (mounted) {
                  setState(() {
                    _isDeleted = true;
                  });
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Publicación eliminada con éxito.'), backgroundColor: Colors.redAccent),
                  );
                }
              } catch (e) {
                print('Error al borrar publicación: $e');
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeleted) return const SizedBox.shrink(); // Esconde la tarjeta de forma instantánea al borrar
    final post = widget.post;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la Publicación
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primary.withOpacity(0.2),
                  backgroundImage: post.userAvatarUrl != null
                      ? CachedNetworkImageProvider(post.userAvatarUrl!)
                      : null,
                  child: post.userAvatarUrl == null
                      ? Text(
                          post.username.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.username,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      post.filterName,
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _timeAgo(post.createdAt),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Contenedor de Imagen con Control de Comparación
          GestureDetector(
            onLongPressStart: (_) {
              setState(() {
                _viewOriginal = true;
              });
            },
            onLongPressEnd: (_) {
              setState(() {
                _viewOriginal = false;
              });
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 1, // Relación de aspecto 1:1
                  child: CachedNetworkImage(
                    imageUrl: _viewOriginal ? post.originalImageUrl : post.processedImageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: const Color(0xFF1E2030),
                      child: const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: const Color(0xFF1E2030),
                      child: const Icon(Icons.error, color: Colors.redAccent),
                    ),
                  ),
                ),

                if (_viewOriginal)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.secondary, width: 1.5),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.compare, color: AppTheme.secondary, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'IMAGEN ORIGINAL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.touch_app, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'MANTÉN PRESIONADO PARA VER ORIGINAL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Fila de Botones Sociales e Indicador GPU
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? Colors.redAccent : AppTheme.textPrimary,
                      ),
                      onPressed: _handleLike,
                    ),
                    if (_likesCount > 0)
                      Text(
                        '$_likesCount',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.mode_comment_outlined, color: AppTheme.textPrimary),
                  onPressed: _showCommentsBottomSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.send_outlined, color: AppTheme.textPrimary),
                  onPressed: _showShareBottomSheet,
                ),
                if (_isOwner)
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textPrimary),
                    onPressed: _showPostOptionsMenu,
                  ),

                if (post.metrics != null)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showMetrics = !_showMetrics;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showMetrics 
                            ? AppTheme.primary.withOpacity(0.2)
                            : Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _showMetrics ? AppTheme.primary : const Color(0xFF1E293B),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt, color: AppTheme.accent, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'GPU: ${post.metrics!.executionTimeMs.toStringAsFixed(2)} ms',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Descripción y Pie de Foto
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                children: [
                  TextSpan(
                    text: '${post.username} ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: _descriptionText,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          if (_showMetrics && post.metrics != null) ...[
            MetricDashboard(
              metrics: post.metrics!,
              filterName: post.filterName,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays >= 7) {
      return '${(difference.inDays / 7).floor()} sem';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays} d';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours} h';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes} min';
    } else {
      return 'Hace instantes';
    }
  }
}

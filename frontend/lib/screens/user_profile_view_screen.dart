import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/supabase_service.dart';
import '../services/backend_service.dart';
import '../models/post.dart';
import '../widgets/post_card.dart';
import '../core/theme.dart';
import 'chat_detail_screen.dart';

class UserProfileViewScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> profile;

  const UserProfileViewScreen({
    Key? key,
    required this.userId,
    required this.profile,
  }) : super(key: key);

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  late Future<List<Post>> _userPostsFuture;
  final _supabase = SupabaseService.instance.client;
  bool _isFollowing = false;
  bool _isLoadingFollow = true;
  int _followersCount = 0;
  int _followedCount = 0;
  int _likesCount = 0;
  String? _description;

  @override
  void initState() {
    super.initState();
    _loadProfileStats();
    _checkIfFollowing();
    _loadPosts();
  }

  void _loadPosts() {
    setState(() {
      _userPostsFuture = BackendService.instance.getUserPosts(widget.userId);
    });
  }

  // Comprueba si el usuario actual sigue a este perfil
  Future<void> _checkIfFollowing() async {
    final currentUserId = SupabaseService.instance.currentUserId;
    if (currentUserId == null) return;

    try {
      final response = await _supabase
          .from('follows')
          .select()
          .eq('follower_id', currentUserId)
          .eq('followed_id', widget.userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isFollowing = response != null;
          _isLoadingFollow = false;
        });
      }
    } catch (e) {
      print('Error al verificar follow: $e');
      if (mounted) {
        setState(() {
          _isLoadingFollow = false;
        });
      }
    }
  }

  // Carga estadísticas de Supabase (seguidores, seguidos, likes recibidos)
  Future<void> _loadProfileStats() async {
    try {
      // 1. Obtener seguidores
      final followersResp = await _supabase
          .from('follows')
          .select('id')
          .eq('followed_id', widget.userId);
      
      // 2. Obtener seguidos
      final followedResp = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', widget.userId);

      // 3. Obtener biografía/descripción fresca
      final profileResp = await _supabase
          .from('user_profiles')
          .select('description')
          .eq('id', widget.userId)
          .maybeSingle();

      // 4. Calcular likes acumulados en una sola llamada relacional
      final postsResp = await _supabase
          .from('posts')
          .select('id, likes(id)')
          .eq('user_id', widget.userId);

      int totalLikes = 0;
      if (postsResp != null) {
        for (var post in postsResp) {
          final likesList = post['likes'] as List<dynamic>?;
          totalLikes += likesList?.length ?? 0;
        }
      }

      if (mounted) {
        setState(() {
          _followersCount = followersResp?.length ?? 0;
          _followedCount = followedResp?.length ?? 0;
          _likesCount = totalLikes;
          _description = profileResp?['description'] as String?;
        });
      }
    } catch (e) {
      print('Error al cargar estadísticas de perfil ajeno: $e');
    }
  }

  // Alterna el estado de seguimiento (Follow/Unfollow)
  Future<void> _toggleFollow() async {
    final currentUserId = SupabaseService.instance.currentUserId;
    if (currentUserId == null) return;

    setState(() {
      _isLoadingFollow = true;
    });

    try {
      if (_isFollowing) {
        // Dejar de seguir
        await _supabase
            .from('follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('followed_id', widget.userId);
        
        setState(() {
          _isFollowing = false;
          _followersCount = (_followersCount - 1).clamp(0, 99999);
        });
      } else {
        // Seguir
        await _supabase.from('follows').insert({
          'follower_id': currentUserId,
          'followed_id': widget.userId,
        });

        setState(() {
          _isFollowing = true;
          _followersCount++;
        });
      }
    } catch (e) {
      print('Error al alternar follow: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo procesar la acción: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() {
        _isLoadingFollow = false;
      });
    }
  }

  // Redirecciona directamente a la conversación de chat
  void _startChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          receiverId: widget.userId,
          receiverUsername: widget.profile['username'] as String? ?? 'usuario',
          receiverAvatarUrl: widget.profile['avatar_url'] as String?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.profile['username'] as String? ?? 'usuario';
    final fullName = widget.profile['full_name'] as String? ?? 'Usuario UPSGlam';
    final avatarUrl = widget.profile['avatar_url'] as String?;
    final bioText = _description ?? '🖥️ Desarrollador UPSGlam\n⚡ Procesando imágenes de super alta resolución en CUDA!';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '@$username',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: () async {
          _loadProfileStats();
          _checkIfFollowing();
          _loadPosts();
          await _userPostsFuture;
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado del Perfil
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppTheme.primary, AppTheme.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFF1E2030),
                        backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                        child: avatarUrl == null
                            ? Text(
                                username.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 28,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 28),

                    // Estadísticas (Fotos, Likes, Seguidos, Seguidores)
                    Expanded(
                      child: FutureBuilder<List<Post>>(
                        future: _userPostsFuture,
                        builder: (context, snapshot) {
                          final postCount = snapshot.data?.length ?? 0;

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatColumn('Fotos', postCount.toString()),
                              _buildStatColumn('Likes', _likesCount.toString()),
                              _buildStatColumn('Seguidores', _followersCount.toString()),
                              _buildStatColumn('Seguidos', _followedCount.toString()),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Nombre Completo y Biografía
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bioText,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Botones de acción: Seguir y Mensaje
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Expanded(
                      child: _isLoadingFollow
                          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isFollowing ? const Color(0xFF1E293B) : AppTheme.primary,
                                side: _isFollowing ? const BorderSide(color: Color(0xFF334155)) : null,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _toggleFollow,
                              child: Text(
                                _isFollowing ? 'Siguiendo' : 'Seguir',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF1E293B)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _startChat,
                        icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                        label: const Text(
                          'Mensaje',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: Color(0xFF1E293B), height: 1),

              // Pestaña Grid
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Icon(Icons.grid_on_rounded, color: AppTheme.primary, size: 24),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),

              // Cuadrícula de fotos del usuario
              FutureBuilder<List<Post>>(
                future: _userPostsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      ),
                    );
                  } else if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          'Error al cargar fotos: ${snapshot.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    );
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60.0, horizontal: 20.0),
                      child: Column(
                        children: [
                          Icon(Icons.photo_library_outlined, size: 48, color: AppTheme.textSecondary.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          const Text(
                            'No hay publicaciones aún',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Las fotos procesadas en la GPU aparecerán aquí.',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  }

                  final posts = snapshot.data!;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(2),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: posts.length,
                    itemBuilder: (context, index) {
                      final post = posts[index];

                      return GestureDetector(
                        onTap: () => _showPostDetailDialog(post),
                        child: CachedNetworkImage(
                          imageUrl: post.processedImageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: const Color(0xFF1E2030)),
                          errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.redAccent),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  void _showPostDetailDialog(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Publicación'),
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
  }
}

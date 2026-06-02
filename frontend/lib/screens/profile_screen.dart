import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/backend_service.dart';
import '../models/post.dart';
import '../widgets/post_card.dart';
import 'login_screen.dart';
import '../core/theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userProfile;
  late Future<List<Post>> _userPostsFuture;
  bool _isLoadingProfile = true;
  final _supabase = SupabaseService.instance.client;
  RealtimeChannel? _profileChangesChannel;

  // Estadísticas reales del perfil
  int _postCount = 0;
  int _likesCount = 0;
  int _followersCount = 0;
  int _followedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _subscribeToProfileChanges();
  }

  @override
  void dispose() {
    if (_profileChangesChannel != null) {
      _supabase.removeChannel(_profileChangesChannel!);
    }
    super.dispose();
  }

  void _subscribeToProfileChanges() {
    final userId = SupabaseService.instance.currentUserId;
    if (userId == null) return;

    _profileChangesChannel = _supabase.channel('public:profile_changes');

    // Escuchar cambios en posts
    _profileChangesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'posts',
      callback: (payload) {
        _loadProfileData();
      },
    );

    // Escuchar cambios en likes
    _profileChangesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'likes',
      callback: (payload) {
        _loadProfileData();
      },
    );

    // Escuchar cambios en follows
    _profileChangesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'follows',
      callback: (payload) {
        _loadProfileData();
      },
    );

    // Escuchar cambios en perfiles de usuario
    _profileChangesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_profiles',
      callback: (payload) {
        _loadProfileData();
      },
    );

    _profileChangesChannel!.subscribe();
  }

  void _loadProfileData() {
    setState(() {
      _isLoadingProfile = true;
    });

    final userId = SupabaseService.instance.currentUserId;
    if (userId == null) return;

    // 1. Obtener perfil desde Supabase
    SupabaseService.instance.getCurrentUserProfile().then((profile) {
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoadingProfile = false;
        });
        _loadStats(userId);
      }
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    });

    // 2. Obtener publicaciones del usuario
    setState(() {
      _userPostsFuture = BackendService.instance.getUserPosts(userId);
    });
  }

  // Consulta los contadores reales en la base de datos
  Future<void> _loadStats(String userId) async {
    try {
      // Optimizamos en una única llamada relacional para contar posts y sumar likes recibidos
      final postsResp = await _supabase
          .from('posts')
          .select('id, likes(id)')
          .eq('user_id', userId);
      
      final pCount = postsResp?.length ?? 0;

      int totalLikes = 0;
      if (postsResp != null) {
        for (var post in postsResp) {
          final likesList = post['likes'] as List<dynamic>?;
          totalLikes += likesList?.length ?? 0;
        }
      }

      // C. Contar seguidores
      final followersResp = await _supabase
          .from('follows')
          .select('id')
          .eq('followed_id', userId);

      // D. Contar seguidos
      final followedResp = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', userId);

      if (mounted) {
        setState(() {
          _postCount = pCount;
          _likesCount = totalLikes;
          _followersCount = followersResp?.length ?? 0;
          _followedCount = followedResp?.length ?? 0;
        });
      }
    } catch (e) {
      print('Error al cargar estadísticas reales: $e');
    }
  }

  // Abre el menú inferior flotante de Configuración
  void _showSettingsBottomSheet() {
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
                  leading: const Icon(Icons.photo_camera_rounded, color: AppTheme.accent),
                  title: const Text('Cambiar foto de perfil', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickAndUploadAvatarDirectly();
                  },
                ),
                const Divider(color: Color(0xFF1E293B)),
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: AppTheme.primary),
                  title: const Text('Editar perfil (Nombre y Bio)', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showEditProfileBottomSheet();
                  },
                ),
                const Divider(color: Color(0xFF1E293B)),
                ListTile(
                  leading: const Icon(Icons.vpn_key_rounded, color: AppTheme.secondary),
                  title: const Text('Cambiar contraseña', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showChangePasswordDialog();
                  },
                ),
                const Divider(color: Color(0xFF1E293B)),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  title: const Text('Cerrar sesión', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _handleLogout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Método para cambiar la foto de perfil directamente desde el menú
  Future<void> _pickAndUploadAvatarDirectly() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (image == null) return;

      // Mostrar cargando
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );

      final bytes = kIsWeb ? await image.readAsBytes() : await File(image.path).readAsBytes();
      final userId = SupabaseService.instance.currentUserId;
      final filename = 'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'avatars/$filename';

      await _supabase.storage.from('upsglam-images').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(contentType: 'image/jpeg'),
      );

      final publicUrl = _supabase.storage.from('upsglam-images').getPublicUrl(storagePath);
      
      final currentFullName = _userProfile?['full_name'] as String? ?? '';
      final currentDescription = _userProfile?['description'] as String? ?? '';

      await SupabaseService.instance.updateUserProfile(
        fullName: currentFullName,
        description: currentDescription,
        avatarUrl: publicUrl,
      );

      Navigator.of(context).pop(); // Quitar cargando
      _loadProfileData(); // Recargar

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Foto de perfil actualizada con éxito! 🎉'), backgroundColor: AppTheme.accent),
      );
    } catch (e) {
      Navigator.of(context).pop(); // Quitar cargando en caso de error
      print('Error al subir avatar directamente: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir imagen: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // Modal para editar la descripción del perfil y subir nueva foto
  void _showEditProfileBottomSheet() {
    final currentFullName = _userProfile?['full_name'] as String? ?? '';
    final currentDescription = _userProfile?['description'] as String? ?? '';
    final descriptionController = TextEditingController(text: currentDescription);
    final fullNameController = TextEditingController(text: currentFullName);
    
    String? tempAvatarUrl = _userProfile?['avatar_url'] as String?;
    bool isUploading = false;

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
        return StatefulBuilder(
          builder: (context, setModalState) {
            
            // Función para seleccionar e iniciar la subida de avatar a Supabase Storage
            Future<void> pickAndUploadAvatar() async {
              try {
                final picker = ImagePicker();
                final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                if (image == null) return;

                setModalState(() {
                  isUploading = true;
                });

                final bytes = kIsWeb ? await image.readAsBytes() : await File(image.path).readAsBytes();
                final userId = SupabaseService.instance.currentUserId;
                final filename = 'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                final storagePath = 'avatars/$filename';

                await _supabase.storage.from('upsglam-images').uploadBinary(
                  storagePath,
                  bytes,
                  fileOptions: FileOptions(contentType: 'image/jpeg'),
                );

                final publicUrl = _supabase.storage.from('upsglam-images').getPublicUrl(storagePath);
                
                setModalState(() {
                  tempAvatarUrl = publicUrl;
                  isUploading = false;
                });
              } catch (e) {
                print('Error al subir avatar: $e');
                setModalState(() {
                  isUploading = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al subir imagen: $e'), backgroundColor: Colors.redAccent),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.65,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Editar Perfil',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Selector visual de Foto de Perfil
                    Center(
                      child: GestureDetector(
                        onTap: isUploading ? null : pickAndUploadAvatar,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 46,
                              backgroundColor: AppTheme.primary.withOpacity(0.1),
                              backgroundImage: tempAvatarUrl != null
                                  ? CachedNetworkImageProvider(tempAvatarUrl!)
                                  : null,
                              child: tempAvatarUrl == null
                                  ? const Icon(Icons.person, size: 40, color: AppTheme.primary)
                                  : null,
                            ),
                            Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.4),
                              ),
                              child: isUploading
                                  ? const CircularProgressIndicator(color: AppTheme.primary)
                                  : const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 24),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Campo Nombre Completo
                    Text(
                      'NOMBRE COMPLETO',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        hintText: 'Tu nombre completo...',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Campo Descripción / Bio
                    Text(
                      'BIOGRAFÍA / DESCRIPCIÓN',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Cuéntanos un poco sobre ti y tus procesamientos en CUDA...',
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Botón Guardar Cambios
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: isUploading ? null : () async {
                        try {
                          await SupabaseService.instance.updateUserProfile(
                            fullName: fullNameController.text.trim(),
                            description: descriptionController.text.trim(),
                            avatarUrl: tempAvatarUrl,
                          );
                          Navigator.of(context).pop();
                          _loadProfileData(); // Recargar datos frescos
                        } catch (e) {
                          print('Error al guardar perfil: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      },
                      child: const Text('GUARDAR CAMBIOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  // Muestra diálogo para cambiar la contraseña a través de Supabase Auth
  void _showChangePasswordDialog() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cambiar contraseña', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Ingresa tu nueva contraseña para actualizar tu seguridad:'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Nueva contraseña...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () async {
              final newPass = passwordController.text.trim();
              if (newPass.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('La contraseña debe tener al menos 6 caracteres.'), backgroundColor: Colors.redAccent),
                );
                return;
              }

              try {
                // Actualización oficial de atributos en Supabase Auth
                await _supabase.auth.updateUser(
                  UserAttributes(password: newPass),
                );
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('¡Contraseña actualizada con éxito! 🔐'), backgroundColor: AppTheme.accent),
                );
              } catch (e) {
                print('Error al cambiar contraseña: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas salir de tu cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(context).pop();
              await SupabaseService.instance.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = _userProfile?['username'] as String? ?? 'usuario';
    final fullName = _userProfile?['full_name'] as String? ?? 'Usuario UPSGlam';
    final avatarUrl = _userProfile?['avatar_url'] as String?;
    final bioText = _userProfile?['description'] as String? ?? 
        '🖥️ Desarrollador UPSGlam\n⚡ Procesando imágenes de super alta resolución en CUDA!';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '@$username',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            tooltip: 'Configuración',
            onPressed: _showSettingsBottomSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: () async {
          _loadProfileData();
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
                        backgroundImage: avatarUrl != null
                            ? CachedNetworkImageProvider(avatarUrl)
                            : null,
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

                    // Estadísticas (Fotos, Likes, Seguidores, Seguidos)
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatColumn('Fotos', _postCount.toString()),
                          _buildStatColumn('Likes', _likesCount.toString()),
                          _buildStatColumn('Seguidores', _followersCount.toString()),
                          _buildStatColumn('Seguidos', _followedCount.toString()),
                        ],
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
              const SizedBox(height: 24),
              const Divider(color: Color(0xFF1E293B), height: 1),

              // Pestaña de Grid
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Icon(Icons.grid_on_rounded, color: AppTheme.primary, size: 24),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),

              // Cuadrícula de fotos cargadas
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
                            'No tienes publicaciones aún',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Las fotos que proceses en la GPU aparecerán aquí.',
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
                          placeholder: (context, url) => Container(
                            color: const Color(0xFF1E2030),
                          ),
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

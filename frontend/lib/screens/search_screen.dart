import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/supabase_service.dart';
import '../core/theme.dart';
import 'user_profile_view_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final List<Map<String, dynamic>> _searchResults = [];
  List<String> _searchHistory = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Carga el historial desde shared_preferences
  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _searchHistory = prefs.getStringList('upsglam_search_history') ?? [];
      });
    } catch (e) {
      print('Error al cargar historial: $e');
    }
  }

  // Guarda el historial en shared_preferences
  Future<void> _saveSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('upsglam_search_history', _searchHistory);
    } catch (e) {
      print('Error al guardar historial: $e');
    }
  }

  // Añade una consulta al historial
  void _addToHistory(String query) {
    if (query.trim().isEmpty) return;
    
    setState(() {
      _searchHistory.remove(query); // Evitar duplicados
      _searchHistory.insert(0, query); // Insertar al inicio
      if (_searchHistory.length > 10) {
        _searchHistory = _searchHistory.sublist(0, 10); // Limitar a 10
      }
    });
    _saveSearchHistory();
  }

  // Elimina una consulta individual del historial
  void _removeFromHistory(String query) {
    setState(() {
      _searchHistory.remove(query);
    });
    _saveSearchHistory();
  }

  // Limpia todo el historial
  void _clearHistory() {
    setState(() {
      _searchHistory.clear();
    });
    _saveSearchHistory();
  }

  // Realiza la búsqueda en Supabase
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults.clear();
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final currentUserId = SupabaseService.instance.currentUserId;
      final response = await SupabaseService.instance.client
          .from('user_profiles')
          .select()
          .or('username.ilike.%$query%,full_name.ilike.%$query%')
          .limit(20);

      if (mounted) {
        setState(() {
          _searchResults.clear();
          if (response != null) {
            for (var item in response) {
              // No mostrarse a uno mismo en los resultados de búsqueda si no es necesario
              if (item['id'] != currentUserId) {
                _searchResults.add(item as Map<String, dynamic>);
              }
            }
          }
          _isLoading = false;
        });
        _addToHistory(query);
      }
    } catch (e) {
      print('Error en búsqueda: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al realizar búsqueda: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Explorar',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra de búsqueda con diseño premium
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onSubmitted: _performSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar usuarios por nombre o username...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults.clear();
                            _hasSearched = false;
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (text) {
                setState(() {}); // Re-renderizar para mostrar/ocultar el botón borrar
              },
            ),
          ),

          // Contenedor principal
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _hasSearched
                    ? _buildSearchResults()
                    : _buildSearchHistory(),
          ),
        ],
      ),
    );
  }

  // Widget para resultados de búsqueda
  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: AppTheme.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(
              'No se encontraron resultados',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Intenta con otro nombre o nombre de usuario.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const Divider(color: Color(0xFF1E293B), height: 1),
      itemBuilder: (context, index) {
        final profile = _searchResults[index];
        final username = profile['username'] as String? ?? 'usuario';
        final fullName = profile['full_name'] as String? ?? 'Usuario UPSGlam';
        final avatarUrl = profile['avatar_url'] as String?;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          leading: CircleAvatar(
            radius: 24,
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
          title: Text(
            '@$username',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          subtitle: Text(
            fullName,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
          onTap: () {
            // Navegar al perfil del otro usuario
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserProfileViewScreen(
                  userId: profile['id'] as String,
                  profile: profile,
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Widget para el historial de búsqueda
  Widget _buildSearchHistory() {
    if (_searchHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 48, color: AppTheme.textSecondary.withOpacity(0.3)),
            const SizedBox(height: 12),
            const Text(
              'Busca a tus amigos',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Encuentra otros desarrolladores y entusiastas de CUDA.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BÚSQUEDAS RECIENTES',
                style: GoogleFonts.shareTechMono(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              TextButton(
                onPressed: _clearHistory,
                child: const Text(
                  'Borrar todo',
                  style: TextStyle(color: AppTheme.primary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _searchHistory.length,
            itemBuilder: (context, index) {
              final query = _searchHistory[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, color: AppTheme.textSecondary),
                title: Text(
                  query,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
                  onPressed: () => _removeFromHistory(query),
                ),
                onTap: () {
                  _searchController.text = query;
                  _performSearch(query);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

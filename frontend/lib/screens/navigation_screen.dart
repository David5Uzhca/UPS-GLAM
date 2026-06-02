import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'feed_screen.dart';
import 'search_screen.dart';
import 'upload_screen.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';
import '../services/supabase_service.dart';
import '../core/theme.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({Key? key}) : super(key: key);

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  int _selectedIndex = 0;
  int _unreadCount = 0;
  final _supabase = SupabaseService.instance.client;
  late final List<Widget> _screens;
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _screens = [
      const FeedScreen(),
      const SearchScreen(),
      UploadScreen(onUploadComplete: () => _onItemTapped(0)),
      const ChatListScreen(),
      const ProfileScreen(),
    ];
    _loadUnreadCount();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    if (_messagesChannel != null) {
      _supabase.removeChannel(_messagesChannel!);
    }
    super.dispose();
  }

  // Consulta la cantidad de mensajes no leídos en la base de datos
  Future<void> _loadUnreadCount() async {
    final currentUserId = SupabaseService.instance.currentUserId;
    if (currentUserId == null) return;

    try {
      final response = await _supabase
          .from('messages')
          .select('id')
          .eq('receiver_id', currentUserId)
          .eq('is_read', false);

      if (mounted) {
        setState(() {
          _unreadCount = response?.length ?? 0;
        });
      }
    } catch (e) {
      print('Error al cargar mensajes no leídos: $e');
    }
  }

  // Se suscribe a inserciones y actualizaciones en la tabla messages para actualizar el badge en tiempo real
  void _subscribeToMessages() {
    _messagesChannel = _supabase.channel('public:unread_messages_count').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        _loadUnreadCount();
      },
    );
    _messagesChannel!.subscribe();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Color(0xFF1E293B), // Borde sutil
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed, // Permite 5 ítems de manera fija y bonita
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              activeIcon: Icon(Icons.home_filled, color: AppTheme.primary),
              label: 'Inicio',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.search),
              activeIcon: Icon(Icons.search, color: AppTheme.primary),
              label: 'Buscar',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.add_box_outlined),
              activeIcon: Icon(Icons.add_box, color: AppTheme.primary),
              label: 'Publicar',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                label: Text('$_unreadCount'),
                isLabelVisible: _unreadCount > 0,
                child: const Icon(Icons.chat_bubble_outline),
              ),
              activeIcon: Badge(
                label: Text('$_unreadCount'),
                isLabelVisible: _unreadCount > 0,
                child: const Icon(Icons.chat_bubble, color: AppTheme.primary),
              ),
              label: 'Mensajes',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person, color: AppTheme.primary),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}



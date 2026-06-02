import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/backend_service.dart';
import '../core/theme.dart';
import '../widgets/metric_dashboard.dart';
import '../models/post.dart';

class UploadScreen extends StatefulWidget {
  final VoidCallback? onUploadComplete;

  const UploadScreen({Key? key, this.onUploadComplete}) : super(key: key);

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedImage;
  Uint8List? _webImageBytes; // Soporte para Web (opcional)
  final _descriptionController = TextEditingController();
  int _selectedFilterId = 1; // Filtro 1 por defecto (Bordes)
  bool _isProcessing = false;
  String _currentStepText = '';

  Uint8List? _previewImageBytes; // Imagen procesada devuelta por el endpoint de previsualización
  GpuMetrics? _previewMetrics;   // Métricas devueltas por la previsualización
  bool _showOriginalInPreview = false; // Alternar visualización en contenedor de previsualización

  final List<Map<String, dynamic>> _filters = [
    {
      'id': 1,
      'name': 'Bordes',
      'icon': Icons.filter_b_and_w,
      'color': Colors.grey,
      'desc': 'Convolución Laplaciana en escala de grises. Detecta contornos.',
    },
    {
      'id': 2,
      'name': 'Enfoque',
      'icon': Icons.hdr_strong,
      'color': Colors.amber,
      'desc': 'Unsharp Masking RGB. Aumenta la nitidez y contraste.',
    },
    {
      'id': 3,
      'name': 'Cartoon',
      'icon': Icons.palette_outlined,
      'color': AppTheme.secondary,
      'desc': 'Caricatura. Detecta bordes y aplana la paleta de color.',
    },
    {
      'id': 4,
      'name': 'Sepia',
      'icon': Icons.color_lens_outlined,
      'color': Colors.brown,
      'desc': 'Filtro Sepia. Matriz de color cálida en GPU.',
    },
    {
      'id': 5,
      'name': 'Invertido',
      'icon': Icons.difference_outlined,
      'color': Colors.deepOrange,
      'desc': 'Filtro Invertido. Inversión de colores completa en GPU.',
    },
    {
      'id': 6,
      'name': 'Pixelado',
      'icon': Icons.grid_view_outlined,
      'color': Colors.purple,
      'desc': 'Filtro Pixelado. Agrupamiento de píxeles en mosaicos 16x16.',
    },
    {
      'id': 7,
      'name': 'Burbujas Isotipo',
      'icon': Icons.bubble_chart_outlined,
      'color': Colors.blue,
      'desc': 'Filtro Burbujas. Marco bicolor y logos de isotipo con 30% de transparencia.',
    },
  ];

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 85, // Optimización de tamaño de imagen
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _webImageBytes = bytes;
            _selectedImage = File(pickedFile.path);
            _previewImageBytes = null;
            _previewMetrics = null;
          });
        } else {
          setState(() {
            _selectedImage = File(pickedFile.path);
            _previewImageBytes = null;
            _previewMetrics = null;
          });
        }
        // Desencadenar previsualización automática
        _handlePreview();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _handlePreview() async {
    if (_selectedImage == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _currentStepText = 'Iniciando pipeline de previsualizacion...';
    });

    try {
      setState(() {
        _currentStepText = 'Paso 1: Preparando datos de la imagen...';
      });
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _currentStepText = 'Paso 2: Enviando imagen a la GPU para previsualizacion...';
      });

      final response = await BackendService.instance.previewPostFilter(
        filePath: _selectedImage!.path,
        webBytes: _webImageBytes,
        filterId: _selectedFilterId,
      );

      setState(() {
        _currentStepText = 'Paso 3: Decodificando y renderizando respuesta de la GPU...';
      });
      await Future.delayed(const Duration(milliseconds: 400));

      if (response.imageBase64.isNotEmpty) {
        setState(() {
          _previewImageBytes = base64Decode(response.imageBase64);
          _previewMetrics = response.metrics;
          _showOriginalInPreview = false;
        });
      } else {
        throw Exception('El microservicio GPU retorno una respuesta vacia.');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vista previa de la GPU cargada exitosamente.'),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.redAccent),
                SizedBox(width: 10),
                Text('Error en Previsualizacion'),
              ],
            ),
            content: Text('No se pudo previsualizar el filtro GPU.\n\nDetalles: ${e.toString().replaceAll('Exception:', '')}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido', style: TextStyle(color: AppTheme.primary)),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _handleProcessAndPublish() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _currentStepText = 'Iniciando pipeline de publicacion...';
    });

    try {
      // Paso 1: Subir imagen original a Supabase Storage
      setState(() {
        _currentStepText = 'Paso 1: Subiendo imagen original a Supabase Cloud...';
      });

      final bytes = kIsWeb ? _webImageBytes! : await _selectedImage!.readAsBytes();
      final filename = 'original_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'originals/$filename';

      final client = SupabaseService.instance.client;
      await client.storage.from('upsglam-images').uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      final originalUrl = client.storage.from('upsglam-images').getPublicUrl(storagePath);

      // Paso 2: Invocar Orquestador Spring WebFlux
      setState(() {
        _currentStepText = 'Paso 2: Desencadenando orquestador reactivo de Spring Boot...';
      });
      await Future.delayed(const Duration(milliseconds: 800)); // Para dar feedback visual limpio

      // Paso 3: Orquestación GPU (PyCUDA) en el backend
      setState(() {
        _currentStepText = 'Paso 3: Compilando y ejecutando Kernel CUDA en la GPU fisica...';
      });
      await Future.delayed(const Duration(milliseconds: 1000));

      // Paso 4: Subida de salida y guardado en BD
      setState(() {
        _currentStepText = 'Paso 4: Registrando metricas de hardware y publicando...';
      });

      await BackendService.instance.createPost(
        originalImageUrl: originalUrl,
        filterId: _selectedFilterId,
        description: _descriptionController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Procesamiento GPU completado y publicado exitosamente.'),
            backgroundColor: AppTheme.accent,
          ),
        );
        _resetForm();
        widget.onUploadComplete?.call();
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.redAccent),
                SizedBox(width: 10),
                Text('Error en Pipeline'),
              ],
            ),
            content: Text('No se pudo completar el procesamiento GPU en el backend.\n\nDetalles: ${e.toString().replaceAll('Exception:', '')}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido', style: TextStyle(color: AppTheme.primary)),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _resetForm() {
    setState(() {
      _selectedImage = null;
      _webImageBytes = null;
      _descriptionController.clear();
      _selectedFilterId = 1;
      _previewImageBytes = null;
      _previewMetrics = null;
      _showOriginalInPreview = false;
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Nueva Publicación',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedImage != null)
            TextButton(
              onPressed: _isProcessing ? null : _resetForm,
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedImage == null) ...[
                    // Estado Inicial: Seleccionar Imagen
                    GestureDetector(
                      onTap: () => _showImageSourceBottomSheet(),
                      child: Container(
                        height: 250,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFF1E293B), width: 1.5),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add_photo_alternate_outlined, size: 48, color: AppTheme.primary),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Selecciona una imagen',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Formatos compatibles: JPG, JPEG, PNG',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Estado Activo: Imagen cargada + Configurar Publicación
                    Stack(
                      children: [
                        Container(
                          height: 280,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF1E293B), width: 1.5),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: _previewImageBytes != null && !_showOriginalInPreview
                                ? Image.memory(_previewImageBytes!, fit: BoxFit.cover)
                                : (kIsWeb
                                    ? Image.memory(_webImageBytes!, fit: BoxFit.cover)
                                    : Image.file(_selectedImage!, fit: BoxFit.cover)),
                          ),
                        ),
                        // Badge de Vista Previa o Original
                        if (_previewImageBytes != null)
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _showOriginalInPreview 
                                    ? Colors.black.withOpacity(0.7) 
                                    : AppTheme.accent.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _showOriginalInPreview ? Colors.white24 : AppTheme.accent,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                _showOriginalInPreview ? 'ORIGINAL' : 'VISTA PREVIA GPU',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        // Botón flotante para alternar Original/Vista Previa
                        if (_previewImageBytes != null)
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showOriginalInPreview = !_showOriginalInPreview;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.75),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppTheme.primary, width: 1),
                                ),
                                child: Icon(
                                  _showOriginalInPreview ? Icons.visibility : Icons.visibility_off,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Carrusel de Selección de Filtros GPU
                    Text(
                      'SELECCIONAR FILTRO GPU (9x9)',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 110,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _filters.length,
                        itemBuilder: (context, index) {
                          final filter = _filters[index];
                          final isSelected = _selectedFilterId == filter['id'];

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedFilterId = filter['id'];
                                _previewImageBytes = null;
                                _previewMetrics = null;
                                _showOriginalInPreview = false;
                              });
                              _handlePreview();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 100,
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primary.withOpacity(0.15) : AppTheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? AppTheme.primary : const Color(0xFF1E293B),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    filter['icon'] as IconData,
                                    color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    filter['name'] as String,
                                    style: TextStyle(
                                      color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Descripción del Filtro Seleccionado
                    Text(
                      _filters.firstWhere((f) => f['id'] == _selectedFilterId)['desc'] as String,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    
                    if (_previewMetrics != null) ...[
                      const SizedBox(height: 16),
                      MetricDashboard(
                        metrics: _previewMetrics!,
                        filterName: _filters.firstWhere((f) => f['id'] == _selectedFilterId)['name'] as String,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Campo de Pie de Foto (Descripción)
                    Text(
                      'PIE DE FOTO',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un pie de foto sobre tu procesamiento...',
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Botón de acción: PUBLICAR (procesado automáticamente al seleccionar)
                    if (_previewImageBytes != null)
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _handleProcessAndPublish,
                        icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                        label: const Text('PUBLICAR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          shadowColor: AppTheme.accent.withOpacity(0.4),
                          elevation: 10,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // Pantalla de Carga Translúcida y Dashboard del Pipeline
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withOpacity(0.4),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const CircularProgressIndicator(
                          color: AppTheme.primary,
                          strokeWidth: 4,
                        ),
                      ),
                      const SizedBox(height: 36),
                      Text(
                        'PIPELINE DE PROCESAMIENTO HETEROGÉNEO',
                        style: GoogleFonts.shareTechMono(
                          color: AppTheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF020617),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Text(
                          _currentStepText,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.shareTechMono(
                            color: const Color(0xFFF1F5F9),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Por favor, no cierres la aplicación.',
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showImageSourceBottomSheet() {
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
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Seleccionar Origen',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: AppTheme.primary),
                  title: const Text('Galería de Fotos'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                const Divider(color: Color(0xFF1E293B)),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.primary),
                  title: const Text('Cámara del Dispositivo'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class Post {
  final String id;
  final String originalImageUrl;
  final String processedImageUrl;
  final String? description;
  final DateTime createdAt;
  final String username;
  final String? userAvatarUrl;
  final String filterName;
  final int likesCount;
  final bool likedByMe;
  final GpuMetrics? metrics;

  Post({
    required this.id,
    required this.originalImageUrl,
    required this.processedImageUrl,
    this.description,
    required this.createdAt,
    required this.username,
    this.userAvatarUrl,
    required this.filterName,
    required this.likesCount,
    required this.likedByMe,
    this.metrics,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      originalImageUrl: json['originalImageUrl'] as String,
      processedImageUrl: json['processedImageUrl'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      username: json['username'] as String,
      userAvatarUrl: json['userAvatarUrl'] as String?,
      filterName: json['filterName'] ?? 'Filtro Desconocido',
      likesCount: (json['likesCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      metrics: json['metrics'] != null 
          ? GpuMetrics.fromJson(json['metrics'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalImageUrl': originalImageUrl,
      'processedImageUrl': processedImageUrl,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'username': username,
      'userAvatarUrl': userAvatarUrl,
      'filterName': filterName,
      'likesCount': likesCount,
      'likedByMe': likedByMe,
      'metrics': metrics?.toJson(),
    };
  }
}

class GpuMetrics {
  final int imageWidth;
  final int imageHeight;
  final int blockDimX;
  final int gridDimX;
  final int totalThreads;
  final double executionTimeMs;
  final String? status;

  GpuMetrics({
    required this.imageWidth,
    required this.imageHeight,
    required this.blockDimX,
    required this.gridDimX,
    required this.totalThreads,
    required this.executionTimeMs,
    this.status,
  });

  factory GpuMetrics.fromJson(Map<String, dynamic> json) {
    return GpuMetrics(
      imageWidth: (json['image_width'] ?? json['imageWidth'] as num?)?.toInt() ?? 0,
      imageHeight: (json['image_height'] ?? json['imageHeight'] as num?)?.toInt() ?? 0,
      blockDimX: (json['block_dim_x'] ?? json['blockDimX'] as num?)?.toInt() ?? 0,
      gridDimX: (json['grid_dim_x'] ?? json['gridDimX'] as num?)?.toInt() ?? 0,
      totalThreads: (json['total_threads'] ?? json['totalThreads'] as num?)?.toInt() ?? 0,
      executionTimeMs: (json['execution_time_ms'] ?? json['executionTimeMs'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
      'blockDimX': blockDimX,
      'gridDimX': gridDimX,
      'totalThreads': totalThreads,
      'executionTimeMs': executionTimeMs,
      'status': status,
    };
  }
}

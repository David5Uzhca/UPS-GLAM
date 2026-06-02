package ec.edu.ups.backend.service;

import ec.edu.ups.backend.dto.GpuProcessingResponse;
import ec.edu.ups.backend.dto.PostCreateRequest;
import ec.edu.ups.backend.dto.PostResponse;
import ec.edu.ups.backend.model.GpuMetric;
import ec.edu.ups.backend.model.Post;
import ec.edu.ups.backend.repository.GpuMetricRepository;
import ec.edu.ups.backend.repository.PostRepository;
import ec.edu.ups.backend.repository.UserProfileRepository;
import org.springframework.http.codec.multipart.FilePart;
import org.springframework.core.io.buffer.DataBufferUtils;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.ZonedDateTime;
import java.util.Base64;
import java.util.UUID;

@Service
public class PostService {

    private final PostRepository postRepository;
    private final GpuMetricRepository gpuMetricRepository;
    private final UserProfileRepository userProfileRepository;
    private final PyCudaClientService pyCudaClient;
    private final SupabaseStorageService storageService;

    public PostService(PostRepository postRepository,
                       GpuMetricRepository gpuMetricRepository,
                       UserProfileRepository userProfileRepository,
                       PyCudaClientService pyCudaClient,
                       SupabaseStorageService storageService) {
        this.postRepository = postRepository;
        this.gpuMetricRepository = gpuMetricRepository;
        this.userProfileRepository = userProfileRepository;
        this.pyCudaClient = pyCudaClient;
        this.storageService = storageService;
    }

    /**
     * Orquesta el flujo completo: Descarga -> PyCUDA -> Supabase Storage -> PostgreSQL
     */
    public Mono<PostResponse> createPost(PostCreateRequest request, UUID userId) {
        return storageService.downloadImage(request.getOriginalImageUrl())
            .flatMap(imageBytes -> {
                String tempFilename = "img_" + userId + "_" + System.currentTimeMillis() + ".jpg";
                // Llamamos a la GPU de PyCUDA
                return pyCudaClient.processImage(imageBytes, tempFilename, request.getFilterId())
                    .flatMap(gpuResponse -> {
                        if (!"SUCCESS".equals(gpuResponse.getStatus())) {
                            return Mono.error(new RuntimeException("Error en PyCUDA: " + gpuResponse.getMessage()));
                        }
                        
                        // Decodificamos la imagen base64 de vuelta a binario
                        byte[] processedBytes = Base64.getDecoder().decode(gpuResponse.getImage_base64());
                        String processedFilename = "processed_" + tempFilename;
                        
                        // Subimos la nueva imagen a Supabase Storage
                        return storageService.uploadProcessedImage(processedBytes, processedFilename)
                            .flatMap(processedUrl -> {
                                // Guardamos el Post en PostgreSQL
                                Post post = Post.builder()
                                        .userId(userId)
                                        .filterId(request.getFilterId())
                                        .originalImageUrl(request.getOriginalImageUrl())
                                        .processedImageUrl(processedUrl)
                                        .description(request.getDescription())
                                        .createdAt(ZonedDateTime.now())
                                        .build();
                                
                                return postRepository.save(post)
                                    .flatMap(savedPost -> {
                                        // Guardamos las métricas técnicas de la GPU
                                        GpuProcessingResponse.GpuMetricsDto metrics = gpuResponse.getMetrics();
                                        GpuMetric metric = GpuMetric.builder()
                                                .postId(savedPost.getId())
                                                .filterId(request.getFilterId())
                                                .userId(userId)
                                                .imageWidth(metrics.getImage_width())
                                                .imageHeight(metrics.getImage_height())
                                                .blockDimX(metrics.getBlock_dim_x())
                                                .gridDimX(metrics.getGrid_dim_x())
                                                .totalThreads(metrics.getTotal_threads())
                                                .executionTimeMs(metrics.getExecution_time_ms())
                                                .status("SUCCESS")
                                                .createdAt(ZonedDateTime.now())
                                                .build();
                                                
                                        return gpuMetricRepository.save(metric)
                                            .thenReturn(savedPost); // Retornamos el post guardado
                                    });
                            });
                    });
            })
            .flatMap(savedPost -> userProfileRepository.findById(userId)
                .map(user -> toPostResponse(savedPost, user.getUsername(), user.getAvatarUrl()))
                .switchIfEmpty(Mono.fromSupplier(() ->
                        toPostResponse(savedPost, "usuario", null)))
            );
    }

    private static PostResponse toPostResponse(Post savedPost, String username, String avatarUrl) {
        return PostResponse.builder()
                .id(savedPost.getId())
                .originalImageUrl(savedPost.getOriginalImageUrl())
                .processedImageUrl(savedPost.getProcessedImageUrl())
                .description(savedPost.getDescription())
                .createdAt(savedPost.getCreatedAt())
                .username(username)
                .userAvatarUrl(avatarUrl)
                .filterName("Filtro ID: " + savedPost.getFilterId())
                .likesCount(0L)
                .likedByMe(false)
                .build();
    }

    /**
     * Procesa la imagen enviada para previsualización usando el microservicio PyCUDA.
     */
    public Mono<GpuProcessingResponse> previewFilter(FilePart filePart, Integer filterId) {
        return DataBufferUtils.join(filePart.content())
            .flatMap(dataBuffer -> {
                byte[] bytes = new byte[dataBuffer.readableByteCount()];
                dataBuffer.read(bytes);
                DataBufferUtils.release(dataBuffer);
                
                String tempFilename = "preview_" + System.currentTimeMillis() + "_" + filePart.filename();
                return pyCudaClient.processImage(bytes, tempFilename, filterId);
            });
    }
}

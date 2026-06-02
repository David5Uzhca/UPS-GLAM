package ec.edu.ups.backend.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.util.Map;

@Service
public class SupabaseStorageService {

    private final WebClient webClient;
    private final String supabaseUrl;
    private final String serviceKey;

    public SupabaseStorageService(WebClient.Builder webClientBuilder,
                                  @Value("${upsglam.supabase.url}") String supabaseUrl,
                                  @Value("${upsglam.supabase.service-key}") String serviceKey,
                                  @Value("${upsglam.supabase.anon-key}") String anonKey) {
        this.supabaseUrl = supabaseUrl;
        this.serviceKey = serviceKey;
        this.webClient = webClientBuilder
                .baseUrl(supabaseUrl + "/storage/v1/object")
                .defaultHeader("Authorization", "Bearer " + serviceKey)
                .defaultHeader("apiKey", serviceKey)
                .build();
    }

    /**
     * Sube un arreglo de bytes (imagen procesada) al bucket upsglam-images
     * @return Retorna la URL pública de la imagen
     */
    public Mono<String> uploadProcessedImage(byte[] imageBytes, String filename) {
        return webClient.post()
                .uri("/upsglam-images/" + filename)
                .contentType(MediaType.IMAGE_JPEG)
                .bodyValue(imageBytes)
                .retrieve()
                .bodyToMono(Map.class)
                .map(response -> supabaseUrl + "/storage/v1/object/public/upsglam-images/" + filename);
    }
    
    /**
     * Descarga una imagen pública dada su URL para enviarla a procesar
     */
    public Mono<byte[]> downloadImage(String imageUrl) {
        return WebClient.builder()
                .codecs(configurer -> configurer
                        .defaultCodecs()
                        .maxInMemorySize(32 * 1024 * 1024)) // 32MB buffer
                .build()
                .get()
                .uri(imageUrl)
                .retrieve()
                .bodyToMono(byte[].class);
    }
}

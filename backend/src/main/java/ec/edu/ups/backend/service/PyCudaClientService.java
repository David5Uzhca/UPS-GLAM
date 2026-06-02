package ec.edu.ups.backend.service;

import ec.edu.ups.backend.dto.GpuProcessingResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@Service
public class PyCudaClientService {

    private final WebClient webClient;

    public PyCudaClientService(WebClient.Builder webClientBuilder,
                               @Value("${upsglam.gpu-api.url}") String gpuApiUrl) {
        this.webClient = webClientBuilder.baseUrl(gpuApiUrl).build();
    }

    /**
     * Envia la imagen y el filtro a procesar a la tarjeta de video (Microservicio PyCUDA)
     */
    public Mono<GpuProcessingResponse> processImage(byte[] imageBytes, String filename, Integer filterId) {
        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
        
        body.add("file", new ByteArrayResource(imageBytes) {
            @Override
            public String getFilename() {
                return filename;
            }
        });
        body.add("filter_id", filterId);

        return webClient.post()
                .uri("/process")
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .bodyValue(body)
                .retrieve()
                .bodyToMono(GpuProcessingResponse.class);
    }
}

package ec.edu.ups.backend.controller;

import ec.edu.ups.backend.dto.GpuProcessingResponse;
import ec.edu.ups.backend.dto.PostCreateRequest;
import ec.edu.ups.backend.dto.PostResponse;
import ec.edu.ups.backend.service.PostService;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.codec.multipart.FilePart;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import jakarta.validation.Valid;
import java.util.UUID;

@RestController
@RequestMapping("/api/posts")
public class PostController {

    private final PostService postService;

    public PostController(PostService postService) {
        this.postService = postService;
    }

    /**
     * Endpoint para crear una publicación (Descarga original -> GPU -> Supabase Storage -> BD)
     */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<PostResponse> createPost(@Valid @RequestBody PostCreateRequest request,
                                         Authentication authentication) {
                                             
        // Extraemos el ID del usuario desde el token JWT validado por Spring Security
        Jwt jwt = (Jwt) authentication.getPrincipal();
        UUID userId = UUID.fromString(jwt.getClaimAsString("sub"));
        
        return postService.createPost(request, userId);
    }

    /**
     * Endpoint para previsualizar el filtro sin crear publicación en base de datos.
     */
    @PostMapping(value = "/preview", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public Mono<GpuProcessingResponse> previewFilter(@RequestPart("file") FilePart file,
                                                     @RequestParam("filterId") Integer filterId) {
        return postService.previewFilter(file, filterId);
    }
}

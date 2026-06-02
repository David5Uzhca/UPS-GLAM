package ec.edu.ups.backend.dto;

import lombok.Builder;
import lombok.Data;

import java.time.ZonedDateTime;
import java.util.UUID;

@Data
@Builder
public class PostResponse {
    private UUID id;
    private String originalImageUrl;
    private String processedImageUrl;
    private String description;
    private ZonedDateTime createdAt;
    
    // User info
    private String username;
    private String userAvatarUrl;
    
    // Filter info
    private String filterName;
    
    // Social info
    private Long likesCount;
    private Boolean likedByMe;
}

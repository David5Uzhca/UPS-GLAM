package ec.edu.ups.backend.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

import java.time.ZonedDateTime;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Table("posts")
public class Post {
    
    @Id
    private UUID id;
    
    private UUID userId;
    
    private Integer filterId;
    
    private String originalImageUrl;
    
    private String processedImageUrl;
    
    private String description;
    
    private ZonedDateTime createdAt;
}

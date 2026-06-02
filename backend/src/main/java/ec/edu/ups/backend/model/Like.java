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
@Table("likes")
public class Like {
    
    @Id
    private UUID id;
    
    private UUID postId;
    
    private UUID userId;
    
    private ZonedDateTime createdAt;
}

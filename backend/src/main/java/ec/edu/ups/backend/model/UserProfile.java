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
@Table("user_profiles")
public class UserProfile {
    
    @Id
    private UUID id;
    
    private String username;
    
    private String fullName;
    
    private String avatarUrl;
    
    private ZonedDateTime createdAt;
}

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
@Table("gpu_metrics")
public class GpuMetric {
    
    @Id
    private UUID id;
    
    private UUID postId;
    
    private Integer filterId;
    
    private UUID userId;
    
    private Integer imageWidth;
    
    private Integer imageHeight;
    
    private Integer blockDimX;
    
    private Integer gridDimX;
    
    private Long totalThreads;
    
    private Double executionTimeMs;
    
    private String status;
    
    private ZonedDateTime createdAt;
}

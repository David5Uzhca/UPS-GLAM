package ec.edu.ups.backend.dto;

import lombok.Data;
import java.util.Map;

@Data
public class GpuProcessingResponse {
    private String status;
    private String image_base64;
    private GpuMetricsDto metrics;
    private String message; // En caso de error
    
    @Data
    public static class GpuMetricsDto {
        private Integer filter_id;
        private Integer image_width;
        private Integer image_height;
        private Integer block_dim_x;
        private Integer grid_dim_x;
        private Long total_threads;
        private Double execution_time_ms;
    }
}

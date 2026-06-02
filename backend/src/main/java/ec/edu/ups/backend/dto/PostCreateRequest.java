package ec.edu.ups.backend.dto;

import lombok.Data;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

@Data
public class PostCreateRequest {
    
    @NotBlank(message = "La URL de la imagen original es obligatoria")
    private String originalImageUrl;
    
    @NotNull(message = "Debe seleccionar un filtro")
    private Integer filterId;
    
    private String description;
}

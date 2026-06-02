package ec.edu.ups.backend.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

import java.time.ZonedDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Table("filters")
public class Filter {
    
    @Id
    private Integer id;
    
    private String name;
    
    private String description;
    
    private Integer kernelSize;
    
    private ZonedDateTime createdAt;
}

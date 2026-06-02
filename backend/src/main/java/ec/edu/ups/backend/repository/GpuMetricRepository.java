package ec.edu.ups.backend.repository;

import ec.edu.ups.backend.model.GpuMetric;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import java.util.UUID;
import reactor.core.publisher.Mono;

@Repository
public interface GpuMetricRepository extends ReactiveCrudRepository<GpuMetric, UUID> {
    Mono<GpuMetric> findByPostId(UUID postId);
}

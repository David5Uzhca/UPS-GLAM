package ec.edu.ups.backend.repository;

import ec.edu.ups.backend.model.Like;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import java.util.UUID;
import reactor.core.publisher.Mono;

@Repository
public interface LikeRepository extends ReactiveCrudRepository<Like, UUID> {
    Mono<Long> countByPostId(UUID postId);
    Mono<Void> deleteByPostIdAndUserId(UUID postId, UUID userId);
    Mono<Boolean> existsByPostIdAndUserId(UUID postId, UUID userId);
}

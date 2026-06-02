package ec.edu.ups.backend.repository;

import ec.edu.ups.backend.model.Post;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import java.util.UUID;
import reactor.core.publisher.Flux;

@Repository
public interface PostRepository extends ReactiveCrudRepository<Post, UUID> {
    Flux<Post> findByUserIdOrderByCreatedAtDesc(UUID userId);
}

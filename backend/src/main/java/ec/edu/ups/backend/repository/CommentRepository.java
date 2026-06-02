package ec.edu.ups.backend.repository;

import ec.edu.ups.backend.model.Comment;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import java.util.UUID;
import reactor.core.publisher.Flux;

@Repository
public interface CommentRepository extends ReactiveCrudRepository<Comment, UUID> {
    Flux<Comment> findByPostIdOrderByCreatedAtDesc(UUID postId);
}

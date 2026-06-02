package ec.edu.ups.backend.repository;

import ec.edu.ups.backend.model.Filter;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Mono;

@Repository
public interface FilterRepository extends ReactiveCrudRepository<Filter, Integer> {
    Mono<Filter> findByName(String name);
}

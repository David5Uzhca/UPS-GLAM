package ec.edu.ups.backend.repository;

import ec.edu.ups.backend.model.UserProfile;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import java.util.UUID;

@Repository
public interface UserProfileRepository extends ReactiveCrudRepository<UserProfile, UUID> {
}

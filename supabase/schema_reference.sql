-- UPSGlam: esquema de referencia (PostgreSQL / Supabase)
-- Ajustar según migraciones reales del proyecto. Usado por Spring Data R2DBC.

-- Perfiles (sincronizado con auth.users vía trigger en Supabase)
CREATE TABLE IF NOT EXISTS user_profiles (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username    TEXT UNIQUE NOT NULL,
    full_name   TEXT,
    avatar_url  TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Catálogo de filtros GPU
CREATE TABLE IF NOT EXISTS filters (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    kernel_size INTEGER DEFAULT 9,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Publicaciones
CREATE TABLE IF NOT EXISTS posts (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID NOT NULL REFERENCES user_profiles(id),
    filter_id            INTEGER NOT NULL REFERENCES filters(id),
    original_image_url   TEXT NOT NULL,
    processed_image_url  TEXT NOT NULL,
    description          TEXT,
    created_at           TIMESTAMPTZ DEFAULT NOW()
);

-- Métricas de ejecución CUDA por publicación
CREATE TABLE IF NOT EXISTS gpu_metrics (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id            UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    filter_id          INTEGER NOT NULL,
    user_id            UUID NOT NULL REFERENCES user_profiles(id),
    image_width        INTEGER,
    image_height       INTEGER,
    block_dim_x        INTEGER,
    grid_dim_x         INTEGER,
    total_threads      BIGINT,
    execution_time_ms  DOUBLE PRECISION,
    status             TEXT,
    created_at         TIMESTAMPTZ DEFAULT NOW()
);

-- Social (modelos presentes; API Flutter pendiente)
CREATE TABLE IF NOT EXISTS likes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES user_profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS comments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES user_profiles(id),
    content    TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Datos iniciales de filtros
INSERT INTO filters (id, name, description, kernel_size) VALUES
    (1, 'Bordes',  'Convolución Laplaciana en escala de grises (detección de contornos)', 9),
    (2, 'Enfoque', 'Unsharp masking RGB (nitidez y contraste)', 9),
    (3, 'Cartoon', 'Detección de bordes + paleta de color aplanada', 9)
ON CONFLICT (id) DO NOTHING;

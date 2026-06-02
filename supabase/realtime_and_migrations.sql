-- ====================================================================
-- UPSGlam: SQL Migraciones y Configuración de Tiempo Real (Realtime)
-- ====================================================================
-- INSTRUCCIONES:
-- 1. Copia todo el contenido de este script.
-- 2. Ve a la consola de Supabase (https://supabase.com).
-- 3. Entra a tu proyecto, ve a la pestaña "SQL Editor" en el menú izquierdo.
-- 4. Crea un "New Query", pega este código y haz clic en "Run".
-- ====================================================================

-- 1. Asegurar la columna 'description' en 'user_profiles'
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS description TEXT;

-- 2. Crear tabla de Mensajería (si no existe) y asegurar columna 'is_read'
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    sender_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE NOT NULL,
    receiver_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE NOT NULL,
    content TEXT,
    post_id UUID REFERENCES public.posts(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Asegurar la columna 'is_read' en la tabla 'messages'
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_read BOOLEAN DEFAULT false;

-- Habilitar RLS en mensajes (si no está habilitado)
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Crear políticas de seguridad para mensajes si no existen
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'messages' AND policyname = 'Cualquiera puede enviar mensajes a otro.'
    ) THEN
        CREATE POLICY "Cualquiera puede enviar mensajes a otro." ON public.messages 
        FOR INSERT TO authenticated WITH CHECK (auth.uid() = sender_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'messages' AND policyname = 'Usuarios pueden leer sus propios mensajes.'
    ) THEN
        CREATE POLICY "Usuarios pueden leer sus propios mensajes." ON public.messages 
        FOR SELECT TO authenticated USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'messages' AND policyname = 'Usuarios pueden actualizar sus propios mensajes recibidos.'
    ) THEN
        CREATE POLICY "Usuarios pueden actualizar sus propios mensajes recibidos." ON public.messages 
        FOR UPDATE TO authenticated USING (auth.uid() = receiver_id) WITH CHECK (auth.uid() = receiver_id);
    END IF;
END
$$;


-- 3. Crear tabla de Seguimiento (si no existe)
CREATE TABLE IF NOT EXISTS public.follows (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    follower_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE NOT NULL,
    followed_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(follower_id, followed_id)
);

-- Habilitar RLS en follows
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'El catálogo de seguidores es público.'
    ) THEN
        CREATE POLICY "El catálogo de seguidores es público." ON public.follows FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'Cualquiera puede seguir a alguien.'
    ) THEN
        CREATE POLICY "Cualquiera puede seguir a alguien." ON public.follows FOR INSERT TO authenticated WITH CHECK (auth.uid() = follower_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'Cualquiera puede dejar de seguir a alguien.'
    ) THEN
        CREATE POLICY "Cualquiera puede dejar de seguir a alguien." ON public.follows FOR DELETE TO authenticated USING (auth.uid() = follower_id);
    END IF;
END
$$;


-- 4. Crear tabla de Notificaciones (si no existe)
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    receiver_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE NOT NULL,
    type TEXT NOT NULL, -- 'LIKE', 'COMMENT', 'FOLLOW'
    post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
    content TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Habilitar RLS en notificaciones
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'notifications' AND policyname = 'Usuarios pueden leer sus propias notificaciones.'
    ) THEN
        CREATE POLICY "Usuarios pueden leer sus propias notificaciones." ON public.notifications 
        FOR SELECT TO authenticated USING (auth.uid() = receiver_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'notifications' AND policyname = 'Cualquiera puede insertar notificaciones.'
    ) THEN
        CREATE POLICY "Cualquiera puede insertar notificaciones." ON public.notifications 
        FOR INSERT TO authenticated WITH CHECK (true);
    END IF;
END
$$;


-- 5. HABILITAR TIEMPO REAL (REALTIME) PARA TODAS LAS TABLAS CLAVE
-- Supabase requiere añadir explícitamente las tablas a la publicación 'supabase_realtime' para transmitir cambios
DO $$
BEGIN
    -- Intentar añadir posts
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.posts;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    -- Intentar añadir messages
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    -- Intentar añadir likes
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.likes;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    -- Intentar añadir comments
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.comments;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    -- Intentar añadir follows
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.follows;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    -- Intentar añadir notifications
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
END
$$;

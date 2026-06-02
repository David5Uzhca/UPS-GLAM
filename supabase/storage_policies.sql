-- UPSGlam: políticas RLS para el bucket upsglam-images
-- Ejecutar en Supabase → SQL Editor (proyecto UPSGlam)
--
-- El bucket PUBLIC solo permite leer archivos sin auth.
-- Las subidas (INSERT) requieren políticas explícitas en storage.objects.

-- Opcional: eliminar políticas previas con el mismo nombre si re-ejecutas
DROP POLICY IF EXISTS "upsglam_authenticated_upload_originals" ON storage.objects;
DROP POLICY IF EXISTS "upsglam_authenticated_upload_processed" ON storage.objects;
DROP POLICY IF EXISTS "upsglam_public_read" ON storage.objects;
DROP POLICY IF EXISTS "upsglam_authenticated_read" ON storage.objects;

-- Lectura pública (coherente con bucket PUBLIC)
CREATE POLICY "upsglam_public_read"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'upsglam-images');

-- Lectura para usuarios autenticados
CREATE POLICY "upsglam_authenticated_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'upsglam-images');

-- Flutter: sube originales a originals/...
CREATE POLICY "upsglam_authenticated_upload_originals"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'upsglam-images'
  AND (storage.foldername(name))[1] = 'originals'
);

-- Backend (service role) sube processed_*.jpg en la raíz del bucket
CREATE POLICY "upsglam_authenticated_upload_processed"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'upsglam-images'
  AND name LIKE 'processed_%'
);

import numpy as np
import time
from PIL import Image
from numba import njit
import pycuda.driver as cuda
import pycuda.autoinit
from pycuda.compiler import SourceModule

import filtros

# =====================================================
# ==================== VALIDACION =====================
# =====================================================

@njit
def verificar_resultados(outCPU, outGPU, sizeOut):
    iguales = True
    for i in range(sizeOut):
        if abs(int(outCPU[i]) - int(outGPU[i])) > 1:
            iguales = False
            break
    return iguales

# =====================================================
# =================== KERNELS CUDA ====================
# =====================================================

cuda_kernels = """
#define KERNEL_SIZE 9
#define KERNEL_HALF 4

__global__ void convolucionGPU_Gris(
    unsigned char* input,
    unsigned char* output,
    int width,
    int height,
    int channels,
    float* kernel
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (idx < width * height) {
        int x = idx % width;
        int y = idx / width;

        float suma = 0.0f;

        for (int i = 0; i < KERNEL_SIZE; i++) {
            for (int j = 0; j < KERNEL_SIZE; j++) {
                int row = min(max(y + i - KERNEL_HALF, 0), height - 1);
                int col = min(max(x + j - KERNEL_HALF, 0), width - 1);
                int pixel_idx = (row * width + col) * channels;

                float gris = 0.299f * input[pixel_idx] +
                             0.587f * input[pixel_idx + 1] +
                             0.114f * input[pixel_idx + 2];

                suma += gris * kernel[i * KERNEL_SIZE + j];
            }
        }

        output[idx] = (unsigned char)fminf(fmaxf(suma, 0.0f), 255.0f);
    }
}

__global__ void convolucionGPU_RGB(
    unsigned char* input,
    unsigned char* output,
    int width,
    int height,
    int channels,
    float* kernel
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (idx < width * height) {
        int x = idx % width;
        int y = idx / width;

        for (int ch = 0; ch < channels; ch++) {
            float suma = 0.0f;

            for (int i = 0; i < KERNEL_SIZE; i++) {
                for (int j = 0; j < KERNEL_SIZE; j++) {
                    int row = min(max(y + i - KERNEL_HALF, 0), height - 1);
                    int col = min(max(x + j - KERNEL_HALF, 0), width - 1);
                    int pixel_idx = (row * width + col) * channels + ch;

                    suma += input[pixel_idx] * kernel[i * KERNEL_SIZE + j];
                }
            }

            int outIdx = idx * channels + ch;
            output[outIdx] = (unsigned char)fminf(fmaxf(suma, 0.0f), 255.0f);
        }
    }
}

__global__ void cartoon_GPU(
    unsigned char* input,
    unsigned char* output,
    int width,
    int height,
    int channels,
    float* kernel
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (idx < width * height) {
        int x = idx % width;
        int y = idx / width;

        float borde = 0.0f;

        for (int i = 0; i < KERNEL_SIZE; i++) {
            for (int j = 0; j < KERNEL_SIZE; j++) {
                int row = min(max(y + i - KERNEL_HALF, 0), height - 1);
                int col = min(max(x + j - KERNEL_HALF, 0), width - 1);
                int pixel_idx = (row * width + col) * channels;

                float gris = 0.299f * input[pixel_idx] +
                             0.587f * input[pixel_idx + 1] +
                             0.114f * input[pixel_idx + 2];

                borde += gris * kernel[i * KERNEL_SIZE + j];
            }
        }

        int outIdx = idx * channels;
        for (int ch = 0; ch < channels; ch++) {
            unsigned char color = (input[outIdx + ch] / 64) * 64;
            output[outIdx + ch] = (borde > 250.0f) ? 0 : color;
        }
    }
}
"""
mod = SourceModule(cuda_kernels)
convolucionGPU_Gris = mod.get_function("convolucionGPU_Gris")
convolucionGPU_RGB = mod.get_function("convolucionGPU_RGB")
cartoon_GPU = mod.get_function("cartoon_GPU")

# =====================================================
# =================== CPU FUNCTIONS ===================
# =====================================================
# Utilizamos Numba @njit para compilar la funcion a C y que sea igual de rapida
# de lo contrario, Python nativo demoraria horas procesando esto.

@njit
def convolucionCPU_Gris(input_img, output_img, width, height, channels, kernel):
    for y in range(height):
        for x in range(width):
            suma = 0.0
            for i in range(filtros.KERNEL_SIZE):
                for j in range(filtros.KERNEL_SIZE):
                    row = min(max(y + i - filtros.KERNEL_HALF, 0), height - 1)
                    col = min(max(x + j - filtros.KERNEL_HALF, 0), width - 1)
                    pixel_idx = (row * width + col) * channels
                    
                    gris = (0.299 * input_img[pixel_idx] + 
                            0.587 * input_img[pixel_idx + 1] + 
                            0.114 * input_img[pixel_idx + 2])
                    
                    suma += gris * kernel[i * filtros.KERNEL_SIZE + j]
            
            output_img[y * width + x] = min(max(suma, 0.0), 255.0)

@njit
def convolucionCPU_RGB(input_img, output_img, width, height, channels, kernel):
    for y in range(height):
        for x in range(width):
            for ch in range(channels):
                suma = 0.0
                for i in range(filtros.KERNEL_SIZE):
                    for j in range(filtros.KERNEL_SIZE):
                        row = min(max(y + i - filtros.KERNEL_HALF, 0), height - 1)
                        col = min(max(x + j - filtros.KERNEL_HALF, 0), width - 1)
                        pixel_idx = (row * width + col) * channels + ch
                        
                        suma += input_img[pixel_idx] * kernel[i * filtros.KERNEL_SIZE + j]
                
                outIdx = (y * width + x) * channels + ch
                output_img[outIdx] = min(max(suma, 0.0), 255.0)

@njit
def cartoon_CPU(input_img, output_img, width, height, channels, kernel):
    for y in range(height):
        for x in range(width):
            borde = 0.0
            for i in range(filtros.KERNEL_SIZE):
                for j in range(filtros.KERNEL_SIZE):
                    row = min(max(y + i - filtros.KERNEL_HALF, 0), height - 1)
                    col = min(max(x + j - filtros.KERNEL_HALF, 0), width - 1)
                    pixel_idx = (row * width + col) * channels
                    
                    gris = (0.299 * input_img[pixel_idx] + 
                            0.587 * input_img[pixel_idx + 1] + 
                            0.114 * input_img[pixel_idx + 2])
                    
                    borde += gris * kernel[i * filtros.KERNEL_SIZE + j]
            
            outIdx = (y * width + x) * channels
            for ch in range(channels):
                color = (input_img[outIdx + ch] // 64) * 64
                output_img[outIdx + ch] = 0 if borde > 250.0 else color

# =====================================================
# ==================== PROCESAMIENTO ==================
# =====================================================

def procesarFiltro(nombre, tipo, kernel, img_arr, w, h, c):
    esBordes = (tipo == 1)
    
    sizeIn = w * h * c
    sizeOut = (w * h) if esBordes else (w * h * c)
    
    outCPU = np.zeros(sizeOut, dtype=np.uint8)
    outGPU = np.zeros(sizeOut, dtype=np.uint8)
    
    print("\n====================================")
    print(f"FILTRO: {nombre} ({filtros.KERNEL_SIZE}x{filtros.KERNEL_SIZE})")
    print("====================================")
    if esBordes:
        print("[MODO] ESCALA DE GRISES\n[INFO] El filtro usa SOLO 1 CANAL")
    else:
        print("[MODO] RGB\n[INFO] El filtro usa 3 CANALES (R,G,B)")
    print("====================================")
    
    # ================= CPU =================
    startCPU = time.perf_counter()
    
    if tipo == 1:
        convolucionCPU_Gris(img_arr, outCPU, w, h, c, kernel)
    elif tipo == 2:
        convolucionCPU_RGB(img_arr, outCPU, w, h, c, kernel)
    else:
        cartoon_CPU(img_arr, outCPU, w, h, c, kernel)
        
    tiempoCPU = time.perf_counter() - startCPU
    print(f"[CPU] Tiempo: {tiempoCPU:.6f} s")
    
    # ================= GPU =================
    
    d_in = cuda.mem_alloc(img_arr.nbytes)
    d_out = cuda.mem_alloc(outGPU.nbytes)
    d_kernel = cuda.mem_alloc(kernel.nbytes)
    
    cuda.memcpy_htod(d_in, img_arr)
    cuda.memcpy_htod(d_kernel, kernel)
    
    block = (256, 1, 1)
    totalPixels = w * h
    grid = ((totalPixels + 255) // 256, 1, 1)
    
    start_event = cuda.Event()
    stop_event = cuda.Event()
    
    start_event.record()
    
    # PyCUDA requiere numpy types explicitos
    if tipo == 1:
        convolucionGPU_Gris(d_in, d_out, np.int32(w), np.int32(h), np.int32(c), d_kernel, block=block, grid=grid)
    elif tipo == 2:
        convolucionGPU_RGB(d_in, d_out, np.int32(w), np.int32(h), np.int32(c), d_kernel, block=block, grid=grid)
    else:
        cartoon_GPU(d_in, d_out, np.int32(w), np.int32(h), np.int32(c), d_kernel, block=block, grid=grid)
        
    stop_event.record()
    stop_event.synchronize()
    
    tiempoGPU = start_event.time_till(stop_event) / 1000.0
    print(f"[GPU] Tiempo: {tiempoGPU:.6f} s")
    
    totalHilos = grid[0] * block[0]
    print(f"[INFO] Hilos creados: {totalHilos} en dimension X")
    print(f"[INFO] Speedup: {tiempoCPU/tiempoGPU:.2f}x")
    
    cuda.memcpy_dtoh(outGPU, d_out)
    
    # ================= VALIDACION =================
    correcto = verificar_resultados(outCPU, outGPU, sizeOut)
    print("====================================")
    if correcto:
        print("[CHECK] Verificacion CPU vs GPU: CORRECTA (Coinciden)")
    else:
        print("[CHECK] Verificacion CPU vs GPU: ERROR (Hay diferencias)")
    print("====================================")
    
    # ================= GUARDAR =================
    filename = f"resultado_{nombre}.jpg"
    
    if esBordes:
        out_image = outGPU.reshape((h, w))
    else:
        out_image = outGPU.reshape((h, w, c))
        
    Image.fromarray(out_image).save(filename, quality=100)
    print(f"[FILE] Guardado: {filename}")

# =====================================================
# ======================== MAIN =======================
# =====================================================

def main():
    try:
        img = Image.open("input.jpg").convert('RGB')
    except Exception as e:
        print("ERROR: No se encontro input.jpg. Por favor asegurate de copiar la imagen en esta carpeta.")
        return
        
    w, h = img.size
    c = 3
    
    img_arr = np.array(img, dtype=np.uint8).flatten()
    
    print("====================================")
    print("IMAGEN RGB CARGADA")
    print(f"Resolucion: {w} x {h}")
    print(f"Canales RGB: {c}")
    print("====================================")
    
    # Numba Warming up:
    # Numba compila la funcion la primera vez que la llamamos. 
    # Llamamos a funciones con imagenes vacias (dummy) para que el tiempo 
    # de compilacion no contamine el tiempo del CPU.
    print("[INFO] Compilando CPU (Numba JIT Warming up)...")
    dummy_img = np.zeros(27, dtype=np.uint8)
    dummy_out = np.zeros(9, dtype=np.uint8)
    convolucionCPU_Gris(dummy_img, dummy_out, 3, 3, 3, filtros.kernelBordes)
    dummy_out_rgb = np.zeros(27, dtype=np.uint8)
    convolucionCPU_RGB(dummy_img, dummy_out_rgb, 3, 3, 3, filtros.kernelEnfoque)
    cartoon_CPU(dummy_img, dummy_out_rgb, 3, 3, 3, filtros.kernelCartoon)
    print("[INFO] CPU JIT Lista.\n")
    
    procesarFiltro("Bordes", 1, filtros.kernelBordes, img_arr, w, h, c)
    procesarFiltro("Enfoque", 2, filtros.kernelEnfoque, img_arr, w, h, c)
    procesarFiltro("Cartoon", 3, filtros.kernelCartoon, img_arr, w, h, c)

if __name__ == "__main__":
    main()

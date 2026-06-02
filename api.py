import io
import base64
import logging
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse

import filtros

logger = logging.getLogger("upsglam-gpu-api")

# FastAPI ejecuta endpoints sync en un thread pool sin contexto CUDA.
# Todo el trabajo GPU va a un único hilo con su propio contexto PyCUDA.
_gpu_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="cuda-gpu")
_gpu_runtime = {}

app = FastAPI(
    title="UPSGlam GPU Processing API",
    description="Microservicio para procesamiento de imagenes en GPU",
)

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

__global__ void sepia_GPU(
    unsigned char* input,
    unsigned char* output,
    int width,
    int height,
    int channels
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < width * height) {
        int pixel_idx = idx * channels;
        float r = input[pixel_idx];
        float g = input[pixel_idx + 1];
        float b = input[pixel_idx + 2];

        float tr = 0.393f * r + 0.769f * g + 0.189f * b;
        float tg = 0.349f * r + 0.686f * g + 0.168f * b;
        float tb = 0.272f * r + 0.534f * g + 0.131f * b;

        output[pixel_idx] = (unsigned char)fminf(tr, 255.0f);
        output[pixel_idx + 1] = (unsigned char)fminf(tg, 255.0f);
        output[pixel_idx + 2] = (unsigned char)fminf(tb, 255.0f);
    }
}

__global__ void negative_GPU(
    unsigned char* input,
    unsigned char* output,
    int width,
    int height,
    int channels
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < width * height) {
        int pixel_idx = idx * channels;
        output[pixel_idx] = 255 - input[pixel_idx];
        output[pixel_idx + 1] = 255 - input[pixel_idx + 1];
        output[pixel_idx + 2] = 255 - input[pixel_idx + 2];
    }
}

__global__ void pixelate_GPU(
    unsigned char* input,
    unsigned char* output,
    int width,
    int height,
    int channels,
    int pixel_size
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < width * height) {
        int x = idx % width;
        int y = idx / width;

        int bx = (x / pixel_size) * pixel_size;
        int by = (y / pixel_size) * pixel_size;

        bx = min(max(bx, 0), width - 1);
        by = min(max(by, 0), height - 1);

        int src_idx = (by * width + bx) * channels;
        int dst_idx = idx * channels;

        output[dst_idx] = input[src_idx];
        output[dst_idx + 1] = input[src_idx + 1];
        output[dst_idx + 2] = input[src_idx + 2];
    }
}

__global__ void custom_bubbles_GPU(
    unsigned char* input,
    unsigned char* output,
    int width,
    int height,
    int channels,
    unsigned char* logo,
    int logo_w,
    int logo_h,
    int* bubble_coords,
    int num_bubbles,
    int border_width
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < width * height) {
        int x = idx % width;
        int y = idx / width;
        int dst_idx = idx * channels;

        if (x < border_width || x >= width - border_width || y < border_width || y >= height - border_width) {
            if (x + y < (width + height) / 2) {
                output[dst_idx] = 255;
                output[dst_idx + 1] = 215;
                output[dst_idx + 2] = 0;
            } else {
                output[dst_idx] = 0;
                output[dst_idx + 1] = 102;
                output[dst_idx + 2] = 204;
            }
            return;
        }

        bool inside_bubble = false;
        for (int i = 0; i < num_bubbles; i++) {
            int bx = bubble_coords[i * 2];
            int by = bubble_coords[i * 2 + 1];

            if (x >= bx && x < bx + logo_w && y >= by && y < by + logo_h) {
                int lx = x - bx;
                int ly = y - by;
                int logo_idx = (ly * logo_w + lx) * 4;

                unsigned char la = logo[logo_idx + 3];
                if (la > 10) {
                    float alpha = 0.30f;

                    float lr = logo[logo_idx];
                    float lg = logo[logo_idx + 1];
                    float lb = logo[logo_idx + 2];

                    float ir = input[dst_idx];
                    float ig = input[dst_idx + 1];
                    float ib = input[dst_idx + 2];

                    output[dst_idx] = (unsigned char)(alpha * lr + (1.0f - alpha) * ir);
                    output[dst_idx + 1] = (unsigned char)(alpha * lg + (1.0f - alpha) * ig);
                    output[dst_idx + 2] = (unsigned char)(alpha * lb + (1.0f - alpha) * ib);

                    inside_bubble = true;
                    break;
                }
            }
        }

        if (!inside_bubble) {
            output[dst_idx] = input[dst_idx];
            output[dst_idx + 1] = input[dst_idx + 1];
            output[dst_idx + 2] = input[dst_idx + 2];
        }
    }
}
"""


def _init_cuda_worker():
    import pycuda.driver as cuda
    import pycuda.autoinit  # noqa: F401 — contexto en este hilo
    from pycuda.compiler import SourceModule

    mod = SourceModule(cuda_kernels)
    _gpu_runtime["cuda"] = cuda
    _gpu_runtime["gpu_name"] = cuda.Device(0).name()
    _gpu_runtime["convolucionGPU_Gris"] = mod.get_function("convolucionGPU_Gris")
    _gpu_runtime["convolucionGPU_RGB"] = mod.get_function("convolucionGPU_RGB")
    _gpu_runtime["cartoon_GPU"] = mod.get_function("cartoon_GPU")
    _gpu_runtime["sepia_GPU"] = mod.get_function("sepia_GPU")
    _gpu_runtime["negative_GPU"] = mod.get_function("negative_GPU")
    _gpu_runtime["pixelate_GPU"] = mod.get_function("pixelate_GPU")
    _gpu_runtime["custom_bubbles_GPU"] = mod.get_function("custom_bubbles_GPU")
    logger.info("CUDA inicializado en hilo dedicado: %s", _gpu_runtime["gpu_name"])


def _process_on_gpu(image_bytes: bytes, filter_id: int) -> dict:
    cuda = _gpu_runtime["cuda"]

    if filter_id == 1:
        kernel = filtros.kernelBordes
        func = _gpu_runtime["convolucionGPU_Gris"]
        es_bordes = True
    elif filter_id == 2:
        kernel = filtros.kernelEnfoque
        func = _gpu_runtime["convolucionGPU_RGB"]
        es_bordes = False
    elif filter_id == 3:
        kernel = filtros.kernelCartoon
        func = _gpu_runtime["cartoon_GPU"]
        es_bordes = False
    elif filter_id == 4:
        kernel = None
        func = _gpu_runtime["sepia_GPU"]
        es_bordes = False
    elif filter_id == 5:
        kernel = None
        func = _gpu_runtime["negative_GPU"]
        es_bordes = False
    elif filter_id == 6:
        kernel = None
        func = _gpu_runtime["pixelate_GPU"]
        es_bordes = False
    elif filter_id == 7:
        kernel = None
        func = _gpu_runtime["custom_bubbles_GPU"]
        es_bordes = False
    else:
        raise ValueError("filter_id invalido. Use 1 a 7")

    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    w, h = img.size
    c = 3
    img_arr = np.array(img, dtype=np.uint8).flatten()

    size_out = (w * h) if es_bordes else (w * h * c)
    out_gpu = np.zeros(size_out, dtype=np.uint8)

    block = (256, 1, 1)
    total_pixels = w * h
    grid = ((total_pixels + 255) // 256, 1, 1)
    total_threads = grid[0] * block[0]

    d_in = cuda.mem_alloc(img_arr.nbytes)
    d_out = cuda.mem_alloc(out_gpu.nbytes)
    
    to_free = [d_in, d_out]
    try:
        cuda.memcpy_htod(d_in, img_arr)

        start_event = cuda.Event()
        stop_event = cuda.Event()
        start_event.record()

        if filter_id in (1, 2, 3):
            d_kernel = cuda.mem_alloc(kernel.nbytes)
            to_free.append(d_kernel)
            cuda.memcpy_htod(d_kernel, kernel)
            func(
                d_in,
                d_out,
                np.int32(w),
                np.int32(h),
                np.int32(c),
                d_kernel,
                block=block,
                grid=grid,
            )
        elif filter_id in (4, 5):
            func(
                d_in,
                d_out,
                np.int32(w),
                np.int32(h),
                np.int32(c),
                block=block,
                grid=grid,
            )
        elif filter_id == 6:
            pixel_size = 16
            func(
                d_in,
                d_out,
                np.int32(w),
                np.int32(h),
                np.int32(c),
                np.int32(pixel_size),
                block=block,
                grid=grid,
            )
        elif filter_id == 7:
            import os
            import random
            LOGO_PATH = os.path.join("frontend", "lib", "resources", "isotipo.png")
            if not os.path.exists(LOGO_PATH):
                LOGO_PATH = "isotipo.png"
            
            logo_img = Image.open(LOGO_PATH).convert("RGBA")
            logo_img = logo_img.resize((80, 80))
            logo_w, logo_h = logo_img.size
            logo_arr = np.array(logo_img, dtype=np.uint8).flatten()
            
            num_bubbles = 8
            border_width = 25
            bubble_coords = []
            for _ in range(num_bubbles):
                bx = random.randint(border_width, max(border_width, w - border_width - logo_w))
                by = random.randint(border_width, max(border_width, h - border_width - logo_h))
                bubble_coords.append(bx)
                bubble_coords.append(by)
            bubble_coords_arr = np.array(bubble_coords, dtype=np.int32)
            
            d_logo = cuda.mem_alloc(logo_arr.nbytes)
            d_bubble_coords = cuda.mem_alloc(bubble_coords_arr.nbytes)
            to_free.extend([d_logo, d_bubble_coords])
            
            cuda.memcpy_htod(d_logo, logo_arr)
            cuda.memcpy_htod(d_bubble_coords, bubble_coords_arr)
            
            func(
                d_in,
                d_out,
                np.int32(w),
                np.int32(h),
                np.int32(c),
                d_logo,
                np.int32(logo_w),
                np.int32(logo_h),
                d_bubble_coords,
                np.int32(num_bubbles),
                np.int32(border_width),
                block=block,
                grid=grid,
            )

        stop_event.record()
        stop_event.synchronize()
        tiempo_gpu = start_event.time_till(stop_event) / 1000.0
        cuda.memcpy_dtoh(out_gpu, d_out)
    finally:
        for ptr in to_free:
            ptr.free()

    if es_bordes:
        out_image = out_gpu.reshape((h, w))
    else:
        out_image = out_gpu.reshape((h, w, c))

    result_img = Image.fromarray(out_image)
    buffered = io.BytesIO()
    result_img.save(buffered, format="JPEG", quality=90)
    img_str = base64.b64encode(buffered.getvalue()).decode("utf-8")

    return {
        "status": "SUCCESS",
        "image_base64": img_str,
        "metrics": {
            "filter_id": filter_id,
            "image_width": w,
            "image_height": h,
            "block_dim_x": block[0],
            "grid_dim_x": grid[0],
            "total_threads": total_threads,
            "execution_time_ms": round(tiempo_gpu * 1000, 4),
        },
    }


def _run_on_gpu(fn, *args):
    return _gpu_executor.submit(fn, *args).result()


# Inicializar CUDA al arrancar el proceso (bloquea hasta que la GPU está lista)
_run_on_gpu(_init_cuda_worker)


@app.get("/")
def health_check():
    return {
        "status": "ok",
        "message": "API de procesamiento GPU (PyCUDA) activa.",
        "gpu": _gpu_runtime.get("gpu_name", "no inicializada"),
    }


@app.post("/process")
def process_image(file: UploadFile = File(...), filter_id: int = Form(...)):
    if filter_id not in (1, 2, 3, 4, 5, 6, 7):
        raise HTTPException(
            status_code=400,
            detail="filter_id invalido. Use 1 a 7",
        )

    try:
        image_bytes = file.file.read()
        result = _run_on_gpu(_process_on_gpu, image_bytes, filter_id)
        return JSONResponse(content=result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        logger.exception("Error en /process filter_id=%s", filter_id)
        return JSONResponse(
            status_code=500,
            content={"status": "ERROR", "message": str(e)},
        )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)

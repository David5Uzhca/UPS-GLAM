import numpy as np

KERNEL_SIZE = 9
KERNEL_HALF = 4
KERNEL_AREA = 81

# ================= FILTRO DE BORDES (9x9) =================
kernelBordes = np.full(KERNEL_AREA, -1.0, dtype=np.float32)
kernelBordes[40] = 80.0

# ================= FILTRO DE ENFOQUE (9x9) =================
kernelEnfoque = np.full(KERNEL_AREA, -1.0, dtype=np.float32)
kernelEnfoque[40] = 81.0

# ================= FILTRO CARTOON (9x9) =================
kernelCartoon = np.full(KERNEL_AREA, -1.0, dtype=np.float32)
kernelCartoon[40] = 80.0

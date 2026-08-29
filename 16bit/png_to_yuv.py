import numpy as np
from PIL import Image

PADDING_IN_PNG = 10
DIGIT = 28
TILE = DIGIT + 2 * PADDING_IN_PNG   # 48
N = 900
N2 = 30                              # 30x30 grid

FRAME_PAD = 2
FRAME = DIGIT + 2 * FRAME_PAD        # 32, matches the RTL's expected input size

img = Image.open("test_900.png").convert("L")
arr = np.array(img)
assert arr.shape == (TILE * N2, TILE * N2)

out = bytearray()
for i in range(N2):
    for j in range(N2):
        tile = arr[TILE*i:TILE*(i+1), TILE*j:TILE*(j+1)]
        digit28 = tile[PADDING_IN_PNG:PADDING_IN_PNG+DIGIT,
                        PADDING_IN_PNG:PADDING_IN_PNG+DIGIT]
        frame32 = np.pad(digit28, ((FRAME_PAD,FRAME_PAD),(FRAME_PAD,FRAME_PAD)), 'constant')
        out += frame32.astype(np.uint8).tobytes()

assert len(out) == N * 32 * 32
with open("test_900f.yuv", "wb") as f:
    f.write(out)
print("wrote", len(out), "bytes =", N, "frames")
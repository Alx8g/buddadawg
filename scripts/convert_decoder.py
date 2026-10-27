"""Pack decoder.npz into decoder.bin (raw little-endian arrays, back to back) + decoder.json (name -> dtype, shape, offset)."""
import json, sys
import numpy as np

npz, out_dir = sys.argv[1:3]
z = np.load(npz)
index, blob = {}, bytearray()
for name in z.files:
    a = np.ascontiguousarray(z[name])
    index[name] = {"dtype": a.dtype.name, "shape": list(a.shape), "offset": len(blob)}
    blob += a.tobytes()
open(f"{out_dir}/decoder.bin", "wb").write(blob)
json.dump(index, open(f"{out_dir}/decoder.json", "w"), indent=1)
print(len(blob) // 1024 // 1024, "MB,", len(index), "arrays")

"""Telecharge quelques seances MM-Fit (montre gauche + labels) depuis le zip de 1,7 Go par requetes Range.
Usage : python fetch_mmfit.py <dossier> [w00 w01 ...]"""
import io, zipfile, urllib.request, os, sys
URL = "https://s3.eu-west-2.amazonaws.com/vradu.uk/mm-fit.zip"

class RangeFile(io.RawIOBase):
    def __init__(self, url):
        self.url = url; self.pos = 0
        self.size = int(urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=60).headers["Content-Length"])
    def seekable(self): return True
    def readable(self): return True
    def seek(self, off, whence=0):
        self.pos = {0: off, 1: self.pos + off, 2: self.size + off}[whence]; return self.pos
    def tell(self): return self.pos
    def readinto(self, b):
        if self.pos >= self.size: return 0
        end = min(self.size - 1, self.pos + len(b) - 1)
        d = urllib.request.urlopen(urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"}), timeout=120).read()
        b[:len(d)] = d; self.pos += len(d); return len(d)

def main():
    out = sys.argv[1]; workouts = sys.argv[2:] or ["w00", "w01", "w02", "w03", "w04"]
    os.makedirs(out, exist_ok=True)
    zf = zipfile.ZipFile(io.BufferedReader(RangeFile(URL), buffer_size=1 << 20))
    for n in zf.namelist():
        parts = n.split("/")
        if len(parts) >= 3 and parts[1] in workouts and (n.endswith("sw_l_acc.npy") or n.endswith("labels.csv")):
            with zf.open(n) as f, open(os.path.join(out, parts[-1]), "wb") as o: o.write(f.read())
            print("ok", n)

if __name__ == "__main__":
    main()

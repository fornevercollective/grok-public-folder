import sys

from grok_paths import ROOT

sys.path.insert(0, str(ROOT))
from grok_api import import_all_artifacts

count, _, bin_name = import_all_artifacts()
if count == 0:
    print("no files yet")
else:
    print(f"imported {count} into {bin_name}")
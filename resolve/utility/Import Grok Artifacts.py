#!/usr/bin/env python3
import sys

sys.path.insert(0, "/Users/tref/film/grok-public-folder")
from grok_api import import_all_artifacts

count, _, bin_name = import_all_artifacts()
if count == 0:
    print("no files yet")
else:
    print(f"imported {count} into {bin_name}")
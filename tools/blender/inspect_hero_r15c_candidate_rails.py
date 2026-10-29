"""Reuse topology extractor against independently saved R15c, in fresh evidence."""
import importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('r15c_component_extractor',ROOT/'tools/blender/inspect_hero_r15c_baseline_rails.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
module.SOURCE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15c-blockout-01.blend'
module.DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15c-blockout-01/candidate-rail-components-01'
module.__file__=__file__
if __name__=='__main__':raise SystemExit(module.main())

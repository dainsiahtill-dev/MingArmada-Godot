"""Apply the established paired-camera receipt audit to R16."""
import importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('r16_review_audit',ROOT/'tools/research/verify_hero_r15b_review_pair.py')
audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
audit.DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r16-blockout-01'
if __name__=='__main__':raise SystemExit(audit.main())

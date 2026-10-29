"""Verify R9b with exactly the same bytewise checks used for R9."""
from pathlib import Path
import verify_hero_r9_texture_delta as contract

def main():
    root = Path(__file__).resolve().parents[2]
    contract.PNG = root / 'assets/textures/hero_fuchuan_r9/sunfaded-cinnabar-hemp-sail.png'
    contract.EXPECTED_PNG_SHA = 'f89da712948d0b3f3f72506f1375fbe27c8fabee6d816c5ea055ced67b491970'
    contract.TARGET = root / 'assets/models/hero_fuchuan_v3_r9b'
    contract.CANDIDATE_REVISION = 'r9b'
    contract.main()


if __name__ == '__main__':
    main()

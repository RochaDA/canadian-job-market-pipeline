"""Checks that the project root can be imported as `src.*` when running pytest
from anywhere, without needing to install the project as a package."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

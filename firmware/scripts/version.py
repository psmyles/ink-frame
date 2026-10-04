# FW_VERSION for the build (docs/ota.md): INKFRAME_FW_VERSION, which the release workflow
# sets from the fw-v* tag, else the development version below. Frames compare
# MAJOR.MINOR.PATCH only, so a release must be numbered above what's out there.
import os

Import("env")  # noqa: F821 (PlatformIO)

DEVELOPMENT = "0.1.0-dev"
version = os.environ.get("INKFRAME_FW_VERSION") or DEVELOPMENT
env.Append(CPPDEFINES=[("FW_VERSION", env.StringifyMacro(version))])  # noqa: F821
print(f"Ink Frame firmware {version}")

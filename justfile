set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    just --list

lint:
    bash -n ups-status.sh
    shellcheck ups-status.sh
    python3 -m py_compile tests/test_ups_status.py

test:
    python3 -m unittest discover -s tests -v

check: lint test
